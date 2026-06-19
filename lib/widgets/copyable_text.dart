/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../mixin/fields_common.dart';

class CopyableText extends StatelessWidget with FieldsCommon {
  final String text;

  const CopyableText({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text(
                text,
                style: const TextStyle(fontSize: 16.0),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          horizontalSpacing(),
          if (text.startsWith('http://') || text.startsWith('https://'))
            IconButton(
              icon: const Icon(Icons.link),
              color: Theme.of(context).primaryColor,
              onPressed: () async {
                final Uri url = Uri.parse(text);
                try {
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    throw 'Could not launch browser context for: $text';
                  }
                } catch (e) {
                  log('URL redirection failure: $e');
                }
              },
              tooltip: 'Open url',
            ),
          IconButton(
            icon: const Icon(Icons.copy),
            color: Theme.of(context).primaryColor,
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            tooltip: 'Copy to clipboard',
          ),
        ],
      ),
    );
  }
}
