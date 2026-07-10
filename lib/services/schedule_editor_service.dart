/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter_common/tool.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../models/schedule.dart';

class ScheduleEditorService {
  final String? initialYaml;
  ScheduleEditorService(this.initialYaml);

  Future<String> toYaml(
    DateTime start,
    int cycleWeeks,
    List<ScheduleItem> items,
  ) async {
    final editor = YamlEditor(
      initialYaml == null || initialYaml!.trim().isEmpty ? '{}' : initialYaml!,
    );
    editor.update(['metadata'], await generateAuditPayload());

    try {
      editor.parseAt(['schedule']);
    } catch (_) {
      editor.update(['schedule'], {});
    }

    editor.update(['schedule', 'start'], _date(start));
    editor.update(['schedule', 'repeatWeeks'], cycleWeeks);
    updateItems(editor, ['schedule', 'items'], items, singleItemAsArray: true);

    return editor.toString();
  }

  void updateItems(
    YamlEditor editor,
    List<dynamic> parentKeys,
    List<dynamic> items, {
    bool singleItemAsArray = false,
  }) {
    if (items.isEmpty) {
      try {
        editor.remove(parentKeys);
      } catch (_) {}
      return;
    }

    try {
      final node = editor.parseAt(parentKeys).value;
      if (node is! List) {
        editor.update(parentKeys, [node]);
      }
    } catch (e) {
      editor.update(parentKeys, []);
    }

    final currentItems = editor.parseAt(parentKeys).value;
    final List<int> matchedIndexes = [];
    final int originalItemLength = currentItems.length;

    for (int i = 0; i < items.length; i++) {
      if (updateItem(editor, parentKeys, items[i], i)) {
        matchedIndexes.add(i);
      }
    }

    // Now remove all existing items not present in current items
    for (int i = originalItemLength; i > 0; i--) {
      if (!matchedIndexes.contains(i - 1)) {
        editor.remove([...parentKeys, i - 1]);
      }
    }

    // If single item convert to object from list
    if (!singleItemAsArray && items.length == 1) {
      final node = editor.parseAt(parentKeys).value;
      if (node is List && node.isNotEmpty) {
        editor.update(parentKeys, node[0]);
      }
    }
  }

  bool updateItem(
    YamlEditor editor,
    List<dynamic> parentKeys,
    dynamic item,
    int i,
  ) {
    bool matched = false;
    if (item is ScheduleItem || item is ScheduleSlot) {
      try {
        final newkeys = [...parentKeys, item.index];
        editor.parseAt(newkeys);
        matched = true;
        if (item is ScheduleItem) {
          if (!item.changed) {
            return matched;
          }
          if (item.isScalar) {
            updateKeyValue(editor, parentKeys, i, item.title);
          } else {
            updateScheduleItem(editor, newkeys, item);
          }
        } else if (item is ScheduleSlot) {
          if (item.changed) {
            updateSlot(editor, newkeys, item);
          } else {
            return matched;
          }
        }
      } catch (_) {
        appendToList(editor, parentKeys, item);
      }
    } else if (item is String || item is int) {
      final currentItems = editor.parseAt(parentKeys).value;
      int index = updatePrimitiveToList(editor, currentItems, parentKeys, item);
      if (index >= 0) {
        matched = true;
      }
    }

    return matched;
  }

  void updateScheduleItem(
    YamlEditor editor,
    List<dynamic> keys,
    ScheduleItem it,
  ) {
    if (!it.enabled) {
      editor.update([...keys, 'enabled'], it.enabled);
    }
    updateKeyValue(
      editor,
      keys,
      'title',
      it.title,
      valueCheck: ScheduleItem.itemWithoutTitle,
    );
    updateKeyValue(editor, keys, 'category', it.category);
    updateKeyValue(editor, keys, 'description', it.description);
    updateKeyValue(editor, keys, 'time', it.durationMin);
    updateKeyValue(editor, keys, 'reps', it.reps);
    updateKeyValue(editor, keys, 'setsAndReps', it.setsAndReps);
    updateKeyValue(editor, keys, 'audio', it.audio);
    updateItems(editor, [...keys, 'link'], it.links);
    List<ScheduleSlot> as = it.actualSlots();
    if (as.isNotEmpty) {
      updateItems(
        editor,
        [...keys, 'schedule'],
        as,
        singleItemAsArray: it.slotsAsArray,
      );
    } else {
      try {
        editor.remove([...keys, 'schedule']);
      } catch (_) {}
    }
    updateItems(editor, [...keys, 'items'], it.children);
  }

  void updateSlot(YamlEditor editor, List<dynamic> keys, ScheduleSlot slot) {
    if (!slot.enabled) {
      editor.update([...keys, 'enabled'], slot.enabled);
    }
    if (slot.weeks.isNotEmpty) {
      updateKeyValue(editor, keys, 'week', slot.weekYamlValue());
    }
    if (slot.days.isNotEmpty) {
      updateKeyValue(editor, keys, 'days', slot.daysYamlValue());
    }
    if (slot.hasTime) {
      updateKeyValue(editor, keys, 'timeStart', slot.timeStart);
      updateKeyValue(editor, keys, 'timeEnd', slot.timeEnd);
    }
    updateKeyValue(editor, keys, 'description', slot.description);
  }

  int updatePrimitiveToList<T>(
    YamlEditor editor,
    YamlList currentItems,
    List<dynamic> parentKeys,
    T value,
  ) {
    for (int i = 0; i < currentItems.length; i++) {
      final currentItem = currentItems[i];
      if (currentItem is T && currentItem == value) {
        return i;
      }
    }

    appendToList(editor, parentKeys, value);
    return -1;
  }

  void appendToList(YamlEditor editor, List<dynamic> keys, dynamic it) {
    if (it is String || it is int) {
      editor.appendToList(keys, it);
    } else if (it is ScheduleItem) {
      if (it.isScalar) {
        editor.appendToList(keys, it.title);
      } else {
        editor.appendToList(keys, itemToYaml(it));
      }
    } else if (it is ScheduleSlot) {
      editor.appendToList(keys, itemToYaml(it));
    }
  }

  dynamic itemToYaml(dynamic it) {
    if (it is ScheduleItem) {
      return it.toYaml();
    } else if (it is ScheduleSlot) {
      return it.toMap();
    }
    return {};
  }

  void updateKeyValue<T>(
    YamlEditor editor,
    List<dynamic> keys,
    T key,
    dynamic value, {
    dynamic valueCheck,
  }) {
    final newKeys = [...keys, key];
    if (value != valueCheck) {
      try {
        final current = editor.parseAt(newKeys).value;
        if ('$current' == '$value') return;
      } catch (_) {}
      editor.update(newKeys, value);
    } else {
      try {
        editor.remove(newKeys);
      } catch (_) {}
    }
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
