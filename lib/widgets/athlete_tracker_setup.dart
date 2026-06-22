/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'package:flutter/material.dart';

class AthleteTrackerSetup extends StatelessWidget {
  final TextEditingController repoController;
  final TextEditingController tokenController;
  final TextEditingController cryptoPasswordController;
  final VoidCallback onInitialize;

  const AthleteTrackerSetup({
    super.key,
    required this.repoController,
    required this.tokenController,
    required this.cryptoPasswordController,
    required this.onInitialize,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Athlete Tracker Setup')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: repoController,
                decoration: const InputDecoration(
                  labelText: 'GitHub Repository Target (owner/repo)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tokenController,
                decoration: const InputDecoration(
                  labelText: 'GitHub PAT Token',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cryptoPasswordController,
                decoration: const InputDecoration(
                  labelText: 'AES Decryption Key Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onInitialize,
                child: const Text('Initialize Tracker Workspace'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
