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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';

import 'biometric_sync_service.dart';

class PreferencesBackupService {
  final _secureStorage = const FlutterSecureStorage();

  Future<String?> exportSystemPreferences() async {
    try {
      final p = await SharedPreferences.getInstance();

      final Map<String, dynamic> configBackup = {
        "backup_version": "2026.3",
        "timestamp": DateTime.now().toIso8601String(),

        "pdf_url": await _secureStorage.read(key: "pdf_download_url") ?? "",
        "pdf_password":
            await _secureStorage.read(key: "pdf_encryption_password") ?? "",
        "pdf_last_page": p.getInt('last_pdf_page') ?? 1,
        "pdf_local_path": p.getString('last_picked_local_path') ?? "",

        "git_json_repo":
            await _secureStorage.read(key: "git_repo_target") ?? "",
        "git_json_token":
            await _secureStorage.read(key: "git_access_token") ?? "",
        "git_json_password":
            await _secureStorage.read(key: "git_aes_password") ?? "",
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

        final prefs = await SharedPreferences.getInstance();

        // 1. Unpack Training Manual Credentials
        if (config.containsKey("pdf_url")) {
          await _secureStorage.write(
            key: "pdf_download_url",
            value: config["pdf_url"],
          );
        }
        if (config.containsKey("pdf_password")) {
          await _secureStorage.write(
            key: "pdf_encryption_password",
            value: config["pdf_password"],
          );
        }
        if (config["pdf_local_path"] != null &&
            config["pdf_local_path"] != "") {
          await prefs.setString(
            'last_picked_local_path',
            config["pdf_local_path"],
          );
        }
        await prefs.setInt('last_pdf_page', config["pdf_last_page"] ?? 1);

        if (config.containsKey("git_json_repo")) {
          await _secureStorage.write(
            key: "git_repo_target",
            value: config["git_json_repo"],
          );
        }
        if (config.containsKey("git_json_token")) {
          await _secureStorage.write(
            key: "git_access_token",
            value: config["git_json_token"],
          );
        }
        if (config.containsKey("git_json_password")) {
          await _secureStorage.write(
            key: "git_aes_password",
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
