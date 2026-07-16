import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/item_repository.dart';
import '../../core/utils/ocr_service.dart';
import '../../core/utils/photo_permission_helper.dart';
import '../widgets/common_widgets.dart';
import 'gallery_picker_screen.dart';

typedef OcrAssetChooser = Future<String?> Function();
typedef OcrRecognizer = Future<String> Function(String assetId);

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    this.assetChooser,
    this.recognizer,
    this.itemRepository,
  });

  final OcrAssetChooser? assetChooser;
  final OcrRecognizer? recognizer;
  final ItemRepository? itemRepository;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  static const _photoPermissionHelper = PhotoPermissionHelper();

  List<ItemModel> _items = [];
  Map<String, int> _stats = {};
  bool _loading = true;
  bool _ocrInFlight = false;
  late ItemRepository _repository;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = _resolveRepository();
    _repository.addListener(_handleItemMutation);
    _load();
  }

  @override
  void didUpdateWidget(covariant InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemRepository != widget.itemRepository) {
      _bindRepository(_resolveRepository());
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _repository.removeListener(_handleItemMutation);
    super.dispose();
  }

  ItemRepository _resolveRepository() {
    return widget.itemRepository ?? context.read<AppState>().items;
  }

  void _bindRepository(ItemRepository repository) {
    if (identical(repository, _repository)) return;
    _repository.removeListener(_handleItemMutation);
    _repository = repository;
    _repository.addListener(_handleItemMutation);
    _load();
  }

  void _handleItemMutation() => _load();

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final repository = _repository;
    if (mounted) setState(() => _loading = true);
    try {
      final items = await repository.getInboxItems();
      final stats = await repository.getTodayStats();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _items = items;
        _stats = stats;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAndOcr() async {
    if (_ocrInFlight) return;

    final repository = _repository;
    setState(() => _ocrInFlight = true);
    OverlayEntry? loadingOverlay;

    try {
      String? assetId;
      try {
        assetId = await (widget.assetChooser ?? _chooseOcrAsset)();
      } catch (_) {
        _showOcrMessage('选择图片失败，请重试');
        return;
      }
      if (!mounted || assetId == null) return;

      final overlay = OverlayEntry(
        builder: (_) => const Stack(
          fit: StackFit.expand,
          children: [
            ModalBarrier(dismissible: false, color: Color(0x66000000)),
            Center(
              child: CircularProgressIndicator(key: Key('inbox-ocr-loading')),
            ),
          ],
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(overlay);
      loadingOverlay = overlay;

      late final String text;
      try {
        final recognizer =
            widget.recognizer ?? OcrService.instance.recognizeAsset;
        text = await recognizer(assetId);
      } catch (_) {
        _showOcrMessage('文字识别失败，请重试');
        return;
      }
      if (!mounted) return;

      if (text.trim().isEmpty) {
        _showOcrMessage('未识别到文字');
        return;
      }

      final parsed = OcrParser.parse(text);
      late final ItemModel draft;
      try {
        draft = await repository.createOcrDraftWithAttachment(
          ocrText: text,
          assetId: assetId,
          title: parsed['title'] ?? '会议截图',
        );
      } catch (_) {
        _showOcrMessage('保存识别结果失败，请重试');
        return;
      }
      if (!mounted) return;

      context.push('/ocr-confirm/${draft.id}');
    } finally {
      loadingOverlay?.remove();
      _ocrInFlight = false;
      if (mounted) setState(() {});
    }
  }

  Future<String?> _chooseOcrAsset() async {
    final perm = await _photoPermissionHelper.requestImagePermission();
    if (!mounted) return null;
    if (!_photoPermissionHelper.hasImageAccess(perm)) {
      await _showPhotoPermissionDialog();
      return null;
    }
    return Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const GalleryPickerScreen()),
    );
  }

  void _showOcrMessage(String message) {
    if (!mounted) return;
    snack(context, message);
  }

  Future<void> _showPhotoPermissionDialog() async {
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要相册权限'),
        content: const Text('选择截图需要访问相册中的图片。您可以前往系统设置开启权限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (!mounted || shouldOpenSettings != true) return;

    try {
      await _photoPermissionHelper.openSettings();
    } catch (_) {
      if (!mounted) return;
      snack(context, '无法打开系统设置，请手动前往应用设置');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收件箱')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummary(),
                  const SizedBox(height: 16),
                  _buildQuickActions(),
                  const SizedBox(height: 20),
                  const SectionHeader(title: '待处理'),
                  if (_items.isEmpty)
                    const AppCard(child: Text('暂无待处理事项，可通过下方快捷入口添加'))
                  else
                    ..._items.map(_buildItemCard),
                ],
              ),
      ),
    );
  }

  Widget _buildSummary() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '今日待处理',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statChip('收件箱', _stats['inbox'] ?? 0, AppColors.primary),
              const SizedBox(width: 8),
              _statChip('悬停', _stats['pending'] ?? 0, AppColors.accentOrange),
              const SizedBox(width: 8),
              _statChip('今日日程', _stats['today'] ?? 0, AppColors.accentGreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        _action(
          Icons.document_scanner,
          '截图导入',
          _ocrInFlight ? null : _pickAndOcr,
        ),
        _action(Icons.mic_none, '语音', () => context.push('/voice')),
        _action(Icons.edit_note, '快录', () => context.push('/create')),
        _action(Icons.photo_camera, '拍照识图', _ocrInFlight ? null : _pickAndOcr),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: onTap == null
                      ? AppColors.textSecondary
                      : AppColors.primary,
                ),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemCard(ItemModel item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        accentColor: AppColors.forItemType(item.type),
        onTap: () => context.push('/item/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            if (item.ocrText != null && item.ocrText!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.ocrText!.split('\n').first,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.hourglass_empty,
                  size: 14,
                  color: AppColors.accentOrange,
                ),
                const SizedBox(width: 4),
                const Text(
                  '待确认',
                  style: TextStyle(fontSize: 12, color: AppColors.accentOrange),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.push('/ocr-confirm/${item.id}'),
                  child: const Text('去确认'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
