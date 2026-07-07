/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../mixins/yaml_diff_deviation.dart';
import '../models/schedule.dart';
import '../services/schedule_editor_service.dart';
import '../services/schedule_parser_service.dart';

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
    with YamlDiffDeviation {
  bool _dirty = false;
  final _parser = ScheduleParser();
  late ScheduleEditorService _service;
  List<Map<String, dynamic>> _audioMap = [];

  DateTime start = DateTime.now();
  int weeks = 2;
  final List<ScheduleItem> items = [];
  late final TextEditingController _weeksController;

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
      final (s, w, its) = _parser.parse(
        widget.initialYaml!,
        includeDisabled: true,
      );
      start = s;
      weeks = w;
      items.addAll(its);
    }
    _weeksController = TextEditingController(text: weeks.toString());
  }

  @override
  void dispose() {
    _weeksController.dispose();
    super.dispose();
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
                          setState(() => start = d);
                        }
                      },
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Repeat every (weeks)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      controller: _weeksController,
                      onChanged: (v) {
                        _markDirty();
                        weeks = int.tryParse(v) ?? weeks;
                      },
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
            ...items.asMap().entries.map(
              (e) => _ItemCard(
                key: ValueKey(e.value),
                item: e.value,
                maxWeeks: weeks,
                audioMap: _audioMap,
                onChanged: (u) {
                  _markDirty();
                  setState(() => items[e.key] = u);
                },
                onDelete: () {
                  _markDirty();
                  setState(() => items.removeAt(e.key));
                  for (int i = e.key; i < items.length; i++) {
                    final item = items[i];
                    item.index--;
                    item.changed = true;
                  }
                },
              ),
            ),
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
        maxWeeks: weeks,
        audioMap: _audioMap,
      ),
    );
    if (result != null) {
      if (update != null) {
        update(result);
      } else {
        setState(() => items.add(result));
      }
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _save() async {
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
  }
}

class _ItemCard extends StatefulWidget {
  final ScheduleItem item;
  final ValueChanged<ScheduleItem> onChanged;
  final VoidCallback onDelete;
  final int maxWeeks;
  final List<Map<String, dynamic>> audioMap;
  const _ItemCard({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDelete,
    required this.maxWeeks,
    required this.audioMap,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
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
        title: Row(
          children: [
            if (!_item.enabled)
              const Icon(Icons.visibility_off, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              _item.title,
              style: TextStyle(
                decoration: _item.enabled ? null : TextDecoration.lineThrough,
                color: _item.enabled ? null : Colors.grey,
              ),
            ),
          ],
        ),
        subtitle: Text(
          [
            if (_item.category != null) _item.category!,
            '${_item.slots.length} slots',
          ].join(' • '),
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
                    r.index = _item.children.length - 1;
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
            ],
          ),
          ..._item.children.asMap().entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(left: 24, right: 8, bottom: 8),
              child: _ItemCard(
                key: ValueKey(e.value),
                item: e.value,
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
                onDelete: () {
                  _item.children.removeAt(e.key);
                  for (int i = e.key; i < _item.children.length; i++) {
                    final item = _item.children[i];
                    item.index--;
                    item.changed = true;
                  }
                  _update(_item..changed = true);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemEditorDialog extends StatefulWidget {
  final ScheduleItem? item;
  final int maxWeeks;
  final List<Map<String, dynamic>> audioMap;
  const _ItemEditorDialog({
    this.item,
    required this.maxWeeks,
    this.audioMap = const [],
  });
  @override
  State<_ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<_ItemEditorDialog> {
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
              _field(title, 'Title *'),
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
              ...slots.asMap().entries.map(
                (e) => ListTile(
                  dense: true,
                  title: Text(
                    'W:${_c(e.value.weeks)} • ${_days(e.value.days)} • ${e.value.timeStart}-${e.value.timeEnd}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => _editSlot(e.key),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => slots.removeAt(e.key)),
                      ),
                    ],
                  ),
                  onTap: () => _editSlot(e.key),
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

  String _c(List<int> v) => v.join(',');
  String _days(List<int> d) => d
      .map((e) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][e - 1])
      .join(',');

  void _editSlot(int? idx) async {
    final existing = idx != null ? slots[idx] : null;
    final s = await showDialog<ScheduleSlot>(
      context: context,
      builder: (_) => _SlotPicker(maxWeeks: widget.maxWeeks, slot: existing),
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

  void _save() {
    final audio = audioValue == 'custom' ? customAudio.text.trim() : audioValue;
    final item = ScheduleItem(
      title: title.text.trim().isEmpty
          ? ScheduleParser.dummyTitle
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
  const _SlotPicker({required this.maxWeeks, this.slot});
  @override
  State<_SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<_SlotPicker> {
  late Set<int> weeks;
  late Set<int> days;
  late TimeOfDay start;
  late TimeOfDay end;

  @override
  void initState() {
    super.initState();
    weeks = Set.from(widget.slot?.weeks ?? [1]);
    days = Set.from(widget.slot?.days ?? [1, 2, 3, 4, 5]);
    start = _p(widget.slot?.timeStart ?? '09:00');
    end = _p(widget.slot?.timeEnd ?? '10:00');
  }

  TimeOfDay _p(String t) => TimeOfDay(
    hour: int.parse(t.split(':')[0]),
    minute: int.parse(t.split(':')[1]),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.slot == null ? 'Add Slot' : 'Edit Slot'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            children: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                .asMap()
                .entries
                .map((e) {
                  final d = e.key + 1;
                  return FilterChip(
                    label: Text(e.value),
                    selected: days.contains(d),
                    onSelected: (v) =>
                        setState(() => v ? days.add(d) : days.remove(d)),
                  );
                })
                .toList(),
          ),
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
    Navigator.pop(
      context,
      ScheduleSlot(
        weeks.toList()..sort(),
        days.toList()..sort(),
        false,
        f(start),
        f(end),
        -1,
        '',
        '',
        changed: true,
      ),
    );
  }
}

void addSlotKeysIfMissing(ScheduleItem item, List<ScheduleSlot> slots) {
  for (int i = 0; i < slots.length; i++) {
    if (slots[i].changed) {
      final s = slots[i];
      s.index = i;
    }
  }
}
