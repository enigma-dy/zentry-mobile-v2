import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/live_tv/server_playback_session.dart';
import 'package:predict/src/live_tv/tv_catalog.dart';

void main() {
  final a = TvSource(
    'A',
    Uri.parse('https://a.test'),
    referer: Uri.parse('https://origin.test'),
  );
  final b = TvSource('B', Uri.parse('https://b.test'));
  final c = TvSource('C', Uri.parse('https://c.test'));
  test('starts at selected server, tries each once, then stops', () {
    final session = ServerPlaybackSession([a, b, c], b);
    expect(session.current, b);
    expect(session.fail(0), isTrue);
    expect(session.current, c);
    expect(session.fail(1), isTrue);
    expect(session.current, a);
    expect(session.current.referer, a.referer);
    expect(session.fail(2), isTrue);
    expect(session.exhausted, isTrue);
    expect(session.fail(2), isFalse);
    session.retry();
    expect(session.current, b);
    expect(session.exhausted, isFalse);
  });
  test(
    'stale failures cannot skip a new server; manual choice resets cycle',
    () {
      final session = ServerPlaybackSession([a, b, c], a);
      session.fail(0);
      expect(session.fail(0), isFalse);
      expect(session.current, b);
      session.select(2);
      expect(session.fail(1), isFalse);
      expect(session.current, c);
      session.fail(2);
      expect(session.current, a);
      session.fail(3);
      expect(session.current, b);
    },
  );
  test('deduplicates URLs and includes missing selected source', () {
    final session = ServerPlaybackSession([a, a], b);
    expect(session.sources, [a, b]);
    expect(session.select(-1), isFalse);
    expect(session.select(99), isFalse);
    expect(session.select(1), isFalse);
    final single = ServerPlaybackSession([a], a)..fail(0);
    expect(single.exhausted, isTrue);
    expect(single.select(0), isTrue);
    expect(single.exhausted, isFalse);
  });
}
