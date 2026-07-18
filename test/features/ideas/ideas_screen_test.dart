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
}

class _ScriptedIdeaRepository extends IdeaRepository {
  _ScriptedIdeaRepository(List<Object> results)
    : _results = List<Object>.of(results);

  final List<Object> _results;
  final List<String?> requestedTags = [];
  int getAllCalls = 0;

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
