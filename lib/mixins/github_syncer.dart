/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

/* Flow:
 *   ┌─────────────────────────────────────────────────────────┐
 *   ↓                                                         │
 * Timer -> sync -> has it modified? -no-> pull -> load -> update last sync
 *   ↑              since last sync?         ↑
 *   │                  │                    │               
 *   │                  │                    └────────────────────────┐
 *   │                  └yes-> user intervention required? -no-> push ┘ 
 *   │                                   │                         ↑
 *   │ ┌─────────────────────────────────┘                         │
 *   │ └yes-> show user dialog box->if user resolves conflits?-yes-┘
 *   │                                       │
 *   └───────retain local/remote changes <-no┘  
 */
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/encrypt_decryt_service.dart';
import '../services/preferences_backup_service.dart';

mixin GitHubSyncer<DataType> implements EncryptDecryptService {
  static final keyGitRepo = PreferencesBackupService.keyGitRepo;
  static final keyGitToken = PreferencesBackupService.keyGitToken;
  static final keyEncPwd = PreferencesBackupService.keyEncPwd;

  bool isSyncBlocked = false;
  bool isSyncInProgress = false;
  bool isModified = false;

  SharedPreferences get sharedPreferences;
  FlutterSecureStorage get secureStorage;
  http.Client get client;

  String get keyHasSyncDataModified;
  String get keyDocumentLastModified;
  String get keyDocumentSha;

  String? appSha;
  String? appEtag;

  bool get isModifiable;
  String get localFileName;
  String get githubFilePath;
  Duration get syncDuration;

  void notifySyncStarted();
  void notifySyncDone();
  void notifySyncFailed();
  Future<void> processContentPostLoad(Uint8List content);
  Future<void> processConflicts(Uint8List serverData, String serverSha);
  Future<void> syncDataLoader();

  Future<Uint8List> getContentsForWrite() async {
    final cacheFile = await _cacheFile();
    return await cacheFile.readAsBytes();
  }

  Timer? _syncTimer;

  Future<void> initializeSyncer() async {
    appSha = sharedPreferences.getString(keyDocumentSha);
    appEtag = sharedPreferences.getString(keyDocumentLastModified);
    isModified = sharedPreferences.getBool(keyHasSyncDataModified) ?? false;

    await _loadSyncData();

    _syncTimer = Timer.periodic(syncDuration, (_) {
      _syncFromNetwork(true);
    });
  }

  void disposeSyncer() {
    _syncTimer?.cancel();
  }

  Future<void> syncData() async {
    await _syncFromNetwork(true);
  }

  Future<void> _loadSyncData() async {
    final cacheFile = await _cacheFile();
    bool cacheFileExists =
        cacheFile.existsSync() && appEtag != null && appEtag!.isNotEmpty;
    if (cacheFileExists) {
      unawaited(
        // No edit should be allowed until sync is done
        _syncFromNetwork(true).catchError((e) async {
          log('Error during background sync: $e');
          notifySyncFailed();
          await processContentPostLoad(await cacheFile.readAsBytes());
        }),
      );
      await processContentPostLoad(await cacheFile.readAsBytes());
    } else {
      await _syncFromNetwork(false);
    }
  }

  Future<void> cacheLocally(Uint8List bytes, String sha, String etag) async {
    appSha = sha;
    appEtag = etag;
    final cacheFile = await _cacheFile();
    cacheFile.writeAsBytes(bytes);
    await sharedPreferences.setString(keyDocumentSha, sha);
    await sharedPreferences.setString(keyDocumentLastModified, etag);
  }

  Future<void> _syncFromNetwork(bool background) async {
    if (isSyncInProgress) {
      return;
    }

    try {
      isSyncInProgress = true;
      if (isModifiable && isModified) {
        await _saveToNetwork();
      } else {
        await _loadFromNetwork(background);
      }
    } finally {
      isSyncInProgress = false;
    }
  }

  Future<void> _saveToNetwork() async {
    await pushToGitHubWithAutoMerge();
    final cacheFile = await _cacheFile();
    await processContentPostLoad(await cacheFile.readAsBytes());
  }

  Future<void> _loadFromNetwork(bool background) async {
    bool thereWasException = false;

    try {
      notifySyncStarted();
      final cacheFile = await _cacheFile();
      final lastMod = cacheFile.existsSync() ? appEtag : '';
      final documentSha = cacheFile.existsSync() ? appSha : '';
      final (code, sha, etag, bytes) = await fetchFromGitHub(
        lastModified: lastMod,
        documentSha: documentSha,
      );

      if (cacheFile.existsSync() && code == 304) {
        await processContentPostLoad(await cacheFile.readAsBytes());
      } else if (code == 200) {
        await cacheLocally(bytes!, sha!, etag!);
        await processContentPostLoad(bytes);
        if (background) {
          // If cacheFileExists is true that means earlier
          // we loaded data from cache and now new version
          // of cache is available. So notify.
          syncDataLoader();
        }
      } else {
        log('Error during http call: $code');
        throw (Exception('HTTP $code'));
      }
    } catch (e) {
      thereWasException = true;
      log('Error: $e');
      notifySyncFailed();
      rethrow;
    } finally {
      if (!thereWasException) {
        notifySyncDone();
      }
    }
  }

  Future<void> pushToGitHubWithAutoMerge({String? retryServerFileSha}) async {
    bool thereWasException = false;

    try {
      notifySyncStarted();
      final bytes = await getContentsForWrite();
      final res = await pushToGitHubWithResponse(
        bytes,
        fileSha: retryServerFileSha ?? appSha,
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final fileSha = json.decode(res.body)["content"]["sha"].toString();
        final fileEtag = res.headers['etag'] ?? '';
        await cacheLocally(bytes, fileSha, fileEtag);
      } else if (res.statusCode == 409) {
        final (code, serverFileSha, serverFileEtag, serverData) =
            await fetchFromGitHub();

        if (serverFileSha == null || serverData == null) {
          throw Exception(
            'Failed to pull latest version of $githubFilePath: $code',
          );
        }

        await processConflicts(serverData, serverFileSha);
      } else {
        throw Exception("Push error: ${res.body}");
      }
    } catch (_) {
      thereWasException = true;
      notifySyncFailed();
      rethrow;
    } finally {
      if (!thereWasException) {
        notifySyncDone();
      }
    }
  }

  Future<(int, String?, String?, Uint8List?)> fetchFromGitHub({
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

  Future<http.Response> pushToGitHubWithResponse(
    Uint8List bytes, {
    String? fileSha,
  }) async {
    final (url, headers, pass) = await _getFileInfoRequestData();
    headers["Content-Type"] = "application/json";

    final encryptedBytes = await encryptBytes(bytes, pass);
    final requestBody = {
      "message": "Sync via App Tracker",
      "content": base64Encode(encryptedBytes),
      "sha": ?fileSha,
    };
    return await client.put(
      url,
      headers: headers,
      body: json.encode(requestBody),
    );
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

  Future<File> _cacheFile() async {
    final dir = await getApplicationCacheDirectory();
    return File('${dir.path}/$localFileName');
  }

  Future<bool> hasSyncDataModified() async {
    return isModified;
  }

  Future<void> setSyncDataModified(bool modified) async {
    isModified = modified;
    await sharedPreferences.setBool(keyHasSyncDataModified, modified);
  }
}
