/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

class AudioPlayerPage extends StatefulWidget {
  const AudioPlayerPage({super.key});

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  late AudioPlayer _audioPlayer;
  List<dynamic> _audioList = [];
  String? _currentPlayingFile;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _loadAudioData();
    _setupAudioEventListeners();

    _audioPlayer.durationStream.listen((Duration? dynamicDuration) {
      if (dynamicDuration != null) {
        log(
          "Actual file duration resolved: ${dynamicDuration.inSeconds} seconds",
        );
      }
    });
  }

  void _setupAudioEventListeners() {
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _audioPlayer.stop();
      }
    });
  }

  Future<void> _loadAudioData() async {
    final String response = await rootBundle.loadString('assets/mapping.json');
    setState(() {
      _audioList = json.decode(response);
    });
  }

  Future<void> _handlePlayback(Map<String, dynamic> item) async {
    final fileAssetPath = item['file'];

    if (_currentPlayingFile == fileAssetPath) {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    } else {
      await _audioPlayer.stop();

      try {
        await _loadTrackAndSyncControls(
          fileAssetPath,
          "Tennis Training Tool",
          item['display'],
        );
        setState(() => _currentPlayingFile = fileAssetPath);
        await _audioPlayer.play();
      } catch (e) {
        debugPrint("Error loading audio asset: $e");
      }
    }
  }

  Future<Duration?> _loadTrack(
    String fileAssetPath,
    String album,
    String title, {
    Duration? duration,
  }) {
    return _audioPlayer.setAudioSource(
      AudioSource.asset(
        fileAssetPath,
        tag: MediaItem(
          id: fileAssetPath,
          album: album,
          title: title,
          duration: duration,
        ),
      ),
    );
  }

  Future<void> _loadTrackAndSyncControls(
    String fileAssetPath,
    String album,
    String title,
  ) async {
    try {
      final Duration? trackDuration = await _loadTrack(
        fileAssetPath,
        album,
        title,
      );

      if (trackDuration != null) {
        await _loadTrack(fileAssetPath, album, title, duration: trackDuration);
      }
    } catch (e) {
      log("Audio metadata parse error: $e");
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audio Assets')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _audioList.length,
              itemBuilder: (context, index) {
                final item = _audioList[index];
                final isThisItemActive = _currentPlayingFile == item['file'];

                return StreamBuilder<PlayerState>(
                  stream: _audioPlayer.playerStateStream,
                  builder: (context, snapshot) {
                    final isPlaying = _audioPlayer.playing && isThisItemActive;

                    return ListTile(
                      leading: Icon(
                        isPlaying
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(
                        item['display'],
                        style: TextStyle(
                          fontWeight: isThisItemActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                            ),
                            iconSize: 32,
                            onPressed: () => _handlePlayback(item),
                          ),
                          if (isThisItemActive)
                            IconButton(
                              icon: const Icon(Icons.stop_circle),
                              iconSize: 32,
                              onPressed: () {
                                _audioPlayer.stop();
                              },
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          StreamBuilder<PlayerState>(
            stream: _audioPlayer.playerStateStream,
            builder: (context, snapshot) {
              final isIdle =
                  snapshot.data?.processingState == ProcessingState.idle;
              return (_currentPlayingFile != null && !isIdle)
                  ? _buildMiniController()
                  : const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMiniController() {
    return StreamBuilder<PlayerState>(
      stream: _audioPlayer.playerStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final playing = state?.playing ?? false;
        final isIdle = state?.processingState == ProcessingState.idle;
        final enabled = !isIdle;

        return Container(
          color: Colors.blueGrey.shade50,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10),
                onPressed: enabled
                    ? () => _audioPlayer.seek(
                        _audioPlayer.position - const Duration(seconds: 10),
                      )
                    : null,
              ),
              StreamBuilder<Duration>(
                stream: _audioPlayer.createPositionStream(
                  steps: 20,
                  minPeriod: const Duration(milliseconds: 200),
                  maxPeriod: const Duration(milliseconds: 500),
                ),
                builder: (context, snapshot) {
                  final position = snapshot.data ?? _audioPlayer.position;
                  final duration = _audioPlayer.duration ?? Duration.zero;
                  return Text(
                    "${position.toString().split('.').first} / ${duration.toString().split('.').first}",
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.forward_10),
                onPressed: enabled
                    ? () => _audioPlayer.seek(
                        _audioPlayer.position + const Duration(seconds: 10),
                      )
                    : null,
              ),
              IconButton(
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: () =>
                    playing ? _audioPlayer.pause() : _audioPlayer.play(),
              ),
            ],
          ),
        );
      },
    );
  }
}
