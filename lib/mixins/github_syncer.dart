/*
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_common/app_logger.dart';
import 'package:flutter_common/mixin/encrypt_decryt_service.dart';
import 'package:flutter_common/mixin/syncer_core.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../services/preferences_backup_service.dart';
import '../tool.dart';

mixin GitHubSyncer<DataType>
    implements SyncerCore, EncryptDecryptService, WidgetsBindingObserver {
  static final keyGitRepo = PreferencesBackupService.keyGitRepo;
  static final keyGitToken = PreferencesBackupService.keyGitToken;
  static final keyEncPwd = PreferencesBackupService.keyEncPwd;

  String get githubFilePath;
  bool get isReleaseFile;

  @override
  Future<void> notifyLoadedFromCache() async => AudioNotifier.loadedFromCache();

  @override
  Future<void> notifyLoadedFromNetwork() async =>
      AudioNotifier.loadedFromNetwork();

  @override
  Future<void> notifyLoadErrorOccurred() async => AudioNotifier.errorOccurred();

  Future<void> pushToGitHubWithAutoMerge({
    String? retryServerFileSha,
    bool background = false,
  }) => pushWithAutoMerge(
    retryServerFileSha: retryServerFileSha,
    background: background,
  );

  @override
  Future<(int, String?, String?, Uint8List?)> fetchRemote({
    String? lastModified,
    String? documentSha,
  }) async {
    if (isReleaseFile) {
      return _downloadFromReleaseIfChanged(lastModified);
    }

    final (dataUrl, headers, pass) = await _getFileInfoRequestData(
      lastModified: lastModified,
      documentSha: documentSha,
    );

    final dataRes = await client.get(dataUrl, headers: headers);
    if (dataRes.statusCode == 200) {
      final dataBody = json.decode(dataRes.body);
      final sha = documentSha != null && documentSha.isNotEmpty
          ? documentSha
          : dataBody['sha'];
      final etag =
          dataRes.headers['etag'] ??
          (lastModified != null && lastModified.isNotEmpty ? lastModified : '');
      final (blobUrl, headers, pass) = await _getBlobRequestData(
        documentSha: sha,
      );
      final blobRes = await client.get(blobUrl, headers: headers);
      if (blobRes.statusCode == 200) {
        final blobBody = json.decode(blobRes.body);
        final (sha, bytes) = await _extractContent(blobBody, pass);
        return (blobRes.statusCode, sha, etag, bytes);
      } else {
        return (blobRes.statusCode, null, null, null);
      }
    }

    return (dataRes.statusCode, null, null, null);
  }

  Future<(int, String?, String?, Uint8List?)> _downloadFromReleaseIfChanged(
    String? savedEtag,
  ) async {
    final (tagsUrl, baseHeaders, pass) = await _getReleaseByTagRequestData();
    var res = await client.get(tagsUrl, headers: baseHeaders);
    if (res.statusCode != 200) return (res.statusCode, null, null, null);

    final assets = json.decode(res.body)['assets'] as List;
    final asset = assets.firstWhere(
      (a) => a['name'] == localFileName,
      orElse: () => null,
    );
    if (asset == null) return (res.statusCode, null, null, null);

    final assetId = asset['id'].toString();
    final currentDigest = asset['digest'];

    final (assetsUrl, headers) = await _getReleaseAssetRequestData(assetId);
    res = await client.get(
      assetsUrl,
      headers: {
        ...headers,
        'Accept': 'application/octet-stream',
        'If-None-Match': ?savedEtag,
      },
    );

    if (res.statusCode == 200) {
      final newSha = currentDigest.split(':').last as String?;
      final newEtag = res.headers['etag'];
      final decryptedBytes = await decryptBytes(res.bodyBytes, pass);
      return (res.statusCode, newSha, newEtag, decryptedBytes);
    }
    return (res.statusCode, null, null, null);
  }

  @override
  Future<(PushReturnCode, String?, String?, http.Response)> pushRemote(
    Uint8List bytes, {
    String? fileSha,
  }) async {
    if (isReleaseFile) {
      return _pushToRelease(bytes);
    }

    final (url, headers, pass) = await _getFileInfoRequestData();
    headers["Content-Type"] = "application/json";

    final encryptedBytes = await encryptBytes(bytes, pass);
    final requestBody = {
      "message": "Sync via App Tracker",
      "content": base64Encode(encryptedBytes),
      "sha": ?fileSha,
    };
    final res = await client.put(
      url,
      headers: headers,
      body: json.encode(requestBody),
    );

    PushReturnCode statusCode = [200, 201, 204].contains(res.statusCode)
        ? PushReturnCode.success
        : [409, 412].contains(res.statusCode)
        ? PushReturnCode.conflict
        : PushReturnCode.error;
    final newFileSha = statusCode == PushReturnCode.success
        ? json.decode(res.body)["content"]["sha"].toString()
        : '';
    final newFileEtag = res.headers['etag'] ?? '';

    return (statusCode, newFileSha, newFileEtag, res);
  }

  Future<(String, Uint8List)> _extractContent(
    dynamic dataBody,
    String pass,
  ) async {
    final String fileSha = dataBody["sha"];
    final encryptedBytes = base64Decode(
      dataBody["content"].toString().replaceAll('\n', ''),
    );
    final decryptedBytes = await decryptBytes(encryptedBytes, pass);

    return (fileSha, decryptedBytes);
  }

  Future<(PushReturnCode, String?, String?, http.Response)> _pushToRelease(
    Uint8List bytes,
  ) async {
    final (tagUrl, headers, pass) = await _getReleaseByTagRequestData();
    final encryptedBytes = await encryptBytes(bytes, pass);

    var res = await client.get(tagUrl, headers: headers);
    Map<String, dynamic> release;
    if (res.statusCode == 200) {
      release = json.decode(res.body);
    } else {
      final (releaseUrl, headers) = await _getCreateReleaseRequestData();
      res = await client.post(
        releaseUrl,
        headers: headers,
        body: json.encode({
          'tag_name': documentPath,
          'name': 'App Storage',
          'body': 'Documents',
        }),
      );
      if (res.statusCode != 201) return (PushReturnCode.error, '', '', res);
      release = json.decode(res.body);
    }

    final releaseId = release['id'].toString();
    final assets = (release['assets'] as List);

    {
      final (uploadUrl, headers) = await _getUploadRequestData(
        releaseId,
        '$localFileName.tmp',
      );

      res = await client.post(
        uploadUrl,
        headers: headers,
        body: encryptedBytes,
      );

      if (res.statusCode != 201) {
        return (PushReturnCode.error, '', res.headers['etag'] ?? '', res);
      }
    }

    final tmpAssetId = json.decode(res.body)['id'].toString();
    final tmpEtag = res.headers['etag'] ?? '';

    final old = assets.firstWhere(
      (a) => a['name'] == localFileName,
      orElse: () => null,
    );
    if (old != null) {
      final (deleteUrl, headers) = await _getReleaseAssetRequestData(old['id']);
      await client.delete(deleteUrl, headers: headers);
    }

    {
      final (assetUrl, headers) = await _getReleaseAssetRequestData(tmpAssetId);
      res = await client.patch(
        assetUrl,
        headers: headers,
        body: json.encode({'name': localFileName}),
      );

      if (res.statusCode == 200) {
        final newSha = json.decode(res.body)['id'].toString();
        final newEtag = res.headers['etag'] ?? '';
        return (PushReturnCode.success, newSha, newEtag, res);
      } else {
        return (PushReturnCode.error, '', tmpEtag, res);
      }
    }
  }

  Future<(String, String, String)> _getServerConfig() async {
    final repo = await secureStorage.read(key: keyGitRepo) ?? '';
    final token = await secureStorage.read(key: keyGitToken) ?? '';
    final password = await secureStorage.read(key: keyEncPwd) ?? '';
    return (repo, token, password);
  }

  Future<(String, Map<String, String>, String)> _getRequestData({
    String? lastModified,
    String? documentSha,
  }) async {
    final (repo, token, pass) = await _getServerConfig();
    final headers = {
      "Authorization": "Bearer $token",
      if (lastModified != null && lastModified.isNotEmpty)
        'If-None-Match': lastModified,
    };
    return (repo, headers, pass);
  }

  Future<(Uri, Map<String, String>, String)> _getFileInfoRequestData({
    String? lastModified,
    String? documentSha,
  }) async {
    final (repo, headers, pass) = await _getRequestData(
      lastModified: lastModified,
      documentSha: documentSha,
    );
    final url =
        "https://api.github.com/repos/$repo/contents/$githubFilePath.enc";
    final uri = Uri.parse(url);
    appLogger.d('url: $url');
    return (uri, headers, pass);
  }

  Future<(Uri, Map<String, String>, String)> _getBlobRequestData({
    String? lastModified,
    required String documentSha,
  }) async {
    final (repo, headers, pass) = await _getRequestData(
      lastModified: lastModified,
      documentSha: documentSha,
    );
    final url = 'https://api.github.com/repos/$repo/git/blobs/$documentSha';
    final uri = Uri.parse(url);
    appLogger.d('Blob url: $url');
    return (uri, headers, pass);
  }

  Future<(Uri, Map<String, String>, String)>
  _getReleaseByTagRequestData() async {
    final (repo, headers, pass) = await _getRequestData();
    final url =
        'https://api.github.com/repos/$repo/releases/tags/$documentPath';
    final uri = Uri.parse(url);
    appLogger.d('url: $url');
    return (uri, headers, pass);
  }

  Future<(Uri, Map<String, String>)> _getCreateReleaseRequestData() async {
    final (repo, headers, _) = await _getRequestData();
    final url = 'https://api.github.com/repos/$repo/releases';
    final uri = Uri.parse(url);
    appLogger.d('url: $url');
    return (uri, {...headers, 'Content-Type': 'application/json'});
  }

  Future<(Uri, Map<String, String>)> _getUploadRequestData(
    String releaseId,
    String tmpName,
  ) async {
    final (repo, headers, _) = await _getRequestData();
    final url =
        'https://uploads.github.com/repos/$repo/releases/$releaseId/assets?name=$tmpName';
    final uri = Uri.parse(url);
    appLogger.d('url: $url');
    return (uri, {...headers, 'Content-Type': 'application/octet-stream'});
  }

  Future<(Uri, Map<String, String>)> _getReleaseAssetRequestData(
    String assetId,
  ) async {
    final (repo, headers, _) = await _getRequestData();
    final url = 'https://api.github.com/repos/$repo/releases/assets/$assetId';
    final uri = Uri.parse(url);
    appLogger.d('url: $url');
    return (uri, headers);
  }
}
