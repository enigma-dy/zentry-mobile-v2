import 'dart:convert';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ytdlp_flutter/ytdlp_flutter.dart';

class ResolvedStream {
  const ResolvedStream(
    this.url,
    this.headers,
    this.title, {
    this.usesBrowser = false,
  });

  final Uri url;
  final Map<String, String> headers;
  final String title;
  final bool usesBrowser;
}

/// Selects a single HTTP stream with both audio and video.
/// Separate audio/video tracks cannot be played as one video_player URL.
ResolvedStream selectStream(Map<String, dynamic> raw, String title) {
  final candidates =
      <Map<String, dynamic>>[
        raw,
        for (final value in raw['formats'] as List? ?? const [])
          if (value is Map) Map<String, dynamic>.from(value),
      ].where((format) {
        final uri = Uri.tryParse(format['url']?.toString() ?? '');
        return uri != null &&
            uri.host.isNotEmpty &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            format['vcodec'] != null &&
            format['vcodec'] != 'none' &&
            format['acodec'] != null &&
            format['acodec'] != 'none' &&
            format['has_drm'] != true;
      }).toList();

  double height(Map<String, dynamic> format) =>
      (format['height'] as num?)?.toDouble() ?? 0;
  candidates.sort((a, b) => height(b).compareTo(height(a)));
  if (candidates.isEmpty) {
    throw StateError(
      'No playable combined audio/video stream was found. '
      'The page may be unsupported, expired, protected, or use separate tracks.',
    );
  }

  final selected = candidates.first;
  final headers = <String, String>{};
  for (final source in [raw['http_headers'], selected['http_headers']]) {
    if (source is Map) {
      for (final entry in source.entries) {
        headers[entry.key.toString()] = entry.value.toString();
      }
    }
  }
  return ResolvedStream(Uri.parse(selected['url'] as String), headers, title);
}

const _browserChannel = MethodChannel('stream_browser');

Future<void> cancelStreamDetection() =>
    _browserChannel.invokeMethod<void>('cancel');

Future<void> completeStreamHandoff() =>
    _browserChannel.invokeMethod<void>('handoff');

Future<ResolvedStream> _resolveInBrowser(Uri page, {String? referer}) async {
  final data = await _browserChannel.invokeMapMethod<String, dynamic>(
    'resolve',
    {'url': page.toString(), 'referer': ?referer},
  );
  final url = Uri.tryParse(data?['url']?.toString() ?? '');
  if (url == null ||
      url.host.isEmpty ||
      !['http', 'https'].contains(url.scheme)) {
    throw StateError('No playable stream was detected on this page.');
  }
  return ResolvedStream(
    url,
    Map<String, String>.from(data?['headers'] as Map? ?? const {}),
    data?['title']?.toString() ?? 'Video',
    usesBrowser: true,
  );
}

Uri parsePageUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      !['https', 'http'].contains(uri.scheme)) {
    throw const FormatException('Enter a valid HTTP or HTTPS webpage URL.');
  }
  return uri;
}

Future<ResolvedStream> resolvePage(
  String input, {
  void Function(String)? onStatus,
  bool Function()? shouldContinue,
  bool preferBrowser = false,
  String? referer,
}) async {
  final uri = parsePageUrl(input);
  void checkActive() {
    if (shouldContinue != null && !shouldContinue()) {
      throw StateError('Stream detection was cancelled.');
    }
  }

  checkActive();
  if (RegExp(
    r'\.(m3u8|mpd|mp4|webm)$',
    caseSensitive: false,
  ).hasMatch(uri.path)) {
    return ResolvedStream(uri, const {}, 'Video');
  }
  onStatus?.call('Finding stream…');
  if (preferBrowser) return _resolveInBrowser(uri, referer: referer);
  try {
    return await _resolveWithYtdlp(uri).timeout(const Duration(seconds: 20));
  } on Exception {
    checkActive();
    onStatus?.call('Finding stream…');
    return _resolveInBrowser(uri, referer: referer);
  } on StateError {
    checkActive();
    onStatus?.call('Finding stream…');
    return _resolveInBrowser(uri, referer: referer);
  }
}

Future<ResolvedStream> _resolveWithYtdlp(Uri uri) async {
  await Ytdlp.init();
  // Version 0.1.0's public getVideoInfo drops raw metadata on Android.
  // Its native method returns the complete JSON, including playback URLs.
  // Use the plugin's existing channel until its wrapper preserves raw data.
  final json = await const MethodChannel(
    'ytdlp_flutter',
  ).invokeMethod<String>('getVideoInfo', {'url': uri.toString()});
  if (json == null || json.isEmpty) {
    throw StateError('The extractor did not provide stream metadata.');
  }
  final raw = jsonDecode(json) as Map<String, dynamic>;
  return selectStream(raw, raw['title']?.toString() ?? 'Video');
}
