/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:developer';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  final FlutterSecureStorage secureStorage;

  PreferencesBackupService(this.secureStorage);

  Future<void> upgradePreferences(Map<String, dynamic> config) async {
    for (final key in [keyGitRepo, keyGitToken, keyEncPwd]) {
      if (config[key] == null) {
        if (_keyMappings.containsKey(key)) {
          for (final xKey in _keyMappings[key]!) {
            final value = await secureStorage.read(key: xKey);
            if (value != null) {
              await secureStorage.write(key: key, value: value);
            }
          }
        }
      }

      if (_keyMappings.containsKey(key)) {
        for (final xKey in _keyMappings[key]!) {
          if (await secureStorage.containsKey(key: xKey)) {
            log('Deleting $xKey as $key is used now.');
            await secureStorage.delete(key: xKey);
          }
        }
      }
    }

    for (final key in _keysToBeDeleted) {
      if (await secureStorage.containsKey(key: key)) {
        log('Deleting $key as it is no longer used now.');
        await secureStorage.delete(key: key);
      }
    }
  }
}
