import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/utils/ocr_service.dart';
import '../widgets/common_widgets.dart';
import 'gallery_picker_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<ItemModel> _items = [];
  Map<String, int> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final app = context.read<AppState>();
    _items = await app.items.getInboxItems();
    _stats = await app.items.getTodayStats();
    setState(() => _loading = false);
  }

  Future<void> _pickAndOcr() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.isAuth) {
      if (mounted) snack(context, '需要相册权限以选择截图');
      return;
    }
    final assetId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const GalleryPickerScreen()),
    );
    if (assetId == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final text = await OcrService.instance.recognizeAsset(assetId);
    if (!mounted) return;
    Navigator.pop(context);

    final parsed = OcrParser.parse(text);
    final app = context.read<AppState>();
    final draft = await app.items.createDraft(
      type: 'meeting',
      title: parsed['title'] ?? '会议截图',
      ocrText: text,
    );
    await app.items.addAttachment(
      itemId: draft.id,
      assetId: assetId,
    );
    if (!mounted) return;
    context.push('/ocr-confirm/${draft.id}');
    _load();
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
                    const AppCard(
                      child: Text('暂无待处理事项，可通过下方快捷入口添加'),
                    )
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
            Text('$count', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        _action(Icons.document_scanner, '截图导入', _pickAndOcr),
        _action(Icons.mic_none, '语音', () => context.push('/voice')),
        _action(Icons.edit_note, '快录', () => context.push('/create')),
        _action(Icons.photo_camera, '拍照识图', _pickAndOcr),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
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
                Icon(icon, color: AppColors.primary),
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
            Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            if (item.ocrText != null && item.ocrText!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.ocrText!.split('\n').first,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.hourglass_empty, size: 14, color: AppColors.accentOrange),
                const SizedBox(width: 4),
                const Text('待确认', style: TextStyle(fontSize: 12, color: AppColors.accentOrange)),
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
