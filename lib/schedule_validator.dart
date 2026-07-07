import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

import 'models/schedule.dart';
import 'services/schedule_parser_service.dart';

void main(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : 'assets/training_schedule.yaml';
  final text = await File(path).readAsString();
  final doc = loadYamlDocument(text);
  final parser = ScheduleParser();

  try {
    final (start, weeks, items) = parser.parseDocument(doc);
    debugPrint('✓ YAML valid\n');
    _printWeekly(items, weeks);
  } on YamlValidationError catch (e) {
    stderr.writeln(
      '✗ ${e.message}${e.line != null ? ' (line ${e.line})' : ''}',
    );
    exit(1);
  }
}

void _printWeekly(List<ScheduleItem> items, int cycleWeeks) {
  const days = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  bool hasSlot(ScheduleItem it, int w, int d) =>
      it.slots.any((s) => s.weeks.contains(w) && s.days.contains(d));

  void printNode(
    ScheduleItem node,
    int w,
    int d,
    String? pStart,
    String? pEnd,
    String pad,
    bool last,
  ) {
    // skip placeholder nodes
    if (node.title.trim().isEmpty || node.title == ScheduleParser.dummyTitle) {
      final kids = node.children.where((c) => hasSlot(c, w, d)).toList();
      for (var i = 0; i < kids.length; i++) {
        printNode(
          kids[i],
          w,
          d,
          pStart,
          pEnd,
          pad,
          i == kids.length - 1 && last,
        );
      }
      return;
    }

    final slots =
        node.slots
            .where((s) => s.weeks.contains(w) && s.days.contains(d))
            .toList()
          ..sort((a, b) => _toMin(a.timeStart).compareTo(_toMin(b.timeStart)));

    for (var si = 0; si < slots.length; si++) {
      final s = slots[si];
      final isLastSlot = si == slots.length - 1 && last;
      final sameAsParent = pStart == s.timeStart && pEnd == s.timeEnd;
      final branch = isLastSlot ? '└' : '├';

      if (!sameAsParent) {
        debugPrint(
          '$pad$branch─ • ${_fmt(s.timeStart)}-${_fmt(s.timeEnd)} ─ ${node.title}',
        );
      } else {
        debugPrint('$pad$branch─ ${node.title}');
      }

      final childPad = pad + (isLastSlot ? ' ' : '│ ');
      final kids = node.children.where((c) => hasSlot(c, w, d)).toList();
      for (var i = 0; i < kids.length; i++) {
        printNode(
          kids[i],
          w,
          d,
          s.timeStart,
          s.timeEnd,
          childPad,
          i == kids.length - 1,
        );
      }
    }
  }

  debugPrint('Schedule');
  for (var w = 1; w <= cycleWeeks; w++) {
    final weekLast = w == cycleWeeks;
    debugPrint('${weekLast ? '└' : '├'}─ Week $w');
    final weekPad = weekLast ? ' ' : '│ ';

    for (var d = 1; d <= 7; d++) {
      final dayNodes = items.where((n) => hasSlot(n, w, d)).toList();
      if (dayNodes.isEmpty) continue;

      debugPrint('$weekPad${'├'}─ ${days[d]}');
      final dayPad = '$weekPad│ ';

      for (var i = 0; i < dayNodes.length; i++) {
        printNode(
          dayNodes[i],
          w,
          d,
          null,
          null,
          dayPad,
          i == dayNodes.length - 1,
        );
      }
    }
  }
}

String _fmt(String hhmm) {
  final p = hhmm.split(':');
  var h = int.parse(p[0]);
  final m = p[1];
  final ampm = h >= 12 ? 'PM' : 'AM';
  h = h % 12;
  if (h == 0) h = 12;
  return '$h:$m $ampm';
}

int _toMin(String t) {
  final p = t.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}
