import 'package:speech_to_text/speech_to_text.dart';

typedef SpeechTextCallback = void Function(String text, bool isFinal);
typedef SpeechSessionCallback = void Function();

abstract interface class SpeechInput {
  Future<bool> ensureReady();

  Future<bool> hasPermission();

  Future<void> startListening({
    required Object sessionOwner,
    required SpeechTextCallback onText,
    SpeechSessionCallback? onSessionEnded,
    SpeechSessionCallback? onSessionError,
  });

  Future<void> stopListening({required Object sessionOwner});
}

class SpeechService implements SpeechInput {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final _speech = SpeechToText();
  bool _initialized = false;
  Future<void> _operationQueue = Future.value();
  Object? _latestRequestedOwner;
  int _latestRequestedGeneration = 0;
  SpeechSessionCallback? _onSessionEnded;
  SpeechSessionCallback? _onSessionError;

  @override
  Future<bool> ensureReady() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (_) => _notifySessionError(),
      onStatus: (status) {
        if (status == SpeechToText.doneStatus) {
          _notifySessionEnded();
        }
      },
    );
    return _initialized;
  }

  bool get isListening => _speech.isListening;

  @override
  Future<bool> hasPermission() async {
    await ensureReady();
    return _speech.hasPermission;
  }

  @override
  Future<void> startListening({
    required Object sessionOwner,
    required SpeechTextCallback onText,
    SpeechSessionCallback? onSessionEnded,
    SpeechSessionCallback? onSessionError,
  }) {
    final generation = ++_latestRequestedGeneration;
    _latestRequestedOwner = sessionOwner;
    return _enqueue(
      () => _startListening(
        sessionOwner,
        generation,
        onText,
        onSessionEnded,
        onSessionError,
      ),
    );
  }

  @override
  Future<void> stopListening({required Object sessionOwner}) {
    if (!identical(_latestRequestedOwner, sessionOwner)) {
      return Future.value();
    }

    _latestRequestedOwner = null;
    _latestRequestedGeneration++;
    _clearSessionCallbacks();
    return _enqueue(_speech.stop);
  }

  Future<void> _startListening(
    Object sessionOwner,
    int generation,
    SpeechTextCallback onText,
    SpeechSessionCallback? onSessionEnded,
    SpeechSessionCallback? onSessionError,
  ) async {
    if (!_isLatestRequest(sessionOwner, generation)) return;

    final ready = await ensureReady();
    if (!_isLatestRequest(sessionOwner, generation)) return;
    if (!ready) throw StateError('语音识别不可用');

    await _speech.stop();
    if (!_isLatestRequest(sessionOwner, generation)) return;

    final locales = await _speech.locales();
    if (!_isLatestRequest(sessionOwner, generation)) return;
    final zh = locales.where((l) => l.localeId.startsWith('zh')).toList();
    final localeId = zh.isNotEmpty ? zh.first.localeId : 'zh_CN';

    try {
      _onSessionEnded = () {
        if (_isLatestRequest(sessionOwner, generation)) {
          onSessionEnded?.call();
        }
      };
      _onSessionError = () {
        if (_isLatestRequest(sessionOwner, generation)) {
          onSessionError?.call();
        }
      };
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenMode: ListenMode.confirmation,
          pauseFor: const Duration(seconds: 8),
          listenFor: const Duration(seconds: 60),
        ),
        onResult: (result) =>
            onText(result.recognizedWords, result.finalResult),
      );
    } catch (_) {
      _clearSessionCallbacks();
      if (!_isLatestRequest(sessionOwner, generation)) {
        await _speech.stop();
      }
      rethrow;
    }

    if (!_isLatestRequest(sessionOwner, generation)) {
      _clearSessionCallbacks();
      await _speech.stop();
    }
  }

  void _clearSessionCallbacks() {
    _onSessionEnded = null;
    _onSessionError = null;
  }

  void _notifySessionEnded() {
    final callback = _onSessionEnded;
    _clearSessionCallbacks();
    callback?.call();
  }

  void _notifySessionError() {
    final callback = _onSessionError;
    _clearSessionCallbacks();
    callback?.call();
  }

  bool _isLatestRequest(Object sessionOwner, int generation) {
    return identical(_latestRequestedOwner, sessionOwner) &&
        _latestRequestedGeneration == generation;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operationQueue.then((_) => operation());
    _operationQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> dispose({required Object sessionOwner}) =>
      stopListening(sessionOwner: sessionOwner);
}
