/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

class ScheduleItem {
  final String title;
  final String? category;
  final String? description;
  bool enabled;
  bool changed;
  final bool isScalar;
  final bool slotsAsArray;
  final bool hasSlots;
  final List<ScheduleSlot> slots;
  final List<ScheduleItem> children;
  final int? durationMin;
  final int? reps;
  final List<String> links;
  final String? audio;
  final String? setsAndReps;
  //final List<dynamic> keys;
  int index;

  ScheduleItem({
    required this.title,
    this.category,
    this.description,
    this.slots = const [],
    this.enabled = true,
    this.changed = false,
    this.isScalar = false,
    this.slotsAsArray = false,
    this.hasSlots = false,
    this.children = const [],
    this.durationMin,
    this.reps,
    this.links = const [],
    this.audio,
    this.setsAndReps,
    required this.index,
  });

  dynamic toYaml() {
    if (isScalar) return title;
    return toMap();
  }

  List<ScheduleSlot> actualSlots() => hasSlots ? slots : [];

  Map<String, dynamic> toMap() {
    final as = actualSlots();

    return {
      if (title.isNotEmpty && title != '__DUMMY__') 'title': title,
      if (category != null && category!.isNotEmpty) 'category': category,
      if (description != null && description!.isNotEmpty)
        'description': description,
      if (durationMin != null) 'time': durationMin,
      if (reps != null) 'reps': reps.toString(),
      if (links.isNotEmpty) 'link': links.length > 1 ? links : links[0],
      if (audio != null) 'audio': audio,
      if (setsAndReps != null) 'setsAndReps': setsAndReps,
      if (as.isNotEmpty)
        'schedule': as.length > 1
            ? as.map((s) => s.toMap()).toList()
            : as[0].toMap(),
      if (!enabled) 'enabled': false,
      if (children.isNotEmpty)
        'items': children.map((child) => child.toYaml()).toList(),
    };
  }
}

class ScheduleSlot {
  bool enabled;
  bool hasTime;
  final List<int> weeks;
  final List<int> days; // 1=Mon..7=Sun
  final String timeStart;
  final String timeEnd;
  final String? description;
  int index;
  bool changed;
  final String originalWeeks;
  final String originalDays;
  ScheduleSlot(
    this.weeks,
    this.days,
    this.hasTime,
    this.timeStart,
    this.timeEnd,
    this.index,
    this.originalWeeks,
    this.originalDays, {
    this.description,
    this.enabled = true,
    this.changed = false,
  });

  dynamic weekYamlValue() {
    final value = changed ? compressValues(weeks) : originalWeeks;
    try {
      return int.parse(value);
    } catch (_) {
      return value;
    }
  }

  dynamic daysYamlValue() {
    final value = changed ? compressValues(days) : originalDays;
    try {
      return int.parse(value);
    } catch (_) {
      return value;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'week': weekYamlValue(),
      'days': daysYamlValue(),
      if (hasTime) 'timeStart': timeStart,
      if (hasTime) 'timeEnd': timeEnd,
      if (description != null) 'description': description,
      if (!enabled) 'enabled': false,
    };
  }
}

class YamlValidationError implements Exception {
  final String message;
  final int? line;
  YamlValidationError(this.message, this.line);
  @override
  String toString() => line != null ? 'Line $line: $message' : message;
}

String compressValues(List<int> v) {
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
