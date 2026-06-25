/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../models/schedule.dart';
import '../services/preferences_backup_service.dart';
import '../services/schedule_parser_service.dart';
import '../services/schedule_sync_service.dart';
import '../services/tracker_sync_service.dart';
import '../widgets/setup_page.dart';

class SchedulePage extends StatefulWidget {
  final FlutterSecureStorage secureStorage;

  const SchedulePage(this.secureStorage, {super.key});
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late StreamSubscription<void>? _resyncSubscription;

  bool _isConfigured = false;
  List<ScheduleItem> _items = [];
  DateTime _currentDay = DateTime.now();
  late DateTime _leftLimit;
  late DateTime _rightLimit;
  Timer? _syncTimer;
  final _start = DateTime(2026, 6, 22);
  final _cycleWeeks = 8;

  late AudioPlayer _audioPlayer;
  String? _currentPlayingFile;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _audioPlayer.stop();
        setState(() => _currentPlayingFile = null);
      }
    });
    _init();
    _syncTimer = Timer.periodic(const Duration(hours: 1), (_) => _load());
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('tz_lock')) {
      await prefs.setString('tz_lock', DateTime.now().timeZoneName);
    }
    final now = DateTime.now();
    final daysSince = now.difference(_start).inDays;
    final cycles = (daysSince / (_cycleWeeks * 7)).floor();
    final cycleStart = _start.add(Duration(days: cycles * _cycleWeeks * 7));
    _leftLimit = cycleStart.subtract(Duration(days: _cycleWeeks * 7));
    _rightLimit = cycleStart.add(Duration(days: _cycleWeeks * 14));
    _load();

    _resyncSubscription = TrackerSyncService.globalResyncTrigger.stream.listen((
      _,
    ) {
      if (mounted) {
        _load();
      }
    });
  }

  Future<void> _load() async {
    final url = await widget.secureStorage.read(
      key: PreferencesBackupService.keyScheduleYamlUrl,
    );
    final pwd = await widget.secureStorage.read(
      key: PreferencesBackupService.keyEncPwd,
    );
    if (url == null || pwd == null) {
      _isConfigured = false;
      return;
    }
    try {
      final text = await ScheduleSyncService(url, pwd).load();
      final parser = ScheduleParser(startDate: _start, cycleWeeks: _cycleWeeks);
      final items = parser.parse(text);
      setState(() {
        _items = items;
        _isConfigured = true;
      });
    } catch (e) {
      log('Error: $e');
      setState(() => _isConfigured = false);
    }
  }

  Future<void> _handleAudio(ScheduleItem item) async {
    final file = item.audio!;
    if (_currentPlayingFile == file) {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    } else {
      await _audioPlayer.stop();
      await _audioPlayer.setAudioSource(
        AudioSource.asset(
          file,
          tag: MediaItem(id: file, album: 'Tennis Training', title: item.title),
        ),
      );
      setState(() => _currentPlayingFile = file);
      await _audioPlayer.play();
    }
    setState(() {});
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConfigured) {
      return SetupPage(widget.secureStorage, (url, password) async {
        await widget.secureStorage.write(
          key: PreferencesBackupService.keyScheduleYamlUrl,
          value: url,
        );
        await widget.secureStorage.write(
          key: PreferencesBackupService.keyEncPwd,
          value: password,
        );
        TrackerSyncService.globalResyncTrigger.add(null);
      }, PreferencesBackupService(widget.secureStorage));
    }
    if (_items.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dayItems = _itemsForDay(_currentDay);
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('EEE d MMM').format(_currentDay)),
        actions: [IconButton(icon: const Icon(Icons.sync), onPressed: _load)],
      ),
      body: dayItems.isEmpty
          ? const Center(child: Text('Free time / Rest day'))
          : ListView.builder(
              itemCount: dayItems.length,
              itemBuilder: (_, i) {
                final it = dayItems[i];
                return Card(
                  margin: const EdgeInsets.all(12),
                  child: ExpansionTile(
                    title: Text(
                      it.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${it.slots.first.timeStart} - ${it.slots.first.timeEnd}'
                      '${it.setsAndReps != null ? ' • ${it.setsAndReps}' : ''}',
                    ),
                    children: [
                      if (it.description != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Text(
                            it.description!,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      ...it.children.map(
                        (c) => ListTile(
                          leading: Icon(
                            c.audio == _currentPlayingFile &&
                                    _audioPlayer.playing
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: Text(c.title),
                          subtitle: Text(
                            [
                              if (c.setsAndReps != null) c.setsAndReps!,
                              if (c.durationMin != null) '${c.durationMin} min',
                              if (c.reps != null) '×${c.reps}',
                            ].join(' • '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (c.audio != null)
                                IconButton(
                                  icon: Icon(
                                    c.audio == _currentPlayingFile &&
                                            _audioPlayer.playing
                                        ? Icons.pause_circle
                                        : Icons.play_circle,
                                  ),
                                  iconSize: 32,
                                  onPressed: () => _handleAudio(c),
                                ),
                              for (final l in c.links)
                                IconButton(
                                  icon: Icon(
                                    l.contains('youtube') ||
                                            l.contains('youtu.be')
                                        ? Icons.ondemand_video
                                        : Icons.link,
                                  ),
                                  onPressed: () => _openLink(l),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _currentDay.isAfter(_leftLimit)
                  ? () => setState(
                      () => _currentDay = _currentDay.subtract(
                        const Duration(days: 1),
                      ),
                    )
                  : null,
            ),
            const Text('swipe days'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _currentDay.isBefore(_rightLimit)
                  ? () => setState(
                      () => _currentDay = _currentDay.add(
                        const Duration(days: 1),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  List<ScheduleItem> _itemsForDay(DateTime day) {
    final weekNum = ((day.difference(_start).inDays ~/ 7) % _cycleWeeks) + 1;
    final dayNum = day.weekday;
    return _items
        .where(
          (it) => it.slots.any(
            (s) => s.weeks.contains(weekNum) && s.days.contains(dayNum),
          ),
        )
        .toList()
      ..sort(
        (a, b) => a.slots.first.timeStart.compareTo(b.slots.first.timeStart),
      );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _audioPlayer.dispose();
    _resyncSubscription?.cancel();
    super.dispose();
  }
}
