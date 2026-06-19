/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';

import '../mixin/fields_common.dart';
import 'copyable_text.dart';

class AppUpdateDialog extends StatelessWidget with FieldsCommon {
  final String? downloadUrl;
  final String? latestVersion;
  final String? changeLog;
  final VoidCallback? onProceed;
  final VoidCallback? onDismiss;

  const AppUpdateDialog({
    super.key,
    required this.downloadUrl,
    required this.latestVersion,
    required this.changeLog,
    this.onProceed,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.system_update_alt, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          const Text('New Update Available'),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Latest Version: ${latestVersion ?? "Unknown"}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            verticalSpacing(size: 12),
            if (downloadUrl != null) ...[
              Row(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Package Link:',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  horizontalSpacing(),
                  Expanded(
                    child: CopyableText(
                      text: downloadUrl!,
                    ),
                  ),
                ],
              ),
            ],
            const Divider(),
            verticalSpacing(),
            Text(
              'Changelog / Commits:',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            verticalSpacing(),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: IntrinsicHeight(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        changeLog ?? 'No direct commit information provided.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (onDismiss != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDismiss!();
            },
            child: const Text('Dismiss'),
          ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            if (onProceed != null) onProceed!();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(onProceed == null ? 'OK' : 'Install Update'),
        ),
      ],
    );
  }
}
