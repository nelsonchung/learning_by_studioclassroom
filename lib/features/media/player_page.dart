import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Only source-verified provider pages can be opened by this player.
bool isOfficialVideoUri(Uri uri) {
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasPort) {
    return false;
  }
  if (uri.host == 'www.linetv.tw') {
    return RegExp(r'^/player/\d+/eps/\d+/?$').hasMatch(uri.path);
  }
  return (uri.host == 'www.youtube.com' || uri.host == 'm.youtube.com') &&
      uri.path == '/watch' &&
      RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(uri.queryParameters['v'] ?? '');
}

/// Uses the installed application identity, never a publisher's website identity.
@visibleForTesting
({Uri uri, Map<String, String> headers}) officialVideoRequest(
  Uri source,
  String applicationId,
) {
  if (!isOfficialVideoUri(source)) {
    throw ArgumentError.value(source, 'source', 'Unsupported video source');
  }
  if (source.host == 'www.linetv.tw') {
    return (uri: source, headers: const {});
  }
  final identity = applicationId.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9_]+(?:\.[a-z0-9_-]+)+$').hasMatch(identity)) {
    throw ArgumentError.value(
      applicationId,
      'applicationId',
      'Invalid installed app identity',
    );
  }
  return (
    uri: Uri.https('www.youtube.com', '/embed/${source.queryParameters['v']}', {
      'playsinline': '1',
      'rel': '0',
    }),
    headers: {'Referer': 'https://$identity'},
  );
}

bool _isPlayerNavigation(Uri target, Uri source) {
  if (source.host == 'www.linetv.tw') {
    return isOfficialVideoUri(target) &&
        target.host == source.host &&
        target.path == source.path;
  }
  if (isOfficialVideoUri(target)) {
    return (target.host == 'www.youtube.com' ||
            target.host == 'm.youtube.com') &&
        target.queryParameters['v'] == source.queryParameters['v'];
  }
  return target.scheme == 'https' &&
      target.userInfo.isEmpty &&
      !target.hasPort &&
      target.host == 'www.youtube.com' &&
      target.path == '/embed/${source.queryParameters['v']}';
}

/// The plugins do not expose a main-frame flag for HTTP errors. Match the
/// failing request against the document instead; unknown (notably WKWebView)
/// responses must not turn an ad/subframe failure into a playback failure.
@visibleForTesting
bool isMainDocumentHttpFailure(HttpResponseError error, Uri documentUri) {
  final status = error.response?.statusCode;
  final failedUri = error.request?.uri ?? error.response?.uri;
  return status != null &&
      status >= 400 &&
      status <= 599 &&
      failedUri != null &&
      failedUri.replace(fragment: '') == documentUri.replace(fragment: '');
}

/// Small boundary around the native view, allowing lifecycle tests without a
/// platform WebView. A session is created once per route, including fullscreen.
abstract class VideoSession {
  Widget get view;
  Future<void> load();
  Future<void> stop();
}

