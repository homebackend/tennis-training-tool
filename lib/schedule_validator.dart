import 'dart:io';
import 'package:yaml/yaml.dart';

import 'models/schedule.dart';
import 'services/schedule_parser_service.dart';

void main1(List<String> xargs) {
  final args = List<String>.from(xargs);
  args.add('training_schedule.yaml');
  if (args.isEmpty) {
    print('Usage: dart run bin/validate.dart <schedule.yaml>');
    exit(1);
  }
  final text = File(args[0]).readAsStringSync();
  final doc = loadYamlDocument(text);
  try {
    final parser = ScheduleParser(
      startDate: DateTime(2026, 6, 22),
      cycleWeeks: 8,
    );
    final items = parser.parseDocument(doc);
    print('✓ Valid — ${items.length} top-level items');
    _dump(items, 0);
  } on YamlValidationError catch (e) {
    print('✗ ${e}');
    exit(2);
  }
}

void _dump(List<ScheduleItem> items, int indent) {
  final pad = ' ' * indent;
  for (final it in items) {
    print('$pad- ${it.title}${it.category != null ? ' [${it.category}]' : ''}');
    for (final s in it.slots) {
      print(
        '$pad weeks:${s.weeks.join(',')} days:${s.days.join(',')} ${s.timeStart}-${s.timeEnd}',
      );
    }
    if (it.children.isNotEmpty) _dump(it.children, indent + 1);
  }
}

void main2(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : 'assets/training_schedule.yaml';
  final text = await File(path).readAsString();

  final doc = loadYamlDocument(text);
  final root = doc.contents as YamlMap;
  final sched = root['schedule'] as YamlMap;

  // read cycle info from yaml if present, else default
  final start =
      DateTime.tryParse(sched['startDate']?.toString() ?? '') ??
      DateTime(2025, 1, 6);
  final weeks = sched['cycleWeeks'] is int ? sched['cycleWeeks'] as int : 8;

  final parser = ScheduleParser(startDate: start, cycleWeeks: weeks);

  try {
    final items = parser.parseDocument(doc);
    print(
      '✓ YAML valid — $weeks-week cycle starting ${start.toIso8601String().split('T').first}\n',
    );
    _printTree(items);
  } on YamlValidationError catch (e) {
    final loc = e.line != null ? ' (line ${e.line})' : '';
    stderr.writeln('✗ ${e.message}$loc');
    exit(1);
  }
}

void _printTree(List<ScheduleItem> items, [String indent = '']) {
  const dayNames = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final isLast = i == items.length - 1;
    final branch = isLast ? '└─' : '├─';
    final nextIndent = indent + (isLast ? ' ' : '│ ');

    // title line
    final cat = item.category != null ? ' [${item.category}]' : '';
    stdout.writeln('$indent$branch ${item.title}$cat');

    // slots
    for (final slot in item.slots) {
      final weeks = _fmtRange(slot.weeks);
      final days = slot.days.map((d) => dayNames[d]).join(',');
      final time = '${slot.timeStart}-${slot.timeEnd}';
      stdout.writeln('$nextIndent• weeks $weeks • $days • $time');
    }

    // children
    if (item.children.isNotEmpty) {
      _printTree(item.children, nextIndent);
    }
  }
}

String _fmtRange(List<int> nums) {
  if (nums.isEmpty) return '';
  nums.sort();
  final parts = <String>[];
  int start = nums.first, prev = start;
  for (var i = 1; i <= nums.length; i++) {
    if (i < nums.length && nums[i] == prev + 1) {
      prev = nums[i];
      continue;
    }
    parts.add(start == prev ? '$start' : '$start-$prev');
    if (i < nums.length) {
      start = prev = nums[i];
    }
  }
  return parts.join(',');
}

class _Occ {
  final String start, end, title, path;
  _Occ(this.start, this.end, this.title, this.path);
}

void main(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : 'assets/training_schedule.yaml';
  final text = await File(path).readAsString();

  final doc = loadYamlDocument(text);
  final root = doc.contents as YamlMap;
  final sched = root['schedule'] as YamlMap;
  final start =
      DateTime.tryParse(sched['startDate']?.toString() ?? '') ??
      DateTime(2025, 1, 6);
  final weeks = sched['cycleWeeks'] is int ? sched['cycleWeeks'] as int : 8;

  final parser = ScheduleParser(startDate: start, cycleWeeks: weeks);

  try {
    final items = parser.parseDocument(doc);
    print('✓ YAML valid\n');
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
    if (node.title == null ||
        node.title.trim().isEmpty ||
        node.title == 'Untitled') {
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
        print(
          '$pad$branch─ • ${_fmt(s.timeStart)}-${_fmt(s.timeEnd)} ─ ${node.title}',
        );
      } else {
        print('$pad$branch─ ${node.title}');
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

  print('Schedule');
  for (var w = 1; w <= cycleWeeks; w++) {
    final weekLast = w == cycleWeeks;
    print('${weekLast ? '└' : '├'}─ Week $w');
    final weekPad = weekLast ? ' ' : '│ ';

    for (var d = 1; d <= 7; d++) {
      final dayNodes = items.where((n) => hasSlot(n, w, d)).toList();
      if (dayNodes.isEmpty) continue;

      print('$weekPad${'├'}─ ${days[d]}');
      final dayPad = weekPad + '│ ';

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
