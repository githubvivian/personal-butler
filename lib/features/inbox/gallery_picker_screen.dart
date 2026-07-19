import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/photo_permission_helper.dart';

class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({
    super.key,
    this.loadTimeout = const Duration(seconds: 10),
  });

  final Duration loadTimeout;

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen> {
  List<AssetEntity> _assets = [];
  bool _loading = true;
  PermissionState? _permissionState;
  bool _empty = false;
  bool _permissionLost = false;
  bool _hasError = false;
  final Set<_PendingGalleryLoad> _pendingLoads = <_PendingGalleryLoad>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final pending in _pendingLoads.toList(growable: false)) {
      pending.cancel();
    }
    _pendingLoads.clear();
    super.dispose();
  }

  Future<T> _withLoadTimeout<T>(Future<T> operation) {
    late final _GalleryLoadDeadline<T> deadline;
    deadline = _GalleryLoadDeadline<T>(
      operation: operation,
      timeout: widget.loadTimeout,
      onDone: () => _pendingLoads.remove(deadline),
    );
    _pendingLoads.add(deadline);
    return deadline.future;
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _assets = [];
      _empty = false;
      _permissionLost = false;
      _hasError = false;
      _loading = true;
    });
    try {
      final permissionState = await _withLoadTimeout(
        PhotoManager.getPermissionState(
          requestOption: PhotoPermissionHelper.imagePermissionRequestOption,
        ),
      );
      if (!mounted) return;
      if (!permissionState.hasAccess) {
        setState(() {
          _permissionState = permissionState;
          _permissionLost = true;
          _loading = false;
        });
        return;
      }
      final paths = await _withLoadTimeout(
        PhotoManager.getAssetPathList(
          type: RequestType.image,
          onlyAll: true,
          filterOption: FilterOptionGroup(
            imageOption: const FilterOption(
              sizeConstraint: SizeConstraint(ignoreSize: true),
            ),
            orders: [
              const OrderOption(type: OrderOptionType.createDate, asc: false),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (paths.isEmpty) {
        setState(() {
          _permissionState = permissionState;
          _empty = true;
          _loading = false;
        });
        return;
      }
      final recent = paths.first;
      final assets = await _withLoadTimeout(
        recent.getAssetListPaged(page: 0, size: 120),
      );
      if (!mounted) return;
      setState(() {
        _permissionState = permissionState;
        _assets = assets;
        _empty = assets.isEmpty;
        _loading = false;
      });
    } catch (_) {
      _showLoadError();
    }
  }

  Future<void> _selectLimitedPhotos() async {
    if (_loading) return;
    setState(() {
      _assets = [];
      _empty = false;
      _permissionLost = false;
      _hasError = false;
      _loading = true;
    });
    try {
      await PhotoManager.presentLimited(type: RequestType.image);
      if (!mounted) return;
      await _load();
    } catch (_) {
      _showLoadError();
    }
  }

  void _showLoadError() {
    if (!mounted) return;
    setState(() {
      _assets = [];
      _empty = false;
      _permissionLost = false;
      _hasError = true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选择相册图片'),
            Text(
              '仅保存相册引用，不复制原图',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('相册加载失败'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : _permissionLost
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('相册权限已关闭'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.maybePop(context),
                        child: const Text('返回'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                ],
              ),
            )
          : _empty && _permissionState == PermissionState.limited
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('当前没有可供应用访问的照片'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _selectLimitedPhotos,
                    child: const Text('选择照片'),
                  ),
                ],
              ),
            )
          : _empty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('相册中暂无图片'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('重新加载')),
                ],
              ),
            )
          : _buildGallery(),
    );
  }

  Widget _buildGallery() {
    final grid = GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _assets.length,
      itemBuilder: (_, i) {
        final asset = _assets[i];
        return GestureDetector(
          onTap: () => Navigator.pop(context, asset.id),
          child: FutureBuilder<Widget?>(
            future: _thumb(asset),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Container(
                  color: AppColors.border,
                  alignment: Alignment.center,
                  child: const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              if (snap.hasError || !snap.hasData || snap.data == null) {
                return Container(
                  color: AppColors.border,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textSecondary,
                  ),
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: snap.data,
              );
            },
          ),
        );
      },
    );
    if (_permissionState != PermissionState.limited) return grid;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('gallery_select_more_limited'),
              onPressed: _selectLimitedPhotos,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('选择更多照片'),
            ),
          ),
        ),
        Expanded(child: grid),
      ],
    );
  }

  Future<Widget?> _thumb(AssetEntity asset) async {
    final data = await asset
        .thumbnailDataWithSize(const ThumbnailSize(200, 200))
        .timeout(const Duration(seconds: 10));
    if (data == null) return null;
    return Image.memory(
      data,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: AppColors.border,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

abstract interface class _PendingGalleryLoad {
  void cancel();
}

class _GalleryLoadDeadline<T> implements _PendingGalleryLoad {
  _GalleryLoadDeadline({
    required Future<T> operation,
    required Duration timeout,
    required this._onDone,
  }) {
    _timer = Timer(
      timeout,
      () => _completeError(
        TimeoutException('Gallery metadata load timed out.', timeout),
        StackTrace.current,
      ),
    );
    operation.then<void>(_complete, onError: _completeError);
  }

  final Completer<T> _completer = Completer<T>();
  late final Timer _timer;
  VoidCallback? _onDone;
  bool _settled = false;

  Future<T> get future => _completer.future;

  void _complete(T value) {
    if (!_settle()) return;
    _completer.complete(value);
  }

  void _completeError(Object error, StackTrace stackTrace) {
    if (!_settle()) return;
    _completer.completeError(error, stackTrace);
  }

  bool _settle() {
    if (_settled) return false;
    _settled = true;
    _timer.cancel();
    final onDone = _onDone;
    _onDone = null;
    onDone?.call();
    return true;
  }

  @override
  void cancel() {
    _completeError(const _GalleryLoadCancelled(), StackTrace.current);
  }
}

class _GalleryLoadCancelled implements Exception {
  const _GalleryLoadCancelled();
}
