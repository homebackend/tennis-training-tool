/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pretty_diff_text/pretty_diff_text.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

import 'yaml_diff.dart';

mixin YamlDiffPretty implements YamlDiff {
  dynamic _canonicalize(dynamic node, {bool sortLists = true}) {
    if (node is YamlMap || node is Map) {
      final map = <String, dynamic>{};
      final keys = node.keys.map((k) => k.toString()).toList()..sort();
      for (final k in keys) {
        map[k] = _canonicalize(node[k], sortLists: sortLists);
      }
      return map;
    }
    if (node is YamlList || node is List) {
      var list = node
          .map((e) => _canonicalize(e, sortLists: sortLists))
          .toList();
      if (sortLists) {
        list.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      }
      return list;
    }
    return node;
  }

  String normalizeYaml(String yamlStr, {bool sortLists = true}) {
    if (yamlStr.trim().isEmpty) return '';
    final doc = loadYaml(yamlStr);
    final canonical = _canonicalize(doc, sortLists: sortLists);
    return YamlWriter().write(canonical);
  }

  @override
  Future<bool> showYamlDiffDialog(
    BuildContext context, {
    required String existingYaml,
    required String newYaml,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            final baseStyle = Theme.of(ctx).textTheme.bodyMedium!.copyWith(
              fontFamily: 'RobotoMono',
              fontSize: 14,
              height: 1.4,
              color: Theme.of(ctx).colorScheme.onSurface,
            );

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.compare_arrows),
                  SizedBox(width: 8),
                  Text('Review YAML changes'),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.85,
                height: 460,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'green = added • red = removed (keys sorted)',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          primary: true,
                          padding: const EdgeInsets.all(12),
                          child: PrettyDiffText(
                            oldText: existingYaml,
                            newText: newYaml,
                            diffCleanupType: DiffCleanupType.EFFICIENCY,
                            defaultTextStyle: baseStyle,
                            addedTextStyle: baseStyle.copyWith(
                              backgroundColor: Colors.green.withValues(
                                alpha: 0.18,
                              ),
                              color: Colors.green[800],
                            ),
                            deletedTextStyle: baseStyle.copyWith(
                              backgroundColor: Colors.red.withValues(
                                alpha: 0.18,
                              ),
                              color: Colors.red[800],
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ) ??
        false;
  }
}
