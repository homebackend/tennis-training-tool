/*
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_common/mixin/encrypt_decryt_service.dart';
import 'package:flutter_common/mixin/syncer_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../mixins/github_syncer.dart';
import 'tracker_sync_service.dart';

class PdfListSyncerService
    with
        EncryptDecryptService,
        SyncerCore,
        GitHubSyncer,
        WidgetsBindingObserver {
  static final String keyAdditionalPdfListIsModified =
      'additional_pdf_list_is_modified';
  static final String keyAdditionalPdfListLastModified =
      'additional_pdf_list_last_modified';
  static final String keyAdditionalPdfListSha = 'additional_pdf_list_sha';

  @override
  FlutterSecureStorage secureStorage;
  @override
  SharedPreferences sharedPreferences;

  List<String> allFiles = [];
  StreamSubscription<void>? _listResyncSubscription;

  PdfListSyncerService(this.secureStorage, this.sharedPreferences);

  Future<void> initListLoad() async {
    await initializeSyncer();
    _listResyncSubscription = TrackerSyncService.globalResyncTrigger.stream
        .listen((_) {
          initializeSyncer();
        });
  }

  void dispose() {
    _listResyncSubscription?.cancel();
  }

  @override
  Client get client => Client();

  @override
  String get githubFilePath => '$documentPath/$localFileName';

  @override
  bool get isModifiable => true;

  @override
  String get keyDocumentLastModified => keyAdditionalPdfListLastModified;

  @override
  String get keyDocumentSha => keyAdditionalPdfListSha;

  @override
  String get keyHasSyncDataModified => keyAdditionalPdfListIsModified;

  @override
  String get localFileName => 'additional_files.lst';

  @override
  void notifySyncDone() {}

  @override
  void notifySyncFailed() {}

  @override
  void notifySyncStarted() {}

  @override
  Future<void> processConflicts(Uint8List serverData, String serverSha) async {
    final serverFiles = _parseLines(serverData);
    Set<String> files = {};
    files.addAll(allFiles);
    files.addAll(serverFiles);
    allFiles = files.toList()..sort();
    pushToGitHubWithAutoMerge(retryServerFileSha: serverSha, background: false);
  }

  @override
  Future<void> processContentPostLoad(Uint8List content) async {
    allFiles = _parseLines(content);
  }

  @override
  Future<Uint8List> getContentsForWrite() async {
    return Uint8List.fromList(utf8.encode(allFiles.join('\n')));
  }

  @override
  Future<void> syncDataLoader() async {}

  @override
  Duration get syncDuration => Duration(hours: 1);

  List<String> _parseLines(Uint8List content) {
    if (content.isEmpty) return [];
    final text = utf8.decode(content, allowMalformed: true);
    return const LineSplitter()
        .convert(text)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> addFile(String fileName) async {
    final Set<String> files = {};
    files.addAll(allFiles);
    files.add(fileName);
    allFiles = files.toList()..sort();
    await setSyncDataModified(true);
    syncData(force: true);
  }
}
