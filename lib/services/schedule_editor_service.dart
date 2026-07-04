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
    updateListWithKey(editor, ['schedule'], 'items', items);

    return editor.toString();
  }

  void updateListWithKey(
    YamlEditor editor,
    List<dynamic> keys,
    String key,
    List<dynamic> items,
  ) {
    final newKeys = [...keys, key];

    try {
      editor.parseAt(newKeys);
    } catch (e) {
      editor.update(newKeys, []);
    }

    final YamlList currentItems = editor.parseAt(newKeys).value as YamlList;
    final List<int> matchedIndexes = [];
    final int originalItemLength = currentItems.length;

    for (final item in items) {
      int index = -1;

      for (int i = 0; i < currentItems.length; i++) {
        final currentItem = currentItems[i];
        if ((currentItem is YamlMap &&
                item is ScheduleItem &&
                !item.isScalar &&
                currentItem.value['title'] == item.title) ||
            (currentItem is String &&
                item is ScheduleItem &&
                item.isScalar &&
                currentItem == item.title)) {
          matchedIndexes.add(i);
          index = i;
          break;
        }
      }

      if (index == -1) {
        // New Item
        // Simple convert of map and append
        appendToList(editor, newKeys, item);
      } else {
        // Existing item
        // Here attribute level updation is performed
        updateItem(editor, [...newKeys, index], item);
      }
    }

    // Now remove all existing items not present in current items
    for (int i = originalItemLength; i > 0; i--) {
      if (!matchedIndexes.contains(i - 1)) {
        editor.remove([...newKeys, i - 1]);
      }
    }

    if (items.isEmpty) {
      editor.remove(newKeys);
    }
  }

  void updateItem(YamlEditor editor, List<dynamic> keys, dynamic it) {
    if (it is String || it is int) {
      editor.update(keys, it);
    } else if (it is ScheduleItem) {
      if (it.isScalar) {
        editor.update(keys, it.title);
      } else {
        updateKeyValue(
          editor,
          keys,
          'title',
          it.title,
          valueCheck: '__DUMMY__',
        );
        updateKeyValue(editor, keys, 'category', it.category);
        updateKeyValue(editor, keys, 'description', it.description);
        updateKeyValue(editor, keys, 'time', it.durationMin);
        updateKeyValue(editor, keys, 'reps', it.reps);
        updateKeyValue(editor, keys, 'setsAndReps', it.setsAndReps);
        updateKeyValue(editor, keys, 'audio', it.audio);
        updateListWithKey(editor, keys, 'link', it.links);
        updateListWithKey(editor, keys, 'items', it.children);
      }
    }
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

  void updateKeyValue(
    YamlEditor editor,
    List<dynamic> keys,
    String key,
    dynamic value, {
    dynamic valueCheck,
  }) {
    if (value != valueCheck) {
      editor.update([...keys, key], value);
    } else {
      try {
        editor.remove([...keys, key]);
      } catch (_) {}
    }
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
