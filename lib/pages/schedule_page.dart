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
  DateTime _currentTime = DateTime.now();
  late DateTime _leftLimit;
  late DateTime _rightLimit;
  Timer? _syncTimer;
  Timer? _pageTimer;
  late DateTime _start;
  late int _cycleWeeks;

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
    _pageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      setState(() {
        if (now.day != _currentDay.day ||
            now.month != _currentDay.month ||
            now.year != _currentDay.year) {
          _currentDay = now;
        }
        _currentTime = now;
      });
    });
  }

  Future<void> _init() async {
    _load();

    _resyncSubscription = TrackerSyncService.globalResyncTrigger.stream.listen((
      _,
    ) {
      if (mounted) _load();
    });
  }

  Future<void> _calculateTimes(DateTime start, int cycleWeeks) async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('tz_lock')) {
      await prefs.setString('tz_lock', DateTime.now().timeZoneName);
    }
    final now = DateTime.now();
    final daysSince = now.difference(start).inDays;
    final cycles = (daysSince / (cycleWeeks * 7)).floor();
    final cycleStart = start.add(Duration(days: cycles * cycleWeeks * 7));
    _leftLimit = cycleStart.subtract(Duration(days: cycleWeeks * 7));
    _rightLimit = cycleStart.add(Duration(days: cycleWeeks * 14));
  }

  Future<void> _load() async {
    final url = await widget.secureStorage.read(
      key: PreferencesBackupService.keyScheduleYamlUrl,
    );
    final pwd = await widget.secureStorage.read(
      key: PreferencesBackupService.keyEncPwd,
    );
    if (url == null || pwd == null) {
      setState(() => _isConfigured = false);
      return;
    }
    try {
      final text = await ScheduleSyncService(url, pwd).load();
      final parser = ScheduleParser();
      final (start, cycleWeeks, items) = parser.parse(text);
      await _calculateTimes(start, cycleWeeks);
      setState(() {
        _start = start;
        _cycleWeeks = cycleWeeks;
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
    try {
      if (_currentPlayingFile == file) {
        _audioPlayer.playing
            ? await _audioPlayer.pause()
            : await _audioPlayer.play();
      } else {
        await _audioPlayer.stop();
        final source = file.startsWith('http')
            ? AudioSource.uri(
                Uri.parse(file),
                tag: MediaItem(
                  id: file,
                  title: item.title,
                  album: 'Tennis Training',
                ),
              )
            : AudioSource.asset(
                file,
                tag: MediaItem(
                  id: file,
                  title: item.title,
                  album: 'Tennis Training',
                ),
              );
        await _audioPlayer.setAudioSource(source);
        setState(() => _currentPlayingFile = file);
        await _audioPlayer.play();
      }
      setState(() {});
    } catch (e) {
      log('Audio error: $e');
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
        (a, b) => _slotForDay(a).timeStart.compareTo(_slotForDay(b).timeStart),
      );
  }

  bool _matchesDay(ScheduleItem it) {
    final weekNum =
        ((_currentDay.difference(_start).inDays ~/ 7) % _cycleWeeks) + 1;
    final dayNum = _currentDay.weekday;
    return it.slots.any(
      (s) => s.weeks.contains(weekNum) && s.days.contains(dayNum),
    );
  }

  ScheduleSlot _slotForDay(ScheduleItem it) {
    final weekNum =
        ((_currentDay.difference(_start).inDays ~/ 7) % _cycleWeeks) + 1;
    final dayNum = _currentDay.weekday;
    return it.slots.firstWhere(
      (s) => s.weeks.contains(weekNum) && s.days.contains(dayNum),
      orElse: () => it.slots.first,
    );
  }

  String _fmt(String hhmm) {
    final p = hhmm.split(':');
    return DateFormat(
      'h:mm a',
    ).format(DateTime(0, 1, 1, int.parse(p[0]), int.parse(p[1])));
  }

  Widget _buildNode(ScheduleItem item, int depth) {
    final children = item.children.where(_matchesDay).toList()
      ..sort(
        (a, b) => _slotForDay(a).timeStart.compareTo(_slotForDay(b).timeStart),
      );

    final slot = _slotForDay(item);
    final subtitle =
        '${_fmt(slot.timeStart)} - ${_fmt(slot.timeEnd)}'
        '${item.setsAndReps != null ? ' • ${item.setsAndReps}' : ''}';

    if (item.title == 'Untitled' || item.title.trim().isEmpty) {
      return Column(
        children: children.map((c) => _buildNode(c, depth)).toList(),
      );
    }

    if (children.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.only(left: 16 + depth * 16.0, right: 16),
        leading: item.audio != null
            ? IconButton(
                icon: Icon(
                  item.audio == _currentPlayingFile && _audioPlayer.playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                ),
                onPressed: () => _handleAudio(item),
              )
            : null,
        title: Text(item.title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in item.links)
              IconButton(
                icon: Icon(
                  l.contains('youtu') ? Icons.ondemand_video : Icons.link,
                ),
                onPressed: () => _openLink(l),
              ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.only(left: 16 + depth * 8.0, right: 16),
        title: Text(
          item.title,
          style: TextStyle(
            fontWeight: depth == 0 ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        subtitle: Text(subtitle),
        children: [
          if (item.description != null)
            Padding(
              padding: EdgeInsets.only(
                left: 16 + depth * 8.0,
                right: 16,
                bottom: 4,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  item.description!,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            ),
          if (item.audio != null)
            ListTile(
              leading: IconButton(
                icon: Icon(
                  item.audio == _currentPlayingFile && _audioPlayer.playing
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
                onPressed: () => _handleAudio(item),
              ),
              title: const Text('Play audio'),
              dense: true,
            ),
          ...children.map((c) => _buildNode(c, depth + 1)),
        ],
      ),
    );
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
          : ListView(
              children: dayItems.map((it) => _buildNode(it, 0)).toList(),
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
            IconButton(
              icon: const Icon(Icons.home),
              tooltip: 'Today',
              onPressed: () => setState(() {
                final now = DateTime.now();
                _currentDay = DateTime(now.year, now.month, now.day);
              }),
            ),
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

  @override
  void dispose() {
    _syncTimer?.cancel();
    _pageTimer?.cancel();
    _audioPlayer.dispose();
    _resyncSubscription?.cancel();
    super.dispose();
  }
}
