/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

mixin EncryptDecryptService {
  Future<Uint8List> encryptBytes(Uint8List plain, String password) async {
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await Pbkdf2.hmacSha256(
      iterations: 10000,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final box = await AesGcm.with256bits().encrypt(plain, secretKey: key);
    return Uint8List.fromList([
      ...salt,
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
  }

  Future<Uint8List> decryptBytes(Uint8List data, String password) async {
    final salt = data.sublist(0, 16);
    final nonce = data.sublist(16, 28);
    final macBytes = data.sublist(28, 44);
    final ct = data.sublist(44);

    final derived = await Pbkdf2.hmacSha256(
      iterations: 10000,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

    return Uint8List.fromList(
      await AesGcm.with256bits().decrypt(
        SecretBox(ct, nonce: nonce, mac: Mac(macBytes)),
        secretKey: derived,
      ),
    );
  }
}
