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
    required this.slots,
    this.enabled = true,
    this.children = const [],
    this.durationMin,
    this.reps,
    this.links = const [],
    this.audio,
    this.setsAndReps,
  });
}

class ScheduleSlot {
  bool enabled;
  final List<int> weeks;
  final List<int> days; // 1=Mon..7=Sun
  final String timeStart;
  final String timeEnd;
  final String? description;
  ScheduleSlot(
    this.weeks,
    this.days,
    this.timeStart,
    this.timeEnd, [
    this.description,
    this.enabled = true,
  ]);
}

class YamlValidationError implements Exception {
  final String message;
  final int? line;
  YamlValidationError(this.message, this.line);
  @override
  String toString() => line != null ? 'Line $line: $message' : message;
}
