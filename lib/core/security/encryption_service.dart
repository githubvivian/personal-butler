import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionService {
  EncryptionService._();
  static final EncryptionService instance = EncryptionService._();

  static const _dbKeyKey = 'db_encryption_key';
  static const _vaultKeyKey = 'vault_encryption_key';
  final _storage = const FlutterSecureStorage();

  Future<String> getOrCreateDbPassword() async {
    var key = await _storage.read(key: _dbKeyKey);
    if (key != null && key.isNotEmpty) return key;
    key = _generateKeyMaterial();
    await _storage.write(key: _dbKeyKey, value: key);
    return key;
  }

  Future<String> getOrCreateVaultKey() async {
    var key = await _storage.read(key: _vaultKeyKey);
    if (key != null && key.isNotEmpty) return key;
    key = _generateKeyMaterial();
    await _storage.write(key: _vaultKeyKey, value: key);
    return key;
  }

  String _generateKeyMaterial() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  enc.Key _keyFromMaterial(String material) {
    final digest = sha256.convert(utf8.encode(material));
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  Future<String> encryptVaultField(String plain) async {
    final material = await getOrCreateVaultKey();
    final key = _keyFromMaterial(material);
    final iv = enc.IV.fromSecureRandom(16);
    final aes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = aes.encrypt(plain, iv: iv);
    return '${base64.encode(iv.bytes)}:${encrypted.base64}';
  }

  Future<String> decryptVaultField(String cipher) async {
    final parts = cipher.split(':');
    if (parts.length != 2) return '';
    final material = await getOrCreateVaultKey();
    final key = _keyFromMaterial(material);
    final iv = enc.IV(base64.decode(parts[0]));
    final aes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return aes.decrypt(enc.Encrypted.fromBase64(parts[1]), iv: iv);
  }

  Future<String> encryptBackupPayload(
    String json,
    String backupPassword,
  ) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final keyBytes = _deriveKey(backupPassword, salt);
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV.fromSecureRandom(16);
    final aes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = aes.encrypt(json, iv: iv);
    final payload = {
      'v': 1,
      'salt': base64.encode(salt),
      'iv': base64.encode(iv.bytes),
      'data': encrypted.base64,
    };
    return jsonEncode(payload);
  }

  Future<String> decryptBackupPayload(
    String content,
    String backupPassword,
  ) async {
    late final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      throw const FormatException('Backup envelope is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup envelope must be a JSON object.');
    }
    final version = decoded['v'];
    if (version is! int || version != 1) {
      throw const FormatException('Backup envelope version must be integer 1.');
    }
    final saltText = _requiredBackupEnvelopeString(decoded, 'salt');
    final ivText = _requiredBackupEnvelopeString(decoded, 'iv');
    final dataText = _requiredBackupEnvelopeString(decoded, 'data');
    final salt = _decodeBackupEnvelopeBytes(
      'salt',
      saltText,
      expectedLength: 16,
    );
    final ivBytes = _decodeBackupEnvelopeBytes(
      'iv',
      ivText,
      expectedLength: 16,
    );
    final encryptedBytes = _decodeBackupEnvelopeBytes('data', dataText);
    if (encryptedBytes.isEmpty || encryptedBytes.length % 16 != 0) {
      throw const FormatException('Backup envelope data is malformed.');
    }
    final iv = enc.IV(Uint8List.fromList(ivBytes));
    final keyBytes = _deriveKey(backupPassword, salt);
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final aes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return aes.decrypt(
      enc.Encrypted(Uint8List.fromList(encryptedBytes)),
      iv: iv,
    );
  }

  String _requiredBackupEnvelopeString(
    Map<String, dynamic> envelope,
    String field,
  ) {
    final value = envelope[field];
    if (value is! String) {
      throw FormatException('Backup envelope $field must be a string.');
    }
    return value;
  }

  List<int> _decodeBackupEnvelopeBytes(
    String field,
    String value, {
    int? expectedLength,
  }) {
    late final List<int> bytes;
    try {
      bytes = base64.decode(value);
    } on FormatException {
      throw FormatException('Backup envelope $field is malformed.');
    }
    if (expectedLength != null && bytes.length != expectedLength) {
      throw FormatException('Backup envelope $field is malformed.');
    }
    return bytes;
  }

  List<int> _deriveKey(String password, List<int> salt) {
    var block = utf8.encode(password) + salt;
    for (var i = 0; i < 12000; i++) {
      block = sha256.convert(block).bytes;
    }
    return block;
  }
}
