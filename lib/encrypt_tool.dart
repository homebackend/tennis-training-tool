/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:developer';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

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

  final salt = SecretKeyData.random(length: 16).bytes;
  final pbkdf2 = Pbkdf2.hmacSha256(iterations: 10000, bits: 256);

  final SecretKey passwordSecretKey = SecretKey(utf8.encode(password));
  final SecretKey derivedKey = await pbkdf2.deriveKey(
    secretKey: passwordSecretKey,
    nonce: salt,
  );

  final aesGcm256 = AesGcm.with256bits();

  final fileBytes = await sourceFile.readAsBytes();
  final SecretBox secretBox = await aesGcm256.encrypt(
    fileBytes,
    secretKey: derivedKey,
  );

  final Uint8List encryptedData = Uint8List.fromList([
    ...salt,
    ...secretBox.nonce,
    ...secretBox.mac.bytes,
    ...secretBox.cipherText,
  ]);

  final String outputPath = '${sourceFile.path}.enc';
  await File(outputPath).writeAsBytes(encryptedData);

  log('✨ Successfully encrypted! Upload this file to your URL: $outputPath');
}
