/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';

import 'biometric_sync_service.dart';

class PreferencesBackupService {
  static final keyPdfDownloadUrl = 'pdf_download_url';
  static final keyPdfEncryptionPassword = 'pdf_encryption_password';
  static final keyGitRepoTarget = 'git_repo_target';
  static final keyGitAccessToken = 'git_access_token';
  static final keyGitAesPassword = 'git_aes_password';

  final FlutterSecureStorage _secureStorage;

  PreferencesBackupService(this._secureStorage);

  Future<String?> exportSystemPreferences() async {
    try {
      final Map<String, dynamic> configBackup = {
        "backup_version": "2026.3",
        "timestamp": DateTime.now().toIso8601String(),

        "pdf_url": await _secureStorage.read(key: keyPdfDownloadUrl) ?? "",
        "pdf_password":
            await _secureStorage.read(key: keyPdfEncryptionPassword) ?? "",

        "git_json_repo": await _secureStorage.read(key: keyGitRepoTarget) ?? "",
        "git_json_token":
            await _secureStorage.read(key: keyGitAccessToken) ?? "",
        "git_json_password":
            await _secureStorage.read(key: keyGitAesPassword) ?? "",
      };

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

        if (config.containsKey("pdf_url")) {
          await _secureStorage.write(
            key: keyPdfDownloadUrl,
            value: config["pdf_url"],
          );
        }
        if (config.containsKey("pdf_password")) {
          await _secureStorage.write(
            key: keyPdfEncryptionPassword,
            value: config["pdf_password"],
          );
        }

        if (config.containsKey("git_json_repo")) {
          await _secureStorage.write(
            key: keyGitRepoTarget,
            value: config["git_json_repo"],
          );
        }
        if (config.containsKey("git_json_token")) {
          await _secureStorage.write(
            key: keyGitAccessToken,
            value: config["git_json_token"],
          );
        }
        if (config.containsKey("git_json_password")) {
          await _secureStorage.write(
            key: keyGitAesPassword,
            value: config["git_json_password"],
          );
        }

        BiometricSyncService.globalResyncTrigger.add(null);

        return "Configuration imported! Workspace pipelines successfully refreshed.";
      }
    } catch (e) {
      return "Import failed: Invalid configuration template. $e";
    }
    return null;
  }
}
