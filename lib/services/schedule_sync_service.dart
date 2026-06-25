/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'encrypt_decryt_service.dart';

class ScheduleSyncService with EncryptDecryptService {
  final String url;
  final String password;
  ScheduleSyncService(this.url, this.password);

  Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMod = prefs.getString('sched_lastmod');

    try {
      final res = await http.get(
        Uri.parse(url),
        headers: lastMod != null ? {'If-Modified-Since': lastMod} : {},
      );

      if (res.statusCode == 304) {
        return prefs.getString('sched_cache')!;
      }
      if (res.statusCode == 200) {
        final plain = await decryptBytes(res.bodyBytes, password);
        final text = utf8.decode(plain);
        await prefs.setString('sched_cache', text);
        await prefs.setString(
          'sched_lastmod',
          res.headers['last-modified'] ?? '',
        );
        return text;
      }
      throw Exception('HTTP ${res.statusCode}');
    } catch (e) {
      final cached = prefs.getString('sched_cache');
      if (cached != null) return cached;
      rethrow;
    }
  }
}
