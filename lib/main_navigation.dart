/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/audio_player_page.dart';
import 'pages/schedule_page.dart';
import 'pages/tracker_sync_page.dart';
import 'pages/pdf_viewer_page.dart';
import 'services/preferences_backup_service.dart';
import 'widgets/app_setup.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  bool _initialized = false;
  bool _requireSetup = false;
  int _currentIndex = 0;
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  Future<void> _initialize() async {
    SharedPreferences sharedPreferences = await SharedPreferences.getInstance();

    _pages = [
      SchedulePage(secureStorage, sharedPreferences),
      PdfViewerPage(secureStorage, sharedPreferences),
      const AudioPlayerPage(),
      TrackerSyncPage(secureStorage, sharedPreferences),
    ];

    await PreferencesBackupService(secureStorage).upgradePreferences();
    final gitRepo = await secureStorage.read(
      key: PreferencesBackupService.keyGitRepo,
    );
    final gitToken = await secureStorage.read(
      key: PreferencesBackupService.keyGitToken,
    );
    final encryptionPassword = await secureStorage.read(
      key: PreferencesBackupService.keyEncPwd,
    );
    setState(() {
      _initialized = true;
      if (gitRepo == null || gitToken == null || encryptionPassword == null) {
        _requireSetup = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return CircularProgressIndicator();
    }

    if (_requireSetup) {
      return AppSetup(
        PreferencesBackupService(secureStorage),
        (String gitRepo, String gitToken, String password) async {
          await secureStorage.write(
            key: PreferencesBackupService.keyGitRepo,
            value: gitRepo,
          );
          await secureStorage.write(
            key: PreferencesBackupService.keyGitToken,
            value: gitToken,
          );
          await secureStorage.write(
            key: PreferencesBackupService.keyEncPwd,
            value: password,
          );
          setState(() => _requireSetup = false);
        },
        () => setState(() => _requireSetup = false),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.schedule),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.picture_as_pdf),
            label: 'PDF',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.music_note), label: 'Audio'),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            label: 'Athlete Tracker',
          ),
        ],
      ),
    );
  }
}
