/// Coordinate full-screen formats so app resume cannot stack another ad on an
/// interstitial, and stream retries do not repeatedly interrupt playback.
class FullScreenAdGate {
  static const cooldown = Duration(minutes: 2);
  bool _showing = false;
  DateTime? _lastShown;
  bool _skipNextAppOpen = false;

  bool get isShowing => _showing;

  bool tryBegin(DateTime now) {
    if (_showing ||
        _lastShown != null && now.difference(_lastShown!) < cooldown) {
      return false;
    }
    _showing = true;
    return true;
  }

  void didShow(DateTime now) => _lastShown = now;
  void finish() => _showing = false;
  void skipNextAppOpen() => _skipNextAppOpen = true;
  bool consumeAppOpenSkip() {
    final skip = _skipNextAppOpen;
    _skipNextAppOpen = false;
    return skip;
  }
}

final fullScreenAdGate = FullScreenAdGate();

bool appOpenAdEligible({
  required bool signedIn,
  required bool hasPredictionAccess,
  required bool rootPageVisible,
  required int sessions,
  required Duration away,
}) =>
    signedIn &&
    !hasPredictionAccess &&
    rootPageVisible &&
    sessions >= 3 &&
    away >= const Duration(seconds: 30);
