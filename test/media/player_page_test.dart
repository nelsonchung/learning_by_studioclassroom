import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:learning_by_studioclassroom/features/media/player_page.dart';

class _FakeSession implements VideoSession {
  int loads = 0;
  int stops = 0;
  @override
  final Widget view = const SizedBox(key: Key('official-view'));
  @override
  Future<void> load() async => loads++;
  @override
  Future<void> stop() async => stops++;
}

void _portraitViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  final video = Uri.parse('https://www.linetv.tw/player/10131/eps/1');

  test(
    'accepts provider video URLs and rejects arbitrary or malformed URLs',
    () {
      expect(isOfficialVideoUri(video), isTrue);
      expect(
        isOfficialVideoUri(
          Uri.parse('https://www.youtube.com/watch?v=x0aobOliJG4'),
        ),
        isTrue,
      );
      for (final url in [
        'http://www.linetv.tw/player/1/eps/1',
        'https://www.linetv.tw.evil.test/player/1/eps/1',
        'https://user@www.linetv.tw/player/1/eps/1',
        'https://www.linetv.tw/player/not-a-number/eps/1',
        'https://www.youtube.com/watch?v=bad',
        'https://example.com/',
      ]) {
        expect(isOfficialVideoUri(Uri.parse(url)), isFalse, reason: url);
      }
    },
  );

  test(
    'HTTP failures only affect the main document, not ads or unknown frames',
    () {
      HttpResponseError response(int status, [Uri? request]) =>
          HttpResponseError(
            request: request == null ? null : WebResourceRequest(uri: request),
            response: WebResourceResponse(uri: null, statusCode: status),
          );
      expect(isMainDocumentHttpFailure(response(403, video), video), isTrue);
      expect(isMainDocumentHttpFailure(response(503, video), video), isTrue);
      expect(isMainDocumentHttpFailure(response(200, video), video), isFalse);
      expect(isMainDocumentHttpFailure(response(302, video), video), isFalse);
      expect(
        isMainDocumentHttpFailure(
          response(503, Uri.parse('https://ads.example.com/ad.js')),
          video,
        ),
        isFalse,
      );
      expect(isMainDocumentHttpFailure(response(403), video), isFalse);
      expect(
        isMainDocumentHttpFailure(const HttpResponseError(), video),
        isFalse,
      );
      expect(
        isMainDocumentHttpFailure(
          response(404, video.replace(fragment: 'controls')),
          video,
        ),
        isTrue,
      );
    },
  );

  test('YouTube embed request uses the installed app identity as Referer', () {
    final source = Uri.parse('https://www.youtube.com/watch?v=x0aobOliJG4');
    final request = officialVideoRequest(source, 'com.Example.My_App');
    expect(
      request.uri,
      Uri.parse(
        'https://www.youtube.com/embed/x0aobOliJG4?playsinline=1&rel=0',
      ),
    );
    expect(request.headers, {'Referer': 'https://com.example.my_app'});
    expect(source.path, '/watch');
    final line = officialVideoRequest(video, 'unused');
    expect(line.uri, video);
    expect(line.headers, isEmpty);
    expect(() => officialVideoRequest(source, ''), throwsArgumentError);
    expect(
      () => officialVideoRequest(source, 'example.com/path'),
      throwsArgumentError,
    );
    expect(
      () => officialVideoRequest(
        Uri.parse('https://example.com/watch?v=x0aobOliJG4'),
        'com.example.app',
      ),
      throwsArgumentError,
    );
  });

  testWidgets(
    'fullscreen preserves media, back restores chrome, and cross-route rotation stays ordered',
    (tester) async {
      _portraitViewport(tester);
      await (() async {
        final chrome = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            chrome.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final session = _FakeSession();
        var creations = 0;
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('home')),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerPage(
              videoUri: video,
              title: '測試課程',
              sessionFactory:
                  (
                    uri, {
                    required onLoading,
                    required onError,
                    required onShowFullscreen,
                    required onHideFullscreen,
                  }) {
                    creations++;
                    onLoading(false);
                    return session;
                  },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final original = tester.element(find.byKey(const Key('official-view')));
        final viewport = tester.getRect(
          find.byKey(const Key('video-viewport')),
        );
        final fullscreenControl = tester.getRect(find.byTooltip('全螢幕播放'));
        expect(viewport.height, greaterThanOrEqualTo(200));
        expect(fullscreenControl.top, greaterThanOrEqualTo(viewport.bottom));
        await tester.tap(find.byTooltip('全螢幕播放'));
        await tester.pumpAndSettle();
        expect(
          tester.element(find.byKey(const Key('official-view'))),
          same(original),
        );
        expect(session.loads, 1);
        expect(creations, 1);
        expect(
          chrome
              .where(
                (call) =>
                    call.method == 'SystemChrome.setPreferredOrientations',
              )
              .last
              .arguments,
          [
            'DeviceOrientation.landscapeLeft',
            'DeviceOrientation.landscapeRight',
          ],
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byTooltip('全螢幕播放'), findsOneWidget);
        expect(session.stops, 0);
        await tester.tap(find.byTooltip('全螢幕播放'));
        await tester.pumpAndSettle();
        // Simulate a route being unmounted while still fullscreen.
        navigator.currentState!.removeRoute(
          ModalRoute.of(tester.element(find.byType(PlayerPage)))!,
        );
        await tester.pumpAndSettle();
        expect(session.stops, 1);
        expect(
          chrome
              .where(
                (call) =>
                    call.method == 'SystemChrome.setPreferredOrientations',
              )
              .last
              .arguments,
          ['DeviceOrientation.portraitUp'],
        );
        expect(
          chrome
              .where(
                (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
              )
              .last
              .arguments,
          'SystemUiMode.edgeToEdge',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      })();
      // Run both scenarios in one fake-async zone: the production chrome queue
      // is shared across routes, while separate widget tests own separate clocks.
      await (() async {
        final gate = Completer<void>();
        final orientations = <Object?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemChrome.setPreferredOrientations') {
              orientations.add(call.arguments);
              if (orientations.length == 1) await gate.future;
            }
            return null;
          },
        );
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });
        final navigator = GlobalKey<NavigatorState>();
        final firstSession = _FakeSession();
        final secondSession = _FakeSession();
        MaterialPageRoute<void> route(String title, _FakeSession session) =>
            MaterialPageRoute<void>(
              builder: (_) => PlayerPage(
                videoUri: video,
                title: title,
                sessionFactory:
                    (
                      uri, {
                      required onLoading,
                      required onError,
                      required onShowFullscreen,
                      required onHideFullscreen,
                    }) {
                      onLoading(false);
                      return session;
                    },
              ),
            );
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('home')),
          ),
        );
        final firstRoute = route('第一個播放器', firstSession);
        navigator.currentState!.push(firstRoute);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('全螢幕播放'));
        await tester.pumpAndSettle();
        expect(orientations, hasLength(1));
        expect(gate.isCompleted, isFalse);

        // A's first rotation is still pending when its cleanup and B's fullscreen
        // rotation are requested. The old route must finish restoring before B.
        navigator.currentState!.removeRoute(firstRoute);
        await tester.pumpAndSettle();
        final secondRoute = route('第二個播放器', secondSession);
        navigator.currentState!.push(secondRoute);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('全螢幕播放'));
        await tester.pumpAndSettle();
        gate.complete();
        await tester.pumpAndSettle();
        expect(orientations, [
          [
            'DeviceOrientation.landscapeLeft',
            'DeviceOrientation.landscapeRight',
          ],
          ['DeviceOrientation.portraitUp'],
          [
            'DeviceOrientation.landscapeLeft',
            'DeviceOrientation.landscapeRight',
          ],
        ]);
        expect(firstSession.stops, 1);
        expect(secondSession.stops, 0);
        expect(find.byTooltip('退出全螢幕'), findsOneWidget);

        navigator.currentState!.removeRoute(secondRoute);
        await tester.pumpAndSettle();
        expect(secondSession.stops, 1);
        expect(orientations.last, ['DeviceOrientation.portraitUp']);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      })();
    },
  );

  testWidgets(
    'native fullscreen callbacks and back notify the official player',
    (tester) async {
      _portraitViewport(tester);
      final session = _FakeSession();
      late void Function(Widget, VoidCallback) show;
      late VoidCallback hide;
      var nativeHides = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            videoUri: video,
            title: '測試課程',
            sessionFactory:
                (
                  uri, {
                  required onLoading,
                  required onError,
                  required onShowFullscreen,
                  required onHideFullscreen,
                }) {
                  show = onShowFullscreen;
                  hide = onHideFullscreen;
                  onLoading(false);
                  return session;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      show(
        const ColoredBox(key: Key('native-video'), color: Colors.black),
        () => nativeHides++,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('native-video')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(nativeHides, 1);
      expect(find.byKey(const Key('native-video')), findsNothing);
      expect(find.byTooltip('全螢幕播放'), findsOneWidget);
      show(const SizedBox(), () {});
      hide();
      await tester.pumpAndSettle();
      expect(find.byTooltip('全螢幕播放'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('load errors offer retry on the same session', (tester) async {
    _portraitViewport(tester);
    final session = _FakeSession();
    late VoidCallback error;
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          videoUri: video,
          title: '測試課程',
          sessionFactory:
              (
                uri, {
                required onLoading,
                required onError,
                required onShowFullscreen,
                required onHideFullscreen,
              }) {
                error = onError;
                onLoading(false);
                return session;
              },
        ),
      ),
    );
    await tester.pump();
    error();
    await tester.pump();
    expect(find.text('重試'), findsOneWidget);
    await tester.tap(find.text('重試'));
    await tester.pump();
    expect(session.loads, 2);
    expect(find.text('重試'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
