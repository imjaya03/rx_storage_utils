// import 'dart:convert';

// import 'package:crypto/crypto.dart';

// class EncryptionService {
//   bool enableEncryption = false;
//   String encryptionKey = '';

//   void initEncryption(bool enable, String key) {
//     enableEncryption = enable;
//     encryptionKey = key;
//   }

//   String encrypt(String text) {
//     if (!enableEncryption || encryptionKey.isEmpty) return text;
//     final bytes = utf8.encode(text);
//     final key = utf8.encode(encryptionKey);
//     final hmac = Hmac(sha256, key);
//     final digest = hmac.convert(bytes);
//     final encrypted = List<int>.from(bytes);
//     for (var i = 0; i < encrypted.length; i++) {
//       encrypted[i] = encrypted[i] ^ key[i % key.length];
//     }
//     return '${base64Encode(encrypted)}.$digest';
//   }

//   String decrypt(String text) {
//     if (!enableEncryption || encryptionKey.isEmpty) return text;
//     try {
//       final parts = text.split('.');
//       if (parts.length != 2) return text;
//       final encrypted = base64Decode(parts[0]);
//       final key = utf8.encode(encryptionKey);
//       final decrypted = List<int>.from(encrypted);
//       for (var i = 0; i < decrypted.length; i++) {
//         decrypted[i] = decrypted[i] ^ key[i % key.length];
//       }
//       return utf8.decode(decrypted);
//     } catch (_) {
//       return text;
//     }
//   }
// }
