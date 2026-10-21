import 'dart:collection';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

Widget buildWebPlatformStreamView({
  required String streamUrl,
  required String viewId,
  required bool isDirectStream,
  bool isEmbedStream = false,
  required String streamFormat,
  required Map<String, String> headers,
  VoidCallback? onPlaybackError,
}) {
  return _NativeStreamView(
    key: ValueKey(viewId),
    streamUrl: streamUrl,
    isDirectStream: isDirectStream,
    isEmbedStream: isEmbedStream,
    streamFormat: streamFormat,
    headers: headers,
    onPlaybackError: onPlaybackError,
  );
}

class _NativeStreamView extends StatefulWidget {
  final String streamUrl;
  final bool isDirectStream;
  final bool isEmbedStream;
  final String streamFormat;
  final Map<String, String> headers;
  final VoidCallback? onPlaybackError;

  const _NativeStreamView({
    super.key,
    required this.streamUrl,
    required this.isDirectStream,
    required this.isEmbedStream,
    required this.streamFormat,
    required this.headers,
    this.onPlaybackError,
  });

  @override
  State<_NativeStreamView> createState() => _NativeStreamViewState();
}

class _NativeStreamViewState extends State<_NativeStreamView> {
  BetterPlayerController? _controller;
  bool _loading = false;
  bool _errorReported = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isDirectStream) _connect();
  }

  void _connect() {
    final previous = _controller;
    _controller = null;
    previous?.dispose();
    setState(() {
      _loading = true;
      _errorReported = false;
      _error = null;
    });

    final uri = Uri.tryParse(widget.streamUrl);
    if (uri == null || !uri.hasScheme) {
      setState(() {
        _loading = false;
        _error = 'This stream URL is invalid.';
      });
      return;
    }

    final isDash = widget.streamFormat.toLowerCase() == 'dash';
    final dataSource = BetterPlayerDataSource.network(
      uri.toString(),
      liveStream: true,
      headers: widget.headers,
      videoFormat: isDash
          ? BetterPlayerVideoFormat.dash
          : BetterPlayerVideoFormat.hls,
    );
    final controller = BetterPlayerController(
      const BetterPlayerConfiguration(
        autoPlay: true,
        fit: BoxFit.contain,
        aspectRatio: 16 / 9,
        handleLifecycle: true,
        allowedScreenSleep: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enablePlaybackSpeed: false,
          enableSkips: false,
          progressBarPlayedColor: Color(0xFFFFD700),
          iconsColor: Color(0xFFFFD700),
        ),
      ),
      betterPlayerDataSource: dataSource,
    );
    _controller = controller;
    controller.addEventsListener((event) {
      if (!mounted || !identical(_controller, controller)) return;
      if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
        setState(() => _loading = false);
      } else if (event.betterPlayerEventType ==
          BetterPlayerEventType.exception) {
        setState(() {
          _loading = false;
          _error = 'The live feed could not be started. It may be refreshing.';
        });
        if (!_errorReported) {
          _errorReported = true;
          widget.onPlaybackError?.call();
        }
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedStream) {
      return _NativeEmbedView(url: widget.streamUrl);
    }
    if (!widget.isDirectStream) {
      return const Material(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(height: 14),
              Text(
                'Preparing the in-app live feed',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 5),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'The player will start automatically when a direct feed is ready.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || _error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.tv_off_rounded,
                size: 48,
                color: Color(0xFFFFD700),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _error ?? 'The live feed is not ready yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry feed'),
              ),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Keep the player mounted while it initializes. Returning only a
          // spinner here prevents BetterPlayer from attaching to the native
          // video surface, so its initialized event can never fire.
          BetterPlayer(controller: controller),
          if (_loading)
            const IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFFD700)),
              ),
            ),
        ],
      ),
    );
  }
}

class _NativeEmbedView extends StatefulWidget {
  final String url;

  const _NativeEmbedView({required this.url});

  @override
  State<_NativeEmbedView> createState() => _NativeEmbedViewState();
}

class _NativeEmbedViewState extends State<_NativeEmbedView> {
  static const Set<String> _trustedEmbedHosts = {};

  late final String _allowedHost;
  late final bool _isTrustedUrl;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final parsed = Uri.tryParse(widget.url);
    _allowedHost = parsed?.host.toLowerCase() ?? '';
    _isTrustedUrl = parsed?.scheme == 'https' && _isTrustedHost(_allowedHost);
    if (!_isTrustedUrl) {
      _loading = false;
      _error = 'This playback server is not authorized.';
    }
  }

  bool _isTrustedHost(String host) => _trustedEmbedHosts.any(
    (allowed) => host == allowed || host.endsWith('.$allowed'),
  );

  @override
  Widget build(BuildContext context) {
    if (!_isTrustedUrl) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }
    final uri = WebUri(widget.url);
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: uri),
            initialUserScripts: UnmodifiableListView([
              UserScript(
                source: _popupBlockingScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: false,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              iframeAllow: 'autoplay; fullscreen; picture-in-picture',
              iframeAllowFullscreen: true,
              supportMultipleWindows: false,
              javaScriptCanOpenWindowsAutomatically: false,
              useShouldOverrideUrlLoading: true,
              useOnDownloadStart: true,
              allowFileAccess: false,
              allowContentAccess: false,
              allowFileAccessFromFileURLs: false,
              allowUniversalAccessFromFileURLs: false,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
              safeBrowsingEnabled: true,
              geolocationEnabled: false,
              databaseEnabled: false,
              saveFormData: false,
              thirdPartyCookiesEnabled: false,
              disableDefaultErrorPage: true,
              disableContextMenu: true,
              transparentBackground: false,
            ),
            shouldOverrideUrlLoading: (controller, action) async {
              final target = action.request.url;
              final scheme = target?.scheme.toLowerCase() ?? '';
              if (action.isForMainFrame != true) {
                final safeFrameScheme =
                    scheme == 'https' || scheme == 'about' || scheme == 'blob';
                return safeFrameScheme
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL;
              }
              final host = target?.host.toLowerCase() ?? '';
              final allowed = scheme == 'https' && host == _allowedHost;
              return allowed
                  ? NavigationActionPolicy.ALLOW
                  : NavigationActionPolicy.CANCEL;
            },
            onCreateWindow: (controller, request) async => false,
            onDownloadStartRequest: (controller, request) async {
              // Intentionally ignored. Embedded playback must never download
              // files or hand a URL to another application.
            },
            onPermissionRequest: (controller, request) async =>
                PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.DENY,
                ),
            onLoadStop: (controller, url) {
              if (!mounted) return;
              setState(() {
                _loading = false;
                _error = null;
              });
            },
            onReceivedError: (controller, request, error) {
              if (!mounted || request.isForMainFrame != true) return;
              setState(() {
                _loading = false;
                _error = 'This server could not be loaded.';
              });
            },
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)),
            ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const String _popupBlockingScript = r'''
(() => {
  try {
    Object.defineProperty(window, 'open', {
      value: () => null,
      writable: false,
      configurable: false,
    });
  } catch (_) {
    window.open = () => null;
  }

  document.addEventListener('click', (event) => {
    const element = event.target instanceof Element ? event.target : null;
    const link = element?.closest('a[href]');
    if (!link) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  }, true);

  document.addEventListener('submit', (event) => {
    event.preventDefault();
    event.stopImmediatePropagation();
  }, true);
})();
''';
