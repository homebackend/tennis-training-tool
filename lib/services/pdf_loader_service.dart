/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tracker_sync_service.dart';
import 'encrypt_decryt_service.dart';
import 'preferences_backup_service.dart';

mixin PdfLoaderService implements EncryptDecryptService {
  static final _keyUseLocalPdfPath = 'use_local_pdf_path';
  static final _keyLastPickedLocalPath = 'last_picked_local_path';
  static final _keyLastPdfPage = 'last_pdf_page';
  static final _keyPdfCachedLocalPath = 'pdf_cached_local_path';
  static final _keyPdfNetworkEtag = 'pdf_network_etag';

  FlutterSecureStorage get secureStorage;
  StreamSubscription<void>? _pdfResyncSubscription;
  Timer? _updateCheckTimer;

  bool isConfigured = false;
  bool isLoading = true;
  bool isCheckingNetwork = false;
  int lastSavedPage = 1;
  String? localDecryptedPath;

  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);

  void initPdfLoader() {
    _loadLocalPreferences();

    _pdfResyncSubscription = TrackerSyncService.globalResyncTrigger.stream
        .listen((_) {
          if (mounted) {
            setState(() {
              isConfigured = false;
              isLoading = true;
            });
            _loadLocalPreferences();
          }
        });

    _updateCheckTimer = Timer.periodic(const Duration(minutes: 5), (t) async {
      final prefs = await SharedPreferences.getInstance();

      if (!(prefs.getBool(_keyUseLocalPdfPath) ?? false)) {
        return;
      }

      final u = await secureStorage.read(
        key: PreferencesBackupService.keyPdfDownloadUrl,
      );
      final p = await secureStorage.read(
        key: PreferencesBackupService.keyPdfDownloadUrl,
      );
      if (u != null && p != null) {
        _syncEncryptedDocument(u, p, silentCheck: true);
      }
    });
  }

  void disposePdfLoader() {
    _pdfResyncSubscription?.cancel();
    _updateCheckTimer?.cancel();
  }

  Future<void> _saveFile(
    Uint8List encryptedBytes,
    String password,
    void Function() handler, {
    String? pdfNetworkEtag,
  }) async {
    final Uint8List decryptedBytes = await decryptBytes(
      encryptedBytes,
      password,
    );

    final dir = await getApplicationDocumentsDirectory();
    final localFile = File('${dir.path}/decrypted_manual.pdf');
    await localFile.writeAsBytes(decryptedBytes);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPdfCachedLocalPath, localFile.path);
    if (pdfNetworkEtag != null) {
      await prefs.setString(_keyPdfNetworkEtag, pdfNetworkEtag);
    }
    if (mounted) {
      setState(() {
        isConfigured = true;
        localDecryptedPath = localFile.path;
        handler();
      });
    }
  }

  Future<void> _initializeSyncPipeline(String urlStr, String password) async {
    try {
      final response = await http.get(Uri.parse(urlStr));
      if (response.statusCode == 200) {
        _saveFile(response.bodyBytes, password, () => isConfigured = true);
      } else {
        showSnackBar("Download failed: Status code ${response.statusCode}");
      }
    } catch (e) {
      showSnackBar("Sync pipeline error: $e");
    }
  }

  Future<void> _loadLocalPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    if ((prefs.getBool(_keyUseLocalPdfPath) ?? false)) {
      final prefs = await SharedPreferences.getInstance();
      String path = prefs.getString(_keyLastPickedLocalPath) ?? '';
      int page = prefs.getInt(_keyLastPdfPage) ?? 1;
      setState(() {
        localDecryptedPath = path;
        lastSavedPage = page;
        isConfigured = true;
      });
      return;
    }

    final savedUrl = await secureStorage.read(
      key: PreferencesBackupService.keyPdfDownloadUrl,
    );
    final savedPassword = await secureStorage.read(
      key: PreferencesBackupService.keyEncPwd,
    );

    if (savedUrl != null && savedPassword != null) {
      setUrlPassword(savedUrl, savedPassword);

      final lastCachedPath = prefs.getString(_keyPdfCachedLocalPath);
      if (lastCachedPath != null && await File(lastCachedPath).exists()) {
        // A local cached copy of file exists
        setState(() {
          localDecryptedPath = lastCachedPath;
          lastSavedPage = prefs.getInt(_keyLastPdfPage) ?? 1;
          isConfigured = true;
        });
      } else {
        // A local cached copy doesn't exist so load it again
        await _initializeSyncPipeline(savedUrl, savedPassword);
      }
    }

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> pickLocalDocument() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastPickedLocalPath, path);
      await prefs.setInt(_keyLastPdfPage, 1);
      await prefs.setBool(_keyUseLocalPdfPath, true);

      setState(() {
        isConfigured = true;
        localDecryptedPath = path;
        lastSavedPage = 1;
        setCurrentPageNotifier(1);
        setOutlineNotifierNull();
      });
    }
  }

  Future<void> saveConfigAndFetch(String url, String password) async {
    if (url.isEmpty || password.isEmpty) return;
    TrackerSyncService.globalResyncTrigger.add(null);
    setState(() => isLoading = true);
    await secureStorage.write(
      key: PreferencesBackupService.keyPdfDownloadUrl,
      value: url,
    );
    await secureStorage.write(
      key: PreferencesBackupService.keyEncPwd,
      value: password,
    );

    await _syncEncryptedDocument(url, password);
    setState(() => isLoading = false);
  }

  Future<void> _syncEncryptedDocument(
    String url,
    String password, {
    bool silentCheck = false,
  }) async {
    if (!silentCheck) setState(() => isCheckingNetwork = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyUseLocalPdfPath, false);
      final etag = prefs.getString(_keyPdfNetworkEtag) ?? '';
      final resp = await http.get(
        Uri.parse(url),
        headers: {if (etag.isNotEmpty) 'If-None-Match': etag},
      );

      if (resp.statusCode == 304) {
        final cachedLocalPath = prefs.getString(_keyPdfCachedLocalPath);
        if (cachedLocalPath != null && await File(cachedLocalPath).exists()) {
          setState(() {
            isConfigured = true;
            localDecryptedPath = cachedLocalPath;
          });
          return;
        }
      }

      if (resp.statusCode == 200) {
        _saveFile(
          resp.bodyBytes,
          password,
          setOutlineNotifierNull,
          pdfNetworkEtag:
              resp.headers['etag'] ?? resp.headers['last-modified'] ?? 'valid',
        );
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
    } finally {
      if (!silentCheck) setState(() => isCheckingNetwork = false);
    }
  }

  void showSnackBar(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void setUrlPassword(String url, String password);
  void setOutlineNotifierNull();
  void setCurrentPageNotifier(int value);
}
