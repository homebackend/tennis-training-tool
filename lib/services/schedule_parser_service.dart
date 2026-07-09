/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:collection/collection.dart';
import 'package:yaml/yaml.dart';

import '../mixins/schedule_common.dart';
import '../models/schedule.dart';

class ScheduleParser with ScheduleCommon {
  static final dummyTitle = '__DUMMY__';

  late DateTime startDate;
  late int cycleWeeks;

  ScheduleParser();

  (DateTime, int, List<ScheduleItem>) parse(
    String yamlText, {
    bool includeDisabled = true,
  }) {
    final doc = loadYamlDocument(yamlText);
    return parseDocument(doc, includeDisabled: includeDisabled);
  }

  (DateTime, int, List<ScheduleItem>) parseDocument(
    YamlDocument doc, {
    bool includeDisabled = true,
  }) {
    final root = doc.contents;
    if (root is! YamlMap || !root.containsKey('schedule')) {
      throw YamlValidationError('Missing top-level "schedule"', _line(root));
    }

    final sched = root['schedule'] as YamlMap;
    final startNode = sched.nodes['start'];
    if (startNode == null) {
      throw YamlValidationError('start date is missing', _line(root));
    }
    final weeksNode = sched.nodes['repeatWeeks'];
    if (weeksNode == null) {
      throw YamlValidationError('repeatWeeks is missing', _line(root));
    }
    startDate = DateTime.parse(startNode.toString());
    cycleWeeks = int.parse(weeksNode.toString());
    final itemsNode = sched.nodes['items'];
    if (itemsNode is! YamlList) {
      throw YamlValidationError('"items" must be a list', _line(itemsNode));
    }
    return (
      startDate,
      cycleWeeks,
      itemsNode.nodes
          .mapIndexed((i, n) => _parseNode(n, null, includeDisabled, i))
          .whereType<ScheduleItem>()
          .toList(),
    );
  }

  ScheduleItem? _parseNode(
    YamlNode node,
    ScheduleItem? parent,
    bool includeDisabled,
    int index,
  ) {
    if (node is YamlScalar) {
      return ScheduleItem(
        title: node.value.toString(),
        slots: parent?.slots ?? [],
        isScalar: true,
        index: index,
        hasSlots: false,
      );
    }
    if (node is! YamlMap) {
      throw YamlValidationError('Invalid item', _line(node));
    }

    final enabled = node['enabled'] ?? true;
    if (!includeDisabled && !enabled) {
      return null;
    }

    final title = node['title']?.toString() ?? dummyTitle;
    final category = node['category']?.toString();
    final description = node['description']?.toString();
    final duration = node['time'] is int ? node['time'] as int : null;
    final reps = node['reps'] is int ? node['reps'] as int : null;
    final audio = node['audio']?.toString();
    final setsAndReps = node['setsAndReps']?.toString();

    final links = <String>[];
    final linkVal = node['link'];
    if (linkVal != null) {
      if (linkVal is YamlList) {
        links.addAll(linkVal.map((e) => e.toString()));
      } else {
        links.add(linkVal.toString());
      }
    }

    final slots = <ScheduleSlot>[];
    final schedNode = node.nodes['schedule'];
    if (schedNode != null) {
      final List<YamlNode> entries = schedNode is YamlList
          ? schedNode.nodes
          : (schedNode is YamlMap ? [schedNode] : []);

      for (int i = 0; i < entries.length; i++) {
        final sNode = entries[i];
        final s = sNode as YamlMap;
        if (s.containsKey('weeks')) {
          throw YamlValidationError('Use "week" not "weeks"', _line(s));
        }

        final enabled = s['enabled'] ?? true;
        if (!includeDisabled && !enabled) {
          continue;
        }

        final weekRaw = s['week'];
        final daysRaw = s['days'];
        if (weekRaw == null || daysRaw == null) {
          throw YamlValidationError('week/days missing', _line(s));
        }

        final weeks = _expand(s['week'].toString(), _line(s.nodes['week']));
        final days = _expand(s['days'].toString(), _line(s.nodes['days']));

        final hasTime = s.containsKey('timeStart') && s.containsKey('timeEnd');
        final ts = s['timeStart']?.toString();
        final te = s['timeEnd']?.toString();

        if (parent != null && parent.slots.isNotEmpty) {
          final splits = getEncapsulatingTimeSlots(
            weeks: weeks,
            days: days,
            hasTime: hasTime,
            ts: ts,
            te: te,
            parent: parent,
          );

          for (int i = 0; i < splits.length; i++) {
            final (iw, id, useStart, useEnd) = splits[i];
            slots.add(
              ScheduleSlot(
                iw,
                id,
                hasTime,
                useStart,
                useEnd,
                i,
                weekRaw.toString(),
                daysRaw.toString(),
                description: s['description']?.toString(),
              ),
            );
          }
        } else {
          slots.add(
            ScheduleSlot(
              weeks,
              days,
              hasTime,
              ts ?? '00:00',
              te ?? '23:59',
              i,
              weekRaw.toString(),
              daysRaw.toString(),
              description: s['description']?.toString(),
            ),
          );
        }
      }
    } else if (parent != null) {
      slots.addAll(parent.slots.map((s) => s.copyWith(inherited: true)));
    }

    final children = <ScheduleItem>[];
    final itemsNode = node.nodes['items'];
    if (itemsNode is YamlList) {
      for (int i = 0; i < itemsNode.nodes.length; i++) {
        final c = itemsNode.nodes[i];
        final childItem = _parseNode(
          c,
          ScheduleItem(
            title: title,
            slots: slots,
            index: -1,
            hasSlots: schedNode != null,
            children: [],
          ),
          includeDisabled,
          i,
        );

        if (childItem != null) {
          children.add(childItem);
        }
      }
    }

    return ScheduleItem(
      title: title,
      category: category,
      description: description,
      enabled: enabled,
      slotsAsArray: schedNode is YamlList,
      slots: slots,
      hasSlots: schedNode != null,
      children: children,
      durationMin: duration,
      reps: reps,
      links: links,
      audio: audio,
      setsAndReps: setsAndReps,
      index: index,
    );
  }

  List<int> _expand(String s, int? line) {
    try {
      final out = <int>[];
      for (final part in s.split(',')) {
        final p = part.trim();
        if (p.contains('-')) {
          final a = p.split('-');
          for (var i = int.parse(a[0]); i <= int.parse(a[1]); i++) {
            out.add(i);
          }
        } else if (p.isNotEmpty) {
          out.add(int.parse(p));
        }
      }
      return out;
    } catch (_) {
      throw YamlValidationError('Invalid range "$s"', line);
    }
  }

  int? _line(dynamic node) =>
      node is YamlNode ? node.span.start.line + 1 : null;
}
