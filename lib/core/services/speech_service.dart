import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final _speech = SpeechToText();
  bool _initialized = false;

  Future<bool> ensureReady() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    return _initialized;
  }

  bool get isListening => _speech.isListening;

  Future<bool> hasPermission() async {
    await ensureReady();
    return _speech.hasPermission;
  }

  Future<void> startListening({
    required void Function(String text, bool isFinal) onText,
  }) async {
    if (!await ensureReady()) {
      throw StateError('语音识别不可用');
    }
    if (_speech.isListening) await _speech.stop();

    final locales = await _speech.locales();
    final zh = locales.where((l) => l.localeId.startsWith('zh')).toList();
    final localeId = zh.isNotEmpty ? zh.first.localeId : 'zh_CN';

    await _speech.listen(
      localeId: localeId,
      listenMode: ListenMode.confirmation,
      onResult: (result) => onText(result.recognizedWords, result.finalResult),
    );
  }

  Future<void> stopListening() async {
    if (_speech.isListening) await _speech.stop();
  }

  void dispose() {
    _speech.stop();
  }
}
