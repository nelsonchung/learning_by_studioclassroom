import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learning_by_studioclassroom/data/lesson_repository.dart';
import 'package:learning_by_studioclassroom/domain/lesson.dart';
import 'package:learning_by_studioclassroom/features/library/library_page.dart';
import 'package:learning_by_studioclassroom/main.dart';
import 'package:learning_by_studioclassroom/preferences.dart';

class MemoryPreferences extends PreferencesStore {
  Magazine? saved;
  @override
  Future<Magazine?> loadMagazine() async => saved;
  @override
  Future<void> saveMagazine(Magazine magazine) async => saved = magazine;
}

class PendingPreferences extends MemoryPreferences {
  final pending = Completer<Magazine?>();
  @override
  Future<Magazine?> loadMagazine() => pending.future;
}

List<DailyLesson> lessons(Magazine magazine, {bool video = true}) =>
    List.generate(
      4,
      (index) => DailyLesson(
        magazine: magazine,
        date: DateTime.utc(2026, 10, 23 - index),
        title: '${magazine.code} 課程 $index',
        englishTitle: 'Today’s English Lesson $index',
        videoUri: video && index < 3
            ? Uri.parse('https://www.linetv.tw/player/123/eps/${index + 1}')
            : null,
      ),
    );

class FakeRepository extends LessonRepository {
  Future<List<DailyLesson>> Function(Magazine, bool)? handler;
  final calls = <(Magazine, bool)>[];
  @override
  Future<List<DailyLesson>> load(
    Magazine magazine, {
    bool refresh = false,
  }) async {
    calls.add((magazine, refresh));
    return handler?.call(magazine, refresh) ?? lessons(magazine);
  }
}

void main() {
  testWidgets('saved preference cannot overwrite a new user selection', (
    tester,
  ) async {
    final repo = FakeRepository();
    final prefs = PendingPreferences();
    addTearDown(repo.close);
    await tester.pumpWidget(MyApp(repository: repo, preferences: prefs));
    await tester.pump();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    prefs.pending.complete(Magazine.sc);
    await tester.pumpAndSettle();
    expect(find.text('ad 課程 0'), findsOneWidget);
    expect(find.text('sc 課程 0'), findsNothing);
  });
  testWidgets('four dates, magazine selection, and missing fourth video', (
    tester,
  ) async {
    final repo = FakeRepository();
    final prefs = MemoryPreferences();
    addTearDown(repo.close);
    await tester.pumpWidget(MyApp(repository: repo, preferences: prefs));
    await tester.pumpAndSettle();
    expect(find.text('10/23'), findsOneWidget);
    expect(find.text('10/20'), findsOneWidget);
    await tester.ensureVisible(find.text('前三天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前三天'));
    await tester.pumpAndSettle();
    expect(find.text('lt 課程 3'), findsOneWidget);
    await tester.ensureVisible(find.text('觀看每日節目'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '觀看每日節目'))
          .onPressed,
      isNull,
    );
    expect(find.text('目前免費清單未列出'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Advanced'), -250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('ad 課程 3'), findsOneWidget);
    expect(prefs.saved, Magazine.ad);
  });

  testWidgets('old request cannot overwrite newly selected magazine', (
    tester,
  ) async {
    final repo = FakeRepository();
    final delayed = Completer<List<DailyLesson>>();
    repo.handler = (magazine, _) => magazine == Magazine.lt
        ? delayed.future
        : Future.value(lessons(magazine));
    addTearDown(repo.close);
    await tester.pumpWidget(
      MyApp(repository: repo, preferences: MemoryPreferences()),
    );
    await tester.pump();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    delayed.complete(lessons(Magazine.lt));
    await tester.pumpAndSettle();
    expect(find.text('ad 課程 0'), findsOneWidget);
    expect(find.text('lt 課程 0'), findsNothing);
  });

  testWidgets('watch revalidates rolling episode date before pushing player', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.handler = (magazine, refresh) async =>
        lessons(magazine, video: !refresh);
    var opened = false;
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          repository: repo,
          preferences: MemoryPreferences(),
          playerBuilder: (uri, title) {
            opened = true;
            return const Scaffold(body: Text('player'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('觀看每日節目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('觀看每日節目'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.$2, isTrue);
    expect(opened, isFalse);
    expect(find.text('目前免費清單未列出'), findsOneWidget);
  });

  testWidgets('selection survives return from player and uses refreshed URL', (
    tester,
  ) async {
    final repo = FakeRepository();
    final prefs = MemoryPreferences()..saved = Magazine.sc;
    Uri? opened;
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          repository: repo,
          preferences: prefs,
          playerBuilder: (uri, title) {
            opened = uri;
            return Scaffold(appBar: AppBar(title: const Text('測試播放器')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('昨天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('昨天'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('觀看每日節目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('觀看每日節目'));
    await tester.pumpAndSettle();
    expect(opened?.path, '/player/123/eps/2');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('sc 課程 1'), findsOneWidget);
  });

  testWidgets(
    'request failures provide retry, narrow text layout has no overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = FakeRepository();
      repo.handler = (_, _) async => throw StateError('offline');
      addTearDown(repo.close);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MyApp(repository: repo, preferences: MemoryPreferences()),
      );
      await tester.pumpAndSettle();
      expect(find.text('重試'), findsOneWidget);
      repo.handler = (magazine, _) async => lessons(magazine);
      await tester.ensureVisible(find.text('重試'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重試'));
      await tester.pumpAndSettle();
      expect(find.text('lt 課程 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
