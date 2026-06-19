/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ota_update/ota_update.dart';

import '../../constants.dart' as constants;

part 'app_update_state.dart';

class AppUpdateCubit extends Cubit<AppUpdateStatus> {
  AppUpdateCubit() : super(AppUpdateStatus(AppUpdateState.userInput));

  Future<void> tryOtaUpdate(String downloadUrl) async {
    try {
      log('Download url: $downloadUrl');
      OtaUpdate()
          .execute(downloadUrl, destinationFilename: constants.upgradeFileName)
          .listen((OtaEvent event) {
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
              case OtaStatus.INSTALLING:
                emit(AppUpdateStatus(AppUpdateState.inProgress, event: event));
              case OtaStatus.INSTALLATION_DONE:
                log('Installation done. Ideally this should never come');
              case OtaStatus.ALREADY_RUNNING_ERROR:
              case OtaStatus.INSTALLATION_ERROR:
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              case OtaStatus.INTERNAL_ERROR:
              case OtaStatus.DOWNLOAD_ERROR:
              case OtaStatus.CHECKSUM_ERROR:
              case OtaStatus.CANCELED:
                emit(
                  AppUpdateStatus(
                    AppUpdateState.error,
                    error: event.status.toString(),
                  ),
                );
            }
          });
    } catch (e) {
      emit(AppUpdateStatus(AppUpdateState.error, error: e.toString()));
    }
  }

  void skipUpdate() {
    emit(AppUpdateStatus(AppUpdateState.skipped));
  }
}
