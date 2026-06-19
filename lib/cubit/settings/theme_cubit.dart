/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_state.dart';

class ThemeCubit extends Cubit<ThemeState> {
  static final ThemeData _dark = ThemeData.dark();
  static final ThemeData _light = ThemeData.light();

  static final String prefUseDarkTheme = 'useDarkTheme';

  ThemeCubit() : super(ThemeState(_light));

  void toggleTheme(bool useDarkTheme) {
    _toggleTheme(useDarkTheme);
    _saveState(useDarkTheme);
  }

  void _toggleTheme(bool useDarkTheme) {
    if (useDarkTheme) {
      emit(ThemeState(_dark));
    } else {
      emit(ThemeState(_light));
    }
  }

  void _saveState(bool useDarkTheme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefUseDarkTheme, useDarkTheme);
  }

  static Future<bool> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefUseDarkTheme) ?? false;
  }

  Future<void> setInitialTheme() async {
    _toggleTheme(await _loadTheme());
  }
}
