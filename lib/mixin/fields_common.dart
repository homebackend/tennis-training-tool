/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';

mixin FieldsCommon {
  Widget verticalSpacing({double? size = 8.0}) {
    return SizedBox(height: size);
  }

  Widget horizontalSpacing({double? size = 8.0}) {
    return SizedBox(width: size);
  }
}
