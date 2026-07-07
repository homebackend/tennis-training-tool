/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';

mixin YamlDiff {
  Future<bool> showYamlDiffDialog(
    BuildContext context, {
    required String existingYaml,
    required String newYaml,
  });
}
