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
import 'package:http/http.dart';
import 'package:path_provider/path_provider.dart';

import '../mixins/github_syncer.dart';
import 'tracker_sync_service.dart';
import 'encrypt_decryt_service.dart';

mixin PdfLoaderService implements EncryptDecryptService, GitHubSyncer {
  static final _keyLastPickedLocalPath = 'last_picked_local_path';
  static final String keyLastPdfPage = 'last_pdf_page';
  static final String keyPdfIsModified = 'pdf_is_modified';
  static final String keyPdfDocumentSha = 'pdf_document_sha';
  static final String keyPdfLastModified = 'pdf_last_modified';

  StreamSubscription<void>? _pdfResyncSubscription;

  bool isLoading = true;
  bool isCheckingNetwork = false;
  int lastSavedPage = 1;
  String? localDecryptedPath;
  bool syncInProgress = false;

  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);

  Future<void> initPdfLoader() async {
    _loadLocalPreferences();

    _pdfResyncSubscription = TrackerSyncService.globalResyncTrigger.stream
        .listen((_) {
          if (mounted) {
            setState(() {
              isLoading = true;
            });
            _loadLocalPreferences();
          }
        });
  }

  void disposePdfLoader() {
    disposeSyncer();
    _pdfResyncSubscription?.cancel();
  }

  @override
  Client get client => Client();

  @override
  String get githubFilePath => 'tennis-coaching/$localFileName';

  @override
  bool get isModifiable => true;

  @override
  String get keyDocumentLastModified => keyPdfLastModified;

  @override
  String get keyDocumentSha => keyPdfDocumentSha;

  @override
  String get keyHasSyncDataModified => keyPdfIsModified;

  @override
  String get localFileName => 'training_manual.pdf';

  @override
  void notifySyncDone() {
    setState(() => syncInProgress = false);
  }

  @override
  void notifySyncFailed() {
    setState(() => syncInProgress = false);
  }

  @override
  void notifySyncStarted() {
    setState(() => syncInProgress = true);
  }

  @override
  Future<void> processConflicts(Uint8List serverData, String serverSha) async {}

  @override
  Future<void> processContentPostLoad(Uint8List content) async {
    final dir = await getApplicationCacheDirectory();
    setState(() {
      localDecryptedPath = '${dir.path}/$localFileName';
      lastSavedPage = 1;
    });
  }

  @override
  Future<void> syncDataLoader() async {}

  @override
  Duration get syncDuration => Duration(hours: 1);

  Future<void> _loadLocalPreferences() async {
    await initializeSyncer();

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> pickLocalDocument() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final bytes = await File(path).readAsBytes();
      await cacheLocally(bytes, appSha ?? '', appEtag ?? '');
      await processContentPostLoad(bytes);
      await sharedPreferences.setString(_keyLastPickedLocalPath, path);
      await sharedPreferences.setInt(keyLastPdfPage, 1);
      await setSyncDataModified(true);
      syncData();
    }
  }

  void showSnackBar(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void setUrlPassword(String url, String password);
  void setOutlineNotifierNull();
  void setCurrentPageNotifier(int value);
}
