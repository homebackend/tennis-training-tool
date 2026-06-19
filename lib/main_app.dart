/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'cubit/settings/theme_cubit.dart';
import 'cubit/startup/app_initialization_cubit.dart';
import 'main_navigation.dart';
import 'splash.dart';
import 'tool.dart';
import 'update_app.dart';
import 'widgets/app_update_detailer.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeCubit()..setInitialTheme()),
        BlocProvider(create: (_) => AppInitializationCubit()..initialize()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (_, themeState) => MaterialApp(
          title: 'Netr',
          debugShowCheckedModeBanner: false,
          theme: themeState.data,
          home: ScaffoldMessenger(
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  return MultiBlocListener(
                    listeners: [
                      BlocListener<
                        AppInitializationCubit,
                        AppInitializationStatus
                      >(
                        listenWhen: (_, current) =>
                            current.state ==
                            AppInitializationState.showUpdateDetails,
                        listener: (context, status) {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (dialogContext) => AppUpdateDialog(
                              downloadUrl: status.downloadUrl,
                              latestVersion: status.latestVersion,
                              changeLog: status.changeLog,
                            ),
                          );
                        },
                      ),
                      BlocListener<
                        AppInitializationCubit,
                        AppInitializationStatus
                      >(
                        listenWhen: (_, current) =>
                            current.state ==
                            AppInitializationState.updateCheckFailed,
                        listener: (_, status) {
                          log(
                            'Error during check for App update: ${status.error}',
                          );
                          showSnackBar(
                            context,
                            'Unable to check for App update',
                          );
                        },
                      ),
                    ],
                    child:
                        BlocBuilder<
                          AppInitializationCubit,
                          AppInitializationStatus
                        >(
                          builder: (context, status) {
                            switch (status.state) {
                              case AppInitializationState.initialization:
                                return const SplashScreen();
                              case AppInitializationState.showUpdateDetails:
                                return const MainNavigation();
                              case AppInitializationState.updateApp:
                                return UpdateApp(
                                  status.downloadUrl,
                                  status.latestVersion,
                                  status.changeLog,
                                  () => context
                                      .read<AppInitializationCubit>()
                                      .emitInitialized(),
                                );
                              case AppInitializationState.initialized:
                                return const MainNavigation();
                              case AppInitializationState.updateCheckFailed:
                                return const MainNavigation();
                            }
                          },
                        ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
