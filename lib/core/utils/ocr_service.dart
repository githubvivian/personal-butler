import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:photo_manager/photo_manager.dart';

class OcrSourceUnavailableException implements Exception {
  const OcrSourceUnavailableException();
}

class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  TextRecognizer? _recognizer;

  TextRecognizer get recognizer {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.chinese);
    return _recognizer!;
  }

  Future<String> recognizeAsset(String assetId) async {
    final file = await _resolveFile(assetId);
    if (file == null) throw const OcrSourceUnavailableException();
    final input = InputImage.fromFilePath(file.path);
    final result = await recognizer.processImage(input);
    return result.text;
  }

  Future<File?> _resolveFile(String sourceId) async {
    if (sourceId.startsWith('local:')) {
      final path = sourceId.substring('local:'.length);
      if (path.isEmpty) return null;
      final file = File(path);
      return await file.exists() ? file : null;
    }
    final asset = await AssetEntity.fromId(sourceId);
    return asset?.file;
  }

  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}

class OcrParser {
  static Map<String, String?> parse(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    String? title;
    String? location;
    DateTime? dateTime;

    final datePatterns = [
      RegExp(r'(\d{4})[年./-](\d{1,2})[月./-](\d{1,2})'),
      RegExp(r'(\d{1,2})[月./-](\d{1,2})[日号]?'),
    ];
    final timePattern = RegExp(r'(\d{1,2})[:：](\d{2})');

    for (final line in lines) {
      final trimmed = line.trim();
      if (title == null && trimmed.length >= 2 && trimmed.length <= 40) {
        title = trimmed;
      }
      for (final p in datePatterns) {
        final m = p.firstMatch(trimmed);
        if (m != null) {
          try {
            if (m.groupCount >= 3 && m.group(1)!.length == 4) {
              dateTime = DateTime(
                int.parse(m.group(1)!),
                int.parse(m.group(2)!),
                int.parse(m.group(3)!),
              );
            } else if (m.groupCount >= 2) {
              final now = DateTime.now();
              dateTime = DateTime(
                now.year,
                int.parse(m.group(1)!),
                int.parse(m.group(2)!),
              );
            }
          } catch (_) {}
        }
      }
      final tm = timePattern.firstMatch(trimmed);
      if (tm != null && dateTime != null) {
        dateTime = DateTime(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          int.parse(tm.group(1)!),
          int.parse(tm.group(2)!),
        );
      }
      if (location == null &&
          (trimmed.contains('地点') ||
              trimmed.contains('地址') ||
              trimmed.contains('室') ||
              trimmed.contains('楼'))) {
        location = trimmed.replaceAll(RegExp(r'^[地点地址：:]+'), '').trim();
      }
    }

    return {
      'title': title ?? (lines.isNotEmpty ? lines.first : '新事项'),
      'location': location,
      'startAt': dateTime?.toIso8601String(),
    };
  }
}
