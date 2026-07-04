/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:tennis_training_tool/services/tracker_sync_service.dart';

void main() {
  late TrackerSyncService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    service = TrackerSyncService(
      const FlutterSecureStorage(),
      prefs,
      () {},
      () {},
      () {},
      (_) async {},
      client: http.Client(),
    );

    service.appData = {'kids': [], 'biometrics': []};
  });

  Future<List<SheetConflict>> runMerge(
    Map<String, dynamic> local,
    Map<String, dynamic> server,
  ) async {
    service.appData = jsonDecode(jsonEncode(local)); // deep copy
    final serverBytes = Uint8List.fromList(utf8.encode(jsonEncode(server)));

    try {
      await service.processConflicts(serverBytes, 'sha123');
    } on ConcurrentModificationException catch (e) {
      return e.conflicts;
    }
    return [];
  }

  test('no conflict when identical', () async {
    final data = {
      'kids': [
        {'id': 'k1', 'name': 'A'},
      ],
      'biometrics': [
        {'entry_id': 'b1', 'kid_id': 'k1', 'Date': '2025-01-01', 'RPE': '5'},
      ],
    };
    final conflicts = await runMerge(data, data);
    expect(conflicts, isEmpty);
    expect(service.appData['biometrics'].length, 1);
  });

  test('detects edited cell conflict', () async {
    final local = {
      'biometrics': [
        {
          'entry_id': 'b1',
          'kid_id': 'k1',
          'Date': '2025-01-01',
          'RPE': '5',
          'Mood': '4',
        },
      ],
    };
    final server = {
      'biometrics': [
        {
          'entry_id': 'b1',
          'kid_id': 'k1',
          'Date': '2025-01-01',
          'RPE': '7',
          'Mood': '4',
        },
      ],
    };

    final conflicts = await runMerge(local, server);
    expect(conflicts.length, 1);
    final edit = conflicts.first as SheetRowEditedConflict;
    expect(edit.type, 'biometrics');
    expect(edit.conflicts['RPE']!.localValue, '5');
    expect(edit.conflicts['RPE']!.incomingValue, '7');
    expect(service.appData['biometrics'][0]['RPE'], '5');
  });

  test('adds server row when newer date (debug mode)', () async {
    final local = {
      'biometrics': [
        {'entry_id': 'b1', 'Date': '2025-01-01'},
      ],
    };
    final server = {
      'biometrics': [
        {'entry_id': 'b1', 'Date': '2025-01-01'},
        {'entry_id': 'b2', 'Date': '2025-01-02'},
      ],
    };

    final conflicts = await runMerge(local, server);
    expect(conflicts.whereType<SheetRowAddedConflict>().length, 1);
    expect(service.appData['biometrics'].length, 2);
    expect(service.appData['biometrics'][1]['entry_id'], 'b2');
  });

  test('keeps local row when local date newer', () async {
    final local = {
      'biometrics': [
        {'entry_id': 'b1', 'Date': '2025-01-03'},
        {'entry_id': 'b2', 'Date': '2025-01-01'},
      ],
    };
    final server = {
      'biometrics': [
        {'entry_id': 'b1', 'Date': '2025-01-03'},
      ],
    };

    final conflicts = await runMerge(local, server);
    expect(conflicts.whereType<SheetRowDeletedConflict>().length, 1);
    expect(
      service.appData['biometrics'].map((e) => e['entry_id']),
      contains('b2'),
    );
  });

  test('merges kids and biometrics independently', () async {
    final local = {
      'kids': [
        {'id': 'k1', 'name': 'Local'},
      ],
      'biometrics': [],
    };
    final server = {
      'kids': [
        {'id': 'k1', 'name': 'Server'},
      ],
      'biometrics': [],
    };

    final conflicts = await runMerge(local, server);
    final kidConflict = conflicts.first as SheetRowEditedConflict;
    expect(kidConflict.type, 'kids');
    expect(kidConflict.conflicts['name']!.localValue, 'Local');
    expect(kidConflict.conflicts['name']!.incomingValue, 'Server');
  });

  test('handles missing Date gracefully', () async {
    final local = {
      'biometrics': [
        {'entry_id': 'b1'},
      ],
    };
    final server = {
      'biometrics': [
        {'entry_id': 'b1'},
        {'entry_id': 'b2', 'Date': '2025-01-01'},
      ],
    };

    await runMerge(local, server);
    expect(service.appData['biometrics'].length, 2);
  });
}
