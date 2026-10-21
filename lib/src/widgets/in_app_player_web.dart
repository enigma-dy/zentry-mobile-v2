import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

final Set<String> _registeredStreamViewTypes = <String>{};

Widget buildWebPlatformStreamView({
  required String streamUrl,
  required String viewId,
  required bool isDirectStream,
  bool isEmbedStream = false,
  required String streamFormat,
  required Map<String, String> headers,
  VoidCallback? onPlaybackError,
}) {
  final viewType = 'zentry-stream-player-$viewId';

  if (!_registeredStreamViewTypes.contains(viewType)) {
    _registeredStreamViewTypes.add(viewType);
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) {
      final iframe = web.HTMLIFrameElement()
        ..src = streamUrl
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..style.backgroundColor = '#000000'
        ..allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture';

      // Some broadcast providers explicitly refuse to run in a sandboxed
      // iframe. Do not add a sandbox attribute here or in the backend player.
      iframe.setAttribute('allowfullscreen', 'true');

      return iframe;
    });
  }

  return HtmlElementView(key: ValueKey(viewType), viewType: viewType);
}
