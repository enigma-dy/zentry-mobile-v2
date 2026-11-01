import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/ads/watch_ad_gate.dart';

void main() {
  test('waits for ad dismissal before opening playback, and ignores taps while watching', () async {
    final gate = WatchAdGate();
    final dismissed = Completer<void>();
    final playerClosed = Completer<void>();
    final events = <String>[];
    final opening = gate.open(
      showAd: () {
        events.add('ad');
        return dismissed.future;
      },
      openPlayer: () {
        events.add('player');
        return playerClosed.future;
      },
    );
    expect(events, ['ad']);
    dismissed.complete();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['ad', 'player']);
    await gate.open(
      showAd: () async {
        events.add('unexpected ad');
      },
      openPlayer: () async {},
    );
    expect(events, ['ad', 'player']);
    playerClosed.complete();
    await opening;
    await gate.open(
      showAd: () async {
        events.add('next ad');
      },
      openPlayer: () async {
        events.add('next player');
      },
    );
    expect(events, ['ad', 'player', 'next ad', 'next player']);
  });

  test('ad failure does not prevent playback', () async {
    var played = false;
    await WatchAdGate().open(
      showAd: () async {
        throw StateError('Unavailable');
      },
      openPlayer: () async {
        played = true;
      },
    );
    expect(played, isTrue);
  });
}
