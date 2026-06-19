/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void showSnackBar(BuildContext context, String message, {Duration? timeout}) {
  final snackBar = SnackBar(
    content: Text(message),
    duration: timeout ?? const Duration(seconds: 3),
    persist: false,
    action: SnackBarAction(label: 'Ok', onPressed: () {}),
  );
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}

bool isDesktopPlatform() =>
    !kIsWeb && (isLinuxPlatform() || isWindowsPlatform() || isMacOSPlatform());
bool isWindowsPlatform() => Platform.isWindows;
bool isLinuxPlatform() => Platform.isLinux;
bool isMacOSPlatform() => Platform.isMacOS;
bool isMobilePlatform() => !kIsWeb && (isAndroidPlatform() || isIOSPlatform());
bool isAndroidPlatform() => !kIsWeb && Platform.isAndroid;
bool isIOSPlatform() => !kIsWeb && Platform.isIOS;
bool isWebPlatform() => kIsWeb;

bool isArchLinuxDistribution() {
  try {
    final File osReleaseFile = File('/etc/os-release');
    if (osReleaseFile.existsSync()) {
      final String contents = osReleaseFile.readAsStringSync().toLowerCase();

      return contents.contains('id=arch') ||
          contents.contains('id=manjaro') ||
          contents.contains('id_like=arch');
    }
  } catch (e) {
    log('Failed inspecting system distribution configuration settings: $e');
  }
  return false;
}
