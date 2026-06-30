import 'package:yaml_edit/yaml_edit.dart';

import '../models/schedule.dart';

class ScheduleEditorService {
  String toYaml(DateTime start, int cycleWeeks, List<ScheduleItem> items) {
    final data = {
      'schedule': {
        'start': _date(start),
        'repeatWeeks': cycleWeeks,
        'items': items.map(_toMap).toList(),
      },
    };

    final editor = YamlEditor('');
    editor.update([], data);
    return editor.toString();
  }

  Map<String, dynamic> _toMap(ScheduleItem it) {
    final m = <String, dynamic>{'title': it.title};

    if (it.category != null) m['category'] = it.category;
    if (it.description != null) m['description'] = it.description;
    if (it.durationMin != null) m['time'] = it.durationMin;
    if (it.reps != null) m['reps'] = it.reps;
    if (it.setsAndReps != null) m['setsAndReps'] = it.setsAndReps;
    if (it.audio != null) m['audio'] = it.audio;
    if (it.links.isNotEmpty) {
      m['link'] = it.links.length == 1 ? it.links.first : it.links;
    }

    if (it.slots.isNotEmpty) {
      m['schedule'] = it.slots
          .map(
            (s) => {
              'week': _compress(s.weeks),
              'days': _compress(s.days),
              'timeStart': s.timeStart,
              'timeEnd': s.timeEnd,
              if (s.description != null) 'description': s.description,
            },
          )
          .toList();
    }

    if (it.children.isNotEmpty) {
      m['items'] = it.children.map(_toMap).toList();
    }

    return m;
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _compress(List<int> v) {
    v = [...v]..sort();
    final parts = <String>[];
    int start = v.first, prev = v.first;
    for (int i = 1; i <= v.length; i++) {
      if (i == v.length || v[i] != prev + 1) {
        parts.add(start == prev ? '$start' : '$start-$prev');
        if (i < v.length) start = prev = v[i];
      } else {
        prev = v[i];
      }
    }
    return parts.join(',');
  }
}
