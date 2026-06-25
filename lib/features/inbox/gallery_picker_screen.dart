import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/constants/app_constants.dart';

class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({super.key});

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen> {
  List<AssetEntity> _assets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(sizeConstraint: SizeConstraint(ignoreSize: true)),
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (paths.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final recent = paths.first;
    final assets = await recent.getAssetListPaged(page: 0, size: 120);
    setState(() {
      _assets = assets;
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
            Text('仅保存相册引用，不复制原图', style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
    final data = await asset.thumbnailDataWithSize(const ThumbnailSize(200, 200));
    if (data == null) return null;
    return Image.memory(data, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
  }
}
