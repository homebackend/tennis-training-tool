/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../mixins/github_syncer.dart';
import 'encrypt_decryt_service.dart';

class ScheduleSyncService with EncryptDecryptService, GitHubSyncer {
  static final keySchedLastmod = 'sched_lastmod';
  static final keySchedSha = 'sched_sha';
  static final keySchedHasModified = 'sched_has_modified';

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _sharedPreferences;
  final http.Client _client;
  final void Function() syncNotifier;
  final void Function() syncDoneNotifier;
  final Future<void> Function(ScheduleSyncService self) loader;
  ScheduleSyncService(
    this._secureStorage,
    this._sharedPreferences,
    this.syncNotifier,
    this.syncDoneNotifier,
    this.loader, {
    http.Client? client,
  }) : _client = client ?? http.Client();

  String? yaml;

  @override
  http.Client get client => _client;

  @override
  String get githubFilePath => 'tennis-coaching/$localFileName';

  @override
  bool get isModifiable => false;

  @override
  String get keyDocumentLastModified => keySchedLastmod;

  @override
  String get keyDocumentSha => keySchedSha;

  @override
  String get keyHasSyncDataModified => keySchedHasModified;

  @override
  String get localFileName => 'training_schedule.yaml';

  @override
  void notifySyncDone() => syncDoneNotifier();

  @override
  void notifySyncFailed() => syncDoneNotifier();

  @override
  void notifySyncStarted() => syncNotifier();

  @override
  Future<void> processConflicts(Uint8List serverData, String serverSha) async {}

  @override
  Future<void> processContentPostLoad(Uint8List content) async {
    yaml = utf8.decode(content);
  }

  @override
  FlutterSecureStorage get secureStorage => _secureStorage;

  @override
  SharedPreferences get sharedPreferences => _sharedPreferences;

  @override
  Future<void> syncDataLoader() async {
    await loader(this);
  }

  @override
  Duration get syncDuration => Duration(minutes: 30);
}
