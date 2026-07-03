/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
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
import 'schedule_creator_page.dart';

class SchedulePage extends StatefulWidget {
  final FlutterSecureStorage secureStorage;
  const SchedulePage(this.secureStorage, {super.key});
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static final keySelectedCategory = 'selected_category';
  static final keyTZLoc = 'tz_lock';

  late ScheduleSyncService _syncService;
  late StreamSubscription<void>? _resyncSubscription;
  bool _isConfigured = false;
  bool _userHasNavigatedAway = false;
  List<ScheduleItem> _items = [];
  DateTime _currentDay = DateTime.now();
  DateTime _currentTime = DateTime.now();
  late DateTime _leftLimit;
  late DateTime _rightLimit;
  Timer? _pageTimer;
  late DateTime _start;
  late int _cycleWeeks;
  String _selectedCategory = 'all';
  bool _syncInProgress = false;
  String? _currentYaml;

  late AudioPlayer _audioPlayer;
  String? _currentPlayingFile;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  String? _lastLiveId;

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
    _pageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      setState(() {
        if (!_userHasNavigatedAway &&
            (now.day != _currentDay.day ||
                now.month != _currentDay.month ||
                now.year != _currentDay.year)) {
          _currentDay = now;
        }
        _currentTime = now;
      });
      if (!_userHasNavigatedAway) _scrollToLive();
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedCategory = prefs.getString(keySelectedCategory);
    if (selectedCategory != null) {
      setState(() => _selectedCategory = selectedCategory);
    }
    _load();

