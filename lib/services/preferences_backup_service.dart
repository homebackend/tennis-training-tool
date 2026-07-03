/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';

import 'tracker_sync_service.dart';

class PreferencesBackupService {
  static final keyGitRepo = 'git_repo';
  static final keyGitToken = 'git_token';
  static final keyEncPwd = 'encryption_token';

  static final Map<String, List<String>> _keyMappings = {
    keyGitRepo: ['git_json_repo', 'git_repo_target'],
    keyGitToken: ['git_json_token', 'git_access_token'],
    keyEncPwd: [
      'pdf_encryption_password',
      'git_aes_password',
      'git_json_password',
    ],
  };
  static final List<String> _keysToBeDeleted = [
    'pdf_download_url',
    'schedule_yaml_url',
  ];
  final FlutterSecureStorage _secureStorage;

  PreferencesBackupService(this._secureStorage);

  Future<void> upgradePreferences() async {
    final config = await _getValues();
    for (final key in [keyGitRepo, keyGitToken, keyEncPwd]) {
      if (config[key] == null) {
        if (_keyMappings.containsKey(key)) {
          for (final xKey in _keyMappings[key]!) {
            final value = await _secureStorage.read(key: xKey);
            if (value != null) {
              await _secureStorage.write(key: key, value: value);
            }
          }
        }
      }

      if (_keyMappings.containsKey(key)) {
        for (final xKey in _keyMappings[key]!) {
          if (await _secureStorage.containsKey(key: xKey)) {
            log('Deleting $xKey as $key is used now.');
            await _secureStorage.delete(key: xKey);
          }
        }
      }
    }

    for (final key in _keysToBeDeleted) {
      if (await _secureStorage.containsKey(key: key)) {
        log('Deleting $key as it is no longer used now.');
        await _secureStorage.delete(key: key);
      }
    }
  }

  Future<Map<String, dynamic>> _getValues() async {
    final gitRepo = await _secureStorage.read(key: keyGitRepo);
    final gitToken = await _secureStorage.read(key: keyGitToken);
    final encryptionPassword = await _secureStorage.read(key: keyEncPwd);

    final Map<String, dynamic> configBackup = {
      "backup_version": "2026.5",
      "timestamp": DateTime.now().toIso8601String(),
      keyGitRepo: gitRepo,
      keyGitToken: gitToken,
      keyEncPwd: encryptionPassword,
    };

    return configBackup;
  }

  Future<String?> exportSystemPreferences() async {
    try {
      final configBackup = await _getValues();
      final String jsonString = json.encode(configBackup);
      final Uint8List fileBytes = Uint8List.fromList(utf8.encode(jsonString));

      final String? outputPath = await FilePicker.saveFile(
        dialogTitle: 'Export Configuration Settings',
        fileName: 'tennis_tool_config_backup.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: fileBytes,
      );

      if (outputPath != null) {
        await File(outputPath).writeAsBytes(fileBytes);
        return "Configuration keys backed up cleanly!";
      }
    } catch (e) {
      return "Export failed: $e";
    }
    return null;
  }

  Future<String?> importSystemPreferences() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final File selectedFile = File(result.files.single.path!);
        final Map<String, dynamic> config = json.decode(
          await selectedFile.readAsString(),
        );

        for (final key in [keyGitRepo, keyGitToken, keyEncPwd]) {
          if (config.containsKey(key)) {
            await _secureStorage.write(key: key, value: config[key]);
          }
        }

        TrackerSyncService.globalResyncTrigger.add(null);
        return null;
      } else {
        return 'Import failed: No file selected';
      }
    } catch (e) {
      return "Import failed: Invalid configuration template. $e";
    }
  }
}
