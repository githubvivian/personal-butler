import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_state.dart';
import '../../core/services/speech_service.dart';
import '../../core/utils/ocr_service.dart';
import '../widgets/common_widgets.dart';

class VoiceInputScreen extends StatefulWidget {
  const VoiceInputScreen({super.key, this.speechInput});

  final SpeechInput? speechInput;

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

enum _SpeechPhase {
  initializing,
  unavailable,
  idle,
  starting,
  listening,
  stopping,
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  static const _finalResultGrace = Duration(milliseconds: 2200);

  late final SpeechInput _speech;
  final Object _sessionOwner = Object();
  final _text = TextEditingController();
  _SpeechPhase _phase = _SpeechPhase.initializing;
  bool _saving = false;
  int _listenGeneration = 0;
  Completer<void>? _pendingFinalResult;
  int? _pendingFinalGeneration;
  String? _error;

  bool get _isListening =>
      _phase == _SpeechPhase.listening || _phase == _SpeechPhase.stopping;

  bool get _canToggle =>
      !_saving &&
      (_phase == _SpeechPhase.idle || _phase == _SpeechPhase.listening);

  bool get _canSave =>
      !_saving &&
      _phase != _SpeechPhase.starting &&
      _phase != _SpeechPhase.stopping;

  @override
  void initState() {
    super.initState();
    _speech = widget.speechInput ?? SpeechService.instance;
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final ok = await _speech.ensureReady();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _phase = _SpeechPhase.unavailable;
          _error = '本机语音识别不可用，请手动输入文字';
        });
        return;
      }

      final permitted = await _speech.hasPermission();
      if (!mounted) return;
      if (!permitted) {
        setState(() {
          _phase = _SpeechPhase.unavailable;
          _error = '需要麦克风权限才能语音录入';
        });
        return;
      }

      setState(() {
        _phase = _SpeechPhase.idle;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _SpeechPhase.unavailable;
        _error = '语音初始化失败，请手动输入文字';
      });
    }
  }

  Future<void> _toggleListen() async {
    if (_saving) return;
    if (_phase == _SpeechPhase.listening) {
      setState(() {
        _phase = _SpeechPhase.stopping;
        _error = null;
      });

      try {
        await _speech.stopListening(sessionOwner: _sessionOwner);
        if (!mounted) return;
        setState(() => _phase = _SpeechPhase.idle);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _phase = _SpeechPhase.listening;
          _error = '停止语音识别失败，请重试';
        });
      }
      return;
    }
    if (_phase != _SpeechPhase.idle) return;

    _releasePendingFinalResult();
    final generation = ++_listenGeneration;
    _pendingFinalGeneration = generation;
    _pendingFinalResult = Completer<void>();
    setState(() {
      _phase = _SpeechPhase.starting;
      _error = null;
    });

    try {
      await _speech.startListening(
        sessionOwner: _sessionOwner,
        onText: (words, isFinal) {
          if (!mounted || generation != _listenGeneration) return;
          setState(() => _text.text = words);
          if (isFinal) _completePendingFinalResult(generation);
        },
        onSessionEnded: () => _handleSessionEnded(generation),
        onSessionError: () => _handleSessionError(generation),
      );
      if (!mounted || generation != _listenGeneration) {
        await _stopIgnoringErrors();
        return;
      }
      if (_phase != _SpeechPhase.starting) return;
      setState(() => _phase = _SpeechPhase.listening);
    } catch (_) {
      if (!mounted || generation != _listenGeneration) {
        await _stopIgnoringErrors();
        return;
      }
      _releasePendingFinalResult(generation);
      setState(() {
        _phase = _SpeechPhase.idle;
        _error = '启动语音识别失败，请重试';
      });
    }
  }

  void _handleSessionEnded(int generation) {
    if (!mounted || generation != _listenGeneration) return;
    if (_phase != _SpeechPhase.starting && _phase != _SpeechPhase.listening) {
      return;
    }
    _releasePendingFinalResult(generation);
    setState(() {
      _phase = _SpeechPhase.idle;
      _error = null;
    });
  }

  void _handleSessionError(int generation) {
    if (!mounted || generation != _listenGeneration) return;
    if (_phase != _SpeechPhase.starting && _phase != _SpeechPhase.listening) {
      return;
    }
    _releasePendingFinalResult(generation);
    setState(() {
      _phase = _SpeechPhase.idle;
      _error = '语音识别发生错误，请检查麦克风权限或网络后重试';
    });
  }

  Future<bool> _stopBeforeSave() async {
    setState(() {
      _phase = _SpeechPhase.stopping;
      _error = null;
    });
    try {
      await _speech.stopListening(sessionOwner: _sessionOwner);
      if (!mounted) return false;
      setState(() => _phase = _SpeechPhase.idle);
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _phase = _SpeechPhase.listening;
        _error = '停止语音识别失败，请重试';
      });
      return false;
    }
  }

  Future<void> _saveAsItem() => _save((content) async {
    final parsed = OcrParser.parse(content);
    final app = context.read<AppState>();
    final draft = await app.items.createDraft(
      type: 'meeting',
      title: parsed['title'] ?? _firstLine(content),
      ocrText: content,
    );
    if (!mounted) return;
    context.pushReplacement('/ocr-confirm/${draft.id}');
  });

  Future<void> _saveAsIdea() => _save((content) async {
    final app = context.read<AppState>();
    await app.ideas.create(title: _firstLine(content), content: content);
    if (!mounted) return;
    unawaited(snack(context, '已保存到灵感库'));
    context.pop();
  });

  Future<void> _save(Future<void> Function(String content) action) async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final content = await _prepareSaveContent();
      if (content == null || !mounted) return;
      await action(content);
    } catch (_) {
      if (!mounted) return;
      unawaited(snack(context, '保存失败，请重试'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _prepareSaveContent() async {
    if (_phase == _SpeechPhase.listening && !await _stopBeforeSave()) {
      return null;
    }
    if (!mounted) return null;

    await _awaitPendingFinalResult();
    if (!mounted) return null;

    final content = _text.text.trim();
    if (content.isEmpty) {
      unawaited(snack(context, '请先说话或输入文字'));
      return null;
    }
    return content;
  }

  Future<void> _awaitPendingFinalResult() async {
    final pending = _pendingFinalResult;
    final generation = _pendingFinalGeneration;
    if (pending == null ||
        pending.isCompleted ||
        generation != _listenGeneration) {
      return;
    }

    try {
      await pending.future.timeout(_finalResultGrace);
    } on TimeoutException {
      if (identical(_pendingFinalResult, pending) &&
          _pendingFinalGeneration == generation &&
          !pending.isCompleted) {
        pending.complete();
      }
    }
  }

  void _completePendingFinalResult(int generation) {
    final pending = _pendingFinalResult;
    if (_pendingFinalGeneration == generation &&
        pending != null &&
        !pending.isCompleted) {
      pending.complete();
    }
  }

  void _releasePendingFinalResult([int? generation]) {
    if (generation != null && _pendingFinalGeneration != generation) return;
    final pending = _pendingFinalResult;
    if (pending != null && !pending.isCompleted) pending.complete();
    _pendingFinalResult = null;
    _pendingFinalGeneration = null;
  }

  String _firstLine(String text) {
    final line = text.split('\n').first.trim();
    if (line.length <= 30) return line.isEmpty ? '语音灵感' : line;
    return '${line.substring(0, 30)}…';
  }

  Future<void> _stopIgnoringErrors() async {
    try {
      await _speech.stopListening(sessionOwner: _sessionOwner);
    } catch (_) {}
  }

  @override
  void dispose() {
    _listenGeneration++;
    _releasePendingFinalResult();
    unawaited(_stopIgnoringErrors());
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语音录入')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '中文语音转文字',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isListening ? '正在聆听…' : '点击下方麦克风开始说话',
                    style: TextStyle(
                      color: _isListening
                          ? AppColors.accentGreen
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: '识别结果（可修改）',
                  hintText: '说话内容会显示在这里…',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _canToggle ? _toggleListen : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? AppColors.danger : AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_isListening ? AppColors.danger : AppColors.primary)
                              .withValues(alpha: 0.35),
                      blurRadius: _isListening ? 20 : 8,
                      spreadRadius: _isListening ? 4 : 0,
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _canSave ? _saveAsIdea : null,
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('存灵感'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _canSave ? _saveAsItem : null,
                    icon: const Icon(Icons.check),
                    label: const Text('存事项'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
