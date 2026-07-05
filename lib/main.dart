/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';
import 'package:flutter_common/flutter_common.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'constants.dart';
import 'main_navigation.dart';
import 'mixins/github_syncer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  JustAudioMediaKit.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'homebackend.tennis.training.audio',
    androidNotificationChannelName: 'Tennis Training Tool Audio',
    androidNotificationOngoing: true,
    androidShowNotificationBadge: true,
    androidNotificationIcon: 'drawable/ic_bg_audio_icon',
  );

  await AudioNotifier.init();

  if (isDesktopPlatform()) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      title: "Tennis Training Tool",
      center: true,
      skipTaskbar: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.maximize();
      await windowManager.setTitle(appName);
    });
  }

  runApp(
    MainApp(
      githubOrganization,
      githubRepo,
      baseAssetName,
      appName,
      appIcon,
      () => MainNavigation(),
    ),
  );
}
