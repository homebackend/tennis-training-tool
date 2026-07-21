/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:developer';
import 'dart:io';

import 'package:flutter_common/mixin/encrypt_decryt_service.dart';

class Decryptor with EncryptDecryptService {}

void main(List<String> args) async {
  if (args.length < 2) {
    log('Usage: dart run encrypt_tool.dart <path_to_pdf> <password>');
    exit(1);
  }

  final File sourceFile = File(args[0]);
  final String password = args[1];

  if (!await sourceFile.exists()) {
    log('Error: Source file does not exist.');
    exit(1);
  }

  log('Encrypting ${sourceFile.path}...');

  final fileBytes = await sourceFile.readAsBytes();
  final encryptedData = await Decryptor().decryptBytes(fileBytes, password);

  final String outputPath = '${sourceFile.path}.dec';
  await File(outputPath).writeAsBytes(encryptedData);

  log('✨ Successfully encrypted! Upload this file to your URL: $outputPath');
}
