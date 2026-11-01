/// Allows one fresh resolution per user-initiated playback, never an endless loop.
class PlaybackRecovery {
  bool _used = false;
  Duration? _position;
  DateTime? _stalledSince;

  void reset() {
    _used = false;
    _position = null;
    _stalledSince = null;
  }

  bool shouldReconnect({
    required Duration position,
    required bool wantsPlayback,
    required bool hasError,
    required bool atEnd,
    required DateTime now,
  }) {
    if (!wantsPlayback || atEnd) {
      _stalledSince = null;
      _position = position;
      return false;
    }
    if (_used) return false;
    if (hasError) {
      _used = true;
      return true;
    }
    if (_position == null || position != _position) {
      _position = position;
      _stalledSince = null;
      return false;
    }
    _stalledSince ??= now;
    if (now.difference(_stalledSince!) < const Duration(seconds: 20)) {
      return false;
    }
    _used = true;
    return true;
  }
}
