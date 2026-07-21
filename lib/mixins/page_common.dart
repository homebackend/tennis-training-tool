/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';
import 'package:flutter_common/mixin/main_config_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tennis_training_tool/services/preferences_backup_service.dart';

mixin PageCommon {
  bool get mounted;
  BuildContext get context;
  FlutterSecureStorage get secureStorage;

  late final PreferencesBackupService backupService = PreferencesBackupService(
    secureStorage,
  );

  void showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  List<Widget> getAppBarCommonActions(MainConfigManager configManager) => [
    IconButton(
      icon: const Icon(Icons.output),
      tooltip: 'Export Settings',
      onPressed: () async {
        final msg = await configManager.exportSystemPreferences();
        if (msg != null) showSnackBar(msg);
      },
    ),
  ];
}
