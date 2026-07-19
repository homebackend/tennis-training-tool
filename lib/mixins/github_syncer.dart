/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_common/mixin/encrypt_decryt_service.dart';
import 'package:flutter_common/mixin/syncer_core.dart';
import 'package:http/http.dart' as http;

import '../services/preferences_backup_service.dart';
import '../tool.dart';

mixin GitHubSyncer<DataType>
    implements SyncerCore, EncryptDecryptService, WidgetsBindingObserver {
  static final keyGitRepo = PreferencesBackupService.keyGitRepo;
  static final keyGitToken = PreferencesBackupService.keyGitToken;
  static final keyEncPwd = PreferencesBackupService.keyEncPwd;

  String get githubFilePath;

  @override
  Future<void> notifyLoadedFromCache() async => AudioNotifier.loadedFromCache();

  @override
  Future<void> notifyLoadedFromNetwork() async =>
      AudioNotifier.loadedFromNetwork();

  @override
  Future<void> notifyLoadErrorOccurred() async => AudioNotifier.errorOccurred();

  Future<void> pushToGitHubWithAutoMerge({String? retryServerFileSha}) =>
      pushWithAutoMerge(retryServerFileSha: retryServerFileSha);

  @override
  Future<(int, String?, String?, Uint8List?)> fetchRemote({
    String? lastModified,
    String? documentSha,
  }) async {
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
      final etag = lastModified != null && lastModified.isNotEmpty
          ? lastModified
          : dataRes.headers['etag'] ?? '';
      if (dataBody['encoding'] != 'base64' || dataBody['content'] == '') {
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
      } else {
        final (sha, bytes) = await _extractContent(dataBody, pass);
        return (dataRes.statusCode, sha, etag, bytes);
      }
    }

    return (dataRes.statusCode, null, null, null);
  }

  @override
  Future<
    (
      PushReturnCode statusCode,
      String? newVersion,
      String? newEtag,
      http.Response raw,
    )
  >
  pushRemote(Uint8List bytes, {String? fileSha}) async {
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
    log('url: $url');
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
    log('Blob url: $url');
    return (uri, headers, pass);
  }
}
