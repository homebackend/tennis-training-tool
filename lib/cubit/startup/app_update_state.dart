/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

part of 'app_update_cubit.dart';

enum AppUpdateState { userInput, inProgress, skipped, error }

class AppUpdateStatus {
  final AppUpdateState state;
  OtaEvent? event;
  String? error;
  AppUpdateStatus(this.state, {this.event, this.error});
}
