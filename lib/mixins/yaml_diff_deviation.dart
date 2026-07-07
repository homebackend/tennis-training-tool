/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:deviation/deviation.dart';
// ignore: experimental_member_use
import 'package:deviation/unified_diff.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';

import 'yaml_diff.dart';

mixin YamlDiffDeviation implements YamlDiff {
  String buildUnifiedDiff(String oldYaml, String newYaml) {
    final oldLines = oldYaml.replaceAll('\r\n', '\n').split('\n');
    final newLines = newYaml.replaceAll('\r\n', '\n').split('\n');

    final patch = const DiffAlgorithm.myers().compute(oldLines, newLines);

    final diff = UnifiedDiff.fromPatch(
      patch,
      header: UnifiedDiffHeader.simple(),
      context: 5,
    );

    return diff.toString();
  }

  @override
  Future<bool> showYamlDiffDialog(
    BuildContext context, {
    required String existingYaml,
    required String newYaml,
  }) async {
    final diffText = buildUnifiedDiff(existingYaml, newYaml);

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return AlertDialog(
              title: const Text('Review YAML changes'),
              content: SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.85,
                height: 460,
                child: Scrollbar(
                  thumbVisibility: true,
                  // don't give it its own controller – it will find the primary one
                  child: SingleChildScrollView(
                    primary: true, // <-- add this
                    child: HighlightView(
                      diffText,
                      language: 'diff',
                      theme: isDark ? atomOneDarkTheme : githubTheme,
                      padding: const EdgeInsets.all(12),
                      textStyle: const TextStyle(
                        fontFamily: 'RobotoMono',
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ) ??
        false;
  }
}
