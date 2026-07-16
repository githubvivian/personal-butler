import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/services/speech_service.dart';
import 'package:personal_butler/features/inbox/voice_input_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'dispose while ensureReady is pending skips permission and state updates',
    (tester) async {
      final ready = Completer<bool>();
      final speech = _FakeSpeechInput(ensureReadyHandler: () => ready.future);
      final harness = await _pumpVoice(tester, speech: speech);

      harness.popVoice();
      await tester.pumpAndSettle();
      ready.complete(true);
      await _pumpFrames(tester);

      expect(speech.permissionCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dispose while permission is pending skips state updates', (
    tester,
  ) async {
    final permission = Completer<bool>();
    final speech = _FakeSpeechInput(
      hasPermissionHandler: () => permission.future,
    );
    final harness = await _pumpVoice(tester, speech: speech);
    expect(speech.permissionCalls, 1);

    harness.popVoice();
    await tester.pumpAndSettle();
    permission.complete(true);
    await _pumpFrames(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('initialization failure is sanitized and manual input remains', (
    tester,
  ) async {
    final speech = _FakeSpeechInput(
      ensureReadyHandler: () async {
        throw StateError('private speech initialization token');
      },
    );
    await _pumpVoice(tester, speech: speech);

    expect(find.text('语音初始化失败，请手动输入文字'), findsOneWidget);
    expect(
      find.textContaining('private speech initialization token'),
      findsNothing,
    );
    expect(_toggle(tester).onTap, isNull);
    expect(_ideaButton(tester).onPressed, isNotNull);
    expect(_itemButton(tester).onPressed, isNotNull);
    expect(find.byType(VoiceInputScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('speech unavailable still allows a manual idea save', (
    tester,
  ) async {
    final speech = _FakeSpeechInput(ensureReadyHandler: () async => false);
    final ideas = _FakeIdeaRepository();
    await _pumpVoice(tester, speech: speech, ideas: ideas);

    await tester.enterText(find.byType(TextField), '  手工灵感  ');
    await tester.tap(find.text('存灵感'));
    await tester.pumpAndSettle();

    expect(ideas.createCalls, 1);
    expect(ideas.lastTitle, '手工灵感');
    expect(ideas.lastContent, '手工灵感');
    expect(find.byKey(const Key('host-probe')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual item save works while speech initialization is pending', (
    tester,
  ) async {
    final ready = Completer<bool>();
    final speech = _FakeSpeechInput(ensureReadyHandler: () => ready.future);
    final items = _FakeItemRepository();
    await _pumpVoice(tester, speech: speech, items: items);

    await tester.enterText(find.byType(TextField), '初始化期间手工事项');
    expect(_itemButton(tester).onPressed, isNotNull);
    await tester.tap(find.text('存事项'));
    await tester.pumpAndSettle();

    expect(items.createDraftCalls, 1);
    expect(items.lastOcrText, '初始化期间手工事项');
    expect(find.byKey(const Key('ocr-confirm-probe')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-frame start taps invoke speech only once', (tester) async {
    final start = Completer<void>();
    final speech = _FakeSpeechInput(startHandler: (_, _) => start.future);
    await _pumpVoice(tester, speech: speech);

    await tester.tap(find.byIcon(Icons.mic));
    await tester.tap(find.byIcon(Icons.mic));

    expect(speech.startCalls, 1);
    await tester.pump();
    expect(_toggle(tester).onTap, isNull);
    expect(_ideaButton(tester).onPressed, isNull);
    expect(_itemButton(tester).onPressed, isNull);

    start.complete();
    await _pumpFrames(tester);

    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('start failure is sanitized and retryable', (tester) async {
    late final _FakeSpeechInput speech;
    speech = _FakeSpeechInput(
      startHandler: (_, _) async {
        if (speech.startCalls == 1) {
          throw StateError('private microphone start token');
        }
      },
    );
    await _pumpVoice(tester, speech: speech);

    await tester.tap(find.byIcon(Icons.mic));
    await _pumpFrames(tester);

    expect(find.text('启动语音识别失败，请重试'), findsOneWidget);
    expect(find.textContaining('private microphone start token'), findsNothing);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(_toggle(tester).onTap, isNotNull);

    await tester.tap(find.byIcon(Icons.mic));
    await _pumpFrames(tester);

    expect(speech.startCalls, 2);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late start completion after dispose performs caught microphone cleanup',
    (tester) async {
      final start = Completer<void>();
      late final _FakeSpeechInput speech;
      speech = _FakeSpeechInput(
        startHandler: (_, _) => start.future,
        stopHandler: (_) async {
          if (speech.stopCalls == 2) {
            throw StateError('private late cleanup token');
          }
        },
      );
      final harness = await _pumpVoice(tester, speech: speech);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      harness.popVoice();
      await tester.pumpAndSettle();
      expect(speech.stopCalls, 1);

      start.complete();
      await _pumpFrames(tester);

      expect(speech.stopCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late cleanup from a disposed screen does not stop its replacement',
    (tester) async {
      final firstStart = Completer<void>();
      Object? activeOwner;
      late final _FakeSpeechInput speech;
      speech = _FakeSpeechInput(
        startHandler: (sessionOwner, _) {
          activeOwner = sessionOwner;
          return speech.startCalls == 1 ? firstStart.future : Future.value();
        },
        stopHandler: (sessionOwner) async {
          if (identical(activeOwner, sessionOwner)) activeOwner = null;
        },
      );
      final harness = await _pumpVoice(tester, speech: speech);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      harness.popVoice();
      await tester.pumpAndSettle();

      unawaited(harness.router.push<void>('/voice'));
      await tester.pumpAndSettle();
      await _startListening(tester);
      expect(speech.startOwners, hasLength(2));
      expect(
        identical(speech.startOwners.first, speech.startOwners.last),
        false,
      );
      expect(identical(activeOwner, speech.startOwners.last), true);

      firstStart.complete();
      await _pumpFrames(tester);

      expect(identical(activeOwner, speech.startOwners.last), true);
      expect(find.byIcon(Icons.stop), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same-frame stop taps invoke speech only once', (tester) async {
    final stop = Completer<void>();
    late final _FakeSpeechInput speech;
    speech = _FakeSpeechInput(
      stopHandler: (_) => speech.stopCalls == 1 ? stop.future : Future.value(),
    );
    await _pumpVoice(tester, speech: speech);
    await _startListening(tester);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.tap(find.byIcon(Icons.stop));

    expect(speech.stopCalls, 1);
    await tester.pump();
    expect(_toggle(tester).onTap, isNull);
    expect(_ideaButton(tester).onPressed, isNull);
    expect(_itemButton(tester).onPressed, isNull);

    stop.complete();
    await _pumpFrames(tester);

    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop failure is sanitized and restores a retryable session', (
    tester,
  ) async {
    late final _FakeSpeechInput speech;
    speech = _FakeSpeechInput(
      stopHandler: (_) async {
        if (speech.stopCalls == 1) {
          throw StateError('private microphone stop token');
        }
      },
    );
    await _pumpVoice(tester, speech: speech);
    await _startListening(tester);

    await tester.tap(find.byIcon(Icons.stop));
    await _pumpFrames(tester);

    expect(find.text('停止语音识别失败，请重试'), findsOneWidget);
    expect(find.textContaining('private microphone stop token'), findsNothing);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(_toggle(tester).onTap, isNotNull);

    await tester.tap(find.byIcon(Icons.stop));
    await _pumpFrames(tester);

    expect(speech.stopCalls, 2);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose consumes a failing asynchronous stop', (tester) async {
    final speech = _FakeSpeechInput(
      stopHandler: (_) async {
        throw StateError('private dispose stop token');
      },
    );
    final harness = await _pumpVoice(tester, speech: speech);

    harness.popVoice();
    await tester.pumpAndSettle();
    await tester.pump();

    expect(speech.stopCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old session callback is ignored after a second start', (
    tester,
  ) async {
    final speech = _FakeSpeechInput();
    await _pumpVoice(tester, speech: speech);

    await _startListening(tester);
    final firstCallback = speech.callbacks.single;
    await tester.tap(find.byIcon(Icons.stop));
    await _pumpFrames(tester);
    await _startListening(tester);
    final secondCallback = speech.callbacks.last;

    secondCallback('第二次会话', false);
    await tester.pump();
    firstCallback('第一次迟到结果', true);
    await tester.pump();

    expect(_textValue(tester), '第二次会话');
    expect(tester.takeException(), isNull);
  });

  testWidgets('final callback remains accepted after a normal stop', (
    tester,
  ) async {
    final speech = _FakeSpeechInput();
    await _pumpVoice(tester, speech: speech);

    await _startListening(tester);
    final callback = speech.callbacks.single;
    await tester.tap(find.byIcon(Icons.stop));
    await _pumpFrames(tester);
    callback('停止后的最终结果', true);
    await tester.pump();

    expect(_textValue(tester), '停止后的最终结果');
    expect(tester.takeException(), isNull);
  });

  testWidgets('item save persists final text emitted after stop completes', (
    tester,
  ) async {
    final stop = Completer<void>();
    final speech = _FakeSpeechInput(stopHandler: (_) => stop.future);
    final items = _FakeItemRepository();
    await _pumpVoice(tester, speech: speech, items: items);
    await _startListening(tester);
    final callback = speech.callbacks.single;
    callback('尚未最终确认', false);
    await tester.pump();

    await tester.tap(find.text('存事项'));
    await tester.pump();
    expect(speech.stopCalls, 1);

    stop.complete();
    await tester.pump();
    expect(items.createDraftCalls, 0);

    callback('停止后到达的最终事项', true);
    await tester.pumpAndSettle();

    expect(items.createDraftCalls, 1);
    expect(items.lastTitle, '停止后到达的最终事项');
    expect(items.lastOcrText, '停止后到达的最终事项');
    expect(find.byKey(const Key('ocr-confirm-probe')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'save immediately after manual stop waits for its final callback',
    (tester) async {
      final speech = _FakeSpeechInput();
      final items = _FakeItemRepository();
      await _pumpVoice(tester, speech: speech, items: items);
      await _startListening(tester);
      final callback = speech.callbacks.single;
      callback('手动停止前的部分结果', false);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.stop));
      await _pumpFrames(tester);
      expect(find.byIcon(Icons.mic), findsOneWidget);

      await tester.tap(find.text('存事项'));
      await tester.pump();
      expect(items.createDraftCalls, 0);

      callback('手动停止后的最终结果', true);
      await tester.pumpAndSettle();

      expect(items.createDraftCalls, 1);
      expect(items.lastTitle, '手动停止后的最终结果');
      expect(items.lastOcrText, '手动停止后的最终结果');
      expect(find.byKey(const Key('ocr-confirm-probe')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save waiting for stop then dispose performs no database write', (
    tester,
  ) async {
    final stop = Completer<void>();
    late final _FakeSpeechInput speech;
    speech = _FakeSpeechInput(
      stopHandler: (_) => speech.stopCalls == 1 ? stop.future : Future.value(),
    );
    final items = _FakeItemRepository();
    final harness = await _pumpVoice(tester, speech: speech, items: items);
    await _startListening(tester);
    await tester.enterText(find.byType(TextField), '不应写入数据库');

    await tester.tap(find.text('存事项'));
    await tester.pump();
    expect(speech.stopCalls, 1);
    expect(items.createDraftCalls, 0);

    harness.popVoice();
    await tester.pumpAndSettle();
    stop.complete();
    await _pumpFrames(tester);

    expect(items.createDraftCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty save is rejected without repository access', (
    tester,
  ) async {
    final items = _FakeItemRepository();
    final ideas = _FakeIdeaRepository();
    await _pumpVoice(tester, items: items, ideas: ideas);

    await tester.enterText(find.byType(TextField), '  \n  ');
    await tester.tap(find.text('存事项'));
    await tester.pump();

    expect(find.text('请先说话或输入文字'), findsOneWidget);
    expect(items.createDraftCalls, 0);
    expect(ideas.createCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-frame save taps persist only one item snapshot', (
    tester,
  ) async {
    final save = Completer<ItemModel>();
    final items = _FakeItemRepository(
      createDraftHandler:
          ({
            required type,
            required title,
            required inboxStatus,
            required ocrText,
            required owner,
          }) => save.future,
    );
    await _pumpVoice(tester, items: items);
    await tester.enterText(find.byType(TextField), '  项目周会\n明天十点  ');

    await tester.tap(find.text('存事项'));
    await tester.tap(find.text('存事项'));

    expect(items.createDraftCalls, 1);
    await tester.pump();
    expect(_ideaButton(tester).onPressed, isNull);
    expect(_itemButton(tester).onPressed, isNull);

    save.complete(_FakeItemRepository.draft);
    await tester.pumpAndSettle();

    expect(items.lastType, 'meeting');
    expect(items.lastTitle, '项目周会');
    expect(items.lastOcrText, '项目周会\n明天十点');
    expect(find.byKey(const Key('ocr-confirm-probe')), findsOneWidget);
    expect(find.text('confirm:draft-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal idea save preserves destination and trimmed entry', (
    tester,
  ) async {
    final ideas = _FakeIdeaRepository();
    await _pumpVoice(tester, ideas: ideas);
    await tester.enterText(find.byType(TextField), '  一个新灵感  ');

    await tester.tap(find.text('存灵感'));
    await tester.pumpAndSettle();

    expect(ideas.createCalls, 1);
    expect(ideas.lastTitle, '一个新灵感');
    expect(ideas.lastContent, '一个新灵感');
    expect(find.byKey(const Key('host-probe')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('item save failure is sanitized and re-enables controls', (
    tester,
  ) async {
    final items = _FakeItemRepository(
      createDraftHandler:
          ({
            required type,
            required title,
            required inboxStatus,
            required ocrText,
            required owner,
          }) async {
            throw StateError('private item database token');
          },
    );
    await _pumpVoice(tester, items: items);
    await tester.enterText(find.byType(TextField), '事项保存失败');

    await tester.tap(find.text('存事项'));
    await _pumpFrames(tester);

    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.textContaining('private item database token'), findsNothing);
    expect(_ideaButton(tester).onPressed, isNotNull);
    expect(_itemButton(tester).onPressed, isNotNull);
    expect(find.byType(VoiceInputScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('idea save failure is sanitized and re-enables controls', (
    tester,
  ) async {
    final ideas = _FakeIdeaRepository(
      createHandler: ({required title, required content, required tag}) async {
        throw StateError('private idea database token');
      },
    );
    await _pumpVoice(tester, ideas: ideas);
    await tester.enterText(find.byType(TextField), '灵感保存失败');

    await tester.tap(find.text('存灵感'));
    await _pumpFrames(tester);

    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.textContaining('private idea database token'), findsNothing);
    expect(_ideaButton(tester).onPressed, isNotNull);
    expect(_itemButton(tester).onPressed, isNotNull);
    expect(find.byType(VoiceInputScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<_VoiceHarness> _pumpVoice(
  WidgetTester tester, {
  _FakeSpeechInput? speech,
  _FakeItemRepository? items,
  _FakeIdeaRepository? ideas,
}) async {
  final harness = _VoiceHarness(
    speech: speech ?? _FakeSpeechInput(),
    appState: _VoiceAppState(
      items ?? _FakeItemRepository(),
      ideas ?? _FakeIdeaRepository(),
    ),
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(harness.app);
  unawaited(harness.router.push<void>('/voice'));
  await tester.pumpAndSettle();
  expect(find.byType(VoiceInputScreen), findsOneWidget);
  return harness;
}

Future<void> _startListening(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.mic));
  await _pumpFrames(tester);
  expect(find.byIcon(Icons.stop), findsOneWidget);
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

GestureDetector _toggle(WidgetTester tester) {
  final icon = find.byIcon(Icons.stop).evaluate().isNotEmpty
      ? find.byIcon(Icons.stop)
      : find.byIcon(Icons.mic);
  return tester.widget<GestureDetector>(
    find.ancestor(of: icon, matching: find.byType(GestureDetector)).first,
  );
}

OutlinedButton _ideaButton(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '存灵感'));

FilledButton _itemButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, '存事项'));

String _textValue(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

class _VoiceHarness {
  _VoiceHarness({required this.speech, required this.appState}) {
    router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(
          path: '/host',
          builder: (_, _) =>
              const Scaffold(key: Key('host-probe'), body: SizedBox()),
        ),
        GoRoute(
          path: '/voice',
          builder: (_, _) => VoiceInputScreen(speechInput: speech),
        ),
        GoRoute(
          path: '/ocr-confirm/:id',
          builder: (_, state) => Scaffold(
            key: const Key('ocr-confirm-probe'),
            body: Text('confirm:${state.pathParameters['id']}'),
          ),
        ),
      ],
    );
  }

  final _FakeSpeechInput speech;
  final _VoiceAppState appState;
  late final GoRouter router;

  Widget get app => ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp.router(routerConfig: router),
  );

  void popVoice() => router.pop();

  void dispose() {
    router.dispose();
    appState.dispose();
  }
}

class _FakeSpeechInput implements SpeechInput {
  _FakeSpeechInput({
    Future<bool> Function()? ensureReadyHandler,
    Future<bool> Function()? hasPermissionHandler,
    Future<void> Function(Object sessionOwner, SpeechTextCallback onText)?
    startHandler,
    Future<void> Function(Object sessionOwner)? stopHandler,
  }) : ensureReadyHandler = ensureReadyHandler ?? _true,
       hasPermissionHandler = hasPermissionHandler ?? _true,
       startHandler = startHandler ?? _completeStart,
       stopHandler = stopHandler ?? _completeStop;

  Future<bool> Function() ensureReadyHandler;
  Future<bool> Function() hasPermissionHandler;
  Future<void> Function(Object sessionOwner, SpeechTextCallback onText)
  startHandler;
  Future<void> Function(Object sessionOwner) stopHandler;

  int ensureReadyCalls = 0;
  int permissionCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  final callbacks = <SpeechTextCallback>[];
  final startOwners = <Object>[];
  final stopOwners = <Object>[];

  @override
  Future<bool> ensureReady() {
    ensureReadyCalls++;
    return ensureReadyHandler();
  }

  @override
  Future<bool> hasPermission() {
    permissionCalls++;
    return hasPermissionHandler();
  }

  @override
  Future<void> startListening({
    required Object sessionOwner,
    required SpeechTextCallback onText,
  }) {
    startCalls++;
    startOwners.add(sessionOwner);
    callbacks.add(onText);
    return startHandler(sessionOwner, onText);
  }

  @override
  Future<void> stopListening({required Object sessionOwner}) {
    stopCalls++;
    stopOwners.add(sessionOwner);
    return stopHandler(sessionOwner);
  }

  static Future<bool> _true() async => true;
  static Future<void> _completeStart(Object _, SpeechTextCallback _) async {}
  static Future<void> _completeStop(Object _) async {}
}

class _VoiceAppState extends AppState {
  _VoiceAppState(this._items, this._ideas)
    : super(
        initializeNotifications: () async {},
        readInitialized: () async => false,
        validateSession: () async => false,
        syncReminders: () async {},
      );

  final ItemRepository _items;
  final IdeaRepository _ideas;

  @override
  ItemRepository get items => _items;

  @override
  IdeaRepository get ideas => _ideas;
}

typedef _CreateDraftHandler =
    Future<ItemModel> Function({
      required String type,
      required String title,
      required String inboxStatus,
      required String? ocrText,
      required String owner,
    });

class _FakeItemRepository extends ItemRepository {
  _FakeItemRepository({_CreateDraftHandler? createDraftHandler})
    : createDraftHandler = createDraftHandler ?? _createDraft;

  static final draft = ItemModel(
    id: 'draft-1',
    type: 'meeting',
    title: '测试事项',
    inboxStatus: 'inbox',
    createdAt: DateTime(2026, 7, 16),
    updatedAt: DateTime(2026, 7, 16),
  );

  final _CreateDraftHandler createDraftHandler;
  int createDraftCalls = 0;
  String? lastType;
  String? lastTitle;
  String? lastInboxStatus;
  String? lastOcrText;
  String? lastOwner;

  @override
  Future<ItemModel> createDraft({
    required String type,
    String title = '',
    String inboxStatus = 'inbox',
    String? ocrText,
    String owner = 'self',
  }) {
    createDraftCalls++;
    lastType = type;
    lastTitle = title;
    lastInboxStatus = inboxStatus;
    lastOcrText = ocrText;
    lastOwner = owner;
    return createDraftHandler(
      type: type,
      title: title,
      inboxStatus: inboxStatus,
      ocrText: ocrText,
      owner: owner,
    );
  }

  static Future<ItemModel> _createDraft({
    required String type,
    required String title,
    required String inboxStatus,
    required String? ocrText,
    required String owner,
  }) async => draft;
}

typedef _CreateIdeaHandler =
    Future<IdeaModel> Function({
      required String title,
      required String content,
      required String tag,
    });

class _FakeIdeaRepository extends IdeaRepository {
  _FakeIdeaRepository({_CreateIdeaHandler? createHandler})
    : createHandler = createHandler ?? _create;

  final _CreateIdeaHandler createHandler;
  int createCalls = 0;
  String? lastTitle;
  String? lastContent;
  String? lastTag;

  @override
  Future<IdeaModel> create({
    required String title,
    required String content,
    String tag = '生活',
  }) {
    createCalls++;
    lastTitle = title;
    lastContent = content;
    lastTag = tag;
    return createHandler(title: title, content: content, tag: tag);
  }

  static Future<IdeaModel> _create({
    required String title,
    required String content,
    required String tag,
  }) async => IdeaModel(
    id: 'idea-1',
    title: title,
    content: content,
    tag: tag,
    createdAt: DateTime(2026, 7, 16),
  );
}
