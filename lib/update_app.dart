/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../constants.dart' as constants;
import '../cubit/startup/app_update_cubit.dart';
import '../widgets/app_update_detailer.dart';
import '../tool.dart';

class UpdateApp extends StatefulWidget {
  final String? downloadUrl;
  final String? latestVersion;
  final String? changeLog;
  final void Function() back;

  const UpdateApp(
    this.downloadUrl,
    this.latestVersion,
    this.changeLog,
    this.back, {
    super.key,
  });

  @override
  State<UpdateApp> createState() => _UpdateAppState();
}

class _UpdateAppState extends State<UpdateApp> {
  late final AppUpdateCubit _updateCubit;

  @override
  void initState() {
    super.initState();
    _updateCubit = AppUpdateCubit();

    if (_updateCubit.state.state == AppUpdateState.userInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showUpdateDialog(context);
      });
    }
  }

  @override
  void dispose() {
    _updateCubit.close();
    super.dispose();
  }

  void _showUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AppUpdateDialog(
        downloadUrl: widget.downloadUrl,
        latestVersion: widget.latestVersion,
        changeLog: widget.changeLog,
        onProceed: widget.downloadUrl != null
            ? () {
                _updateCubit.tryOtaUpdate(widget.downloadUrl!);
              }
            : null,
        onDismiss: widget.back,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AppUpdateCubit>.value(
      value: _updateCubit,
      child: BlocListener<AppUpdateCubit, AppUpdateStatus>(
        listenWhen: (previous, current) => previous.state != current.state,
        listener: (context, state) {
          if (state.state == AppUpdateState.userInput) {
            _showUpdateDialog(context);
          } else if (state.state == AppUpdateState.skipped) {
            widget.back();
          } else if (state.state == AppUpdateState.error) {
            widget.back();
            showSnackBar(
              context,
              'Failed to make OTA update. Details: ${state.error}',
            );
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text(constants.appName),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.back,
            ),
          ),
          body: BlocBuilder<AppUpdateCubit, AppUpdateStatus>(
            builder: (context, status) {
              switch (status.state) {
                case AppUpdateState.userInput:
                  return const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: "Waiting for user input",
                    ),
                  );
                case AppUpdateState.inProgress:
                  final event = status.event;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Update in progress. Current status:\n${event?.status ?? "Processing"} : ${event?.value ?? ""}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  );
                case AppUpdateState.skipped:
                case AppUpdateState.error:
                  return const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Waiting for App Load',
                    ),
                  );
              }
            },
          ),
        ),
      ),
    );
  }
}
