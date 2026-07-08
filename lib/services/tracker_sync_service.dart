/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_common/tool.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../mixins/github_syncer.dart';
import 'encrypt_decryt_service.dart';

class CellConflict {
  final String columnName;
  final String localValue;
  final bool localValuePresent;
  final String incomingValue;
  final bool incomingValuePresent;

  CellConflict({
    required this.columnName,
    required String? localValue,
    required String? incomingValue,
  }) : localValue = localValue ?? '',
       localValuePresent = localValue != null,
       incomingValue = incomingValue ?? '',
       incomingValuePresent = incomingValue != null;
}

sealed class SheetConflict {
  final Map<String, dynamic> row;
  final String type;
  final String idKey;

  SheetConflict(this.row, this.type, this.idKey);
}

class SheetRowEditedConflict extends SheetConflict {
  final Map<String, CellConflict> conflicts = {};

  SheetRowEditedConflict(super.row, super.type, super.idKey);

  void addCellConflict(CellConflict cellConflict) =>
      conflicts[cellConflict.columnName] = cellConflict;
}

class SheetRowAddedConflict extends SheetConflict {
  void Function() remove;
  SheetRowAddedConflict(super.row, super.type, super.idKey, this.remove);
}

class SheetRowDeletedConflict extends SheetConflict {
  void Function() remove;
  SheetRowDeletedConflict(super.row, super.type, super.idKey, this.remove);
}

class ConcurrentModificationException implements Exception {
  final List<SheetConflict> conflicts;
  final String serverFileSha;
  ConcurrentModificationException(this.conflicts, this.serverFileSha);
}

