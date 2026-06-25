/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tennis_training_tool/services/preferences_backup_service.dart';

class SetupPage extends StatefulWidget {
  final bool pickLocal;
  final FlutterSecureStorage secureStorage;
  final Future<void> Function(String url, String password) loader;
  final Future<void> Function()? pickLocalCopy;
  final PreferencesBackupService backupService;
  const SetupPage(
    this.secureStorage,
    this.loader,
    this.backupService, {
    this.pickLocal = false,
    this.pickLocalCopy,
    super.key,
  });

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _urlController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _urlController.text =
        await widget.secureStorage.read(
          key: PreferencesBackupService.keyScheduleYamlUrl,
        ) ??
        '';
    _passwordController.text =
        await widget.secureStorage.read(
          key: PreferencesBackupService.keyEncPwd,
        ) ??
        '';
  }

  @override
  void dispose() {
    _urlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: 'URL'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Decryption Key'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => widget.loader(
                _urlController.text.trim(),
                _passwordController.text.trim(),
              ),
              child: const Text('Load Remote Document'),
            ),
            if (widget.pickLocal) ...[
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: widget.pickLocalCopy,
                child: const Text('Local File'),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_present),
              label: const Text('Import Configuration File'),
              onPressed: () async {
                final msg = await widget.backupService
                    .importSystemPreferences();
                if (msg != null && mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
