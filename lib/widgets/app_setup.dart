/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';

import '../services/preferences_backup_service.dart';

class AppSetup extends StatefulWidget {
  final PreferencesBackupService backupService;
  final void Function(String gitRepo, String gitToken, String password) onDone;
  final void Function() onImport;
  const AppSetup(this.backupService, this.onDone, this.onImport, {super.key});

  @override
  State<StatefulWidget> createState() => _AppSetupState();
}

class _AppSetupState extends State<AppSetup> {
  late TextEditingController _repoController;
  late TextEditingController _tokenController;
  late TextEditingController _passwordController;
  String? _repoError, _tokenError, _pwdError;

  @override
  void initState() {
    super.initState();
    _repoController = TextEditingController();
    _tokenController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _repoController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Setup')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _repoController,
                decoration: InputDecoration(
                  labelText: 'GitHub Repository Target (owner/repo)',
                  border: const OutlineInputBorder(),
                  errorText: _repoError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tokenController,
                decoration: InputDecoration(
                  labelText: 'GitHub PAT Token',
                  border: OutlineInputBorder(),
                  errorText: _tokenError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'AES Decryption Key/Password',
                  border: OutlineInputBorder(),
                  errorText: _pwdError,
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  final repo = _repoController.text.trim();
                  final token = _tokenController.text.trim();
                  final pwd = _passwordController.text;

                  setState(() {
                    _repoError = repo.isEmpty ? 'Required' : null;
                    _tokenError = token.isEmpty ? 'Required' : null;
                    _pwdError = pwd.isEmpty ? 'Required' : null;
                  });

                  if (repo.isEmpty || token.isEmpty || pwd.isEmpty) return;

                  widget.onDone(repo, token, pwd);
                },
                child: const Text('Complete Setup'),
              ),
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
                  } else {
                    widget.onImport();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
