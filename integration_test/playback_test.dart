import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:learning_by_studioclassroom/data/lesson_repository.dart';
import 'package:learning_by_studioclassroom/domain/lesson.dart';
import 'package:learning_by_studioclassroom/features/media/player_page.dart';
import 'package:learning_by_studioclassroom/main.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Explicit, opt-in live-provider tests: flutter drive --driver
// test_driver/playback_driver.dart --target integration_test/playback_test.dart
// -d <simulator/device>. Ordinary flutter test never calls live providers.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(
    WidgetTester tester,
    Future<bool> Function() ready,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      if (await ready()) return;
    }
    fail('Live player did not become ready within 60 seconds.');
  }

  for (final magazine in Magazine.values) {
    testWidgets('${magazine.code}: live view survives fullscreen without reload', (
      tester,
    ) async {
      final repository = LessonRepository();
      addTearDown(repository.close);
      final lessons = await repository.load(magazine, refresh: true);
      final lesson = lessons.firstWhere((item) => item.videoUri != null);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: PlayerPage(
            videoUri: lesson.videoUri!,
            title: lesson.title ?? magazine.label,
          ),
        ),
      );
      await waitFor(
        tester,
        () async => find.byType(WebViewWidget).evaluate().isNotEmpty,
      );
      final view = tester.widget<WebViewWidget>(find.byType(WebViewWidget));
      final controller = view.platform.params.controller;
      await waitFor(tester, () async {
        try {
          final state = await controller.runJavaScriptReturningResult(
            "document.readyState === 'complete' && location.protocol === 'https:' && document.title.length > 0",
          );
          return state == true || state.toString() == 'true';
        } catch (_) {
          return false;
        }
      });
      final before = await controller.runJavaScriptReturningResult(
        'performance.timeOrigin.toString()',
      );
      Future<Map<String, dynamic>> media() async {
        final raw = await controller.runJavaScriptReturningResult('''
            JSON.stringify((() => {
              const v = document.querySelector('video');
              if (!v) return {found:false};
              const r = v.getBoundingClientRect();
              return {found:true, time:v.currentTime, paused:v.paused,
                duration:Number.isFinite(v.duration) ? v.duration : 0,
                x:r.x+r.width/2, y:r.y+r.height/2, width:innerWidth};
            })())
          ''');
        dynamic value = jsonDecode(raw.toString());
        if (value is String) value = jsonDecode(value);
        return Map<String, dynamic>.from(value as Map);
      }

      num? playingAt;
      if (const bool.fromEnvironment('VERIFY_STREAMS')) {
        // Opt-in decoder/stream check, independent of the default document
        // and rotation tests. Native WebView controls cannot be driven by
        // Flutter gestures reliably; request silent playback in the test.
        await controller.runJavaScript("""
            document.querySelector('.ytp-large-play-button,.vjs-big-play-button')?.click();
            const v = document.querySelector('video');
            if (v) { v.muted = true; v.play().catch(() => {}); }
          """);
        await waitFor(tester, () async {
          final state = await media();
          return state['found'] == true &&
              state['paused'] == false &&
              (state['time'] as num) > 1;
        });
        playingAt = (await media())['time'] as num;
      }
      if (Theme.of(tester.element(find.byType(Scaffold).first)).platform ==
          TargetPlatform.iOS) {
        await tester.pump(const Duration(seconds: 3));
        final diagnostics = await controller.runJavaScriptReturningResult(
          "JSON.stringify({error:document.querySelector('.ytp-error-content-wrap')?.innerText??'',hasVideo:!!document.querySelector('video')})",
        );
        debugPrint('PLAYER ${magazine.code}: $diagnostics');
        await binding.takeScreenshot('${magazine.code}-player-ios');
      }
      final title = await controller.runJavaScriptReturningResult(
        'document.title',
      );
      debugPrint('LIVE ${magazine.code}: $title');
      expect(title.toString(), isNotEmpty);
      await tester.tap(find.byTooltip('全螢幕播放'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byTooltip('退出全螢幕'), findsOneWidget);
      expect(
        tester.view.physicalSize.width,
        greaterThan(tester.view.physicalSize.height),
        reason: 'Fullscreen should rotate the phone into landscape.',
      );
      expect(
        tester.widget<WebViewWidget>(find.byType(WebViewWidget)).platform,
        same(view.platform),
      );
      final after = await controller.runJavaScriptReturningResult(
        'performance.timeOrigin.toString()',
      );
      expect(
        after,
        before,
        reason: 'Fullscreen must not reload the official document.',
      );
      if (playingAt != null) {
        expect(
          (await media())['time'] as num,
          greaterThanOrEqualTo(playingAt),
          reason: 'Fullscreen should preserve video progress.',
        );
      }
      await tester.tap(find.byTooltip('退出全螢幕'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byTooltip('全螢幕播放'), findsOneWidget);
      expect(
        tester.view.physicalSize.height,
        greaterThan(tester.view.physicalSize.width),
        reason: 'Exiting fullscreen should restore portrait.',
      );
      debugPrint(
        jsonEncode({
          'magazine': magazine.code,
          'documentRetained': true,
          'url': lesson.videoUri.toString(),
        }),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('live library screenshot', (tester) async {
    await tester.pumpWidget(const MyApp());
    await waitFor(tester, () async => find.text('今天').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    if (Theme.of(tester.element(find.byType(Scaffold).first)).platform ==
        TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }
    await binding.takeScreenshot(
      'library-${Theme.of(tester.element(find.byType(Scaffold).first)).platform.name}',
    );
  });
}
