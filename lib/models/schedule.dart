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
  bool hasSlots;
  bool isScalar;
  final List<ScheduleSlot> slots;
  final List<ScheduleItem> children;
  final int? durationMin;
  final int? reps;
  final List<String> links;
  final String? audio;
  final String? setsAndReps;

  ScheduleItem({
    required this.title,
    this.category,
    this.description,
    bool? hasSlots,
    List<ScheduleSlot>? slots,
    this.isScalar = false,
    this.enabled = true,
    this.children = const [],
    this.durationMin,
    this.reps,
    this.links = const [],
    this.audio,
    this.setsAndReps,
  }) : hasSlots = hasSlots ?? isScalar
           ? false
           : slots != null && slots.isNotEmpty,
       slots = slots ?? [];

  dynamic toYaml() {
    if (isScalar) return title;
    return toMap();
  }

  Map<String, dynamic> toMap() {
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
      if (hasSlots) 'slots': slots.map((slot) => slot.toMap()),
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
  ScheduleSlot(
    this.weeks,
    this.days,
    this.hasTime,
    this.timeStart,
    this.timeEnd, [
    this.description,
    this.enabled = true,
  ]);

  Map<String, dynamic> toMap() {
    return {
      'week': compressValues(weeks),
      'days': compressValues(days),
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
