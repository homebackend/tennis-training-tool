/*
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_common/app_logger.dart';
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
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          usageType: AndroidUsageType.assistanceSonification,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );

    for (final path in [
      _loadedFromNetwork,
      _loadedFromCache,
      _errorOccurred,
      _changeCurrentItem,
    ]) {
      final player = AudioPlayer();
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(AssetSource(path));
      await player.setVolume(1.0);
      _p[path] = player;
    }
    appLogger.d('AudioNotifier ready: ${_p.length} sounds');
  }

  static void loadedFromNetwork() => play(_loadedFromNetwork);
  static void loadedFromCache() => play(_loadedFromCache);
  static void errorOccurred() => play(_errorOccurred);
  static void changeCurrentItem() => play(_changeCurrentItem);

  static void play(String name) {
    final player = _p[name];
    if (player == null) return;
    appLogger.d('Playing audio: $name');
    player.stop().then((_) => player.resume());
  }
}

String timeAgo(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.isNegative) return 'just now';

  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }

  final weeks = (diff.inDays / 7).floor();
  if (weeks < 5) return '$weeks week${weeks == 1 ? '' : 's'} ago';

  final months = (diff.inDays / 30).floor();
  if (months < 12) return '$months month${months == 1 ? '' : 's'} ago';

  final years = (diff.inDays / 365).floor();
  return '$years year${years == 1 ? '' : 's'} ago';
}
