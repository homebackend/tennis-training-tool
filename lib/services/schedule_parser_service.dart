/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:yaml/yaml.dart';

import '../models/schedule.dart';

class ScheduleParser {
  final DateTime startDate;
  final int cycleWeeks;

  ScheduleParser({required this.startDate, required this.cycleWeeks});

  List<ScheduleItem> parse(String yamlText) {
    final doc = loadYamlDocument(yamlText);
    return parseDocument(doc);
  }

  List<ScheduleItem> parseDocument(YamlDocument doc) {
    final root = doc.contents;
    if (root is! YamlMap || !root.containsKey('schedule')) {
      throw YamlValidationError('Missing top-level "schedule"', _line(root));
    }
    final sched = root['schedule'] as YamlMap;
    final itemsNode = sched.nodes['items'];
    if (itemsNode is! YamlList) {
      throw YamlValidationError('"items" must be a list', _line(itemsNode));
    }
    return itemsNode.nodes.map((n) => _parseNode(n, null)).toList();
  }

  ScheduleItem _parseNode(YamlNode node, ScheduleItem? parent) {
    if (node is YamlScalar) {
      return ScheduleItem(
        title: node.value.toString(),
        slots: parent?.slots ?? [],
      );
    }
    if (node is! YamlMap) {
      throw YamlValidationError('Invalid item', _line(node));
    }

    final title = node['title']?.toString() ?? 'Untitled';
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

      for (final sNode in entries) {
        final s = sNode as YamlMap;
        if (s.containsKey('weeks')) {
          throw YamlValidationError('Use "week" not "weeks"', _line(s));
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
          final childLine = _line(node.nodes['title']) ?? _line(node);
          const names = {
            1: 'Mon',
            2: 'Tue',
            3: 'Wed',
            4: 'Thu',
            5: 'Fri',
            6: 'Sat',
            7: 'Sun',
          };

          // 1. make sure every week/day is covered by SOME parent window
          for (final w in weeks) {
            for (final d in days) {
              final ok = parent.slots.any(
                (ps) => ps.weeks.contains(w) && ps.days.contains(d),
              );
              if (!ok) {
                throw YamlValidationError(
                  'Schedule mismatch at "$title" (line $childLine): ${names[d]} week $w not offered by parent "${parent.title}"',
                  childLine,
                );
              }
            }
          }

          // 2. split child across all matching parent windows (inherit time)
          for (final ps in parent.slots) {
            final iw = weeks.where(ps.weeks.contains).toList();
            final id = days.where(ps.days.contains).toList();
            if (iw.isEmpty || id.isEmpty) continue;

            final useStart = hasTime ? ts! : ps.timeStart;
            final useEnd = hasTime ? te! : ps.timeEnd;

            if (hasTime &&
                (_toMin(useStart) < _toMin(ps.timeStart) ||
                    _toMin(useEnd) > _toMin(ps.timeEnd))) {
              throw YamlValidationError(
                'Time mismatch at "$title": $useStart-$useEnd outside parent ${ps.timeStart}-${ps.timeEnd}',
                childLine,
              );
            }
            slots.add(
              ScheduleSlot(
                iw,
                id,
                useStart,
                useEnd,
                s['description']?.toString(),
              ),
            );
          }
        } else {
          // no parent – keep what was given, or default to full day
          slots.add(
            ScheduleSlot(
              weeks,
              days,
              ts ?? '00:00',
              te ?? '23:59',
              s['description']?.toString(),
            ),
          );
        }
      }
    } else if (parent != null) {
      slots.addAll(parent.slots); // inherit everything
    }

    final children = <ScheduleItem>[];
    final itemsNode = node.nodes['items'];
    if (itemsNode is YamlList) {
      for (final c in itemsNode.nodes) {
        children.add(
          _parseNode(c, ScheduleItem(title: title, slots: slots, children: [])),
        );
      }
    }

    return ScheduleItem(
      title: title,
      category: category,
      description: description,
      slots: slots,
      children: children,
      durationMin: duration,
      reps: reps,
      links: links,
      audio: audio,
      setsAndReps: setsAndReps,
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

  int _toMin(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  // <-- this is the missing helper
  int? _line(dynamic node) =>
      node is YamlNode ? node.span.start.line + 1 : null;
}
