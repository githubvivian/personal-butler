import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/photo_permission_helper.dart';

class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _load();
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
      final permissionState = await PhotoManager.getPermissionState(
        requestOption: PhotoPermissionHelper.imagePermissionRequestOption,
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
      final paths = await PhotoManager.getAssetPathList(
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
      final assets = await recent.getAssetListPaged(page: 0, size: 120);
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
          : GridView.builder(
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
                      if (!snap.hasData) {
                        return Container(color: AppColors.border);
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: snap.data,
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  Future<Widget?> _thumb(AssetEntity asset) async {
    final data = await asset.thumbnailDataWithSize(
      const ThumbnailSize(200, 200),
    );
    if (data == null) return null;
    return Image.memory(
      data,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
