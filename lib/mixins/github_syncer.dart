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

  bool get isModifiable;
  String get localFileName;
  String get githubFilePath;
  Duration get syncDuration;

  void notifySyncStarted();
  void notifySyncDone();
  void notifySyncFailed();
  /*
    final Map<String, dynamic> auditLog = await generateAuditPayload();
    final localData = Map<String, dynamic>.from(content);
    localData['metadata'] = auditLog;
    return json.encode(localdata);
   */
  Future<void> processContentPostLoad(Uint8List content);
  Future<void> processContentPreWrite(Uint8List content);
  Future<void> processConflicts(Uint8List serverData, String serverSha);
  Future<void> syncDataLoader();

  Timer? _syncTimer;

  void initializeSyncer() async {
    _loadSyncData();

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
    final lastMod = sharedPreferences.getString(keyDocumentLastModified) ?? '';
    final lastSha = sharedPreferences.getString(keyDocumentSha) ?? '';
    final cacheFile = await _cacheFile();
    bool cacheFileExists =
        cacheFile.existsSync() && (lastMod.isNotEmpty || lastSha.isNotEmpty);
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

  Future<void> cacheLocally(Uint8List bytes, String sha) async {
    appSha = sha;
    final cacheFile = await _cacheFile();
    cacheFile.writeAsBytes(bytes);
    sharedPreferences.setString(keyDocumentSha, sha);
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
      final lastMod =
          sharedPreferences.getString(keyDocumentLastModified) ?? '';
      final documentSha = sharedPreferences.getString(keyDocumentSha) ?? '';
      final (code, sha, bytes) = await fetchFromGitHub(
        lastModified: lastMod,
        documentSha: documentSha,
      );

      final cacheFile = await _cacheFile();
      if (cacheFile.existsSync() && code == 304) {
        await processContentPostLoad(await cacheFile.readAsBytes());
      } else if (code == 200) {
        await cacheLocally(bytes!, sha!);
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
      final cacheFile = await _cacheFile();
      final bytes = await cacheFile.readAsBytes();
      final res = await pushToGitHubWithResponse(
        bytes,
        fileSha: retryServerFileSha,
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final fileSha = json.decode(res.body)["content"]["sha"].toString();
        await cacheLocally(bytes, fileSha);
      } else if (res.statusCode == 409) {
        final (code, serverFileSha, serverData) = await fetchFromGitHub();

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

  Future<(int, String?, Uint8List?)> fetchFromGitHub({
    String? lastModified,
    String? documentSha,
  }) async {
    final (dataUrl, headers, pass) = await _getFileInfoRequestData();

    final dataRes = await client.get(dataUrl, headers: headers);
    if (dataRes.statusCode == 200) {
      final dataBody = json.decode(dataRes.body);
      if (dataBody['encoding'] != 'base64' || dataBody['content'] == '') {
        final (blobUrl, headers, pass) = await _getBlobRequestData(
          documentSha: documentSha ?? dataBody['sha'],
        );
        final blobRes = await client.get(blobUrl, headers: headers);
        if (blobRes.statusCode == 200) {
          final (sha, bytes) = await _extractContent(dataBody, pass);
          return (blobRes.statusCode, sha, bytes);
        } else {
          return (blobRes.statusCode, null, null);
        }
      } else {
        final (sha, bytes) = await _extractContent(dataBody, pass);
        return (dataRes.statusCode, sha, bytes);
      }
    }

    return (dataRes.statusCode, null, null);
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
      if (documentSha != null && documentSha.isNotEmpty)
        'If-None-Match': documentSha,
      if (lastModified != null && lastModified.isNotEmpty)
        'If-Modified-Since': lastModified,
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
    final uri = Uri.parse(
      "https://api.github.com/repos/$repo/contents/$githubFilePath",
    );
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
    final uri = Uri.parse(
      'https://api.github.com/repos/$repo/git/blobs/$documentSha',
    );
    return (uri, headers, pass);
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationCacheDirectory();
    return File('${dir.path}/$localFileName');
  }
}
