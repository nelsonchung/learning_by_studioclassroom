import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:learning_by_studioclassroom/features/media/player_page.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Offline native WebView geometry check. This reproduces a provider document
// whose 16:9 player is sized from its width, without depending on live streams.
class _LayoutSession implements VideoSession {
  _LayoutSession(this.onLoading)
    : controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);

  final ValueChanged<bool> onLoading;
  final WebViewController controller;
  late final Widget _view = WebViewWidget(controller: controller);

  @override
  Widget get view => _view;

  @override
  Future<void> load() async {
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => onLoading(false)),
    );
    await controller.loadHtmlString('''
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <style>
        html,body { margin:0; background:black; }
        #player { width:100vw; height:calc(100vw * 9 / 16);
          background:linear-gradient(#243b53 90%, #27ae60 90%); }
      </style>
      <div id="player"></div>
    ''');
  }

  @override
  Future<void> stop() => controller.loadRequest(Uri.parse('about:blank'));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LINE TV document fits landscape without clipping its bottom', (
    tester,
  ) async {
    late _LayoutSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          videoUri: Uri.parse('https://www.linetv.tw/player/10131/eps/1'),
          title: 'Layout verification',
          sessionFactory:
              (
                uri, {
                required onLoading,
                required onError,
                required onShowFullscreen,
                required onHideFullscreen,
              }) => session = _LayoutSession(onLoading),
        ),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    var ready = false;
    while (!ready && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      try {
        ready =
            await session.controller.runJavaScriptReturningResult(
              "document.getElementById('player') !== null",
            ) ==
            true;
      } catch (_) {
        // The native document may still be initializing.
      }
    }
    expect(ready, isTrue);
    final original = tester.element(find.byType(WebViewWidget));
    await tester.tap(find.byTooltip('全螢幕播放'));
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.view.physicalSize.width,
      greaterThan(tester.view.physicalSize.height),
    );
    Future<Map<String, dynamic>> geometry() async {
      final raw = await session.controller.runJavaScriptReturningResult('''
        JSON.stringify({
          width:innerWidth, height:innerHeight,
          bottom:document.getElementById('player').getBoundingClientRect().bottom
        })
      ''');
      dynamic decoded = jsonDecode(raw.toString());
      if (decoded is String) decoded = jsonDecode(decoded);
      return Map<String, dynamic>.from(decoded as Map);
    }

    final landscapeDeadline = DateTime.now().add(const Duration(seconds: 15));
    Map<String, dynamic> native = {};
    var settled = false;
    while (!settled && DateTime.now().isBefore(landscapeDeadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      native = await geometry();
      final webViewSize = tester.getSize(find.byType(WebViewWidget));
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      settled =
          (webViewSize.height - screenHeight).abs() < 1 &&
          ((native['width'] as num) - webViewSize.width).abs() < 1 &&
          ((native['height'] as num) - webViewSize.height).abs() < 1;
    }
    expect(
      settled,
      isTrue,
      reason: 'Wait for native WebView to finish resizing: $native',
    );
    debugPrint('NATIVE LANDSCAPE LAYOUT: $native');
    expect(
      native['bottom'] as num,
      lessThanOrEqualTo((native['height'] as num) + 1),
    );
    expect(
      (native['width'] as num) / (native['height'] as num),
      closeTo(16 / 9, 0.01),
    );
    expect(tester.element(find.byType(WebViewWidget)), same(original));
    await tester.pump(const Duration(milliseconds: 500));
    await binding.takeScreenshot('linetv-contained-landscape');
    await tester.tap(find.byTooltip('退出全螢幕'));
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.view.physicalSize.height,
      greaterThan(tester.view.physicalSize.width),
    );
    expect(tester.element(find.byType(WebViewWidget)), same(original));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
