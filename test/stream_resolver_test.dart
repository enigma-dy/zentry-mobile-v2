import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/live_tv/stream_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reads native metadata despite the package wrapper dropping raw data',
    () async {
      const channel = MethodChannel('ytdlp_flutter');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'init') return null;
        expect(call.arguments, {'url': 'https://example.com/watch'});
        return jsonEncode({
          'title': 'Native stream',
          'url': 'https://example.com/stream.m3u8',
          'vcodec': 'h264',
          'acodec': 'aac',
        });
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final stream = await resolvePage('https://example.com/watch');
      expect(calls, ['init', 'getVideoInfo']);
      expect(stream.url.toString(), 'https://example.com/stream.m3u8');
      expect(stream.title, 'Native stream');
    },
  );

  test('selects highest combined stream and preserves format headers', () {
    final result = selectStream({
      'http_headers': {'User-Agent': 'test-agent', 'Referer': 'page'},
      'formats': [
        {
          'url': 'https://example.com/video-only',
          'vcodec': 'h264',
          'acodec': 'none',
          'height': 2160,
        },
        {
          'url': 'https://example.com/low',
          'vcodec': 'h264',
          'acodec': 'aac',
          'height': 360,
        },
        {
          'url': 'https://example.com/high',
          'vcodec': 'h264',
          'acodec': 'aac',
          'height': 1080,
          'http_headers': {'Referer': 'embedded-player'},
        },
        {
          'url': 'https://example.com/protected',
          'vcodec': 'h264',
          'acodec': 'aac',
          'height': 2160,
          'has_drm': true,
        },
      ],
    }, 'Example');

    expect(result.url.toString(), 'https://example.com/high');
    expect(result.headers, {
      'User-Agent': 'test-agent',
      'Referer': 'embedded-player',
    });
  });

  test('reports missing streams instead of treating the webpage as video', () {
    expect(
      () => selectStream({'webpage_url': 'https://example.com'}, 'Page'),
      throwsStateError,
    );
  });

  test('rejects invalid input before initializing native extraction', () async {
    await expectLater(resolvePage('not a URL'), throwsFormatException);
    await expectLater(
      resolvePage('file:///private/video'),
      throwsFormatException,
    );
  });

  test('falls back to hidden browser and preserves its playback headers',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('ytdlp_flutter'),
        (call) async {
      if (call.method == 'init') return null;
      throw PlatformException(code: 'ytdlp_error', message: 'Unsupported URL');
    });
    messenger.setMockMethodCallHandler(const MethodChannel('stream_browser'),
        (call) async {
      expect(call.method, 'resolve');
      expect(call.arguments, {'url': 'https://ntv.st/watch/example'});
      return {
        'url': 'https://cdn.example/live.m3u8?token=abc',
        'title': 'Live match',
        'headers': {
          'Referer': 'https://embed.example/player',
          'Cookie': 'session=abc',
          'User-Agent': 'browser-agent',
        },
      };
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('ytdlp_flutter'), null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('stream_browser'), null);
    });
    final stream = await resolvePage('https://ntv.st/watch/example');
    expect(stream.url.query, 'token=abc');
    expect(stream.headers['Referer'], 'https://embed.example/player');
    expect(stream.headers['Cookie'], 'session=abc');
    expect(stream.title, 'Live match');
    expect(stream.usesBrowser, isTrue);
  });

  test('browser-session reconnect bypasses yt-dlp', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('stream_browser'),
        (call) async {
      expect(call.method, 'resolve');
      return {
        'url': 'https://cdn.example/fresh.m3u8',
        'headers': <String, String>{}
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('stream_browser'), null));
    final stream =
        await resolvePage('https://ntv.st/watch/example', preferBrowser: true);
    expect(stream.url.path, '/fresh.m3u8');
    expect(stream.usesBrowser, isTrue);
  });

  test('plays direct media URLs without either extractor', () async {
    final stream = await resolvePage('https://cdn.example/live.m3u8?token=abc');
    expect(stream.url.toString(), 'https://cdn.example/live.m3u8?token=abc');
  });

  test('does not start browser detection after cancellation', () async {
    await expectLater(
      resolvePage('https://ntv.st/watch/example', shouldContinue: () => false),
      throwsStateError,
    );
  });
}
