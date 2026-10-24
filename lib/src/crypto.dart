import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class Crypto {
  static String cryptoHandler(
    String text,
    String iv,
    String secretKeyString,
    bool encryptText,
  ) {
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(
          encrypt.Key.fromUtf8(secretKeyString),
          mode: encrypt.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );
      final ivValue = encrypt.IV.fromUtf8(iv);
      return encryptText
          ? encrypter.encrypt(text, iv: ivValue).base64
          : encrypter.decrypt64(text, iv: ivValue);
    } catch (_) {
      return text;
    }
  }

  static String encryptAESCryptoJS(String plainText, String passphrase) {
    try {
      final salt = _randomSalt(8);
      final derived = _deriveKeyAndIV(passphrase.trim(), salt);
      final key = Uint8List.fromList(derived.sublist(0, 32));
      final iv = Uint8List.fromList(derived.sublist(32, 48));
      final encrypter = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
      );
      final encrypted = encrypter.encrypt(plainText.trim(), iv: encrypt.IV(iv));
      return base64.encode([
        ...utf8.encode('Salted__'),
        ...salt,
        ...encrypted.bytes,
      ]);
    } catch (_) {
      return plainText;
    }
  }

  static String decryptAESCryptoJS(String encrypted, String passphrase) {
    try {
      final bytes = base64.decode(encrypted.trim());
      final salt = bytes.sublist(8, 16);
      final data = bytes.sublist(16);
      final derived = _deriveKeyAndIV(passphrase.trim(), salt);
      final key = Uint8List.fromList(derived.sublist(0, 32));
      final iv = Uint8List.fromList(derived.sublist(32, 48));
      final encrypter = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
      );
      return encrypter.decrypt64(base64.encode(data), iv: encrypt.IV(iv));
    } catch (_) {
      return encrypted;
    }
  }

  static List<int> _deriveKeyAndIV(String passphrase, List<int> salt) {
    final password = utf8.encode(passphrase);
    final hashes = <int>[];
    var current = <int>[];
    while (hashes.length < 48) {
      current = md5.convert([...current, ...password, ...salt]).bytes;
      hashes.addAll(current);
    }
    return hashes;
  }

  static List<int> _randomSalt(int length) {
    final random = DateTime.now().microsecondsSinceEpoch;
    return List<int>.generate(length, (i) => ((random >> (i % 32)) & 0xff) + 1);
  }
}
