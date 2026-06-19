/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

part of 'app_initialization_cubit.dart';

enum AppInitializationState {
  initialization,
  updateApp,
  showUpdateDetails,
  initialized,
  updateCheckFailed,
}

class AppInitializationStatus {
  final AppInitializationState state;
  String? baseUrl;
  String? downloadUrl;
  String? latestVersion;
  String? changeLog;
  String? error;

  AppInitializationStatus(
    this.state, {
    this.baseUrl,
    this.downloadUrl,
    this.latestVersion,
    this.changeLog,
    this.error,
  });
}
