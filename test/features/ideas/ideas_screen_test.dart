import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/constants/app_constants.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/features/ideas/ideas_screen.dart';

const _failureMessage = '数据加载失败，请重试';
const _emptyMessage = '记录你的灵光一闪';

void main() {
  testWidgets('IdeasScreen ignores an initial load completed after disposal', (
    tester,
  ) async {
    final result = Completer<List<IdeaModel>>();
    final repository = _ScriptedIdeaRepository([result.future]);

    await tester.pumpWidget(
      MaterialApp(home: IdeasScreen(ideaRepository: repository)),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    result.complete([_idea('disposed-result')]);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeasScreen keeps the newest result after rapid tag changes', (
    tester,
  ) async {
    final firstTag = AppConstants.ideaTags[0];
    final secondTag = AppConstants.ideaTags[1];
    final firstResult = Completer<List<IdeaModel>>();
    final secondResult = Completer<List<IdeaModel>>();
    final repository = _ScriptedIdeaRepository([
      <IdeaModel>[],
      firstResult.future,
      secondResult.future,
    ]);

    await tester.pumpWidget(
      MaterialApp(home: IdeasScreen(ideaRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, firstTag));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, firstTag))
          .selected,
      isTrue,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, secondTag));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, secondTag))
          .selected,
      isTrue,
    );

    secondResult.complete([_idea('newest-tag-result', tag: secondTag)]);
    await tester.pump();
    expect(find.text('newest-tag-result'), findsOneWidget);

    firstResult.complete([_idea('stale-tag-result', tag: firstTag)]);
    await tester.pump();

    expect(find.text('newest-tag-result'), findsOneWidget);
    expect(find.text('stale-tag-result'), findsNothing);
    expect(repository.requestedTags, [null, firstTag, secondTag]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeasScreen sanitizes an initial failure and retries', (
    tester,
  ) async {
    const privateMarker = 'private SQLCipher ideas path';
    final repository = _ScriptedIdeaRepository([
      _Failure(StateError(privateMarker)),
      [_idea('recovered-idea')],
    ]);

    await tester.pumpWidget(
      MaterialApp(home: IdeasScreen(ideaRepository: repository)),
    );
    await tester.pumpAndSettle();
    final loadException = tester.takeException();

    expect(find.text(_failureMessage), findsOneWidget);
    expect(find.text(_emptyMessage), findsNothing);
    expect(find.textContaining(privateMarker), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    expect(loadException, isNull);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('recovered-idea'), findsOneWidget);
    expect(find.text(_failureMessage), findsNothing);
    expect(repository.getAllCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IdeasScreen retains its snapshot when refresh fails', (
    tester,
  ) async {
    const privateMarker = 'private refreshed ideas exception';
    final snapshot = List<IdeaModel>.generate(
      12,
      (index) => _idea('snapshot-idea-$index'),
    );
    final repository = _ScriptedIdeaRepository([
      snapshot,
      _Failure(StateError(privateMarker)),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: IdeasScreen(ideaRepository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('snapshot-idea-0'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, 320));
    await tester.pumpAndSettle();
    final refreshException = tester.takeException();

    expect(repository.getAllCalls, 2);
    expect(find.text('snapshot-idea-0'), findsOneWidget);
    expect(find.text(_failureMessage), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining(privateMarker), findsNothing);
    expect(refreshException, isNull);
  });

  testWidgets('empty idea title preserves the draft and can be corrected', (
    tester,
  ) async {
    final selectedTag = AppConstants.ideaTags[1];
    final repository = _ScriptedIdeaRepository([
      <IdeaModel>[],
      [_idea('Trimmed title', tag: selectedTag)],
    ]);

    await tester.pumpWidget(
      MaterialApp(home: IdeasScreen(ideaRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '   ');
    await tester.enterText(find.byType(TextField).at(1), 'draft body');
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .onChanged!(selectedTag);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('记录灵感'), findsOneWidget);
    expect(find.text('请输入标题'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      'draft body',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      selectedTag,
    );
    expect(repository.createCalls, 0);

    await tester.enterText(find.byType(TextField).at(0), '  Trimmed title  ');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('记录灵感'), findsNothing);
    expect(find.text('Trimmed title'), findsOneWidget);
    expect(repository.createCalls, 1);
    expect(repository.getAllCalls, 2);
    expect(repository.created, [
      (title: 'Trimmed title', content: 'draft body', tag: selectedTag),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling an idea draft does not persist or refresh', (
    tester,
  ) async {
    final repository = _ScriptedIdeaRepository([<IdeaModel>[]]);

    await tester.pumpWidget(
      MaterialApp(home: IdeasScreen(ideaRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'cancelled title');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.text('记录灵感'), findsNothing);
    expect(repository.createCalls, 0);
    expect(repository.getAllCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('idea save failure preserves the draft and supports retry', (
    tester,
  ) async {
    const privateMarker = 'private idea persistence marker';
    final selectedTag = AppConstants.ideaTags[1];
    var attempts = 0;
    final repository =
        _ScriptedIdeaRepository([
            <IdeaModel>[],
            [_idea('Retry title', tag: selectedTag)],
          ])
          ..onCreate = (title, content, tag) async {
            attempts++;
            if (attempts == 1) throw StateError(privateMarker);
            return _idea(title, tag: tag);
          };

    await tester.pumpWidget(
      MaterialApp(home: IdeasScreen(ideaRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '  Retry title  ');
    await tester.enterText(find.byType(TextField).at(1), 'draft body');
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .onChanged!(selectedTag);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('记录灵感'), findsOneWidget);
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.textContaining(privateMarker), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      '  Retry title  ',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      'draft body',
    );
    expect(repository.createCalls, 1);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('记录灵感'), findsNothing);
    expect(find.text('Retry title'), findsOneWidget);
    expect(repository.createCalls, 2);
    expect(repository.getAllCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid idea save callbacks persist once', (tester) async {
    final save = Completer<IdeaModel>();
    final repository = _ScriptedIdeaRepository([
      <IdeaModel>[],
      [_idea('Single idea')],
    ])..onCreate = (_, _, _) => save.future;

    await tester.pumpWidget(
      MaterialApp(home: IdeasScreen(ideaRepository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Single idea');
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存'),
    );

    saveButton.onPressed!();
    saveButton.onPressed!();
    await tester.pump();

    expect(repository.createCalls, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
          .onPressed,
      isNull,
    );

    save.complete(_idea('Single idea'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.text('Single idea'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('idea editor cannot write after repository rebind', (
    tester,
  ) async {
    final firstRepository = _ScriptedIdeaRepository([<IdeaModel>[]]);
    final secondRepository = _ScriptedIdeaRepository([<IdeaModel>[]]);
    final repository = ValueNotifier<IdeaRepository>(firstRepository);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<IdeaRepository>(
          valueListenable: repository,
          builder: (_, value, _) => IdeasScreen(
            key: const ValueKey('ideas-screen'),
            ideaRepository: value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'stale draft');

    repository.value = secondRepository;
    await tester.pumpAndSettle();
    expect(find.text('记录灵感'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(firstRepository.createCalls, 0);
    expect(secondRepository.createCalls, 0);
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'stale draft',
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('记录灵感'), findsNothing);
  });

  testWidgets('idea editor remains usable in a narrow large-text viewport', (
    tester,
  ) async {
    final repository = _ScriptedIdeaRepository([<IdeaModel>[]]);

    await tester.pumpWidget(
      _narrowLargeTextHost(IdeasScreen(ideaRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('记录灵感'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _narrowLargeTextHost(Widget child) {
  return MaterialApp(
    home: SizedBox(
      width: 320,
      height: 480,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 480),
          textScaler: TextScaler.linear(2),
        ),
        child: child,
      ),
    ),
  );
}

class _ScriptedIdeaRepository extends IdeaRepository {
  _ScriptedIdeaRepository(List<Object> results)
    : _results = List<Object>.of(results);

  final List<Object> _results;
  final List<String?> requestedTags = [];
  final List<({String title, String content, String tag})> created = [];
  Future<IdeaModel> Function(String title, String content, String tag)?
  onCreate;
  int getAllCalls = 0;
  int createCalls = 0;

  @override
  Future<List<IdeaModel>> getAll({String? tag}) {
    getAllCalls += 1;
    requestedTags.add(tag);
    if (_results.isEmpty) {
      return Future<List<IdeaModel>>.error(
        StateError('unexpected getAll call for tag $tag'),
      );
    }
    final result = _results.removeAt(0);
    if (result is _Failure) {
      return Future<List<IdeaModel>>.error(result.error);
    }
    if (result is Future<List<IdeaModel>>) return result;
    return Future<List<IdeaModel>>.value((result as List).cast<IdeaModel>());
  }

  @override
  Future<IdeaModel> create({
    required String title,
    required String content,
    String tag = '鐢熸椿',
  }) async {
    createCalls += 1;
    created.add((title: title, content: content, tag: tag));
    final handler = onCreate;
    if (handler != null) return handler(title, content, tag);
    return _idea(title, tag: tag);
  }
}

class _Failure {
  const _Failure(this.error);

  final Object error;
}

IdeaModel _idea(String title, {String tag = '生活'}) {
  return IdeaModel(
    id: title,
    title: title,
    content: '$title content',
    tag: tag,
    createdAt: DateTime(2026, 7, 18),
  );
}
