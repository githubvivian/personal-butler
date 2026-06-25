import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_state.dart';
import '../../core/services/speech_service.dart';
import '../../core/utils/ocr_service.dart';
import '../widgets/common_widgets.dart';

class VoiceInputScreen extends StatefulWidget {
  const VoiceInputScreen({super.key});

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  final _speech = SpeechService.instance;
  final _text = TextEditingController();
  bool _listening = false;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await _speech.ensureReady();
    if (!ok) {
      setState(() {
        _error = '本机语音识别不可用，请检查麦克风权限';
      });
      return;
    }
    final permitted = await _speech.hasPermission();
    if (!permitted) {
      setState(() {
        _error = '需要麦克风权限才能语音录入';
      });
      return;
    }
    setState(() => _ready = true);
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stopListening();
      setState(() => _listening = false);
      return;
    }
    setState(() {
      _listening = true;
      _error = null;
    });
    try {
      await _speech.startListening(
        onText: (words, _) {
          if (!mounted) return;
          setState(() => _text.text = words);
        },
      );
    } catch (e) {
      setState(() {
        _listening = false;
        _error = '启动识别失败：$e';
      });
    }
  }

  Future<void> _saveAsItem() async {
    final content = _text.text.trim();
    if (content.isEmpty) {
      snack(context, '请先说话或输入文字');
      return;
    }
    await _speech.stopListening();
    final parsed = OcrParser.parse(content);
    final app = context.read<AppState>();
    final draft = await app.items.createDraft(
      type: 'meeting',
      title: parsed['title'] ?? _firstLine(content),
      ocrText: content,
    );
    if (!mounted) return;
    context.pushReplacement('/ocr-confirm/${draft.id}');
  }

  Future<void> _saveAsIdea() async {
    final content = _text.text.trim();
    if (content.isEmpty) {
      snack(context, '请先说话或输入文字');
      return;
    }
    await _speech.stopListening();
    final app = context.read<AppState>();
    await app.ideas.create(
      title: _firstLine(content),
      content: content,
    );
    if (!mounted) return;
    snack(context, '已保存到灵感库');
    context.pop();
  }

  String _firstLine(String text) {
    final line = text.split('\n').first.trim();
    if (line.length <= 30) return line.isEmpty ? '语音灵感' : line;
    return '${line.substring(0, 30)}…';
  }

  @override
  void dispose() {
    _speech.stopListening();
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
                    _listening ? '正在聆听…' : '点击下方麦克风开始说话',
                    style: TextStyle(
                      color: _listening ? AppColors.accentGreen : AppColors.textSecondary,
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
              onTap: _ready ? _toggleListen : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening ? AppColors.danger : AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: (_listening ? AppColors.danger : AppColors.primary)
                          .withValues(alpha: 0.35),
                      blurRadius: _listening ? 20 : 8,
                      spreadRadius: _listening ? 4 : 0,
                    ),
                  ],
                ),
                child: Icon(
                  _listening ? Icons.stop : Icons.mic,
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
                    onPressed: _saveAsIdea,
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('存灵感'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saveAsItem,
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
