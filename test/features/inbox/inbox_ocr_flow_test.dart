import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/utils/ocr_service.dart';
import 'package:personal_butler/features/inbox/inbox_screen.dart';

void main() {
  testWidgets(
    'StatefulShellRoute success removes the root loader without popping the branch',
    (tester) async {
      final repository = _SpyItemRepository();
      final recognition = Completer<String>();
      final harness = await _pumpInbox(
        tester,
        repository: repository,
        assetChooser: () async => 'asset-1',
        recognizer: (_) => recognition.future,
      );
      final rootPushesBeforeOcr = harness.rootObserver.pushCount;

      await tester.tap(find.text('截图导入'));
      await tester.pump();

      expect(find.byKey(const Key('inbox-ocr-loading')), findsOneWidget);
      expect(harness.branchObserver.popCount, 0);

      recognition.complete('项目周会\n7月15日 10:00');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inbox-ocr-loading')), findsNothing);
      expect(harness.branchObserver.popCount, 0);
      expect(harness.rootObserver.pushCount - rootPushesBeforeOcr, 1);
      expect(find.byKey(const Key('ocr-confirm-probe')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('OCR failure removes the loader and shows only a safe message', (
    tester,
  ) async {
    final repository = _SpyItemRepository();
    final recognition = Completer<String>();
    final harness = await _pumpInbox(
      tester,
      repository: repository,
      assetChooser: () async => 'private-asset-id',
      recognizer: (_) => recognition.future,
    );

    await tester.tap(find.text('截图导入'));
    await tester.pump();
    expect(find.byKey(const Key('inbox-ocr-loading')), findsOneWidget);

    recognition.completeError(StateError('private OCR exception token'));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('inbox-ocr-loading')), findsNothing);
    expect(find.text('文字识别失败，请重试'), findsOneWidget);
    expect(find.textContaining('private OCR exception token'), findsNothing);
    expect(find.textContaining('private-asset-id'), findsNothing);
    expect(repository.atomicCalls, 0);
    expect(repository.createDraftCalls, 0);
    expect(repository.addAttachmentCalls, 0);
    expect(harness.router.routeInformationProvider.value.uri.path, '/inbox');
    expect(tester.takeException(), isNull);
  });

  testWidgets('OCR timeout removes the loader and releases retry actions', (
    tester,
  ) async {
    final repository = _SpyItemRepository();
    final recognition = Completer<String>();
    await _pumpInbox(
      tester,
      repository: repository,
      assetChooser: () async => 'asset-timeout',
      recognizer: (_) => recognition.future,
      ocrTimeout: const Duration(seconds: 1),
    );

    await tester.tap(find.text('截图导入'));
    await tester.pump();
    expect(find.byKey(const Key('inbox-ocr-loading')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('inbox-ocr-loading')), findsNothing);
    expect(find.text('文字识别超时，请重试'), findsOneWidget);
    expect(_actionInkWell(tester, '截图导入').onTap, isNotNull);
    expect(_actionInkWell(tester, '拍照识图').onTap, isNotNull);
    expect(repository.atomicCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank OCR text is not persisted or navigated', (tester) async {
    final repository = _SpyItemRepository();
    final harness = await _pumpInbox(
      tester,
      repository: repository,
      assetChooser: () async => 'asset-blank',
      recognizer: (_) async => '  \n\t ',
    );
    final rootPushesBeforeOcr = harness.rootObserver.pushCount;

    await tester.tap(find.text('截图导入'));
    await _pumpFrames(tester);

    expect(find.text('未识别到文字'), findsOneWidget);
    expect(find.byKey(const Key('inbox-ocr-loading')), findsNothing);
    expect(repository.atomicCalls, 0);
    expect(repository.createDraftCalls, 0);
    expect(repository.addAttachmentCalls, 0);
    expect(harness.rootObserver.pushCount, rootPushesBeforeOcr);
    expect(harness.router.routeInformationProvider.value.uri.path, '/inbox');
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-frame repeated taps run chooser OCR and atomic save once', (
    tester,
  ) async {
    final repository = _SpyItemRepository();
    final choice = Completer<String?>();
    final recognition = Completer<String>();
    var chooserCalls = 0;
    var recognizerCalls = 0;
    await _pumpInbox(
      tester,
      repository: repository,
      assetChooser: () {
        chooserCalls++;
        return choice.future;
      },
      recognizer: (_) {
        recognizerCalls++;
        return recognition.future;
      },
    );

    await tester.tap(find.text('截图导入'));
    await tester.tap(find.text('拍照识图'));

    expect(chooserCalls, 1);
    await tester.pump();
    expect(_actionInkWell(tester, '截图导入').onTap, isNull);
    expect(_actionInkWell(tester, '拍照识图').onTap, isNull);

    choice.complete('asset-once');
    await tester.pump();
    expect(recognizerCalls, 1);
    expect(find.byKey(const Key('inbox-ocr-loading')), findsOneWidget);

    recognition.complete('只处理一次');
    await tester.pumpAndSettle();

    expect(chooserCalls, 1);
    expect(recognizerCalls, 1);
    expect(repository.atomicCalls, 1);
    expect(repository.createDraftCalls, 0);
    expect(repository.addAttachmentCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repository failure is safe and cleans up without navigation', (
    tester,
  ) async {
    final repository = _SpyItemRepository(
      atomicError: StateError('private database path'),
    );
    final harness = await _pumpInbox(
      tester,
      repository: repository,
      assetChooser: () async => 'private-repository-asset',
      recognizer: (_) async => '敏感 OCR 正文',
    );
    final rootPushesBeforeOcr = harness.rootObserver.pushCount;

    await tester.tap(find.text('截图导入'));
    await _pumpFrames(tester);

    expect(find.text('保存识别结果失败，请重试'), findsOneWidget);
    expect(find.textContaining('private database path'), findsNothing);
    expect(find.textContaining('private-repository-asset'), findsNothing);
    expect(find.textContaining('敏感 OCR 正文'), findsNothing);
    expect(find.byKey(const Key('inbox-ocr-loading')), findsNothing);
    expect(repository.atomicCalls, 1);
    expect(harness.rootObserver.pushCount, rootPushesBeforeOcr);
    expect(harness.router.routeInformationProvider.value.uri.path, '/inbox');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'OCR completion after disposal leaves no overlay or Flutter error',
    (tester) async {
      final repository = _SpyItemRepository();
      final recognition = Completer<String>();
      final harness = await _pumpInbox(
        tester,
        repository: repository,
        assetChooser: () async => 'asset-after-dispose',
        recognizer: (_) => recognition.future,
      );

      await tester.tap(find.text('截图导入'));
      await tester.pump();
      expect(find.byKey(const Key('inbox-ocr-loading')), findsOneWidget);

      harness.unmountInbox();
      await tester.pump();
      expect(find.byKey(const Key('gone-probe')), findsOneWidget);
      expect(find.byType(InboxScreen), findsNothing);

      recognition.complete('页面已卸载后的结果');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inbox-ocr-loading')), findsNothing);
      expect(repository.atomicCalls, 0);
      expect(harness.router.routeInformationProvider.value.uri.path, '/inbox');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('success uses only the atomic OCR repository API', (
    tester,
  ) async {
    final repository = _SpyItemRepository();
    await _pumpInbox(
      tester,
      repository: repository,
      assetChooser: () async => 'asset-atomic',
      recognizer: (_) async => '原子写入会议',
    );

    await tester.tap(find.text('截图导入'));
    await tester.pumpAndSettle();

    expect(repository.atomicCalls, 1);
    expect(repository.lastAssetId, 'asset-atomic');
    expect(repository.lastOcrText, '原子写入会议');
    expect(repository.lastTitle, '原子写入会议');
    expect(repository.createDraftCalls, 0);
    expect(repository.addAttachmentCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chooser failure is safe and releases single-flight', (
    tester,
  ) async {
    final repository = _SpyItemRepository();
    var chooserCalls = 0;
    await _pumpInbox(
      tester,
      repository: repository,
      assetChooser: () async {
        chooserCalls++;
        throw StateError('private chooser token');
      },
      recognizer: (_) async => 'unused',
    );

    await tester.tap(find.text('截图导入'));
    await _pumpFrames(tester);

    expect(find.text('选择图片失败，请重试'), findsOneWidget);
    expect(find.textContaining('private chooser token'), findsNothing);
    expect(find.byKey(const Key('inbox-ocr-loading')), findsNothing);
    expect(_actionInkWell(tester, '截图导入').onTap, isNotNull);
    expect(_actionInkWell(tester, '拍照识图').onTap, isNotNull);

    await tester.tap(find.text('拍照识图'));
    await _pumpFrames(tester);

    expect(chooserCalls, 2);
    expect(repository.atomicCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled chooser releases single-flight for a later attempt', (
    tester,
  ) async {
    final repository = _SpyItemRepository();
    var chooserCalls = 0;
    await _pumpInbox(
      tester,
      repository: repository,
      assetChooser: () async {
        chooserCalls++;
        return chooserCalls == 1 ? null : 'asset-after-cancel';
      },
      recognizer: (_) async => '取消后重试',
    );

    await tester.tap(find.text('截图导入'));
    await _pumpFrames(tester);

    expect(repository.atomicCalls, 0);
    expect(_actionInkWell(tester, '截图导入').onTap, isNotNull);
    expect(_actionInkWell(tester, '拍照识图').onTap, isNotNull);

    await tester.tap(find.text('拍照识图'));
    await tester.pumpAndSettle();

    expect(chooserCalls, 2);
    expect(repository.atomicCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<_InboxHarness> _pumpInbox(
  WidgetTester tester, {
  required _SpyItemRepository repository,
  required Future<String?> Function() assetChooser,
  required Future<String> Function(String assetId) recognizer,
  Duration ocrTimeout = OcrService.defaultOperationTimeout,
}) async {
  final harness = _InboxHarness(
    screen: InboxScreen(
      itemRepository: repository,
      assetChooser: assetChooser,
      recognizer: recognizer,
      ocrTimeout: ocrTimeout,
    ),
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  expect(find.byType(InboxScreen), findsOneWidget);
  return harness;
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

InkWell _actionInkWell(WidgetTester tester, String label) {
  return tester.widget<InkWell>(
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
  );
}

class _InboxHarness {
  _InboxHarness({required InboxScreen screen}) {
    router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/inbox',
      observers: [rootObserver],
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              Scaffold(body: navigationShell),
          branches: [
            StatefulShellBranch(
              navigatorKey: branchNavigatorKey,
              observers: [branchObserver],
              routes: [
                GoRoute(
                  path: '/inbox',
                  builder: (_, _) => ValueListenableBuilder<bool>(
                    valueListenable: inboxMounted,
                    builder: (_, isMounted, _) => isMounted
                        ? screen
                        : const Scaffold(
                            key: Key('gone-probe'),
                            body: SizedBox(),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/ocr-confirm/:id',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, state) => Scaffold(
            key: const Key('ocr-confirm-probe'),
            body: Text('confirm:${state.pathParameters['id']}'),
          ),
        ),
      ],
    );
  }

  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final branchNavigatorKey = GlobalKey<NavigatorState>();
  final rootObserver = _CountingNavigatorObserver();
  final branchObserver = _CountingNavigatorObserver();
  final inboxMounted = ValueNotifier<bool>(true);
  late final GoRouter router;

  Widget get app => MaterialApp.router(routerConfig: router);

  void unmountInbox() => inboxMounted.value = false;

  void dispose() {
    router.dispose();
    inboxMounted.dispose();
  }
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;
  int popCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

class _SpyItemRepository extends ItemRepository {
  _SpyItemRepository({this.atomicError});

  final Object? atomicError;
  int atomicCalls = 0;
  int createDraftCalls = 0;
  int addAttachmentCalls = 0;
  String? lastAssetId;
  String? lastOcrText;
  String? lastTitle;

  static final _draft = ItemModel(
    id: 'draft-1',
    type: 'meeting',
    title: '测试草稿',
    inboxStatus: 'inbox',
    createdAt: DateTime(2026, 7, 15),
    updatedAt: DateTime(2026, 7, 15),
  );

  @override
  Future<List<ItemModel>> getInboxItems() async => [];

  @override
  Future<Map<String, int>> getTodayStats() async => {};

  @override
  Future<ItemModel> createOcrDraftWithAttachment({
    required String ocrText,
    required String assetId,
    String title = '',
    String? displayName,
    String owner = 'self',
  }) async {
    atomicCalls++;
    lastOcrText = ocrText;
    lastAssetId = assetId;
    lastTitle = title;
    final error = atomicError;
    if (error != null) throw error;
    return _draft;
  }

  @override
  Future<ItemModel> createDraft({
    required String type,
    String title = '',
    String inboxStatus = 'inbox',
    String? ocrText,
    String owner = 'self',
  }) async {
    createDraftCalls++;
    return _draft;
  }

  @override
  Future<void> addAttachment({
    required String itemId,
    required String assetId,
    String? displayName,
  }) async {
    addAttachmentCalls++;
  }
}
