import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/live_tv/playback_health.dart';

void main() {
  final start = DateTime.utc(2026);
  late PlaybackHealth health;
  setUp(() => health = PlaybackHealth());
  bool observe(
    int seconds, {
    int position = 5,
    bool wants = true,
    bool error = false,
    bool end = false,
  }) => health.hasFailed(
    position: Duration(seconds: position),
    wantsPlayback: wants,
    hasError: error,
    atEnd: end,
    now: start.add(Duration(seconds: seconds)),
  );
  test(
    'allows buffering, resets on progress, fails after 20 seconds frozen',
    () {
      expect(observe(0), isFalse);
      expect(observe(19), isFalse);
      expect(observe(20, position: 6), isFalse);
      expect(observe(39, position: 6), isFalse);
      expect(observe(40, position: 6), isTrue);
      health.reset();
      expect(observe(90), isFalse);
    },
  );
  test('errors fail immediately but intentional pauses and endings do not', () {
    expect(observe(0, error: true), isTrue);
    expect(observe(10, wants: false, error: true), isFalse);
    expect(observe(90, wants: false), isFalse);
    expect(observe(100), isFalse);
    expect(observe(110, end: true), isFalse);
    expect(observe(190, end: true), isFalse);
  });
}
