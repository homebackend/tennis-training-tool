/*
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/app_logger.dart';
import 'package:flutter_common/mixin/main_config_manager.dart';
import 'package:flutter_common/mixin/page_common.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../models/schedule.dart';
import '../services/audio_service.dart';
import '../services/schedule_parser_service.dart';
import '../services/schedule_sync_service.dart';
import '../services/tracker_sync_service.dart';
import '../tool.dart';
import 'schedule_creator_page.dart';

class SchedulePage extends StatefulWidget {
  final FlutterSecureStorage secureStorage;
  final SharedPreferences sharedPreferences;
  final MainConfigManager configManager;
  const SchedulePage(
    this.secureStorage,
    this.sharedPreferences,
    this.configManager, {
    super.key,
  });
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> with PageCommon {
  static final keySelectedCategory = 'selected_category';
  static final keyTZLoc = 'tz_lock';

  late ScheduleSyncService _syncService;
  late StreamSubscription<void>? _resyncSubscription;
  bool _userHasNavigatedAway = false;
  List<ScheduleItem> _items = [];
  DateTime _currentDay = DateTime.now();
  DateTime _currentTime = DateTime.now();
  DateTime _scheduleLastEdited = DateTime.now();
  String? _currentItem;
  late DateTime _leftLimit;
  late DateTime _rightLimit;
  Timer? _pageTimer;
  late DateTime _start;
  late int _cycleWeeks;
  String _selectedCategory = 'all';
  bool _syncInProgress = false;
  late AudioPlayer _audioPlayer;
  String? _currentPlayingFile;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  String? _lastLiveId;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioService.player;
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
    final selectedCategory = widget.sharedPreferences.getString(
      keySelectedCategory,
    );
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
    if (!widget.sharedPreferences.containsKey(keyTZLoc)) {
      await widget.sharedPreferences.setString(
        keyTZLoc,
        DateTime.now().timeZoneName,
      );
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
    try {
      _syncService = ScheduleSyncService(
        widget.secureStorage,
        widget.sharedPreferences,
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
      appLogger.e('Error: $e');
    }
  }

  Future<void> _loadFromYaml(String yaml) async {
    try {
      final parser = ScheduleParser();
      final (metadata, start, cycleWeeks, items) = parser.parse(
        yaml,
        includeDisabled: false,
      );

      _scheduleLastEdited =
          DateTime.tryParse(metadata['sync_timestamp']) ?? DateTime.now();

      await _calculateTimes(start, cycleWeeks);
      setState(() {
        _start = start;
        _cycleWeeks = cycleWeeks;
        _items = items;
        _itemKeys.clear();
        _lastLiveId = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToLive();
      });
    } catch (e) {
      appLogger.e('Error: $e');
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
      appLogger.e('Audio error: $e');
    }
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

  @override
  Widget build(BuildContext context) {
    if (_syncInProgress || _items.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dayItems = _itemsForDay(_currentDay);
    return Scaffold(
      appBar: AppBar(
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: BouncingScrollPhysics(),
          child: Row(
            children: [
              Text(
                '${DateFormat('EEE d MMM').format(_currentDay)} (Week #${_getCurrentWeek(_currentDay)})',
              ),
              SizedBox(width: 15),
              Text(
                '[updated ${timeAgo(_scheduleLastEdited)}]',
                style: TextStyle(fontSize: 14, color: Colors.blue.shade500),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_syncInProgress ? Icons.sync_lock : Icons.sync),
            onPressed: _syncInProgress ? null : _syncService.syncData,
            tooltip: 'Sync Latest Schedule',
          ),
          IconButton(
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScheduleCreatorPage(
                    initialYaml: _syncService.yaml,
                    onSave: (newYaml) async {
                      _syncService.yaml = newYaml;
                      await _syncService.setSyncDataModified(true);
                      await _loadFromYaml(newYaml);
                      await _syncService.syncData();
                    },
                  ),
                ),
              );
            },
          ),
          ...getAppBarCommonActions(widget.configManager),
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
              children: dayItems
                  .mapIndexed(
                    (index, it) => ScheduleNode(
                      item: it,
                      depth: 0,
                      parentLive: false,
                      isLive: _isLive,
                      matchesDay: _matchesDay,
                      slotForDay: _slotForDay,
                      updateTitle: _updateTitle,
                      getKey: _getKey,
                      currentPlayingFile: () => _currentPlayingFile,
                      handleAudio: _handleAudio,
                    ),
                  )
                  .toList(),
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
                await widget.sharedPreferences.setString(
                  keySelectedCategory,
                  v,
                );
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
      final key = _itemKeys[live.id];
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

  void _updateTitle(String title) {
    if (_currentItem != title) {
      AudioNotifier.changeCurrentItem();
    }

    _currentItem = title;
  }

  GlobalKey<State<StatefulWidget>> _getKey(String id, String title) {
    return _itemKeys.putIfAbsent(id, () => GlobalKey(debugLabel: '$title-$id'));
  }

  @override
  FlutterSecureStorage get secureStorage => widget.secureStorage;
}

class ScheduleNode extends StatefulWidget {
  final ScheduleItem item;
  final int depth;
  final bool parentLive;
  final bool Function(ScheduleItem it) matchesDay;
  final ScheduleSlot Function(ScheduleItem it) slotForDay;
  final bool Function(ScheduleItem it) isLive;
  final void Function(String title) updateTitle;
  final GlobalKey<State<StatefulWidget>> Function(String id, String title)
  getKey;
  final String? Function() currentPlayingFile;
  final Future<void> Function(ScheduleItem item) handleAudio;

  const ScheduleNode({
    super.key,
    required this.item,
    required this.depth,
    required this.parentLive,
    required this.matchesDay,
    required this.slotForDay,
    required this.isLive,
    required this.updateTitle,
    required this.getKey,
    required this.currentPlayingFile,
    required this.handleAudio,
  });

  @override
  State<ScheduleNode> createState() => _ScheduleNodeState();
}

class _ScheduleNodeState extends State<ScheduleNode> {
  late AudioPlayer _audioPlayer;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioService.player;
    _expanded = widget.parentLive || widget.isLive(widget.item);
  }

  String _fmt(String hhmm) {
    final p = hhmm.split(':');
    return DateFormat(
      'h:mm a',
    ).format(DateTime(0, 1, 1, int.parse(p[0]), int.parse(p[1])));
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.item.children.where(widget.matchesDay).toList()
      ..sort(
        (a, b) => widget
            .slotForDay(a)
            .timeStart
            .compareTo(widget.slotForDay(b).timeStart),
      );

    final slot = widget.slotForDay(widget.item);
    final isLive = widget.parentLive || widget.isLive(widget.item);

    if (!widget.parentLive && isLive) widget.updateTitle(widget.item.title);

    final itemKey = widget.depth == 0
        ? widget.getKey(widget.item.id, widget.item.title)
        : null;
    final icon = switch (widget.item.category) {
      'nutrition' => Icons.restaurant_menu_outlined,
      'hydration' => Icons.water_drop_outlined,
      'drill' => Icons.sports_tennis_outlined,
      'exercise' => Icons.directions_run_outlined,
      'rest' => Icons.bedtime_outlined,
      _ => widget.depth == 0 ? Icons.task_alt_outlined : null,
    };
    final subtitle =
        '${!_expanded
            ? slot.timeStart != slot.timeEnd
                  ? '${_fmt(slot.timeStart)} - ${_fmt(slot.timeEnd)}'
                  : _fmt(slot.timeStart)
            : ''}'
        '${widget.item.description != null && !widget.item.description!.contains('\n') ? ' • ${widget.item.description}' : ''}'
        '${slot.description != null && !slot.description!.contains('\n') ? ' • ${slot.description}' : ''}'
        '${widget.item.setsAndReps != null ? ' • ${widget.item.setsAndReps}' : ''}'
        '${widget.item.reps != null ? ' • x${widget.item.reps}' : ''}'
        '${widget.item.durationMin != null ? ' • ${widget.item.durationMin} mins' : ''}';
    final lines = [
      ...(widget.item.description ?? '').split('\n'),
      ...(slot.description ?? '').split('\n'),
    ].where((r) => r.isNotEmpty);

    if (widget.item.title == ScheduleItem.itemWithoutTitle ||
        widget.item.title.trim().isEmpty) {
      return Column(
        children: children
            .map(
              (c) => ScheduleNode(
                item: c,
                depth: widget.depth,
                parentLive: isLive,
                isLive: widget.isLive,
                matchesDay: widget.matchesDay,
                slotForDay: widget.slotForDay,
                updateTitle: widget.updateTitle,
                getKey: widget.getKey,
                currentPlayingFile: widget.currentPlayingFile,
                handleAudio: widget.handleAudio,
              ),
            )
            .toList(),
      );
    }

    final linksIcons = [
      if (widget.item.audio != null)
        IconButton(
          icon: Icon(
            widget.item.audio == widget.currentPlayingFile() &&
                    _audioPlayer.playing
                ? Icons.pause_circle_filled
                : Icons.play_circle_fill,
            color: isLive ? Theme.of(context).colorScheme.primary : null,
          ),
          onPressed: () => widget.handleAudio(widget.item),
        ),
      if (widget.item.audio != null &&
          widget.item.audio == widget.currentPlayingFile() &&
          _audioPlayer.playing)
        IconButton(
          icon: Icon(
            Icons.stop_circle_outlined,
            color: isLive ? Theme.of(context).colorScheme.primary : null,
          ),
          onPressed: () {
            _audioPlayer.stop();
            _audioPlayer.seek(Duration.zero);
          },
        ),
      for (final l in widget.item.links)
        IconButton(
          icon: Icon(l.contains('youtu') ? Icons.ondemand_video : Icons.link),
          onPressed: () => _openLink(l),
        ),
    ];

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
          contentPadding: EdgeInsets.only(
            left: 16 + widget.depth * 8.0,
            right: 16,
          ),
          leading: (!isLive && icon == null)
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLive)
                      const Icon(Icons.circle, size: 10, color: Colors.green),
                    if (icon != null)
                      Icon(
                        icon,
                        color: isLive
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                  ],
                ),
          title: Text(
            widget.item.title,
            maxLines: 3,
            style: TextStyle(fontWeight: isLive ? FontWeight.bold : null),
          ),
          subtitle: lines.isNotEmpty
              ? ExpansionTile(
                  title: Text(subtitle, style: const TextStyle(fontSize: 12)),
                  subtitle: linksIcons.length > 1
                      ? Row(
                          mainAxisSize: MainAxisSize.max,
                          children: linksIcons,
                        )
                      : null,
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: lines
                      .map(
                        (l) =>
                            Text('✔ $l', style: const TextStyle(fontSize: 12)),
                      )
                      .toList(),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtitle, style: const TextStyle(fontSize: 12)),
                    if (linksIcons.length > 1)
                      Row(mainAxisSize: MainAxisSize.max, children: linksIcons),
                  ],
                ),
          trailing: linksIcons.length == 1
              ? Row(mainAxisSize: MainAxisSize.min, children: linksIcons)
              : null,
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
          onExpansionChanged: (value) => setState(() => _expanded = value),
          tilePadding: EdgeInsets.only(
            left: 16 + widget.depth * 8.0,
            right: 16,
          ),
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
                if (icon != null)
                  Icon(
                    icon,
                    color: isLive
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                SizedBox(width: 10),
                Text(
                  widget.item.title,
                  style: TextStyle(
                    fontWeight: widget.depth == 0
                        ? FontWeight.bold
                        : FontWeight.w600,
                    color: isLive
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                if (widget.item.audio != null)
                  IconButton(
                    onPressed: () => widget.handleAudio(widget.item),
                    icon: Icon(
                      widget.item.audio == widget.currentPlayingFile() &&
                              _audioPlayer.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),
                if (widget.item.audio != null &&
                    widget.item.audio == widget.currentPlayingFile() &&
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
            if (widget.item.description != null)
              Padding(
                padding: EdgeInsets.only(
                  left: 16 + widget.depth * 8.0,
                  right: 16,
                  bottom: 4,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.item.description!,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ),
            ...children.map(
              (c) => ScheduleNode(
                item: c,
                depth: widget.depth + 1,
                parentLive: isLive,
                isLive: widget.isLive,
                matchesDay: widget.matchesDay,
                slotForDay: widget.slotForDay,
                updateTitle: widget.updateTitle,
                getKey: widget.getKey,
                currentPlayingFile: widget.currentPlayingFile,
                handleAudio: widget.handleAudio,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
