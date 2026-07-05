/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:developer';

import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';

String getNewUuid() {
  return Uuid().v4();
}

class AudioNotifier {
  static const _basePath = 'sounds';
  static const _loadedFromNetwork = '$_basePath/loaded_from_network.mp3';
  static const _loadedFromCache = '$_basePath/loaded_from_cache.mp3';
  static const _errorOccurred = '$_basePath/error_occurred.mp3';
  static const _changeCurrentItem = '$_basePath/change_current_item.mp3';

  static final Map<String, AudioPlayer> _p = {};

  static Future<void> init() async {
    final sounds = [
      _loadedFromNetwork,
      _loadedFromCache,
      _errorOccurred,
      _changeCurrentItem,
    ];

    for (final path in sounds) {
      final player = AudioPlayer();
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setSource(AssetSource(path));
      await player.setVolume(1.0);
      await player.resume();
      await player.pause();
      await player.seek(Duration.zero);
      _p[path] = player;
    }
    log('AudioNotifier ready: ${_p.length} sounds');
  }

  static void loadedFromNetwork() => play(_loadedFromNetwork);
  static void loadedFromCache() => play(_loadedFromCache);
  static void errorOccurred() => play(_errorOccurred);
  static void changeCurrentItem() => play(_changeCurrentItem);

  static void play(String name) {
    final player = _p[name];
    if (player == null) return;
    log('Playing audio: $name');
    player.seek(Duration.zero);
    player.resume();
  }

  static void dispose() {
    for (final p in _p.values) {
      p.dispose();
    }
  }
}
