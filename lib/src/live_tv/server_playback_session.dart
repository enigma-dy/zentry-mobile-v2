import 'tv_catalog.dart';

/// One watching session. Each server is tried once until the viewer retries.
class ServerPlaybackSession {
  ServerPlaybackSession(List<TvSource> available, TvSource initial) {
    final seen = <String>{};
    sources = List.unmodifiable([
      for (final source in [...available, initial])
        if (seen.add(source.url.toString())) source,
    ]);
    currentIndex = sources.indexWhere((s) => s.url == initial.url);
    _preferredIndex = currentIndex;
  }

  late final List<TvSource> sources;
  late int currentIndex;
  late int _preferredIndex;
  int generation = 0;
  bool exhausted = false;
  final _failed = <int>{};
  TvSource get current => sources[currentIndex];

  bool fail(int expectedGeneration) {
    if (expectedGeneration != generation || exhausted) return false;
    _failed.add(currentIndex);
    for (var step = 1; step < sources.length; step++) {
      final next = (currentIndex + step) % sources.length;
      if (_failed.contains(next)) continue;
      currentIndex = next;
      generation++;
      return true;
    }
    exhausted = true;
    return true;
  }

  bool select(int index) {
    if (index < 0 || index >= sources.length) return false;
    if (index == currentIndex && !exhausted) return false;
    currentIndex = _preferredIndex = index;
    _failed.clear();
    exhausted = false;
    generation++;
    return true;
  }

  void retry() {
    currentIndex = _preferredIndex;
    _failed.clear();
    exhausted = false;
    generation++;
  }
}
