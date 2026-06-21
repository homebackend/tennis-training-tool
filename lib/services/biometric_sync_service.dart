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
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import 'encrypt_decryt_service.dart';

class BiometricSyncService with EncryptDecryptService {
  final FlutterSecureStorage _secureStorage;
  static final StreamController<void> globalResyncTrigger =
      StreamController<void>.broadcast();

  static const String _keyRepo = "git_json_repo";
  static const String _keyToken = "git_json_token";
  static const String _keyPassword = "git_json_password";
  static const String _keyDataCache = "json_local_cache";
  static const String _keyShaCache = "json_server_sha";

  static const String _fileName = "tracker.json";

  Map<String, dynamic> appData = {"kids": [], "biometrics": []};
  Map? schema;
  String? serverFileSha;

  BiometricSyncService(this._secureStorage);

  Future<bool> loadCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final String rawYaml = await rootBundle.loadString('assets/schema.yaml');
      schema = loadYaml(rawYaml);
    } catch (e) {
      return false;
    }

    final repo = await _secureStorage.read(key: _keyRepo);
    final token = await _secureStorage.read(key: _keyToken);
    final pass = await _secureStorage.read(key: _keyPassword);

    if (repo != null && token != null && pass != null) {
      final cache = prefs.getString(_keyDataCache);
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
    await _secureStorage.write(key: _keyRepo, value: repo);
    await _secureStorage.write(key: _keyToken, value: token);
    await _secureStorage.write(key: _keyPassword, value: password);
  }

  Future<void> clearSavedSession() async {
    await _secureStorage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDataCache);
    await prefs.remove(_keyShaCache);
    appData = {"kids": [], "biometrics": []};
    serverFileSha = null;
  }

  Future<void> syncFromGitHub() async {
    final String rawYaml = await rootBundle.loadString('assets/schema.yaml');
    schema = loadYaml(rawYaml);

    final repo = await _secureStorage.read(key: _keyRepo) ?? "";
    final token = await _secureStorage.read(key: _keyToken) ?? "";
    final cryptoPass = await _secureStorage.read(key: _keyPassword) ?? "";

    final dataUrl = Uri.parse(
      "https://api.github.com/repos/$repo/contents/$_fileName",
    );

    final dataRes = await http.get(
      dataUrl,
      headers: {"Authorization": "Bearer $token"},
    );
    if (dataRes.statusCode == 200) {
      final dataBody = json.decode(dataRes.body);
      serverFileSha = dataBody["sha"];
      final encryptedBytes = base64Decode(
        dataBody["content"].toString().replaceAll('\n', ''),
      );
      final decryptedBytes = await decryptBytes(encryptedBytes, cryptoPass);
      appData = json.decode(utf8.decode(decryptedBytes));
    } else if (dataRes.statusCode == 404) {
      appData = {"kids": [], "biometrics": []};
      serverFileSha = null;
    } else {
      throw Exception("Data download rejected: Code ${dataRes.statusCode}");
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

  Future<void> pushToGitHub() async {
    final repo = await _secureStorage.read(key: _keyRepo) ?? "";
    final token = await _secureStorage.read(key: _keyToken) ?? "";
    final cryptoPass = await _secureStorage.read(key: _keyPassword) ?? "";

    final url = Uri.parse(
      "https://api.github.com/repos/$repo/contents/$_fileName",
    );
    final plainBytes = utf8.encode(json.encode(appData));
    final encryptedBytes = await encryptBytes(
      Uint8List.fromList(plainBytes),
      cryptoPass,
    );
    final requestBody = {
      "message": "Sync via App Layout Tracker",
      "content": base64Encode(encryptedBytes),
      if (serverFileSha != null) "sha": serverFileSha,
    };
    final res = await http.put(
      url,
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: json.encode(requestBody),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      serverFileSha = json.decode(res.body)["content"]["sha"];
      await cacheLocally();
    } else {
      throw Exception("Push error: ${res.body}");
    }
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
