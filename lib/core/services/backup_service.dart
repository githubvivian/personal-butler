import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../security/encryption_service.dart';

class BackupService {
  final _enc = EncryptionService.instance;

  Future<String> exportEncryptedBackup(String password) async {
    final data = await DatabaseHelper.instance.exportAllData();
    final json = jsonEncode({
      'exported_at': DateTime.now().toIso8601String(),
      'version': 1,
      'tables': data,
    });
    final encrypted = await _enc.encryptBackupPayload(json, password);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/personal_butler_backup_${DateTime.now().millisecondsSinceEpoch}.pbak',
    );
    await file.writeAsString(encrypted);
    return file.path;
  }

  Future<void> shareBackup(String password) async {
    final path = await exportEncryptedBackup(password);
    await Share.shareXFiles([XFile(path)], text: '个人管家加密备份');
  }

  Future<void> importEncryptedBackup(String password) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pbak', 'txt', 'json'],
    );
    if (result == null || result.files.single.path == null) return;
    final content = await File(result.files.single.path!).readAsString();
    final json = await _enc.decryptBackupPayload(content, password);
    final payload = jsonDecode(json) as Map<String, dynamic>;
    final tables = payload['tables'] as Map<String, dynamic>;
    final data = <String, List<Map<String, dynamic>>>{};
    for (final entry in tables.entries) {
      data[entry.key] = (entry.value as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    await DatabaseHelper.instance.replaceAllData(data);
  }
}