    _resyncSubscription = TrackerSyncService.globalResyncTrigger.stream.listen((
      _,
    ) {
      if (mounted) _load();
    });
  }

  Future<void> _calculateTimes(DateTime start, int cycleWeeks) async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(keyTZLoc)) {
      await prefs.setString(keyTZLoc, DateTime.now().timeZoneName);
    }
    final now = DateTime.now();
    final daysSince = now.difference(start).inDays;
    final cycles = (daysSince / (cycleWeeks * 7)).floor();
    final cycleStart = start.add(Duration(days: cycles * cycleWeeks * 7));
    _leftLimit = cycleStart.subtract(Duration(days: cycleWeeks * 7));
    _rightLimit = cycleStart.add(Duration(days: cycleWeeks * 14 - 1));
  }

  int _getCurrentWeek(DateTime d) =>
      1 + ((d.difference(_start).inDays) / 7).toInt() % _cycleWeeks;

  Future<void> _load() async {
    final url = await widget.secureStorage.read(
      key: PreferencesBackupService.keyScheduleYamlUrl,
    );
    final pwd = await widget.secureStorage.read(
      key: PreferencesBackupService.keyEncPwd,
    );
    if (url == null || pwd == null) {
      setState(() {
        _isConfigured = false;
        _syncInProgress = false;
      });
      return;
    }
    try {
      _syncService = ScheduleSyncService(
        widget.secureStorage,
        await SharedPreferences.getInstance(),
        () => setState(() => _syncInProgress = true),
        () => setState(() => _syncInProgress = false),
        (self) async {
          if (self.yaml != null) {
            await _loadFromYaml(self.yaml!);
          }
        },
      );
      await _syncService.initializeSyncer();
      if (_syncService.yaml != null) {
        await _loadFromYaml(_syncService.yaml!);
      }
    } catch (e) {
      log('Error: $e');
      setState(() {
        _isConfigured = false;
        _syncInProgress = false;
      });
    }
  }

  Future<void> _loadFromYaml(String yaml) async {
    _currentYaml = yaml;
    try {
      final parser = ScheduleParser();
      final (start, cycleWeeks, items) = parser.parse(
        yaml,
        includeDisabled: false,
      );
      await _calculateTimes(start, cycleWeeks);
      setState(() {
        _start = start;
        _cycleWeeks = cycleWeeks;
        _items = items;
        _isConfigured = true;
        _itemKeys.clear();
        _lastLiveId = null;
        _syncInProgress = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToLive();
      });
    } catch (e) {
      log('Error: $e');
      setState(() {
        _isConfigured = false;
        _syncInProgress = false;
      });
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
          (it) =>
              it.slots.any(
                (s) => s.weeks.contains(weekNum) && s.days.contains(dayNum),
              ) &&
              _matchesCategory(it),
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

  Widget _buildNode(ScheduleItem item, int depth, bool parentLive) {
    final children = item.children.where(_matchesDay).toList()
      ..sort(
        (a, b) => _slotForDay(a).timeStart.compareTo(_slotForDay(b).timeStart),
      );

    final slot = _slotForDay(item);
    final isLive = parentLive || _isLive(item);
    final itemKey = depth == 0
        ? _itemKeys.putIfAbsent(item.title, () => GlobalKey())
        : null;
    final icon = switch (item.category) {
      'nutrition' => Icons.restaurant_menu_outlined,
      'hydration' => Icons.water_drop_outlined,
      'drill' => Icons.sports_tennis_outlined,
      'exercise' => Icons.directions_run_outlined,
      'rest' => Icons.bedtime_outlined,
      _ => Icons.task_alt_outlined,
    };
    final subtitle =
        '${slot.timeStart != slot.timeEnd ? '${_fmt(slot.timeStart)} - ${_fmt(slot.timeEnd)}' : _fmt(slot.timeStart)}'
        '${item.description != null && !item.description!.contains('\n') ? ' • ${item.description}' : ''}'
        '${slot.description != null && !slot.description!.contains('\n') ? ' • ${slot.description}' : ''}'
        '${item.setsAndReps != null ? ' • ${item.setsAndReps}' : ''}'
        '${item.reps != null ? ' • x${item.reps}' : ''}'
        '${item.durationMin != null ? ' • ${item.durationMin} mins' : ''}';
    final lines = [
      ...(item.description ?? '').split('\n'),
      ...(slot.description ?? '').split('\n'),
    ].where((r) => r.isNotEmpty);

    if (item.title == 'Untitled' || item.title.trim().isEmpty) {
      return Column(
        children: children.map((c) => _buildNode(c, depth, isLive)).toList(),
      );
    }

    if (children.isEmpty) {
      return Container(
        key: itemKey,
        decoration: isLive
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 4,
                  ),
                ),
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.07),
              )
            : null,
        child: ListTile(
          contentPadding: EdgeInsets.only(left: 16 + depth * 16.0, right: 16),
          leading: isLive
              ? const Icon(Icons.circle, size: 10, color: Colors.green)
              : null,
          title: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isLive ? Theme.of(context).colorScheme.primary : null,
                ),
                SizedBox(width: 10),
                Text(
                  item.title,
                  style: TextStyle(fontWeight: isLive ? FontWeight.bold : null),
                ),
                if (item.audio != null)
                  IconButton(
                    icon: Icon(
                      item.audio == _currentPlayingFile && _audioPlayer.playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      color: isLive
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onPressed: () => _handleAudio(item),
                  ),
                if (item.audio != null &&
                    item.audio == _currentPlayingFile &&
                    _audioPlayer.playing)
                  IconButton(
                    icon: Icon(
                      Icons.stop_circle_outlined,
                      color: isLive
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onPressed: () {
                      _audioPlayer.stop();
                      _audioPlayer.seek(Duration.zero);
                    },
                  ),
              ],
            ),
          ),
          subtitle: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: const TextStyle(fontSize: 12)),
              if (lines.length > 1)
                ...lines.map(
                  (l) => Text('✔ $l', style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
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
        ),
      );
    }

    return Container(
      key: itemKey,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: isLive ? 3 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isLive
              ? BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.2,
                )
              : BorderSide.none,
        ),
        color: isLive
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.22)
            : null,
        child: ExpansionTile(
          initiallyExpanded: isLive,
          tilePadding: EdgeInsets.only(left: 16 + depth * 8.0, right: 16),
          title: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                if (isLive)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                Icon(
                  icon,
                  color: isLive ? Theme.of(context).colorScheme.primary : null,
                ),
                SizedBox(width: 10),
                Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: depth == 0 ? FontWeight.bold : FontWeight.w600,
                    color: isLive
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                if (item.audio != null)
                  IconButton(
                    onPressed: () => _handleAudio(item),
                    icon: Icon(
                      item.audio == _currentPlayingFile && _audioPlayer.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),
                if (item.audio != null &&
                    item.audio == _currentPlayingFile &&
                    _audioPlayer.playing)
                  IconButton(
                    onPressed: () {
                      _audioPlayer.stop();
                      _audioPlayer.seek(Duration.zero);
                    },
                    icon: Icon(Icons.stop_circle_outlined),
                  ),
              ],
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
            ...children.map((c) => _buildNode(c, depth + 1, isLive)),
          ],
        ),
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
        title: Text(
          '${DateFormat('EEE d MMM').format(_currentDay)} (Week #${_getCurrentWeek(_currentDay)})',
        ),
        actions: [
          IconButton(
            icon: Icon(_syncInProgress ? Icons.sync_lock : Icons.sync),
            onPressed: _syncInProgress ? null : _load,
          ),
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.edit_calendar_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScheduleCreatorPage(
                      initialYaml: _currentYaml,
                      onSave: (newYaml) => _loadFromYaml(newYaml),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: dayItems.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.insert_emoticon,
                    color: Colors.blueAccent,
                    size: 40,
                  ),
                  Text('Free time / Rest day', style: TextStyle(fontSize: 20)),
                ],
              ),
            )
          : ListView(
              controller: _scrollController,
              children: dayItems.map((it) => _buildNode(it, 0, false)).toList(),
            ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _currentDay.isAfter(_leftLimit)
                  ? () {
                      _userHasNavigatedAway = true;
                      setState(
                        () => _currentDay = _currentDay.subtract(
                          const Duration(days: 1),
                        ),
                      );
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.home),
              tooltip: 'Today',
              onPressed: () {
                _userHasNavigatedAway = false;
                setState(() {
                  final now = DateTime.now();
                  _currentDay = DateTime(now.year, now.month, now.day);
                });
                _scrollToLive();
              },
            ),
            IconButton(
              icon: const Icon(Icons.calendar_month),
              tooltip: 'Select a date',
              onPressed: () async {
                final DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: _currentDay,
                  firstDate: _leftLimit,
                  lastDate: _rightLimit,
                  helpText: 'Select a day to go to',
                  builder: (context, child) {
                    return Theme(data: Theme.of(context), child: child!);
                  },
                );

                if (pickedDate != null) {
                  _userHasNavigatedAway = true;
                  setState(() {
                    _currentDay = pickedDate;
                  });
                  _scrollToLive();
                }
              },
            ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.filter_list,
                color: _selectedCategory == 'all'
                    ? null
                    : Theme.of(context).colorScheme.primary,
              ),
              tooltip: 'Filter by category',
              onSelected: (v) async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                prefs.setString(keySelectedCategory, v);
                setState(() => _selectedCategory = v);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'all',
                  child: Text('All categories'),
                ),
                ..._allCategories().map(
                  (c) => PopupMenuItem(value: c, child: Text(_pretty(c))),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _currentDay.isBefore(_rightLimit)
                  ? () {
                      _userHasNavigatedAway = true;
                      setState(
                        () => _currentDay = _currentDay.add(
                          const Duration(days: 1),
                        ),
                      );
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageTimer?.cancel();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _resyncSubscription?.cancel();
    _syncService.disposeSyncer();
    super.dispose();
  }

  bool _matchesCategory(ScheduleItem it) {
    if (_selectedCategory == 'all') return true;
    return it.category == _selectedCategory;
  }

  List<String> _allCategories() {
    final set = <String>{};
    void collect(ScheduleItem it) {
      if (it.category != null && it.category!.isNotEmpty) set.add(it.category!);
      for (final c in it.children) {
        collect(c);
      }
    }

    for (final it in _items) {
      collect(it);
    }
    return set.toList()..sort();
  }

  bool _isToday() =>
      _currentDay.year == _currentTime.year &&
      _currentDay.month == _currentTime.month &&
      _currentDay.day == _currentTime.day;

  int _toMin(String t) =>
      int.parse(t.split(':')[0]) * 60 + int.parse(t.split(':')[1]);

  bool _isLive(ScheduleItem it) {
    if (!_isToday()) return false;
    final s = _slotForDay(it);
    final now = _currentTime.hour * 60 + _currentTime.minute;
    final ts = _toMin(s.timeStart);
    final te = _toMin(s.timeEnd);
    if (te >= ts) {
      return now >= ts && now < te;
    } else {
      return now >= ts || now < te;
    }
  }

  ScheduleItem? _findTopLive() {
    final dayItems = _itemsForDay(_currentDay);
    bool hasLive(ScheduleItem i) => _isLive(i) || i.children.any(hasLive);
    return dayItems.firstWhereOrNull(hasLive);
  }

  void _scrollToLive() {
    if (!_isToday()) return;
    final live = _findTopLive();
    if (live == null) return;
    if (live.title == _lastLiveId) return;
    _lastLiveId = live.title;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[live.title];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          alignment: 0.0,
        );
      }
    });
  }

  String _pretty(String c) => c[0].toUpperCase() + c.substring(1);
}
