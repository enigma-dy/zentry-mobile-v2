/// A Watch tap is the only trigger. Player navigation waits for ad dismissal.
class WatchAdGate {
  bool _opening = false;

  Future<void> open({
    required Future<void> Function() showAd,
    required Future<void> Function() openPlayer,
  }) async {
    if (_opening) return;
    _opening = true;
    try {
      try {
        await showAd();
      } catch (_) {
        // Unavailable ads must not stop viewers from watching.
      }
      await openPlayer();
    } finally {
      _opening = false;
    }
  }
}
