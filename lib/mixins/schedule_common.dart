/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import '../models/schedule.dart';

class ScheduleValidationError implements Exception {
  final String message;
  ScheduleValidationError(this.message);

  @override
  String toString() => message;
}

mixin ScheduleCommon {
  static final weekNames = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  String? validateTimeSlotsAgainstParent({
    required List<int> weeks,
    required List<int> days,
    required bool hasTime,
    String? ts,
    String? te,
    required ScheduleItem parent,
  }) {
    try {
      getEncapsulatingTimeSlots(
        weeks: weeks,
        days: days,
        hasTime: hasTime,
        ts: ts,
        te: te,
        parent: parent,
      );
      return null;
    } on ScheduleValidationError catch (e) {
      return e.message;
    }
  }

  String? validateChildrenTimeSlotsPostDeletion({
    required ScheduleItem parent,
    required int deletedIndex,
  }) {
    final parentSlots = parent.slots
        .asMap()
        .entries
        .where((e) => e.key != deletedIndex)
        .map((e) => e.value)
        .toList();

    return validateChildrenTimeSlotsAgainstParentSlots(
      parent: parent,
      parentSlots: parentSlots,
    );
  }

  String? validateChildrenTimeSlotsAgainstParentSlots({
    required ScheduleItem parent,
    required List<ScheduleSlot> parentSlots,
  }) {
    for (int i = 0; i < parent.children.length; i++) {
      final child = parent.children[i];
      for (int j = 0; j < child.slots.length; j++) {
        final slot = child.slots[j];
        if (slot.inherited) {
          continue;
        }

        try {
          getEncapsulatingTimeSlotsFromSlots(
            weeks: slot.weeks,
            days: slot.days,
            hasTime: slot.hasTime,
            ts: slot.timeStart,
            te: slot.timeEnd,
            parentSlots: parentSlots,
          );
        } on ScheduleValidationError catch (e) {
          return '${e.message} which is required by child "${child.title}"';
        }
      }
    }

    return null;
  }

  List<(List<int>, List<int>, String, String)>
  getEncapsulatingTimeSlotsFromSlots({
    required List<int> weeks,
    required List<int> days,
    required bool hasTime,
    String? ts,
    String? te,
    String title = '',
    required List<ScheduleSlot> parentSlots,
  }) {
    List<(List<int>, List<int>, String, String)> res = [];

    for (final w in weeks) {
      for (final d in days) {
        final ok = parentSlots.any(
          (ps) => ps.weeks.contains(w) && ps.days.contains(d),
        );
        if (!ok) {
          throw ScheduleValidationError(
            '${weekNames[d]}, week $w not offered by ${title.isNotEmpty ? 'parent $title' : 'this slot'}',
          );
        }
      }
    }

    for (final ps in parentSlots) {
      final iw = weeks.where(ps.weeks.contains).toList();
      final id = days.where(ps.days.contains).toList();
      if (iw.isEmpty || id.isEmpty) continue;

      final useStart = hasTime ? ts! : ps.timeStart;
      final useEnd = hasTime ? te! : ps.timeEnd;

      if (hasTime &&
          (_toMin(useStart) < _toMin(ps.timeStart) ||
              _toMin(useEnd) > _toMin(ps.timeEnd))) {
        throw ScheduleValidationError(
          '$useStart-$useEnd outside parent ${ps.timeStart}-${ps.timeEnd}',
        );
      }

      res.add((iw, id, useStart, useEnd));
    }

    return res;
  }

  List<(List<int>, List<int>, String, String)> getEncapsulatingTimeSlots({
    required List<int> weeks,
    required List<int> days,
    required bool hasTime,
    String? ts,
    String? te,
    required ScheduleItem parent,
  }) {
    return getEncapsulatingTimeSlotsFromSlots(
      weeks: weeks,
      days: days,
      hasTime: hasTime,
      ts: ts,
      te: te,
      title: parent.title,
      parentSlots: parent.slots,
    );
  }

  int _toMin(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  String slotTitle(ScheduleSlot s) =>
      'W:${_c(s.weeks)} • ${_days(s.days)} • ${s.timeStart}-${s.timeEnd}';

  String _days(List<int> d) =>
      d.map((e) => ScheduleCommon.weekNames[e]).join(',');

  String _c(List<int> v) => v.join(',');
}
