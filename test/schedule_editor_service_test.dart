/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:tennis_training_tool/models/schedule.dart';
import 'package:tennis_training_tool/services/schedule_editor_service.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('ScheduleEditorService.toYaml', () {
    late ScheduleEditorService service;

    test('creates new yaml from empty initial', () async {
      service = ScheduleEditorService(null);

      final items = [
        ScheduleItem(
          title: 'Warmup',
          isScalar: false,
          category: 'prep',
          description: '5 min jog',
          durationMin: 5,
          reps: null,
          setsAndReps: null,
          audio: null,
          links: [],
          children: [],
          hasSlots: false,
          slots: [],
          changed: true,
          index: 0,
        ),
        ScheduleItem(
          title: 'Pushups',
          isScalar: true,
          changed: true,
          slots: [],
          hasSlots: false,
          index: 1,
        ),
      ];

      final yamlStr = await service.toYaml(DateTime(2025, 1, 1), 4, items);

      final doc = loadYaml(yamlStr) as YamlMap;

      expect(doc['metadata'], isA<Map>());

      expect(doc['schedule']['start'], '2025-01-01');
      expect(doc['schedule']['repeatWeeks'], 4);

      final yamlItems = doc['schedule']['items'] as YamlList;
      expect(yamlItems.length, 2);

      final warmup = yamlItems[0] as YamlMap;
      expect(warmup['title'], 'Warmup');
      expect(warmup['category'], 'prep');
      expect(warmup['time'], 5);

      expect(yamlItems[1], 'Pushups');
    });

    test('updates existing yaml preserving unrelated keys', () async {
      const initial = '''
metadata:
  created: 2024-12-01
schedule:
  start: 2024-12-01
  repeatWeeks: 2
  items:
    - title: Warmup
      category: old
      link: http://google.com
    - Squats
    - Random Stuff
extra:
  keep: me
''';
      service = ScheduleEditorService(initial);

      final items = [
        ScheduleItem(
          title: 'Warmup',
          isScalar: false,
          category: 'prep',
          description: 'updated',
          durationMin: 10,
          links: ['https://example.com'],
          index: 0,
          changed: true,
        ),
        ScheduleItem(title: 'Squats', isScalar: true, index: 1),
        ScheduleItem(title: 'Plank', isScalar: true, index: 2, changed: true),
      ];

      final yamlStr = await service.toYaml(DateTime(2025, 2, 10), 6, items);
      final doc = loadYaml(yamlStr) as YamlMap;

      expect(doc['extra']['keep'], 'me');

      expect(doc['schedule']['start'], '2025-02-10');
      expect(doc['schedule']['repeatWeeks'], 6);

      final yamlItems = doc['schedule']['items'] as YamlList;
      expect(yamlItems.length, 3);

      final warmup = yamlItems[0] as YamlMap;
      expect(warmup['category'], 'prep');
      expect(warmup['description'], 'updated');
      expect(warmup['time'], 10);
      expect(warmup['link'], 'https://example.com');

      expect(yamlItems[1], 'Squats');
      expect(yamlItems[2], 'Plank');
    });

    test('handles nested children recursively', () async {
      service = ScheduleEditorService('');

      final items = [
        ScheduleItem(
          title: 'Circuit',
          isScalar: false,
          index: 0,
          changed: true,
          children: [
            ScheduleItem(
              title: 'Jumping Jacks',
              isScalar: true,
              index: 0,
              changed: true,
            ),
            ScheduleItem(
              title: 'Core',
              isScalar: false,
              index: 1,
              changed: true,
              children: [
                ScheduleItem(
                  title: 'Situps',
                  isScalar: true,
                  index: 0,
                  changed: true,
                ),
              ],
            ),
          ],
        ),
      ];

      final yamlStr = await service.toYaml(DateTime(2025, 3, 1), 1, items);
      final doc = loadYaml(yamlStr) as YamlMap;

      final circuit = (doc['schedule']['items'] as YamlList)[0] as YamlMap;
      expect(circuit['title'], 'Circuit');

      final children = circuit['items'] as YamlList;
      expect(children[0], 'Jumping Jacks');

      final core = children[1] as YamlMap;
      expect(core['title'], 'Core');
      expect((core['items'] as YamlList)[0], 'Situps');
    });
  });

  test('handle complex yaml structure', () async {
    final service = ScheduleEditorService('''
schedule:
  start: 2026-05-18
  repeatWeeks: 8
  items:
    - title: "Session 3"
      category: exercise
      schedule:
        - week: 1-3,5-7
          days: 1-5
          timeStart: 09:30
          timeEnd: "10:30"
        - week: 4,8
          days: 1-5
          timeStart: 09:30
          timeEnd: "10:00"
      items:
        - title: Everyday drills
          schedule:
            - week: 1-3,5-7
              days: 1-3
              timeStart: 09:30
              timeEnd: 09:45
          items:
            - title: Sleep
              description: Sleep all you want
              setsAndReps: 6 times
              link: https://sleep.com/
        - title: Linear Sprints & Box Jumps.
          schedule:
            week: 1-3,5-7
            days: 1-2
            timeStart: 09:45
            timeEnd: 10:00
          items:
            - schedule:
                week: 1-3,5-7
                days: 1
              items:
                - title: Alpha
                  description: Beta.
                  setsAndReps: 5 x 10m
                  time: 5
                - title: Gamma
                  description: Delta
            - schedule:
                week: 1-3,5-7
                days: 2
              items:
                - title: Box Jumps
                  description: Jump onto a 18-24 box.
                  setsAndReps: 4 x 5
                  time: 8
                - title: Broad Jumps
                  description: Jump for distance from a split-step.
                  setsAndReps: 3 x 5
                  time: 8
        - title: Jogging/Cycling
          schedule:
            - week: 1-3,5-7
              days: 1-4
              timeStart: 10:00
              timeEnd: 10:30
            - week: 4,8
              days: 1-5
              timeStart: 09:30
              timeEnd: 10:00
''');

    final items = [
      ScheduleItem(
        title: "Session 3",
        category: 'unknown',
        hasSlots: true,
        index: 0,
        slots: [
          ScheduleSlot(
            [1, 2, 3, 4, 5, 6, 7],
            [1, 2, 3, 4, 5],
            true,
            '09:30',
            '10:30',
            0,
            '1-3,5-7',
            '1-5',
          ),
          ScheduleSlot(
            [4, 8],
            [1, 2, 3, 4, 5],
            true,
            '09:30',
            '10:00',
            1,
            '4-8',
            '1-5',
          ),
        ],
        children: [
          ScheduleItem(
            title: 'Everyday drills',
            index: 0,
            hasSlots: true,
            slots: [
              ScheduleSlot(
                [1, 2, 3, 5, 6, 7],
                [1, 2, 3],
                true,
                '09:30',
                '09:45',
                0,
                '1-3,5-7',
                '1-3',
              ),
            ],
            children: [
              ScheduleItem(
                title: 'Sleep',
                index: 0,
                description: 'Sleep all you want',
                setsAndReps: '6 times',
                links: ['https://sleep.com/'],
              ),
            ],
          ),
          ScheduleItem(
            title: 'Linear Sprints & Box Jumps.',
            index: 1,
            hasSlots: true,
            slots: [
              ScheduleSlot(
                [1, 2, 3, 5, 6, 7],
                [1, 2],
                true,
                '09:45',
                '10:00',
                0,
                '1-3,5-7',
                '1-2',
              ),
            ],
            children: [
              ScheduleItem(
                title: '__DUMMY__',
                index: 0,
                slots: [
                  ScheduleSlot(
                    [1, 2, 3, 5, 6, 7],
                    [1],
                    false,
                    'a',
                    'b',
                    0,
                    '1-7',
                    '1',
                  ),
                ],
                children: [
                  ScheduleItem(
                    title: 'Alpha',
                    description: 'Beta.',
                    setsAndReps: '5 x 10m',
                    durationMin: 5,
                    index: 0,
                  ),
                  ScheduleItem(title: 'Gamma', description: 'Delta', index: 1),
                ],
              ),
              ScheduleItem(
                title: '__DUMMY__',
                index: 1,
                slots: [
                  ScheduleSlot(
                    [1, 2, 3, 5, 6, 7],
                    [2],
                    false,
                    'timestart',
                    'timeEnd',
                    0,
                    '1-7',
                    '2',
                  ),
                ],
                children: [
                  ScheduleItem(
                    title: 'Box Jumps',
                    description: 'Jump onto a 18-24 box.',
                    setsAndReps: '4 x 5',
                    durationMin: 8,
                    index: 0,
                  ),
                  ScheduleItem(
                    title: 'Broad Jumps',
                    description: 'Jump for distance from a split-step.',
                    setsAndReps: '3 x 5',
                    durationMin: 8,
                    index: 1,
                  ),
                ],
              ),
            ],
          ),
          ScheduleItem(
            title: 'Jogging/Cycling',
            index: 3,
            hasSlots: true,
            slots: [
              ScheduleSlot(
                [1, 2, 3, 5, 6, 7],
                [1, 2, 3, 4],
                true,
                '10:00',
                '10:30',
                0,
                '1-3,5-7',
                '1-4',
              ),
              ScheduleSlot(
                [4, 8],
                [1, 2, 3, 4, 5],
                true,
                '09:30',
                '10:00',
                1,
                '4,8',
                '1-5',
              ),
            ],
          ),
        ],
      ),
      ScheduleItem(
        title: 'Session 4',
        index: 1,
        changed: true,
        children: [ScheduleItem(title: '4.1', index: 0, changed: true)],
      ),
      ScheduleItem(title: 'Squats', isScalar: true, index: 2),
      ScheduleItem(title: 'Plank', isScalar: true, index: 3, changed: true),
    ];

    final yamlStr = await service.toYaml(DateTime(2025, 3, 1), 1, items);
    final doc = loadYaml(yamlStr) as YamlMap;

    final yamlItems = doc['schedule']['items'] as YamlList;
    expect(yamlItems.length, 4);

    expect(yamlItems[0] is YamlMap, true);
    expect(yamlItems[0]['category'], 'exercise');
    expect(yamlItems[0]['schedule'][0]['week'], '1-3,5-7');
    expect(yamlItems[1]['title'], 'Session 4');
    expect(yamlItems[1]['items'].length, 1);
    expect(yamlItems[2], 'Squats');
    expect(yamlItems[3], 'Plank');
  });
}
