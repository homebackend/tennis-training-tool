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
        ),
        ScheduleItem(title: 'Pushups', isScalar: true),
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
          children: [],
        ),
        ScheduleItem(title: 'Squats', isScalar: true),
        ScheduleItem(title: 'Plank', isScalar: true),
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
      expect((warmup['link'] as YamlList).first, 'https://example.com');

      expect(yamlItems[1], 'Squats');
      expect(yamlItems[2], 'Plank');
    });

    test('handles nested children recursively', () async {
      service = ScheduleEditorService('');

      final items = [
        ScheduleItem(
          title: 'Circuit',
          isScalar: false,
          children: [
            ScheduleItem(title: 'Jumping Jacks', isScalar: true),
            ScheduleItem(
              title: 'Core',
              isScalar: false,
              children: [ScheduleItem(title: 'Situps', isScalar: true)],
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
}
