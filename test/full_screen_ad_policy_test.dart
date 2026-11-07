import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/ads/full_screen_ad_policy.dart';
import 'package:predict/src/ads/ad_app_lifecycle_mobile.dart'
    show AdRouteObserver;

void main() {
  test('returning from an ad click suppresses the next app-open attempt', () {
    final gate = FullScreenAdGate();
    gate.skipNextAppOpen();
    expect(gate.consumeAppOpenSkip(), isTrue);
    expect(gate.consumeAppOpenSkip(), isFalse);
  });
  test(
    'full-screen formats cannot stack or immediately repeat on ad return',
    () {
      final gate = FullScreenAdGate();
      final now = DateTime.utc(2026, 11, 7, 12);
      expect(gate.tryBegin(now), isTrue);
      expect(gate.tryBegin(now), isFalse);
      gate.didShow(now);
      gate.finish();
      expect(gate.tryBegin(now.add(const Duration(seconds: 90))), isFalse);
      expect(gate.tryBegin(now.add(const Duration(minutes: 2))), isTrue);
    },
  );

  test('an SDK show failure does not consume the successful-ad cooldown', () {
    final gate = FullScreenAdGate();
    final now = DateTime.utc(2026, 11, 7);
    expect(gate.tryBegin(now), isTrue);
    gate.finish();
    expect(gate.tryBegin(now), isTrue);
  });

  test(
    'app-open skips Pro, new users, quick resumes, playback and other routes',
    () {
      bool eligible({
        bool signedIn = true,
        bool pro = false,
        bool root = true,
        int sessions = 3,
        int seconds = 30,
      }) => appOpenAdEligible(
        signedIn: signedIn,
        hasPredictionAccess: pro,
        rootPageVisible: root,
        sessions: sessions,
        away: Duration(seconds: seconds),
      );
      expect(eligible(), isTrue);
      expect(eligible(signedIn: false), isFalse);
      expect(eligible(pro: true), isFalse);
      expect(eligible(root: false), isFalse);
      expect(eligible(sessions: 2), isFalse);
      expect(eligible(seconds: 29), isFalse);
    },
  );

  test(
    'route observer blocks app-open above the root, including dialogs and video',
    () {
      final observer = AdRouteObserver();
      final root = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      final player = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      final checkout = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
      );
      final dialog = RawDialogRoute<void>(
        pageBuilder: (_, _, _) => const SizedBox(),
      );
      observer.didPush(root, null);
      expect(observer.rootPageVisible, isTrue);
      observer.didPush(player, root);
      expect(observer.rootPageVisible, isFalse);
      observer.didReplace(oldRoute: player, newRoute: checkout);
      expect(observer.rootPageVisible, isFalse);
      observer.didPop(checkout, root);
      expect(observer.rootPageVisible, isTrue);
      observer.didPush(dialog, root);
      expect(observer.rootPageVisible, isFalse);
      observer.didRemove(dialog, root);
      expect(observer.rootPageVisible, isTrue);
    },
  );
}
