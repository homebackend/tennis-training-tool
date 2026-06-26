/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'encrypt_decryt_service.dart';

class ScheduleSyncService with EncryptDecryptService {
  static final keySchedLastmod = 'sched_lastmod';

  final String url;
  final String password;
  final Future<void> Function() loader;
  ScheduleSyncService(this.url, this.password, this.loader);

  Future<String> _loadFromNetwork(bool cacheFileExists) async {
    final prefs = await SharedPreferences.getInstance();
    final lastMod = prefs.getString(keySchedLastmod);
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: cacheFileExists && lastMod != null
            ? {'If-Modified-Since': lastMod}
            : {},
      );

      final cacheFile = await _cacheFile();
      if (cacheFileExists && res.statusCode == 304) {
        return await cacheFile.readAsString();
      }
      if (res.statusCode == 200) {
        final plain = await decryptBytes(res.bodyBytes, password);
        final text = utf8.decode(plain);
        await cacheFile.writeAsString(text);
        final lm = res.headers['last-modified'];
        if (lm != null) await prefs.setString(keySchedLastmod, lm);
        if (cacheFileExists) {
          // If cacheFileExists is true that means earlier
          // we loaded data from cache and now new version
          // of cache is available. So notify.
          loader();
        }
        return text;
      }

      log('Error during http call: ${res.statusCode}');
      throw (Exception('HTTP ${res.statusCode}'));
    } catch (e) {
      log('Error: $e');
      rethrow;
    }
  }

  Future<String> load() async {
    final cacheFile = await _cacheFile();
    bool cacheFileExists = cacheFile.existsSync();
    if (cacheFileExists) {
      _loadFromNetwork(cacheFileExists);
      return await cacheFile.readAsString();
    } else {
      return await _loadFromNetwork(cacheFileExists);
    }
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/training_schedule.yaml');
  }
}
