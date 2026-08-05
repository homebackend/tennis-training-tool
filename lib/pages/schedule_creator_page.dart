/*
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_common/app_logger.dart';
import 'package:flutter_common/tool.dart';

import '../mixins/schedule_common.dart';
import '../mixins/yaml_diff_deviation.dart';
import '../models/schedule.dart';
import '../services/schedule_editor_service.dart';
import '../services/schedule_parser_service.dart';

mixin ScheduleItemManager implements ScheduleCommon {
  void swapItems(List<ScheduleItem> items, int src, int dest) {
    final srcItem = items[src];
    final destItem = items[dest];
    srcItem.shift += dest - src;
    destItem.shift += src - dest;
    srcItem.index = dest;
    destItem.index = src;
    items[src] = destItem;
    items[dest] = srcItem;
  }

  void handleDeletion(List<ScheduleItem> items, int start) {
    for (int i = start; i < items.length; i++) {
      final item = items[i];
      item.index--;
      item.shift--;
    }
  }

  void handleNesting(
    BuildContext context,
    List<ScheduleItem> items,
    int src,
    int dest,
    ScheduleItem Function() onDelete,
  ) {
    if (dest < 0 || dest > items.length || dest == src) {
      return;
    }

    final item = items[src];
    final destItem = items[dest];

    final error = validateTimeSlotsAgainstParent(
      parent: destItem,
      slots: item.actualSlots(),
    );

    if (error != null) {
      showErrorDialog(
        context,
        'Nesting is not allowed for "${item.title}" as timeslots '
        'for "${destItem.title}" are incompatible. '
        'The erring timeslot: $error.',
      );
      return;
    }

    item.index = destItem.children.length;
    item.shift = 0;
    item.changed = true;
    destItem.children.add(item);
    destItem.changed = true;
    onDelete();
  }
}

class ScheduleCreatorPage extends StatefulWidget {
  final void Function(String yaml) onSave;
  final String? initialYaml;
  const ScheduleCreatorPage({
    super.key,
    required this.onSave,
    this.initialYaml,
  });

  @override
  State<ScheduleCreatorPage> createState() => _ScheduleCreatorPageState();
}

class _ScheduleCreatorPageState extends State<ScheduleCreatorPage>
    with YamlDiffDeviation, ScheduleCommon, ScheduleItemManager {
  bool _dirty = false;
  final _parser = ScheduleParser();
  late ScheduleEditorService _service;
  List<Map<String, dynamic>> _audioMap = [];

  DateTime start = DateTime.now();
  int weeks = 2;
  final List<ScheduleItem> items = [];
  late final TextEditingController _weeksController;
  Set<int> _filteredWeeks = {};
  Set<int> _filteredDays = {};

  @override
  void initState() {
    super.initState();

    _service = ScheduleEditorService(widget.initialYaml);

    rootBundle.loadString('assets/mapping.json').then((s) {
      final list = json.decode(s) as List;
      setState(() {
        _audioMap = list
            .map(
              (e) => {
                'file': e['file'] as String,
                'display': e['display'] as String,
              },
            )
            .toList();
      });
    });

    if (widget.initialYaml != null) {
      final (_, s, w, its) = _parser.parse(
        widget.initialYaml!,
        includeDisabled: true,
      );
      start = s;
      weeks = w;
      items.addAll(its);
    }
    _weeksController = TextEditingController(text: weeks.toString());
    _selectToday();
  }

  @override
  void dispose() {
    _weeksController.dispose();
    super.dispose();
  }

  DateTime _getMonday(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  DateTime get mondayOfStartWeek => _getMonday(start);

  int _weekForDate(DateTime date) {
    final monday = mondayOfStartWeek;
    final diff = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(monday).inDays;
    if (diff < 0) return 1;
    return (diff ~/ 7) % weeks + 1;
  }

  int _dayForDate(DateTime date) => date.weekday;

  void _selectToday() {
    final today = DateTime.now();
    _filteredWeeks = {_weekForDate(today)};
    _filteredDays = {_dayForDate(today)};
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldSave = await _confirmExit();
        if (shouldSave == true) {
          await _save();
        } else if (shouldSave == false) {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.initialYaml == null ? 'New Schedule' : 'Edit Schedule',
          ),
          actions: [
            FilledButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schedule Settings',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Start Date'),
                      subtitle: Text(
                        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: start,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) {
                          _markDirty();
                          setState(() {
                            start = d;
                            _selectToday();
                          });
                        }
                      },
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Repeat every (weeks)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        WeeksRangeFormatter(),
                      ],
                      controller: _weeksController,
                      onChanged: (v) {
                        _markDirty();
                        final parsed = int.tryParse(v);
                        if (parsed != null) {
                          setState(() {
                            weeks = parsed;
                            _filteredWeeks.removeWhere((w) => w > weeks);
                          });
                        }
                      },
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Filter by Week'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (int i = 1; i <= weeks; i++)
                              FilterChip(
                                label: Text('W$i'),
                                selected: _filteredWeeks.contains(i),
                                onSelected: (sel) => setState(() {
                                  sel
                                      ? _filteredWeeks.add(i)
                                      : _filteredWeeks.remove(i);
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('Filter by Day'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (int d = 1; d <= 7; d++)
                              FilterChip(
                                label: Text(
                                  ScheduleCommon.weekNames.values.toList()[d -
                                      1],
                                ),
                                selected: _filteredDays.contains(d),
                                onSelected: (sel) => setState(() {
                                  sel
                                      ? _filteredDays.add(d)
                                      : _filteredDays.remove(d);
                                }),
                              ),
                          ],
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _filteredWeeks.clear();
                            _filteredDays.clear();
                          }),
                          child: Text('Clear = Show All'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Items', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: () => _editItem(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            ...items
                .where((item) {
                  if (item.slots.isEmpty) return true;

                  return item.slots.any((s) {
                    final weekOk =
                        _filteredWeeks.isEmpty ||
                        s.weeks.any(_filteredWeeks.contains);
                    final dayOk =
                        _filteredDays.isEmpty ||
                        s.days.any(_filteredDays.contains);
                    return weekOk && dayOk;
                  });
                })
                .toList()
                .asMap()
                .entries
                .map((e) {
                  ScheduleItem onDelete() {
                    _markDirty();
                    final deletedItem = items.removeAt(e.key);
                    setState(() {});
                    handleDeletion(items, e.key);
                    return deletedItem;
                  }

                  return _ItemCard(
                    key: ValueKey(e.value),
                    item: e.value,
                    position: e.key,
                    length: items.length,
                    maxWeeks: weeks,
                    audioMap: _audioMap,
                    onChanged: (u) {
                      _markDirty();
                      setState(() => items[e.key] = u);
                    },
                    onDelete: onDelete,
                    onSwap: (src, dest) {
                      _markDirty();
                      swapItems(items, src, dest);
                      setState(() {});
                    },
                    onOutdentParent: (ScheduleItem item) {
                      _markDirty();
                      item.changed = true;
                      item.shift = 0;
                      item.index = items.length;
                      setState(() => items.add(item));
                    },
                    onNest: (dest) =>
                        handleNesting(context, items, e.key, dest, onDelete),
                  );
                }),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No items yet — tap Add to start')),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmExit() {
    if (!_dirty) return Future.value(false);

    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save schedule before leaving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editItem(
    ScheduleItem? original, [
    Function(ScheduleItem)? update,
  ]) async {
    final result = await showDialog<ScheduleItem>(
      context: context,
      builder: (_) => _ItemEditorDialog(
        item: original,
        parent: null,
        maxWeeks: weeks,
        audioMap: _audioMap,
      ),
    );
    if (result != null) {
      _markDirty();
      if (update != null) {
        update(result);
      } else {
        setState(() => items.add(result));
      }
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _save() async {
    try {
      final yaml = await _service.toYaml(start, weeks, items);
      if (mounted) {
        final shouldSave = await showYamlDiffDialog(
          context,
          existingYaml: widget.initialYaml ?? '',
          newYaml: yaml,
        );

        if (shouldSave) {
          widget.onSave(yaml);
          setState(() => _dirty = false);
          if (mounted) {
            Navigator.pop(context);
          }
        }
      }
    } catch (e) {
      appLogger.e('Error: during schedule yaml generation: $e');
      if (mounted) {
        showErrorDialog(context, 'Schedule yaml generation failed: $e');
      }
    }
  }
}

class _ItemCard extends StatefulWidget {
  final ScheduleItem? parent;
  final ScheduleItem item;
  final int position;
  final int length;
  final ValueChanged<ScheduleItem> onChanged;
  final VoidCallback onDelete;
  final void Function(int src, int dest) onSwap;
  final VoidCallback? onOutdent;
  final void Function(ScheduleItem item) onOutdentParent;
  final void Function(int dest) onNest;
  final int maxWeeks;
  final List<Map<String, dynamic>> audioMap;
  const _ItemCard({
    super.key,
    this.parent,
    required this.onOutdentParent,
    required this.item,
    required this.position,
    required this.length,
    required this.onChanged,
    required this.onDelete,
    required this.onSwap,
    required this.onNest,
    this.onOutdent,
    required this.maxWeeks,
    required this.audioMap,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard>
    with ScheduleCommon, ScheduleItemManager {
  late ScheduleItem _item;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  void _update(ScheduleItem u) {
    setState(() => _item = u);
    widget.onChanged(u);
  }

  @override
  void didUpdateWidget(covariant _ItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      _item = widget.item;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: BouncingScrollPhysics(),
          child: Row(
            children: [
              if (!_item.enabled)
                const Icon(Icons.visibility_off, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                _item.title == ScheduleItem.itemWithoutTitle
                    ? 'Placeholder Item'
                    : _item.title,
                style: TextStyle(
                  decoration: _item.enabled ? null : TextDecoration.lineThrough,
                  fontStyle: _item.isPlaceholderItem ? FontStyle.italic : null,
                  color: _item.enabled
                      ? _item.isPlaceholderItem
                            ? Colors.blue
                            : null
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        subtitle: Column(
          children: [
            if ([
              _item.category,
              _item.children.isNotEmpty,
              _item.reps,
              _item.setsAndReps,
              _item.durationMin,
            ].any((v) => v != null || _item.links.isNotEmpty))
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_item.category != null)
                      Text(
                        _item.category!,
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    if (_item.reps != null) Text('${_item.reps} reps'),
                    if (_item.setsAndReps != null)
                      Text('sets & reps: ${_item.setsAndReps}'),
                    if (_item.durationMin != null)
                      Text('${_item.durationMin} m'),
                    if (_item.links.isNotEmpty)
                      Text('${_item.links.length} links'),
                    if (_item.children.isNotEmpty)
                      Text('${_item.children.length} child entries')
                    else
                      Text('No child entries'),
                  ].expand((e) => [e, Text(' / ')]).toList()..removeLast(),
                ),
              ),
            //if (_item.description != null) Text(_item.description!),
            if (_item.actualSlots().isEmpty) Text('No slots configured'),
            if (_item.actualSlots().isNotEmpty)
              ..._item.actualSlots().map((s) => Text(slotTitle(s))),
          ],
        ),

        children: [
          OverflowBar(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Edit'),
                onPressed: () async {
                  final r = await showDialog<ScheduleItem>(
                    context: context,
                    builder: (_) => _ItemEditorDialog(
                      item: _item,
                      parent: widget.parent,
                      maxWeeks: widget.maxWeeks,
                      audioMap: widget.audioMap,
                    ),
                  );
                  if (r != null) {
                    _update(r..changed = true);
                  }
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add child'),
                onPressed: () async {
                  final r = await showDialog<ScheduleItem>(
                    context: context,
                    builder: (_) => _ItemEditorDialog(
                      maxWeeks: widget.maxWeeks,
                      audioMap: widget.audioMap,
                    ),
                  );
                  if (r != null) {
                    r.index = _item.children.length;
                    addSlotKeysIfMissing(r, r.slots);
                    _update(
                      _item
                        ..changed = true
                        ..children.add(r),
                    );
                  }
                },
              ),
              TextButton.icon(
                icon: Icon(
                  _item.enabled ? Icons.visibility : Icons.visibility_off,
                  color: _item.enabled ? Colors.green : Colors.grey,
                ),
                label: Text(_item.enabled ? 'Enabled' : 'Disabled'),
                style: TextButton.styleFrom(
                  foregroundColor: _item.enabled ? Colors.green : Colors.grey,
                ),
                onPressed: () {
                  final updated = ScheduleItem(
                    title: _item.title,
                    category: _item.category,
                    description: _item.description,
                    durationMin: _item.durationMin,
                    reps: _item.reps,
                    setsAndReps: _item.setsAndReps,
                    audio: _item.audio,
                    links: _item.links,
                    slots: _item.slots,
                    hasSlots: _item.hasSlots,
                    enabled: !_item.enabled,
                    changed: true,
                    children: _item.children,
                    index: _item.index,
                  );
                  widget.onChanged(updated);
                  _update(updated);
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete, size: 18),
                label: const Text('Delete'),
                onPressed: widget.onDelete,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
              if (widget.parent != null && widget.onOutdent != null)
                Tooltip(
                  message: 'Move to grandparent — grandparent becomes parent',
                  child: TextButton.icon(
                    icon: const Icon(Icons.reply_rounded, size: 18),
                    label: const Text('Outdent'),
                    onPressed: () => widget.onOutdent!(),
                  ),
                ),
              if (widget.position != 0)
                Tooltip(
                  message: 'Move up — swap position with previous sibling',
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    label: const Text('Up'),
                    onPressed: () =>
                        widget.onSwap(widget.position, widget.position - 1),
                  ),
                ),
              if (widget.position + 1 != widget.length)
                Tooltip(
                  message: 'Move down — swap position with next sibling',
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    label: const Text('Down'),
                    onPressed: () =>
                        widget.onSwap(widget.position, widget.position + 1),
                  ),
                ),
              if (widget.position != 0)
                Tooltip(
                  message:
                      'Nest inside previous sibling — make item a child of the sibling above it',
                  child: TextButton.icon(
                    icon: Transform.scale(
                      scaleX: -1,
                      child: const Icon(Icons.reply_rounded),
                    ),
                    label: const Text('Nest Above'),
                    onPressed: () => widget.onNest(widget.position - 1),
                  ),
                ),
              if (widget.position + 1 != widget.length)
                Tooltip(
                  message:
                      'Nest inside next sibling — make item a child of the sibling below it',
                  child: TextButton.icon(
                    icon: Transform.scale(
                      scaleX: -1,
                      scaleY: -1,
                      child: const Icon(Icons.reply_rounded),
                    ),
                    label: const Text('Nest Below'),
                    onPressed: () => widget.onNest(widget.position + 1),
                  ),
                ),
            ],
          ),
          ..._item.children.asMap().entries.map((e) {
            ScheduleItem onDelete() {
              final deletedItem = _item.children.removeAt(e.key);
              handleDeletion(_item.children, e.key);
              _update(_item..changed = true);
              return deletedItem;
            }

            return Padding(
              padding: const EdgeInsets.only(left: 24, right: 8, bottom: 8),
              child: _ItemCard(
                key: ValueKey(e.value),
                item: e.value,
                position: e.key,
                length: _item.children.length,
                parent: widget.item,
                maxWeeks: widget.maxWeeks,
                audioMap: widget.audioMap,
                onChanged: (u) {
                  final kids = [..._item.children];
                  kids[e.key] = u;
                  _item.children
                    ..clear()
                    ..addAll(kids);
                  _item.changed = true;
                  _update(_item);
                },
                onDelete: onDelete,
                onSwap: (src, dest) {
                  swapItems(_item.children, src, dest);
                  _update(_item..changed = true);
                },
                onOutdent: () {
                  final item = onDelete();
                  widget.onOutdentParent(item);
                },
                onOutdentParent: (item) {
                  item.changed = true;
                  item.shift = 0;
                  item.index = _item.children.length;
                  setState(() => _item.children.add(item));
                },
                onNest: (dest) => handleNesting(
                  context,
                  _item.children,
                  e.key,
                  dest,
                  onDelete,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ItemEditorDialog extends StatefulWidget {
  final ScheduleItem? item;
  final ScheduleItem? parent;
  final int maxWeeks;
  final List<Map<String, dynamic>> audioMap;
  const _ItemEditorDialog({
    this.item,
    this.parent,
    required this.maxWeeks,
    this.audioMap = const [],
  });
  @override
  State<_ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<_ItemEditorDialog>
    with SlotCommon, ScheduleCommon {
  late final title = TextEditingController(text: widget.item?.title ?? '');
  late String? category = widget.item?.category;
  late final desc = TextEditingController(text: widget.item?.description ?? '');
  late final duration = TextEditingController(
    text: widget.item?.durationMin?.toString() ?? '',
  );
  late final reps = TextEditingController(
    text: widget.item?.reps?.toString() ?? '',
  );
  late final sets = TextEditingController(text: widget.item?.setsAndReps ?? '');
  String? audioValue;
  final customAudio = TextEditingController();
  List<String> links = [];
  final linkCtrl = TextEditingController();
  List<ScheduleSlot> slots = [];
  late bool enabled = widget.item?.enabled ?? true;
  late bool isPlaceHolderItem = widget.item?.isPlaceholderItem ?? false;
  String? _error;

  final categories = const [
    'drill',
    'exercise',
    'hydration',
    'nutrition',
    'rest',
  ];

  @override
  void initState() {
    super.initState();
    slots = List.from(widget.item?.slots ?? []);
    links = List.from(widget.item?.links ?? []);
    final a = widget.item?.audio ?? '';
    if (widget.audioMap.any((m) => m['file'] == a)) {
      audioValue = a;
    } else if (a.isNotEmpty) {
      audioValue = 'custom';
      customAudio.text = a;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'New Item' : 'Edit Item'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Placeholder Item'),
                value: isPlaceHolderItem,
                onChanged: (value) => setState(() {
                  isPlaceHolderItem = value;
                  if (value) {
                    title.text = ScheduleItem.itemWithoutTitle;
                  } else {
                    title.text = widget.item?.title ?? '';
                  }
                }),
              ),
              if (!isPlaceHolderItem) _field(title, 'Title *'),
              SwitchListTile(
                title: const Text('Enabled'),
                value: enabled,
                onChanged: (v) => setState(() => enabled = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => category = v),
              ),
              const SizedBox(height: 8),
              _field(desc, 'Description', maxLines: 2),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      duration,
                      'Duration (min)',
                      type: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field(reps, 'Reps', type: TextInputType.number),
                  ),
                ],
              ),
              _field(sets, 'Sets & Reps'),

              DropdownButtonFormField<String>(
                initialValue: audioValue,
                decoration: const InputDecoration(
                  labelText: 'Audio',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ...widget.audioMap.map(
                    (m) => DropdownMenuItem(
                      value: m['file'] as String,
                      child: Text(m['display'] as String),
                    ),
                  ),
                  const DropdownMenuItem(
                    value: 'custom',
                    child: Text('Custom URL...'),
                  ),
                ],
                onChanged: (v) => setState(() => audioValue = v),
              ),
              if (audioValue == 'custom')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _field(customAudio, 'Audio URL'),
                ),

              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Links',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Wrap(
                spacing: 6,
                children: links
                    .map(
                      (l) => Chip(
                        label: Text(l),
                        onDeleted: () => setState(() => links.remove(l)),
                      ),
                    )
                    .toList(),
              ),
              TextField(
                controller: linkCtrl,
                decoration: const InputDecoration(
                  hintText: 'Add link + Enter',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) {
                    setState(() => links.add(v.trim()));
                    linkCtrl.clear();
                  }
                },
              ),

              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Time Slots',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              ...createSlotRows(slots),
              if (_error != null)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: BouncingScrollPhysics(),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () => _editSlot(null),
                icon: const Icon(Icons.add),
                label: const Text('Add slot'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String l, {
    int maxLines = 1,
    TextInputType? type,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: l,
        border: const OutlineInputBorder(),
      ),
      maxLines: maxLines,
      keyboardType: type,
    ),
  );

  @override
  void _editSlot(int? idx) async {
    final existing = idx != null ? slots[idx] : null;
    final s = await showDialog<ScheduleSlot>(
      context: context,
      builder: (_) => _SlotPicker(
        maxWeeks: widget.maxWeeks,
        slot: existing,
        parent: widget.item,
        parentOfParent: widget.parent,
      ),
    );
    if (s != null) {
      setState(() {
        if (idx == null) {
          slots.add(s);
        } else {
          slots[idx] = s;
        }
      });
    }
  }

  @override
  void _deleteSlot(int idx) {
    if (widget.item != null) {
      final error = validateChildrenTimeSlotsPostDeletion(
        parent: widget.item!,
        deletedIndex: idx,
      );
      if (error != null) {
        setState(() => _error = 'Deletion failed: $error');
        showErrorDialog(context, error);
        return;
      }
    }
    setState(() => slots.removeAt(idx));
  }

  void _save() {
    final audio = audioValue == 'custom' ? customAudio.text.trim() : audioValue;
    final item = ScheduleItem(
      title: isPlaceHolderItem
          ? ScheduleItem.itemWithoutTitle
          : title.text.trim(),
      enabled: enabled,
      changed: true,
      category: category,
      description: desc.text.isEmpty ? null : desc.text,
      durationMin: int.tryParse(duration.text),
      reps: int.tryParse(reps.text),
      setsAndReps: sets.text.isEmpty ? null : sets.text,
      audio: (audio?.isEmpty ?? true) ? null : audio,
      links: links,
      slots: slots,
      hasSlots: widget.item == null ? true : widget.item!.hasSlots,
      children: widget.item?.children ?? [],
      index: widget.item == null ? -1 : widget.item!.index,
    );
    if (widget.item != null) {
      addSlotKeysIfMissing(widget.item!, slots);
    }
    Navigator.pop(context, item);
  }
}

class _SlotPicker extends StatefulWidget {
  final int maxWeeks;
  final ScheduleSlot? slot;
  final ScheduleItem? parent;
  final ScheduleItem? parentOfParent;
  const _SlotPicker({
    required this.maxWeeks,
    this.slot,
    required this.parent,
    required this.parentOfParent,
  });
  @override
  State<_SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<_SlotPicker>
    with SlotCommon, ScheduleCommon {
  late Set<int> weeks;
  late Set<int> days;
  late bool hasTime;
  late TimeOfDay start;
  late TimeOfDay end;
  String? _error;

  @override
  void initState() {
    super.initState();
    weeks = Set.from(widget.slot?.weeks ?? [1]);
    days = Set.from(widget.slot?.days ?? [1, 2, 3, 4, 5]);
    hasTime = widget.slot?.hasTime ?? false;
    start = _p(widget.slot?.timeStart ?? '09:00');
    end = _p(widget.slot?.timeEnd ?? '10:00');
  }

  TimeOfDay _p(String t) => TimeOfDay(
    hour: int.parse(t.split(':')[0]),
    minute: int.parse(t.split(':')[1]),
  );

  @override
  void _copySlot(int idx) {
    if (widget.parent == null) return;

    final slot = widget.parent!.slots[idx];
    setState(() {
      weeks = slot.weeks.toSet();
      days = slot.days.toSet();
      hasTime = slot.hasTime;
      if (hasTime) {
        start = _p(slot.timeStart);
        end = _p(slot.timeEnd);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.slot == null ? 'Add Slot' : 'Edit Slot'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.parent != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Parent Time Slots',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            ...createSlotRows(
              widget.parent!.slots,
              editable: false,
              copyable: true,
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: BouncingScrollPhysics(),
              child: Text(
                'Please ensure that the time slot below is contained within any of the parent time slots above.',
              ),
            ),
          ],
          Divider(),
          const Text('Weeks'),
          Wrap(
            children: List.generate(widget.maxWeeks, (i) {
              final w = i + 1;
              return FilterChip(
                label: Text('W$w'),
                selected: weeks.contains(w),
                onSelected: (v) =>
                    setState(() => v ? weeks.add(w) : weeks.remove(w)),
              );
            }),
          ),
          const SizedBox(height: 12),
          const Text('Days'),
          Wrap(
            children: ScheduleCommon.weekNames.entries.map((e) {
              final d = e.key;
              return FilterChip(
                label: Text(e.value),
                selected: days.contains(d),
                onSelected: (v) =>
                    setState(() => v ? days.add(d) : days.remove(d)),
              );
            }).toList(),
          ),
          CheckboxListTile(
            title: const Text('Has time: Time will be inherited from parent'),
            value: hasTime,
            onChanged: (v) => setState(() => hasTime = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (hasTime) ...[
            ListTile(
              title: Text('Start: ${start.format(context)}'),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: start,
                );
                if (t != null) setState(() => start = t);
              },
            ),
            ListTile(
              title: Text('End: ${end.format(context)}'),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: end,
                );
                if (t != null) setState(() => end = t);
              },
            ),
          ],
          if (_error != null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: BouncingScrollPhysics(),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _done, child: const Text('Save')),
    ],
  );

  void _done() {
    String f(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final ts = f(start);
    final te = f(end);
    final newSlot = ScheduleSlot(
      weeks.toList()..sort(),
      days.toList()..sort(),
      hasTime,
      ts,
      te,
      -1,
      '',
      '',
      changed: true,
    );

    if (widget.parentOfParent != null) {
      // Check if parent ScheduleItem allows this slot
      final err = validateTimeSlotAgainstParent(
        weeks: weeks.toList(),
        days: days.toList(),
        hasTime: hasTime,
        ts: ts,
        te: te,
        parent: widget.parentOfParent!,
      );
      if (err != null) {
        setState(() => _error = 'Validation Error: $err');
        showErrorDialog(context, 'Validation Error: $err');
        return;
      }
    }

    if (widget.slot != null) {
      // Only check children if the slot is being editted and not added
      List<ScheduleSlot> parentSlots = [];
      final err2 = validateChildrenTimeSlotsAgainstParentSlots(
        parent: widget.parent!,
        parentSlots: parentSlots
          ..addAll(widget.parent!.slots) // add all parent slots
          ..add(newSlot) // add new slot
          ..remove(widget.slot), //remove its prior version
      );
      if (err2 != null) {
        setState(() => _error = 'Validation Error: $err2.');
        showSnackBar(context, 'Validation Error: $err2');
        return;
      }
    }

    Navigator.pop(context, newSlot);
  }
}

mixin SlotCommon implements ScheduleCommon {
  void setState(VoidCallback fn);
  void _editSlot(int? idx) async {}
  void _deleteSlot(int idx) async {}
  void _copySlot(int idx) async {}

  List<Widget> createSlotRows(
    List<ScheduleSlot> slots, {
    bool editable = true,
    bool copyable = false,
  }) => slots
      .toList()
      .asMap()
      .entries
      .map(
        (e) => ListTile(
          dense: true,
          title: Text(
            slotTitle(e.value),
            style: e.value.inherited
                ? TextStyle(fontStyle: FontStyle.italic)
                : null,
          ),
          trailing: copyable
              ? Tooltip(
                  message: 'Assign this parent slot\'s value to slot',
                  child: IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => _copySlot(e.key),
                  ),
                )
              : editable
              ? !e.value.inherited
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _editSlot(e.key),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _deleteSlot(e.key),
                          ),
                        ],
                      )
                    : Tooltip(
                        message:
                            'This is inherited from parent, hence not editable',
                        child: Icon(Icons.edit_off),
                      )
              : null,
          onTap: editable && !e.value.inherited ? () => _editSlot(e.key) : null,
        ),
      )
      .toList();
}

void addSlotKeysIfMissing(ScheduleItem item, List<ScheduleSlot> slots) {
  for (int i = 0; i < slots.length; i++) {
    if (slots[i].changed) {
      final s = slots[i];
      s.index = i;
    }
  }
}

class WeeksRangeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(oldValue, newValue) {
    if (newValue.text.isEmpty) return newValue;
    final v = int.tryParse(newValue.text);
    if (v == null) return oldValue;
    if (v < 1 || v > 100) return oldValue;
    return newValue;
  }
}
