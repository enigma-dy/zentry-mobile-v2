import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'ad_config.dart';
import 'ad_frame.dart';
import 'web_ad_preview.dart';

Future<void>? _loader;

Future<void> _loadAdSense() => _loader ??= () async {
  final done = Completer<void>();
  final script = web.HTMLScriptElement()
    ..async = true
    ..crossOrigin = 'anonymous'
    ..src =
        'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${AdConfig.adsensePublisherId}';
  script.addEventListener(
    'load',
    ((web.Event _) {
      if (!done.isCompleted) done.complete();
    }).toJS,
  );
  script.addEventListener(
    'error',
    ((web.Event _) {
      if (!done.isCompleted) {
        done.completeError(StateError('AdSense unavailable'));
      }
    }).toJS,
  );
  web.document.head!.appendChild(script);
  await done.future.timeout(const Duration(seconds: 15));
}();

/// An actual DOM ad unit in Flutter web. No AdMob plugin is imported on web.
class PlatformAdBanner extends StatefulWidget {
  const PlatformAdBanner({super.key, required this.placement, this.onDismiss});
  final AdPlacement placement;
  final VoidCallback? onDismiss;
  @override
  State<PlatformAdBanner> createState() => _PlatformAdBannerState();
}

class _PlatformAdBannerState extends State<PlatformAdBanner> {
  web.HTMLDivElement? _host;
  web.ResizeObserver? _observer;
  bool _failed = false;
  bool _requested = false;
  int _width = 320;

  void _create(Object element) {
    final host = element as web.HTMLDivElement;
    _host = host;
    final unit = web.document.createElement('ins') as web.HTMLElement;
    unit.className = 'adsbygoogle';
    unit.style.cssText =
        'display:inline-block;width:${_width}px;height:${_width == 728 ? 90 : 50}px';
    unit.setAttribute('data-ad-client', AdConfig.adsensePublisherId);
    unit.setAttribute('data-ad-slot', AdConfig.webSlot(widget.placement));
    host.appendChild(unit);
    // Platform views attach asynchronously. Request once the slot has a width.
    _observer = web.ResizeObserver(
      ((JSArray<web.ResizeObserverEntry> _, web.ResizeObserver _) {
        if (host.isConnected && host.clientWidth > 0 && !_requested) {
          _requested = true;
          _observer?.disconnect();
          unawaited(_request(host));
        }
      }).toJS,
    )..observe(host);
  }

  Future<void> _request(web.HTMLDivElement host) async {
    try {
      await _loadAdSense();
      if (!mounted || !host.isConnected) return;
      var queue = globalContext.getProperty<JSObject?>('adsbygoogle'.toJS);
      if (queue == null) {
        queue = <JSAny>[].toJS;
        globalContext.setProperty('adsbygoogle'.toJS, queue);
      }
      queue.callMethod<JSAny?>('push'.toJS, JSObject());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _observer?.disconnect();
    _host?.textContent = '';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AdConfig.webTestMode) {
      return WebAdPreview(onDismiss: widget.onDismiss);
    }
    if (_failed || !AdConfig.webEnabled(widget.placement)) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 336) return const SizedBox.shrink();
        // Keep one unit's dimensions stable throughout its lifetime.
        if (_host == null) _width = constraints.maxWidth >= 744 ? 728 : 320;
        if (constraints.maxWidth < _width + 16) return const SizedBox.shrink();
        return AdFrame(
          child: Center(
            child: SizedBox(
              width: _width.toDouble(),
              height: _width == 728 ? 90 : 50,
              child: HtmlElementView.fromTagName(
                tagName: 'div',
                onElementCreated: _create,
              ),
            ),
          ),
        );
      },
    );
  }
}

class AdPrivacyButton extends StatelessWidget {
  const AdPrivacyButton({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
