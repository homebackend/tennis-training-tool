import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'main_navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  JustAudioMediaKit.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'homebackend.tennis.training.audio',
    androidNotificationChannelName: 'Tennis Audio Playback',
    androidNotificationOngoing: true,
    androidNotificationIcon: 'ic_bg_audio_icon',
  );

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
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
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: MainNavigation());
  }
}
