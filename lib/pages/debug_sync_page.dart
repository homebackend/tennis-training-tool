/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/tracker_sync_service.dart';
import '../widgets/tracker_conflict_dialog.dart';

class DebugSyncPage extends StatefulWidget {
  const DebugSyncPage({super.key});
  @override
  State<DebugSyncPage> createState() => _DebugSyncPageState();
}

class _DebugSyncPageState extends State<DebugSyncPage> {
  late TrackerSyncService svc;
  bool busy = false;
  String log = '';

  TrackerSyncService makeService(http.Client client) {
    return _TestSync(
      client: client,
      storage: FlutterSecureStorage(),
      onLog: (s) => setState(() => log = '$log\n$s'),
    );
  }

  void snack(String m) {
    setState(() => log = '$log\n$m');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> runPipeline() async {
    setState(() => busy = true);
    try {
      await _runSequentialSyncPipeline();
    } catch (e) {
      snack('Error: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _runSequentialSyncPipeline({int attempt = 1}) async {
    try {
      await svc.pushToGitHubWithAutoMerge();
      snack('Committed to Git!');
    } catch (e) {
      if (e is ConcurrentModificationException && attempt <= 3) {
        for (final c in e.conflicts) {
          final ok = await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => TrackerConflictResolutionDialog(c),
          );

          if (ok != true) {
            snack('Commit cancelled');
            return;
          }
        }
        snack('Resolutions applied. Re-trying (Attempt ${attempt + 1}/3)...');
        await _runSequentialSyncPipeline(attempt: attempt + 1);
      } else {
        rethrow;
      }
    }
  }

  // 1. No conflict
  void useCase1() {
    final client = MockClient((req) async {
      if (req.method == 'PUT') {
        return http.Response(
          jsonEncode({
            'content': {'sha': 'new1'},
          }),
          201,
        );
      }
      return http.Response('x', 404);
    });
    svc = makeService(client)
      ..appData = {
        'kids': [
          {'id': '1', 'name': 'My Name', 'Date': '2026-06-25'},
        ],
        'biometrics': [],
      }
      ..serverFileSha = 'old';
    runPipeline();
  }

  // 2. Row changed
  void useCase2() {
    int puts = 0;
    final client = MockClient((req) async {
      if (req.method == 'PUT') {
        puts++;
        return puts == 1
            ? http.Response('conflict', 409)
            : http.Response(
                jsonEncode({
                  'content': {'sha': 'new2'},
                }),
                201,
              );
      }
      final server = {
        'kids': [
          {
            'id': '1',
            'name': 'Your Name',
            'age': '14',
            'remote-only': 'value',
            'Date': '2026-06-20',
          },
          {'id': '2', 'name': 'Their Name', 'Date': '2026-06-20'},
        ],
        'biometrics': [],
      };
      return http.Response(
        jsonEncode({
          'sha': 'srv',
          'content': base64Encode(utf8.encode(jsonEncode(server))),
        }),
        200,
      );
    });
    svc = makeService(client)
      ..appData = {
        'kids': [
          {'id': '1', 'name': 'My Name', 'age': '14', 'Date': '2026-06-25'},
          {'id': '2', 'name': 'Their Name', 'Date': '2026-06-20'},
        ],
        'biometrics': [],
      }
      ..serverFileSha = 'old';
    runPipeline();
  }

  // 3. Local row added, server deleted it
  void useCase3() {
    int puts = 0;
    final client = MockClient((req) async {
      if (req.method == 'PUT') {
        puts++;
        return puts == 1
            ? http.Response('c', 409)
            : http.Response(
                jsonEncode({
                  'content': {'sha': 'new3'},
                }),
                201,
              );
      }
      // server has id 1, local will have id 2
      final server = {
        'kids': [
          {'id': '1', 'name': 'Your Name', 'Date': '2026-06-20'},
          {'id': '2', 'name': 'Their Name', 'Date': '2026-06-25'},
        ],
        'biometrics': [],
      };
      return http.Response(
        jsonEncode({
          'sha': 'srv',
          'content': base64Encode(utf8.encode(jsonEncode(server))),
        }),
        200,
      );
    });
    svc = makeService(client)
      ..appData = {
        'kids': [
          {'id': '1', 'name': 'Your Name', 'Date': '2026-06-20'},
          {'id': '3', 'name': 'My Name', 'Date': '2026-06-25'},
        ],
        'biometrics': [],
      }
      ..serverFileSha = 'old';
    runPipeline();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync Visual Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            ElevatedButton(
              onPressed: busy ? null : useCase1,
              child: const Text('1. No conflict → 200'),
            ),
            ElevatedButton(
              onPressed: busy ? null : useCase2,
              child: const Text('2. Row changed → 409 then merge'),
            ),
            ElevatedButton(
              onPressed: busy ? null : useCase3,
              child: const Text('3. Local add, server deleted → keep/remove'),
            ),
            const SizedBox(height: 20),
            Expanded(child: SingleChildScrollView(child: Text(log))),
          ],
        ),
      ),
    );
  }
}

class _TestSync extends TrackerSyncService {
  final void Function(String) onLog;

  _TestSync({
    required http.Client client,
    required FlutterSecureStorage storage,
    required this.onLog,
  }) : super(storage, client: client);

  @override
  Future<http.Response> pushToGitHubWithResponse() async {
    // build the exact payload your real code sends
    final payload = Map<String, dynamic>.from(appData);
    payload['metadata'] = {
      'lastModified': DateTime.now().toIso8601String(),
      'auditLog': {},
    };

    final pretty = const JsonEncoder.withIndent('  ').convert(payload);

    // print to console and to your screen log
    debugPrint(
      '\n===== GITHUB PAYLOAD =====\n$pretty\n========================\n',
    );
    onLog('\n--- Payload sent ---\n$pretty');

    return super.pushToGitHubWithResponse();
  }

  @override
  Future<(Uri, Map<String, String>, String)> getTrackerServerInfo() async {
    return (Uri.parse('https://fake'), {'': ''}, 'pass');
  }

  Future<Map<String, dynamic>> generateAuditPayload() async => {};
  @override
  Future<Uint8List> encryptBytes(Uint8List d, String p) async => d;
  @override
  Future<Uint8List> decryptBytes(Uint8List d, String p) async => d;
  @override
  Future<void> cacheLocally() async {}
}
