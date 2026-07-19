import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/utils/photo_permission_helper.dart';
import 'package:personal_butler/features/inbox/gallery_picker_screen.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  tearDown(() {
    PhotoManager.withPlugin(PhotoManagerPlugin());
  });

  testWidgets('limited empty paths can select photos and reload', (
    tester,
  ) async {
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.limited, PermissionState.limited],
      pathResults: [[], []],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('当前没有可供应用访问的照片'), findsOneWidget);
    expect(find.text('选择照片'), findsOneWidget);
    expect(find.text('相册中暂无图片'), findsNothing);
    expect(
      plugin.permissionOptions.single,
      same(PhotoPermissionHelper.imagePermissionRequestOption),
    );
    expect(plugin.pathTypes.single, RequestType.image);
    expect(plugin.onlyAllValues.single, isTrue);

    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();

    expect(plugin.presentLimitedTypes, [RequestType.image]);
    expect(plugin.permissionOptions, hasLength(2));
    expect(plugin.pathTypes, hasLength(2));
    expect(find.text('当前没有可供应用访问的照片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lost permission does not query paths and offers recovery', (
    tester,
  ) async {
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.denied],
      pathResults: const [],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('相册权限已关闭'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(plugin.pathTypes, isEmpty);
    expect(find.textContaining('denied'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authorized empty paths show an ordinary empty gallery', (
    tester,
  ) async {
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.authorized],
      pathResults: [[]],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('相册中暂无图片'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('选择照片'), findsNothing);
    expect(find.text('当前没有可供应用访问的照片'), findsNothing);
    expect(plugin.presentLimitedTypes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('limited empty first page uses the limited recovery state', (
    tester,
  ) async {
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.limited],
      pathResults: [
        [_allImagesPath],
      ],
      assetResults: [[]],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('当前没有可供应用访问的照片'), findsOneWidget);
    expect(find.text('选择照片'), findsOneWidget);
    expect(find.text('相册中暂无图片'), findsNothing);
    expect(plugin.assetPathIds, ['all-images']);
    expect(plugin.assetTypes, [RequestType.image]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authorized empty first page uses the ordinary empty state', (
    tester,
  ) async {
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.authorized],
      pathResults: [
        [_allImagesPath],
      ],
      assetResults: [[]],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('相册中暂无图片'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('选择照片'), findsNothing);
    expect(plugin.assetPathIds, ['all-images']);
    expect(plugin.assetTypes, [RequestType.image]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('limited non-empty gallery can select more photos and reload', (
    tester,
  ) async {
    final firstAsset = AssetEntity(
      id: 'asset-1',
      typeInt: AssetType.image.index,
      width: 100,
      height: 100,
    );
    final secondAsset = AssetEntity(
      id: 'asset-2',
      typeInt: AssetType.image.index,
      width: 100,
      height: 100,
    );
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.limited, PermissionState.limited],
      pathResults: [
        [_allImagesPath],
        [_allImagesPath],
      ],
      assetResults: [
        [firstAsset],
        [firstAsset, secondAsset],
      ],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(
      find.byKey(const Key('gallery_select_more_limited')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('gallery_select_more_limited')));
    await tester.pumpAndSettle();

    expect(plugin.presentLimitedTypes, [RequestType.image]);
    expect(plugin.permissionOptions, hasLength(2));
    expect(plugin.pathTypes, hasLength(2));
    expect(plugin.assetPathIds, ['all-images', 'all-images']);
    expect(plugin.thumbnailAssetIds, containsAll(['asset-1', 'asset-2']));
    expect(find.byType(GridView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission check failure shows a safe retry state', (
    tester,
  ) async {
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [_Failure(StateError('private permission token'))],
      pathResults: const [],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('相册加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('private permission token'), findsNothing);
    expect(plugin.pathTypes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission check timeout exposes retry and can recover', (
    tester,
  ) async {
    final permissionResult = Completer<PermissionState>();
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [permissionResult.future, PermissionState.authorized],
      pathResults: [[]],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(
      const MaterialApp(
        home: GalleryPickerScreen(loadTimeout: Duration(seconds: 1)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('相册加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(plugin.pathTypes, isEmpty);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('相册中暂无图片'), findsOneWidget);
    expect(plugin.permissionOptions, hasLength(2));
    expect(plugin.pathTypes, hasLength(1));

    permissionResult.complete(PermissionState.denied);
    await tester.pump();

    expect(find.text('相册中暂无图片'), findsOneWidget);
    expect(find.text('相册权限已关闭'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('path failure can retry and clears the old error', (
    tester,
  ) async {
    final secondPathResult = Completer<List<AssetPathEntity>>();
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [
        PermissionState.authorized,
        PermissionState.authorized,
      ],
      pathResults: [
        _Failure(StateError('private path token')),
        secondPathResult.future,
      ],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('相册加载失败'), findsOneWidget);
    expect(find.textContaining('private path token'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('相册加载失败'), findsNothing);

    secondPathResult.complete([]);
    await tester.pumpAndSettle();

    expect(find.text('相册中暂无图片'), findsOneWidget);
    expect(plugin.permissionOptions, hasLength(2));
    expect(plugin.pathTypes, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('path query timeout shows a safe retry state', (tester) async {
    final pathResult = Completer<List<AssetPathEntity>>();
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.authorized],
      pathResults: [pathResult.future],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(
      const MaterialApp(
        home: GalleryPickerScreen(loadTimeout: Duration(seconds: 1)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('相册加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(plugin.pathTypes, [RequestType.image]);
    expect(plugin.assetPathIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page failure shows a safe retry state', (tester) async {
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.authorized],
      pathResults: [
        [_allImagesPath],
      ],
      assetResults: [_Failure(StateError('private page token'))],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('相册加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('private page token'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first page timeout shows a safe retry state', (tester) async {
    final assetResult = Completer<List<AssetEntity>>();
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.authorized],
      pathResults: [
        [_allImagesPath],
      ],
      assetResults: [assetResult.future],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(
      const MaterialApp(
        home: GalleryPickerScreen(loadTimeout: Duration(seconds: 1)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('相册加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(plugin.assetPathIds, ['all-images']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('limited picker failure shows a safe retry state', (
    tester,
  ) async {
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.limited],
      pathResults: [[]],
      presentLimitedResults: [_Failure(StateError('private limited token'))],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();

    expect(plugin.presentLimitedTypes, [RequestType.image]);
    expect(find.text('相册加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('private limited token'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose before permission completion does not update state', (
    tester,
  ) async {
    final permissionResult = Completer<PermissionState>();
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [permissionResult.future],
      pathResults: const [],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    permissionResult.complete(PermissionState.authorized);
    await tester.pump();

    expect(plugin.pathTypes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose cancels a pending gallery load deadline', (
    tester,
  ) async {
    final permissionResult = Completer<PermissionState>();
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [permissionResult.future],
      pathResults: const [],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(plugin.pathTypes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-empty gallery displays and returns the selected asset id', (
    tester,
  ) async {
    final asset = AssetEntity(
      id: 'asset-1',
      typeInt: AssetType.image.index,
      width: 100,
      height: 100,
    );
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.authorized],
      pathResults: [
        [_allImagesPath],
      ],
      assetResults: [
        [asset],
      ],
    );
    PhotoManager.withPlugin(plugin);
    String? selectedAssetId;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selectedAssetId = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const GalleryPickerScreen()),
              );
            },
            child: const Text('打开相册'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开相册'));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(plugin.thumbnailAssetIds, ['asset-1']);

    final gridItem = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(gridItem);
    await tester.pumpAndSettle();

    expect(selectedAssetId, 'asset-1');
    expect(find.text('打开相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail failure shows a visible placeholder', (tester) async {
    final asset = AssetEntity(
      id: 'asset-error',
      typeInt: AssetType.image.index,
      width: 100,
      height: 100,
    );
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.authorized],
      pathResults: [
        [_allImagesPath],
      ],
      assetResults: [
        [asset],
      ],
      thumbnailResults: [_Failure(StateError('private thumbnail token'))],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.textContaining('private thumbnail token'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail timeout shows a visible placeholder', (tester) async {
    final asset = AssetEntity(
      id: 'asset-timeout',
      typeInt: AssetType.image.index,
      width: 100,
      height: 100,
    );
    final neverCompletes = Completer<Uint8List?>();
    final plugin = _GalleryPhotoManagerPlugin(
      permissionStates: [PermissionState.authorized],
      pathResults: [
        [_allImagesPath],
      ],
      assetResults: [
        [asset],
      ],
      thumbnailResults: [neverCompletes.future],
    );
    PhotoManager.withPlugin(plugin);

    await tester.pumpWidget(const MaterialApp(home: GalleryPickerScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);

    await tester.pump(const Duration(seconds: 11));

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final _allImagesPath = AssetPathEntity(
  id: 'all-images',
  name: 'All images',
  type: RequestType.image,
  isAll: true,
);

class _GalleryPhotoManagerPlugin extends PhotoManagerPlugin {
  _GalleryPhotoManagerPlugin({
    required List<Object> permissionStates,
    required List<Object> pathResults,
    List<Object> assetResults = const [],
    List<Object> presentLimitedResults = const [],
    List<Object> thumbnailResults = const [],
  }) : _permissionStates = List.of(permissionStates),
       _pathResults = List.of(pathResults),
       _assetResults = List.of(assetResults),
       _presentLimitedResults = List.of(presentLimitedResults),
       _thumbnailResults = List.of(thumbnailResults);

  final List<Object> _permissionStates;
  final List<Object> _pathResults;
  final List<Object> _assetResults;
  final List<Object> _presentLimitedResults;
  final List<Object> _thumbnailResults;
  final List<PermissionRequestOption> permissionOptions = [];
  final List<RequestType> pathTypes = [];
  final List<bool> onlyAllValues = [];
  final List<RequestType> presentLimitedTypes = [];
  final List<String> assetPathIds = [];
  final List<RequestType> assetTypes = [];
  final List<String> thumbnailAssetIds = [];

  @override
  Future<PermissionState> getPermissionState(
    PermissionRequestOption requestOption,
  ) async {
    permissionOptions.add(requestOption);
    return _resolve<PermissionState>(_permissionStates.removeAt(0));
  }

  @override
  Future<List<AssetPathEntity>> getAssetPathList({
    bool hasAll = true,
    bool onlyAll = false,
    RequestType type = RequestType.common,
    PMFilter? filterOption,
    required PMPathFilter pathFilterOption,
  }) async {
    pathTypes.add(type);
    onlyAllValues.add(onlyAll);
    return _pathResults.isEmpty
        ? const []
        : _resolvePaths(_pathResults.removeAt(0));
  }

  @override
  Future<List<AssetEntity>> getAssetListPaged(
    String id, {
    required PMFilter? optionGroup,
    int page = 0,
    int size = 15,
    RequestType type = RequestType.common,
  }) async {
    assetPathIds.add(id);
    assetTypes.add(type);
    return _assetResults.isEmpty
        ? const []
        : _resolveAssets(_assetResults.removeAt(0));
  }

  @override
  Future<void> presentLimited(RequestType type) async {
    presentLimitedTypes.add(type);
    if (_presentLimitedResults.isNotEmpty) {
      await _resolve<void>(_presentLimitedResults.removeAt(0));
    }
  }

  @override
  Future<Uint8List?> getThumbnail({
    required String id,
    required ThumbnailOption option,
    PMProgressHandler? progressHandler,
    PMCancelToken? cancelToken,
  }) async {
    thumbnailAssetIds.add(id);
    if (_thumbnailResults.isNotEmpty) {
      return _resolve<Uint8List?>(_thumbnailResults.removeAt(0));
    }
    return null;
  }
}

class _Failure {
  const _Failure(this.error);

  final Object error;
}

Future<T> _resolve<T>(Object value) async {
  if (value is _Failure) throw value.error;
  if (value is Future<T>) return value;
  return value as T;
}

Future<List<AssetPathEntity>> _resolvePaths(Object value) async {
  if (value is _Failure) throw value.error;
  if (value is Future<List<AssetPathEntity>>) return value;
  return (value as List).cast<AssetPathEntity>();
}

Future<List<AssetEntity>> _resolveAssets(Object value) async {
  if (value is _Failure) throw value.error;
  if (value is Future<List<AssetEntity>>) return value;
  return (value as List).cast<AssetEntity>();
}
