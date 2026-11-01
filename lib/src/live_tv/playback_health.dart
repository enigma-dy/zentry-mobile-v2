/// Detects playback failure without mistaking an intentional pause for a stall.
class PlaybackHealth {
  Duration? _position;
  DateTime? _stalledSince;

  void reset() {
    _position = null;
    _stalledSince = null;
  }

  bool hasFailed({
    required Duration position,
    required bool wantsPlayback,
    required bool hasError,
    required bool atEnd,
    required DateTime now,
  }) {
    if (!wantsPlayback || atEnd) {
      _position = position;
      _stalledSince = null;
      return false;
    }
    if (hasError) return true;
    if (_position != position) {
      _position = position;
      _stalledSince = now;
      return false;
    }
    _stalledSince ??= now;
    return now.difference(_stalledSince!) >= const Duration(seconds: 20);
  }
}
