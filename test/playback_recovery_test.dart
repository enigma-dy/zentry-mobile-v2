import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/live_tv/playback_recovery.dart';

void main() {
  final start = DateTime.utc(2026, 10, 23);

  test('reconnects a frozen stream once after 20 seconds without progress', () {
    final recovery = PlaybackRecovery();
    bool observe(int seconds, {int position = 5}) => recovery.shouldReconnect(
          position: Duration(seconds: position),
          wantsPlayback: true,
          hasError: false,
          atEnd: false,
          now: start.add(Duration(seconds: seconds)),
        );
    expect(observe(0), isFalse);
    expect(observe(5), isFalse);
    expect(observe(20), isFalse);
    expect(observe(25), isTrue);
    expect(observe(60), isFalse);
    recovery.reset();
    expect(observe(65, position: 0), isFalse);
    expect(observe(70, position: 1), isFalse);
    expect(observe(75, position: 2), isFalse);
  });

  test('does not reconnect a user-paused or completed video', () {
    final recovery = PlaybackRecovery();
    for (final seconds in [0, 30, 60]) {
      expect(
          recovery.shouldReconnect(
            position: const Duration(seconds: 5),
            wantsPlayback: false,
            hasError: false,
            atEnd: false,
            now: start.add(Duration(seconds: seconds)),
          ),
          isFalse);
      expect(
          recovery.shouldReconnect(
            position: const Duration(seconds: 5),
            wantsPlayback: true,
            hasError: false,
            atEnd: true,
            now: start.add(Duration(seconds: seconds)),
          ),
          isFalse);
    }
  });

  test(
      'refreshes once on a playback error, with budget reset only for a new play',
      () {
    final recovery = PlaybackRecovery();
    bool failed() => recovery.shouldReconnect(
          position: Duration.zero,
          wantsPlayback: true,
          hasError: true,
          atEnd: false,
          now: start,
        );
    expect(failed(), isTrue);
    expect(failed(), isFalse);
    recovery.reset();
    expect(failed(), isTrue);
  });
}
