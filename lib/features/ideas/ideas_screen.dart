import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/other_repositories.dart';
import '../widgets/common_widgets.dart';

class IdeasScreen extends StatefulWidget {
  final IdeaRepository? ideaRepository;

  const IdeasScreen({super.key, this.ideaRepository});

  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

enum _IdeasLoadStatus { loading, ready, failed }

class _IdeasScreenState extends State<IdeasScreen> {
  String? _tag;
  List<IdeaModel> _ideas = [];
  _IdeasLoadStatus _loadStatus = _IdeasLoadStatus.loading;
  bool _hasSnapshot = false;
  int _loadGeneration = 0;

  IdeaRepository get _repository =>
      widget.ideaRepository ?? context.read<AppState>().ideas;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant IdeasScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ideaRepository, widget.ideaRepository)) {
      _ideas = [];
      _hasSnapshot = false;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final tag = _tag;
    final repository = _repository;
    setState(() => _loadStatus = _IdeasLoadStatus.loading);
    try {
      final ideas = await repository.getAll(tag: tag);
      if (!_isCurrentLoad(generation, tag, repository)) return;
      setState(() {
        _ideas = ideas;
        _hasSnapshot = true;
        _loadStatus = _IdeasLoadStatus.ready;
      });
    } catch (_) {
      if (!_isCurrentLoad(generation, tag, repository)) return;
      setState(() => _loadStatus = _IdeasLoadStatus.failed);
    }
  }

  bool _isCurrentLoad(int generation, String? tag, IdeaRepository repository) {
    return mounted &&
        generation == _loadGeneration &&
        tag == _tag &&
        identical(repository, _repository);
  }

  void _selectTag(String? tag) {
    if (_tag != tag) {
      _tag = tag;
      _ideas = [];
      _hasSnapshot = false;
    }
    _load();
  }

  Future<void> _add() async {
    final title = TextEditingController();
    final content = TextEditingController();
    String tag = AppConstants.ideaTags.first;
    String? errorText;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('记录灵感'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              TextField(
                controller: content,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '内容'),
              ),
              DropdownButtonFormField<String>(
                value: tag,
                items: AppConstants.ideaTags
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setLocal(() => tag = v ?? tag),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    errorText!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty) {
                  setLocal(() => errorText = '请输入标题');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !mounted) return;
    final repository = _repository;
    await repository.create(
      title: title.text.trim(),
      content: content.text.trim(),
      tag: tag,
    );
    if (!mounted || !identical(repository, _repository)) return;
    await _load();
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
                    onSelected: (_) => _selectTag(null),
                  ),
                ),
                ...AppConstants.ideaTags.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t),
                      selected: _tag == t,
                      onSelected: (_) => _selectTag(t),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildIdeasContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdeasContent() {
    if (!_hasSnapshot) {
      if (_loadStatus == _IdeasLoadStatus.loading) {
        return _buildCenteredList(const CircularProgressIndicator());
      }
      if (_loadStatus == _IdeasLoadStatus.failed) {
        return _buildCenteredList(_buildFailureNotice());
      }
    }

    if (_ideas.isEmpty) {
      if (_loadStatus == _IdeasLoadStatus.loading) {
        return _buildCenteredList(const CircularProgressIndicator());
      }
      if (_loadStatus == _IdeasLoadStatus.failed) {
        return _buildCenteredList(_buildFailureNotice());
      }
      return _buildCenteredList(const Text('记录你的灵光一闪'));
    }

    final showLoadState = _loadStatus != _IdeasLoadStatus.ready;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _ideas.length + (showLoadState ? 1 : 0),
      itemBuilder: (_, index) {
        if (showLoadState && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _loadStatus == _IdeasLoadStatus.loading
                ? const LinearProgressIndicator()
                : _buildFailureNotice(),
          );
        }
        final idea = _ideas[index - (showLoadState ? 1 : 0)];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        idea.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        idea.tag,
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  idea.content,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCenteredList(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 80),
        Center(child: child),
      ],
    );
  }

  Widget _buildFailureNotice() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('数据加载失败，请重试'),
        TextButton(onPressed: _load, child: const Text('重试')),
      ],
    );
  }
}