class TrackerSyncService
    with EncryptDecryptService, GitHubSyncer, WidgetsBindingObserver {
  static final StreamController<void> globalResyncTrigger =
      StreamController<void>.broadcast();

  static const String _keyDocumentSha = 'json_server_sha';
  static const String _keyLastModified = 'json_last_modified';
  static const String _keyTrackerDataModified = 'has_tracker_data_modified';

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _sharedPreferences;
  final http.Client _client;
  final void Function() syncStartNotifier;
  final void Function() syncDoneNotifier;
  final void Function() syncFailedNotifier;
  final Future<void> Function(TrackerSyncService self) loader;

  Map? schema;
  Map<String, dynamic> appData = {"kids": [], "biometrics": []};

  TrackerSyncService(
    this._secureStorage,
    this._sharedPreferences,
    this.syncStartNotifier,
    this.syncDoneNotifier,
    this.syncFailedNotifier,
    this.loader, {
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<void> initialize() async {
    try {
      final String rawYaml = await rootBundle.loadString('assets/schema.yaml');
      schema = loadYaml(rawYaml);

      await initializeSyncer();
    } catch (e) {
      log('Error during Tracker sync Service init: $e');
    }
  }

  @override
  http.Client get client => _client;

  @override
  String get githubFilePath => 'data/$localFileName';

  @override
  bool get isModifiable => true;

  @override
  String get keyDocumentLastModified => _keyLastModified;

  @override
  String get keyDocumentSha => _keyDocumentSha;

  @override
  String get keyHasSyncDataModified => _keyTrackerDataModified;

  @override
  String get localFileName => 'tracker.json';

  @override
  void notifySyncDone() => syncDoneNotifier();

  @override
  void notifySyncFailed() => syncFailedNotifier();

  @override
  void notifySyncStarted() => syncStartNotifier();

  @override
  Future<void> processConflicts(Uint8List serverData, String serverSha) async {
    final Map<String, dynamic> data = json.decode(utf8.decode(serverData));
    final conflicts = _processConflicts(appData, data, {
      'kids': 'id',
      'biometrics': 'entry_id',
    });

    /* At this stage we have incorporated all conflicts into appData.
       * appFileSha remains same as before. User is now supposed to 
       * merge changes (if required). If user cancles merge or doesn't
       * commit appFileSha remains the same. So changes will have to
       * merge again next time. If user merges and commits but commit
       * fails to happen in three retries, appFileSha remains same. So
       * user will again have to merge and commit. If further changes 
       * happen on the server side in the mean time, those will have 
       * to be merged as well.
       */
    throw ConcurrentModificationException(conflicts, serverSha);
  }

  @override
  Future<void> processContentPostLoad(Uint8List content) async {
    appData = json.decode(utf8.decode(content));
  }

  @override
  Future<Uint8List> getContentsForWrite() async {
    final Map<String, dynamic> auditLog = await generateAuditPayload();
    final localData = Map<String, dynamic>.from(appData);
    localData['metadata'] = auditLog;
    return utf8.encode(json.encode(localData));
  }

  @override
  FlutterSecureStorage get secureStorage => _secureStorage;

  @override
  SharedPreferences get sharedPreferences => _sharedPreferences;

  @override
  Future<void> syncDataLoader() async {
    await loader(this);
  }

  @override
  Duration get syncDuration => Duration(minutes: 30);

  List<dynamic> getPagedAndReverseSortedData({
    required String kidId,
    required String sheetId,
    required int pageOffset,
    required int pageSize,
  }) {
    final List<dynamic> filtered = appData["biometrics"]
        .where((b) => b["kid_id"] == kidId && b["sheet_id"] == sheetId)
        .toList();

    filtered.sort((a, b) {
      final String dateA = a["Date"] ?? a["WeekStart"] ?? "0000-00-00";
      final String dateB = b["Date"] ?? b["WeekStart"] ?? "0000-00-00";
      return dateB.compareTo(dateA);
    });

    final int startPosition = pageOffset;
    if (startPosition >= filtered.length) return [];

    final int endPosition = math.min(startPosition + pageSize, filtered.length);
    return filtered.sublist(startPosition, endPosition);
  }

  List<SheetConflict> _processConflicts(
    Map<String, dynamic> localAppData,
    Map<String, dynamic> serverAppData,
    Map<String, String> dataKeyToId,
  ) {
    List<SheetConflict> conflicts = [];
    List<Map<String, dynamic>> asMapList(dynamic v) {
      if (v == null) return [];
      return (v as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    for (var entry in dataKeyToId.entries) {
      final List<Map<String, dynamic>> mergedData = [];
      final List<Map<String, dynamic>> locData = asMapList(
        localAppData[entry.key],
      );
      final List<Map<String, dynamic>> servData = asMapList(
        serverAppData[entry.key],
      );

      int i = 0;
      int j = 0;
      while (i < locData.length && j < servData.length) {
        final locItem = locData[i];
        final servItem = servData[j];

        if (locItem[entry.value] == servItem[entry.value]) {
          // The two items are same so compare all fields and values and merge
          mergedData.add(locItem);
          i++;
          j++;

          SheetRowEditedConflict sheetConflict = SheetRowEditedConflict(
            locItem,
            entry.key,
            entry.value,
          );

          final allFields = {...servItem.keys, ...locItem.keys}
            ..remove(entry.value);
          for (var field in allFields) {
            final sVal = servItem[field]?.toString();
            final lVal = locItem[field]?.toString();

            if (sVal != lVal) {
              sheetConflict.addCellConflict(
                CellConflict(
                  columnName: field,
                  localValue: lVal,
                  incomingValue: sVal,
                ),
              );
            }
          }

          if (sheetConflict.conflicts.isNotEmpty) {
            conflicts.add(sheetConflict);
          }
        } else {
          // The two items are different so add whichever is latest

          DateTime? locDate = DateTime.tryParse(locItem['Date']);
          DateTime? servDate = DateTime.tryParse(servItem['Date']);
          bool addLocItem = false;
          bool addServItem = false;

          // Both have valid date so add whichever is latest
          if (locDate != null && servDate != null) {
            if (locDate.isAfter(servDate)) {
              addLocItem = true;
            } else {
              addServItem = true;
            }
          } else {
            if (servDate != null) {
              // If servDate is valid locDate can't be, so add servItem
              addServItem = true;
            } else {
              // Whether locDate is null or not we add locItem, since
              // servDate is confirmed to be null at this point.
              addLocItem = true;
            }
          }

          // In release mode we don't create SheetRowDeletedConflict
          // or SheetRowAddedConflict. That is we silently merge.
          // What this does is that if some user added or deleted
          // row(s) in between they will be automatically added
          // always. So effectively delete operation will be ignored.
          // Considering low probability of this happening, going
          // ahead with this approach.
          if (addLocItem) {
            mergedData.add(locItem);
            i++;
            if (kDebugMode) {
              conflicts.add(
                SheetRowDeletedConflict(
                  locItem,
                  entry.key,
                  entry.value,
                  () => mergedData.remove(locItem),
                ),
              );
            }
          } else if (addServItem) {
            mergedData.add(servItem);
            j++;
            if (kDebugMode) {
              conflicts.add(
                SheetRowAddedConflict(
                  servItem,
                  entry.key,
                  entry.value,
                  () => mergedData.remove(servItem),
                ),
              );
            }
          }
        }
      }

      while (i < locData.length) {
        final locItem = locData[i];
        mergedData.add(locItem);
        if (kDebugMode) {
          conflicts.add(
            SheetRowDeletedConflict(
              locItem,
              entry.key,
              entry.value,
              () => mergedData.remove(locItem),
            ),
          );
        }
        i++;
      }

      while (j < servData.length) {
        final servItem = servData[j];
        mergedData.add(servItem);
        if (kDebugMode) {
          conflicts.add(
            SheetRowAddedConflict(
              servItem,
              entry.key,
              entry.value,
              () => mergedData.remove(servItem),
            ),
          );
        }
        j++;
      }

      // Now replace the original array with new merged array
      localAppData[entry.key] = mergedData;
    }

    return conflicts;
  }

  Map<String, dynamic> evaluateRule(
    String sheetId,
    String columnId,
    double val,
    String gender,
  ) {
    if (schema == null || schema!["sheets"] == null) {
      return {"label": "", "color": Colors.black87};
    }

    for (var sheet in schema!["sheets"]) {
      if (sheet["id"] != sheetId) continue;
      for (var col in sheet["columns"]) {
        if (col["id"] != columnId || col["rules"] == null) continue;

        for (var rule in col["rules"]) {
          final String conditionString = rule["condition"].toString();

          if (_checkExpressionMatch(conditionString, val, gender)) {
            return {
              "label": rule["label"],
              "color": _parseColor(rule["color"]),
            };
          }
        }
      }
    }
    return {"label": "", "color": Colors.black87};
  }

  bool _checkExpressionMatch(
    String rawCondition,
    double val,
    String currentGender,
  ) {
    final String cond = rawCondition
        .replaceAll('(', '')
        .replaceAll(')', '')
        .trim();

    final List<String> orClauses = cond.split('||');

    for (var clause in orClauses) {
      final String trimmedClause = clause.trim();

      if (trimmedClause.contains('gender')) {
        final List<String> andSegments = trimmedClause.split('&&');
        if (andSegments.length == 2) {
          final String genderCheckSegment = andSegments[0].trim();
          final String numericCheckSegment = andSegments[1].trim();

          final bool isFemaleBranch =
              genderCheckSegment.contains('female') &&
              currentGender == 'female';
          final bool isMaleBranch =
              genderCheckSegment.contains('male') && currentGender == 'male';

          if (isFemaleBranch || isMaleBranch) {
            if (_evaluateSingleNumericBlock(numericCheckSegment, val)) {
              return true;
            }
          }
        }
      } else {
        if (_evaluateSingleNumericBlock(trimmedClause, val)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _evaluateSingleNumericBlock(String targetBlock, double val) {
    final String clean = targetBlock.replaceAll('val', '').trim();
    if (clean.startsWith("<=")) {
      return val <= double.parse(clean.replaceAll('<=', '').trim());
    }
    if (clean.startsWith("<")) {
      return val < double.parse(clean.replaceAll('<', '').trim());
    }
    if (clean.startsWith(">=")) {
      return val >= double.parse(clean.replaceAll('>=', '').trim());
    }
    if (clean.startsWith(">")) {
      return val > double.parse(clean.replaceAll('>', '').trim());
    }
    return false;
  }

  Color _parseColor(String key) {
    switch (key) {
      case "green":
        return Colors.green.shade700;
      case "amber":
        return Colors.amber.shade800;
      case "orange":
        return Colors.orange.shade800;
      case "deepOrange":
        return Colors.deepOrange.shade700;
      case "red":
        return Colors.red.shade700;
      case "yellow":
        return Colors.yellow.shade700;
      default:
        return Colors.black87;
    }
  }

  Future<void> cacheAppDataLocally() async {
    await cacheLocally(
      utf8.encode(json.encode(appData)),
      appSha ?? '',
      appEtag ?? '',
    );
  }

  dynamic computeFormulaValue(String formula, Map<String, dynamic> rowData) {
    try {
      if (formula == "SleepNight + SleepAfternoon") {
        final double night =
            double.tryParse(rowData["SleepNight"]?.toString() ?? "0") ?? 0;
        final double afternoon =
            double.tryParse(rowData["SleepAfternoon"]?.toString() ?? "0") ?? 0;
        return night + afternoon;
      }

      if (formula == "DailyFlag") {
        final double sleepTotal =
            double.tryParse(rowData["SleepTotal"]?.toString() ?? "0") ?? 0;
        final int rpe = int.tryParse(rowData["RPE"]?.toString() ?? "0") ?? 0;
        final int soreness =
            int.tryParse(rowData["Soreness"]?.toString() ?? "0") ?? 0;
        final int mood = int.tryParse(rowData["Mood"]?.toString() ?? "0") ?? 0;

        // 🔴 Condition 1: High Stress / Fatigue Alert
        if (sleepTotal <= 5 || soreness > 6 || mood < 3) {
          return "🔴";
        }
        // 🟡 Condition 2: Elevated Warning
        if (rpe > 7 || soreness > 4 || mood < 4) {
          return "🟡";
        }
        // 🟢 Fallback Condition: Optimal Status
        return "🟢";
      }

      if (formula == "LimbGirthDiff") {
        final double r =
            double.tryParse(rowData["LimbRight"]?.toString() ?? "0") ?? 0;
        final double l =
            double.tryParse(rowData["LimbLeft"]?.toString() ?? "0") ?? 0;
        if ((r + l) == 0) return 0.0;
        return ((r - l).abs() / ((r + l) / 2)) * 100;
      }

      if (formula == "RotationDelta") {
        final double r =
            double.tryParse(rowData["IntRotationRight"]?.toString() ?? "0") ??
            0;
        final double l =
            double.tryParse(rowData["IntRotationLeft"]?.toString() ?? "0") ?? 0;
        return (r - l).abs();
      }
    } catch (e) {
      debugPrint("Formula Error: $e");
    }
    return 0.0;
  }
}
