/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_common/flutter_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import 'encrypt_decryt_service.dart';
import 'preferences_backup_service.dart';

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
  ConcurrentModificationException(this.conflicts);
}

class TrackerSyncService with EncryptDecryptService {
  final FlutterSecureStorage _secureStorage;
  final http.Client _client;
  static final StreamController<void> globalResyncTrigger =
      StreamController<void>.broadcast();

  static const String _keyDataCache = "json_local_cache";
  static const String _keyShaCache = "json_server_sha";

  static const String _fileName = "tracker.json";

  Map<String, dynamic> appData = {"kids": [], "biometrics": []};
  Map? schema;
  String? serverFileSha;

  TrackerSyncService(this._secureStorage, {http.Client? client})
    : _client = client ?? http.Client();

  Future<(String, String, String)> getServerConfig() async {
    final repo =
        await _secureStorage.read(key: PreferencesBackupService.keyGitRepo) ??
        '';
    final token =
        await _secureStorage.read(key: PreferencesBackupService.keyGitToken) ??
        '';
    final pass =
        await _secureStorage.read(key: PreferencesBackupService.keyEncPwd) ??
        '';

    return (repo, token, pass);
  }

  Future<(Uri, Map<String, String>, String)> getTrackerServerInfo() async {
    final (repo, token, pass) = await getServerConfig();
    final uri = Uri.parse(
      "https://api.github.com/repos/$repo/contents/$_fileName",
    );
    final headers = {"Authorization": "Bearer $token"};
    return (uri, headers, pass);
  }

  Future<bool> loadCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final String rawYaml = await rootBundle.loadString('assets/schema.yaml');
      schema = loadYaml(rawYaml);
    } catch (e) {
      return false;
    }

    final (repo, token, pass) = await getServerConfig();
    if (repo.isNotEmpty && token.isNotEmpty && pass.isNotEmpty) {
      String? cache = prefs.getString(_keyDataCache);
      if (cache == null) {
        // Try to load cache since it is missing
        await syncFromGitHub();
        cache = prefs.getString(_keyDataCache);
      }
      if (cache != null) {
        appData = json.decode(cache);
        serverFileSha = prefs.getString(_keyShaCache);
        return true;
      }
    }
    return false;
  }

  Future<void> saveServerConfig({
    required String repo,
    required String token,
    required String password,
  }) async {
    await _secureStorage.write(
      key: PreferencesBackupService.keyGitRepo,
      value: repo,
    );
    await _secureStorage.write(
      key: PreferencesBackupService.keyGitToken,
      value: token,
    );
    await _secureStorage.write(
      key: PreferencesBackupService.keyEncPwd,
      value: password,
    );
  }

  Future<void> clearSavedSession() async {
    await _secureStorage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDataCache);
    await prefs.remove(_keyShaCache);
    appData = {"kids": [], "biometrics": []};
    serverFileSha = null;
  }

  Future<(int, String?, Map<String, dynamic>?)> fetchFromGitHub() async {
    final (dataUrl, headers, pass) = await getTrackerServerInfo();

    final dataRes = await _client.get(dataUrl, headers: headers);
    if (dataRes.statusCode == 200) {
      final dataBody = json.decode(dataRes.body);
      final String fileSha = dataBody["sha"];
      final encryptedBytes = base64Decode(
        dataBody["content"].toString().replaceAll('\n', ''),
      );
      final decryptedBytes = await decryptBytes(encryptedBytes, pass);
      final Map<String, dynamic> data = json.decode(
        utf8.decode(decryptedBytes),
      );
      return (dataRes.statusCode, fileSha, data);
    } else if (dataRes.statusCode == 404) {
      return (dataRes.statusCode, null, {"kids": [], "biometrics": []});
    } else {
      return (dataRes.statusCode, null, null);
    }
  }

  Future<void> syncFromGitHub() async {
    final (code, fileSha, data) = await fetchFromGitHub();

    if (fileSha == null && data == null) {
      throw Exception("Data download rejected: Code $code");
    }

    if (fileSha != null) {
      serverFileSha = fileSha;
    }
    if (data != null) {
      appData = data;
    }

    await cacheLocally();
  }

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

    final int endPosition = min(startPosition + pageSize, filtered.length);
    return filtered.sublist(startPosition, endPosition);
  }

  Future<http.Response> pushToGitHubWithResponse() async {
    final (url, headers, pass) = await getTrackerServerInfo();
    headers["Content-Type"] = "application/json";

    final Map<String, dynamic> auditLog = await generateAuditPayload();
    final localData = Map<String, dynamic>.from(appData);
    localData['metadata'] = auditLog;

    final plainBytes = utf8.encode(json.encode(localData));
    final encryptedBytes = await encryptBytes(
      Uint8List.fromList(plainBytes),
      pass,
    );
    final requestBody = {
      "message": "Sync via App Layout Tracker",
      "content": base64Encode(encryptedBytes),
      if (serverFileSha != null) "sha": serverFileSha,
    };
    return await _client.put(
      url,
      headers: headers,
      body: json.encode(requestBody),
    );
  }

  Future<void> pushToGitHub() async {
    final res = await pushToGitHubWithResponse();

    if (res.statusCode == 200 || res.statusCode == 201) {
      serverFileSha = json.decode(res.body)["content"]["sha"];
      await cacheLocally();
    }
  }

  Future<void> pushToGitHubWithAutoMerge() async {
    final res = await pushToGitHubWithResponse();

    if (res.statusCode == 200 || res.statusCode == 201) {
      serverFileSha = json.decode(res.body)["content"]["sha"];
      await cacheLocally();
    } else if (res.statusCode == 409) {
      final (code, serverFileSha, serverData) = await fetchFromGitHub();

      if ((serverFileSha == null && serverData == null) || serverData == null) {
        throw Exception('Failed to pull latest version of $_fileName: $code');
      }

      final conflicts = processConflicts(appData, serverData, {
        'kids': 'id',
        'biometrics': 'entry_id',
      });

      throw ConcurrentModificationException(conflicts);
    } else {
      throw Exception("Push error: ${res.body}");
    }
  }

  List<SheetConflict> processConflicts(
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

  Future<void> cacheLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDataCache, json.encode(appData));
    if (serverFileSha != null) {
      await prefs.setString(_keyShaCache, serverFileSha!);
    }
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
