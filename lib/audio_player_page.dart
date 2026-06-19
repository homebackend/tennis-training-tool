import 'dart:convert';
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
  }

  void _setupAudioEventListeners() {
    // Stop playback immediately at track end (prevents repeat or auto-advance)
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

      // Load local asset bundle and pipe metadata to lock screen system
      final audioSource = AudioSource.asset(
        fileAssetPath,
        tag: MediaItem(
          id: fileAssetPath,
          album: "Local Audio Library",
          title: item['display'],
          // Optional: Add a local artwork image asset for the lock screen background
          // artUri: Uri.parse('asset:///assets/lockscreen_art.png'),
        ),
      );

      try {
        await _audioPlayer.setAudioSource(audioSource);
        setState(() => _currentPlayingFile = fileAssetPath);
        await _audioPlayer.play();
      } catch (e) {
        debugPrint("Error loading audio asset: $e");
      }
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
                                setState(() => _currentPlayingFile = null);
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
          // Persistent Bottom Mini-Controller for seek controls
          if (_currentPlayingFile != null) _buildMiniController(),
        ],
      ),
    );
  }

  Widget _buildMiniController() {
    return Container(
      color: Colors.blueGrey.shade50,
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.replay_10),
            onPressed: () => _audioPlayer.seek(
              _audioPlayer.position - const Duration(seconds: 10),
            ),
          ),
          Text(
            "${_audioPlayer.position.toString().split('.').first} / ${_audioPlayer.duration?.toString().split('.').first ?? '0:00:00'}",
          ),
          IconButton(
            icon: const Icon(Icons.forward_10),
            onPressed: () => _audioPlayer.seek(
              _audioPlayer.position + const Duration(seconds: 10),
            ),
          ),
        ],
      ),
    );
  }
}
