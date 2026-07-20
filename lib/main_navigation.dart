/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';
import 'package:flutter_common/main_with_app_setup.dart';
import 'package:flutter_common/mixin/main_config_manager.dart';
import 'package:flutter_common/widgets/app_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/audio_player_page.dart';
import 'pages/schedule_page.dart';
import 'pages/tracker_sync_page.dart';
import 'pages/pdf_viewer_page.dart';
import 'services/preferences_backup_service.dart';
import 'services/tracker_sync_service.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends MainWithAppSetupState<MainNavigation>
    with MainConfigManager {
  static final List<AppSetupField> _appSetupFields = [
    AppSetupField(
      PreferencesBackupService.keyGitRepo,
      'GitHub Repository Target (owner/repo)',
      false,
    ),
    AppSetupField(
      PreferencesBackupService.keyGitToken,
      'GitHub PAT Token',
      false,
    ),
    AppSetupField(
      PreferencesBackupService.keyEncPwd,
      'AES Decryption Key/Password',
      true,
    ),
  ];

  int _currentIndex = 0;
  late final List<Widget> _pages;

  @override
  List<AppSetupField> get appSetupFields => _appSetupFields;

  @override
  void notifyConfigReload() {
    TrackerSyncService.globalResyncTrigger.add(null);
  }

  @override
  Future<void> initializeState(SharedPreferences sharedPreferences) async {
    _pages = [
      SchedulePage(secureStorage, sharedPreferences, this),
      PdfViewerPage(secureStorage, sharedPreferences, this),
      const AudioPlayerPage(),
      TrackerSyncPage(secureStorage, sharedPreferences, this),
    ];

    await PreferencesBackupService(
      secureStorage,
    ).upgradePreferences(await getConfigValues());
  }

  @override
  Widget buildMainApp(BuildContext context) => Scaffold(
    body: IndexedStack(index: _currentIndex, children: _pages),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _currentIndex,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.blue,
      unselectedItemColor: Colors.grey,
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_view_day),
          activeIcon: Icon(Icons.calendar_view_day_outlined),
          label: 'Schedule',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.picture_as_pdf), label: 'PDF'),
        BottomNavigationBarItem(icon: Icon(Icons.music_note), label: 'Audio'),
        BottomNavigationBarItem(
          icon: Icon(Icons.analytics_outlined),
          label: 'Athlete Tracker',
        ),
      ],
    ),
  );
}
