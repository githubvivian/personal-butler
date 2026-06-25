import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../widgets/common_widgets.dart';

class IdeasScreen extends StatefulWidget {
  const IdeasScreen({super.key});

  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
  String? _tag;
  List<IdeaModel> _ideas = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _ideas = await context.read<AppState>().ideas.getAll(tag: _tag);
    setState(() {});
  }

  Future<void> _add() async {
    final title = TextEditingController();
    final content = TextEditingController();
    String tag = AppConstants.ideaTags.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('记录灵感'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: '标题')),
              TextField(controller: content, maxLines: 4, decoration: const InputDecoration(labelText: '内容')),
              DropdownButtonFormField<String>(
                value: tag,
                items: AppConstants.ideaTags.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setLocal(() => tag = v ?? tag),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    await context.read<AppState>().ideas.create(title: title.text.trim(), content: content.text.trim(), tag: tag);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('灵感库'),
        actions: [IconButton(onPressed: _add, icon: const Icon(Icons.add))],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('全部'),
                    selected: _tag == null,
                    onSelected: (_) {
                      _tag = null;
                      _load();
                    },
                  ),
                ),
                ...AppConstants.ideaTags.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t),
                      selected: _tag == t,
                      onSelected: (_) {
                        _tag = t;
                        _load();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _ideas.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 80),
                      Center(child: Text('记录你的灵光一闪')),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _ideas.length,
                      itemBuilder: (_, i) {
                        final idea = _ideas[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(idea.title,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    ),
                                    Chip(
                                      label: Text(idea.tag, style: const TextStyle(fontSize: 11)),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(idea.content, style: const TextStyle(color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