typedef VideoSessionFactory =
    VideoSession Function(
      Uri uri, {
      required ValueChanged<bool> onLoading,
      required VoidCallback onError,
      required void Function(Widget view, VoidCallback hide) onShowFullscreen,
      required VoidCallback onHideFullscreen,
    });

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.videoUri,
    required this.title,
    @visibleForTesting this.sessionFactory,
  });

  final Uri videoUri;
  final String title;
  final VideoSessionFactory? sessionFactory;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoSession? _session;
  bool _loading = true;
  bool _failed = false;
  bool _externalOpened = false;
  bool _disposing = false;
  bool _fullscreen = false;
  Widget? _nativeFullscreen;
  VoidCallback? _hideNative;
  static Future<void> _chromeChanges = Future<void>.value();

  @override
  void initState() {
    super.initState();
    final supported =
        widget.sessionFactory != null ||
        (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS));
    if (!isOfficialVideoUri(widget.videoUri) || !supported) return;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final factory = widget.sessionFactory ?? _OfficialVideoSession.new;
      _session = factory(
        widget.videoUri,
        onLoading: (value) {
          if (mounted) setState(() => _loading = value);
        },
        onError: () {
          if (mounted) setState(() => _failed = true);
        },
        onShowFullscreen: (view, hide) {
          if (!mounted || _disposing) {
            hide();
            return;
          }
          setState(() {
            _nativeFullscreen = view;
            _hideNative = hide;
          });
          _setFullscreen(true);
        },
        onHideFullscreen: () {
          if (!mounted || _disposing) return;
          setState(() {
            _nativeFullscreen = null;
            _hideNative = null;
          });
          _setFullscreen(false);
        },
      );
      if (mounted) setState(() {});
      await _session!.load();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _setFullscreen(bool value) {
    if (!mounted) return;
    setState(() => _fullscreen = value);
    _queueChrome(value);
  }

  void _queueChrome(bool fullscreen) {
    // Serialize transitions so disposing during rotation cannot leave the next
    // route stuck in landscape or immersive mode.
    _chromeChanges = _chromeChanges
        .catchError((Object _) {})
        .then((_) async {
          await SystemChrome.setPreferredOrientations(
            fullscreen
                ? [
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ]
                : [DeviceOrientation.portraitUp],
          );
          await SystemChrome.setEnabledSystemUIMode(
            fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
          );
        })
        .catchError((Object _) {});
  }

  void _exitFullscreen() {
    final hide = _hideNative;
    setState(() {
      _nativeFullscreen = null;
      _hideNative = null;
    });
    hide?.call();
    _setFullscreen(false);
  }

  Future<void> _openOfficial() async {
    if (!isOfficialVideoUri(widget.videoUri)) return;
    try {
      await _session?.stop();
      if (mounted && _session != null) {
        setState(() {
          _externalOpened = true;
          _failed = true;
        });
      }
      final opened = await launchUrl(
        widget.videoUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Could not launch provider');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法開啟官方影片，請稍後再試。')));
      }
    }
  }

  Future<void> _retry() async {
    setState(() {
      _failed = false;
      _externalOpened = false;
      _loading = true;
    });
    try {
      if (_session == null) {
        await _initialize();
      } else {
        await _session!.load();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _hideNative?.call();
    unawaited(
      _session?.stop().catchError((Object _) {}) ?? Future<void>.value(),
    );
    _queueChrome(false);
    super.dispose();
  }

  static const _paper = Color(0xFFF8F7F3);
  static const _ink = Color(0xFF262522);
  static const _rust = Color(0xFFB65D43);

  String get _provider =>
      widget.videoUri.host.contains('youtube.com') ? 'YouTube' : 'LINE TV';

  Widget _header(bool valid) {
    return SizedBox(
      height: _fullscreen ? 48 : 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              tooltip: _fullscreen ? '退出全螢幕' : '返回',
              onPressed: _fullscreen
                  ? _exitFullscreen
                  : () => Navigator.of(context).maybePop(),
              color: _fullscreen ? Colors.white : _ink,
              icon: Icon(
                _fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.arrow_back_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _fullscreen ? widget.title : '每日節目',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _fullscreen ? Colors.white70 : _ink,
                  fontSize: _fullscreen ? 13 : 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!_fullscreen && valid)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEAE3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _provider,
                  style: const TextStyle(
                    color: Color(0xFF716C63),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _unavailable(bool valid) {
    return ColoredBox(
      color: const Color(0xFF20201E),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_circle_outline_rounded,
                size: 36,
                color: Colors.white38,
              ),
              const SizedBox(height: 14),
              Text(
                !valid
                    ? '影片來源無效。'
                    : _failed
                    ? (_externalOpened ? '已開啟官方影片' : '暫時無法載入影片')
                    : '請開啟官方影片觀看',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _externalOpened ? '返回 App 後，可重新載入影片。' : '稍後重試，或透過下方按鈕前往官方觀看。',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              if (_failed)
                TextButton(
                  onPressed: _retry,
                  child: const Text(
                    '重試',
                    style: TextStyle(color: Color(0xFFE9B09A)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _details(bool valid) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'WATCH & LEARN',
                style: TextStyle(
                  color: _rust,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 25,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '由 $_provider 提供每日節目',
                style: const TextStyle(color: Color(0xFF827C72), fontSize: 12),
              ),
              const SizedBox(height: 24),
              const Divider(height: 1, color: Color(0xFFE3DFD6)),
              const SizedBox(height: 22),
              const Text(
                '留一點時間，聽見英語。',
                style: TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                '點選影片開始觀看；橫向全螢幕，讓字幕更清楚。',
                style: TextStyle(
                  color: Color(0xFF827C72),
                  fontSize: 13,
                  height: 1.8,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_session != null && !_failed)
                    Tooltip(
                      message: '全螢幕播放',
                      child: FilledButton.icon(
                        onPressed: () => _setFullscreen(true),
                        icon: const Icon(Icons.fullscreen_rounded, size: 20),
                        label: const Text('全螢幕播放'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _ink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  if (valid)
                    OutlinedButton.icon(
                      onPressed: _openOfficial,
                      icon: const Icon(Icons.north_east_rounded, size: 16),
                      label: const Text('開啟官方影片'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _ink,
                        side: const BorderSide(color: Color(0xFFD6D0C5)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                '播放進度與字幕設定，請使用影片中的官方控制項。',
                style: TextStyle(
                  color: Color(0xFF999185),
                  fontSize: 11,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final valid = isOfficialVideoUri(widget.videoUri);
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreen) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: _fullscreen ? Colors.black : _paper,
        body: SafeArea(
          left: !_fullscreen,
          top: !_fullscreen,
          right: !_fullscreen,
          bottom: !_fullscreen,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chromeHeight = _fullscreen ? 0.0 : 66.0;
              final available = (constraints.maxHeight - chromeHeight).clamp(
                0.0,
                double.infinity,
              );
              final inlineHeight = (constraints.maxWidth * 9 / 16).clamp(
                200.0,
                double.infinity,
              );
              final videoHeight = _fullscreen
                  ? available
                  : inlineHeight.clamp(0.0, available);
              // LINE TV sizes its inline player from the document width. On
              // wide phones a full-width 16:9 player is taller than the screen.
              // Constrain the document itself; retain the same native view.
              final containDocument =
                  _fullscreen &&
                  _nativeFullscreen == null &&
                  widget.videoUri.host == 'www.linetv.tw';
              final documentWidth = containDocument
                  ? (videoHeight * 16 / 9).clamp(0.0, constraints.maxWidth)
                  : constraints.maxWidth;
              final documentHeight = containDocument
                  ? documentWidth * 9 / 16
                  : videoHeight;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    children: [
                      Visibility(visible: !_fullscreen, child: _header(valid)),
                      // Loading feedback and app controls sit outside provider pixels.
                      Visibility(
                        visible: !_fullscreen,
                        child: SizedBox(
                          height: 2,
                          child: _loading && !_failed && _session != null
                              ? const LinearProgressIndicator(
                                  color: _rust,
                                  backgroundColor: Colors.transparent,
                                )
                              : const SizedBox.expand(),
                        ),
                      ),
                      // Fixed element position and session keep playback intact when
                      // the viewport changes between inline and fullscreen.
                      SizedBox(
                        key: const Key('video-viewport'),
                        height: videoHeight,
                        width: double.infinity,
                        child: ColoredBox(
                          color: Colors.black,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Center(
                                child: SizedBox(
                                  width: documentWidth,
                                  height: documentHeight,
                                  child: Visibility(
                                    visible: _session != null && !_failed,
                                    maintainState: true,
                                    child:
                                        _session?.view ??
                                        const SizedBox.expand(),
                                  ),
                                ),
                              ),
                              if (_session == null || _failed)
                                _unavailable(valid),
                              ?_nativeFullscreen,
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Visibility(
                          visible: !_fullscreen,
                          maintainState: true,
                          child: _details(valid),
                        ),
                      ),
                    ],
                  ),
                  if (_fullscreen)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: SafeArea(
                        minimum: const EdgeInsets.all(8),
                        child: IconButton.filledTonal(
                          tooltip: '退出全螢幕',
                          onPressed: _exitFullscreen,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.fullscreen_exit_rounded),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OfficialVideoSession implements VideoSession {
  _OfficialVideoSession(
    this.uri, {
    required this.onLoading,
    required this.onError,
    required this.onShowFullscreen,
    required this.onHideFullscreen,
  });

  final Uri uri;
  final ValueChanged<bool> onLoading;
  final VoidCallback onError;
  final void Function(Widget, VoidCallback) onShowFullscreen;
  final VoidCallback onHideFullscreen;
  WebViewController? _controller;
  Widget? _view;
  bool _stopped = false;
  Uri? _documentUri;

  @override
  Widget get view => _view ?? const SizedBox.expand();

  @override
  Future<void> load() async {
    _stopped = false;
    if (_controller == null) {
      final PlatformWebViewControllerCreationParams params =
          WebViewPlatform.instance is WebKitWebViewPlatform
          ? WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
              mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
            )
          : const PlatformWebViewControllerCreationParams();
      final controller = WebViewController.fromPlatformCreationParams(params);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.black);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            final target = Uri.tryParse(url);
            if (target != null && _isPlayerNavigation(target, uri)) {
              _documentUri = target;
            }
            onLoading(true);
          },
          onPageFinished: (_) => onLoading(false),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && !_stopped) onError();
          },
          onHttpError: (error) {
            if (!_stopped &&
                isMainDocumentHttpFailure(error, _documentUri ?? uri)) {
              onError();
            }
          },
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final target = Uri.tryParse(request.url);
            if (request.url == 'about:blank' ||
                (target != null && _isPlayerNavigation(target, uri))) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );
      if (controller.platform case final AndroidWebViewController android) {
        await android.setMediaPlaybackRequiresUserGesture(false);
        await android.setCustomWidgetCallbacks(
          onShowCustomWidget: onShowFullscreen,
          onHideCustomWidget: onHideFullscreen,
        );
      }
      // Publish only a fully configured controller. If any awaited setup
      // operation throws, retry creates and configures a fresh controller.
      if (_stopped) return;
      final view = WebViewWidget(controller: controller);
      _controller = controller;
      _view = view;
    }
    if (_stopped) return;
    onLoading(true);
    final applicationId = uri.host == 'www.linetv.tw'
        ? ''
        : (await PackageInfo.fromPlatform()).packageName;
    if (_stopped) return;
    final request = officialVideoRequest(uri, applicationId);
    _documentUri = request.uri;
    await _controller!.loadRequest(request.uri, headers: request.headers);
    onLoading(true); // Also publishes the newly created native view.
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await _controller?.loadRequest(Uri.parse('about:blank'));
  }
}
