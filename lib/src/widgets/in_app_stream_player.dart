import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stream_model.dart';
import '../services/sports_service.dart';
import 'in_app_player_stub.dart'
    if (dart.library.js_interop) 'in_app_player_web.dart';

int nextAvailableStreamSourceIndex({
  required int currentIndex,
  required int sourceCount,
  required Set<int> failedIndexes,
}) {
  if (sourceCount < 2) return -1;
  for (int offset = 1; offset < sourceCount; offset++) {
    final candidate = (currentIndex + offset) % sourceCount;
    if (!failedIndexes.contains(candidate)) return candidate;
  }
  return -1;
}

class InAppStreamPlayer extends StatefulWidget {
  final LiveStreamEventModel streamEvent;
  final List<LiveStreamEventModel> allEvents;
  final VoidCallback? onBack;
  final ValueChanged<LiveStreamEventModel>? onSelectEvent;
  final bool isFullscreen;
  final String apiBaseUrl;
  final Future<void> Function()? onRefreshStream;

  const InAppStreamPlayer({
    super.key,
    required this.streamEvent,
    this.allEvents = const [],
    this.onBack,
    this.onSelectEvent,
    this.isFullscreen = false,
    this.apiBaseUrl = '',
    this.onRefreshStream,
  });

  @override
  State<InAppStreamPlayer> createState() => _InAppStreamPlayerState();
}

class _InAppStreamPlayerState extends State<InAppStreamPlayer> {
  static int _nextPlayerInstance = 0;

  int _selectedSourceIndex = 0;
  int _playerRevision = 0;
  late final int _playerInstance;
  late String _activeUrl;
  String _activeFormat = '';
  bool _tryRelay = false;
  final Set<int> _failedSourceIndexes = <int>{};

  @override
  void initState() {
    super.initState();
    _playerInstance = ++_nextPlayerInstance;
    _updateActiveStream();
  }

  @override
  void didUpdateWidget(covariant InAppStreamPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_streamSignature(oldWidget.streamEvent) !=
        _streamSignature(widget.streamEvent)) {
      if (oldWidget.streamEvent.id != widget.streamEvent.id) {
        _selectedSourceIndex = 0;
      }
      _failedSourceIndexes.clear();
      _tryRelay = false;
      _updateActiveStream();
      _playerRevision++;
    }
  }

  String _streamSignature(LiveStreamEventModel event) => <String>[
    event.id,
    ...event.playbackSources.map((stream) => stream.url),
  ].join('|');

  void _updateActiveStream() {
    final streams = widget.streamEvent.playbackSources;

    if (streams.isNotEmpty && _selectedSourceIndex < streams.length) {
      _activeUrl = streams[_selectedSourceIndex].url;
      _activeFormat = streams[_selectedSourceIndex].format.toLowerCase();
      if (_activeFormat.isEmpty) {
        _activeFormat = _activeUrl.toLowerCase().contains('.mpd')
            ? 'dash'
            : 'hls';
      }
    } else {
      // CS3 returns adaptive media links only. HTML embeds and coverage pages
      // are never passed to a playback surface.
      _activeUrl = '';
      _activeFormat = '';
    }
  }

  String get _playbackUrl {
    if (_activeFormat.isEmpty || widget.apiBaseUrl.trim().isEmpty) {
      return _activeUrl;
    }
    if (_activeFormat == 'embed') return _activeUrl;
    // Native adaptive streams are played directly. The HLS provider URLs work
    // as raw M3U8 links, so mobile should request them exactly as returned.
    // Flutter Web still uses the backend relay to avoid browser CORS limits.
    if (!kIsWeb && !_tryRelay &&
        (_activeFormat == 'hls' || _activeFormat == 'dash')) {
      return _activeUrl;
    }
    final base = widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final relayUrl =
        '$base/api/v1/live-streams/${Uri.encodeComponent(widget.streamEvent.id)}/hls/$_selectedSourceIndex';
    // Native players need the media manifest itself. The HTML wrapper is only
    // used by our browser adaptive-media surface.
    if (!kIsWeb) return relayUrl;
    return Uri.parse('$base/api/v1/live-streams/play')
        .replace(
          queryParameters: {
            'url': relayUrl,
            'hls': (_activeFormat == 'hls').toString(),
            'dash': (_activeFormat == 'dash').toString(),
            'title': widget.streamEvent.displayTitle,
          },
        )
        .toString();
  }

  Map<String, String> get _activeHeaders {
    final streams = widget.streamEvent.playbackSources;
    if (_selectedSourceIndex < 0 || _selectedSourceIndex >= streams.length) {
      return const {};
    }
    return streams[_selectedSourceIndex].headers;
  }

  Future<void> _reloadPlayer() async {
    await widget.onRefreshStream?.call();
    if (!mounted) return;
    setState(() {
      _failedSourceIndexes.clear();
      _tryRelay = false;
      _updateActiveStream();
      _playerRevision++;
    });
  }

  void _handlePlaybackError(int failedIndex) {
    if (!mounted || failedIndex != _selectedSourceIndex) return;
    if (!_tryRelay && _activeFormat == 'hls' &&
        widget.apiBaseUrl.trim().isNotEmpty) {
      setState(() {
        _tryRelay = true;
        _playerRevision++;
      });
      return;
    }
    _failedSourceIndexes.add(failedIndex);
    final nextIndex = nextAvailableStreamSourceIndex(
      currentIndex: failedIndex,
      sourceCount: widget.streamEvent.playbackSources.length,
      failedIndexes: _failedSourceIndexes,
    );
    if (nextIndex < 0) return;

    final failedLabel = failedIndex < _sourceLabels.length
        ? _sourceLabels[failedIndex]
        : 'Server ${failedIndex + 1}';
    final nextLabel = nextIndex < _sourceLabels.length
        ? _sourceLabels[nextIndex]
        : 'Server ${nextIndex + 1}';
    setState(() {
      _tryRelay = false;
      _selectedSourceIndex = nextIndex;
      _updateActiveStream();
      _playerRevision++;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('$failedLabel stopped. Switching to $nextLabel...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<String> get _sourceLabels {
    final list = <String>[];
    for (int i = 0; i < widget.streamEvent.playbackSources.length; i++) {
      final label = widget.streamEvent.playbackSources[i].label.trim();
      list.add(label.isEmpty ? 'Server ${i + 1}' : label);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.streamEvent.displayTitle;
    final sourceLabels = _sourceLabels;
    final sourceIndex = _selectedSourceIndex;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0B12),
        borderRadius: BorderRadius.circular(widget.isFullscreen ? 0 : 16),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Control & Match Title Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF1E142B),
            child: Row(
              children: [
                if (widget.onBack != null) ...[
                  InkWell(
                    onTap: widget.onBack,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_rounded,
                            size: 16,
                            color: Color(0xFFFFD700),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'All Fixtures',
                            style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                // Live Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 6, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _reloadPlayer,
                  tooltip: 'Reload stream',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: Color(0xFF00E676),
                  ),
                ),
              ],
            ),
          ),

          // Stream Source Selector Chips (if multiple sources exist)
          if (sourceLabels.length > 1)
            Container(
              height: 34,
              color: const Color(0xFF160F20),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: sourceLabels.length,
                itemBuilder: (context, idx) {
                  final isSel = idx == _selectedSourceIndex;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _failedSourceIndexes.clear();
                        _tryRelay = false;
                        _selectedSourceIndex = idx;
                        _updateActiveStream();
                        _playerRevision++;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFFFFD700)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sourceLabels[idx],
                        style: TextStyle(
                          color: isSel
                              ? const Color(0xFF0D0B12)
                              : Colors.white70,
                          fontSize: 11,
                          fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Embedded Video Player View
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: buildWebPlatformStreamView(
                    streamUrl: _playbackUrl,
                    viewId:
                        '${widget.streamEvent.id}-$sourceIndex-$_playerInstance-$_playerRevision',
                    isDirectStream:
                        _activeFormat.isNotEmpty && _activeFormat != 'embed',
                    isEmbedStream: _activeFormat == 'embed',
                    streamFormat: _activeFormat,
                    headers: !kIsWeb && !_tryRelay &&
                            (_activeFormat == 'hls' ||
                                _activeFormat == 'dash')
                        ? _activeHeaders
                        : const {},
                    onPlaybackError: kIsWeb
                        ? null
                        : () => _handlePlaybackError(sourceIndex),
                  ),
                ),
              ],
            ),
          ),

          if (sourceLabels.isNotEmpty || widget.streamEvent.channels.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: const Color(0xFF140D1F),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.live_tv_rounded,
                        size: 14,
                        color: Color(0xFFFFD700),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Channels covering this fixture:',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 38,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: sourceLabels.isNotEmpty
                          ? sourceLabels.length
                          : widget.streamEvent.channels.length,
                      itemBuilder: (context, idx) {
                        final selectable = sourceLabels.isNotEmpty;
                        final label = selectable
                            ? sourceLabels[idx]
                            : widget.streamEvent.channels[idx];
                        final isCurrent =
                            selectable && idx == _selectedSourceIndex;
                        return GestureDetector(
                          onTap: () {
                            if (!selectable) return;
                            setState(() {
                              _failedSourceIndexes.clear();
                              _tryRelay = false;
                              _selectedSourceIndex = idx;
                              _updateActiveStream();
                              _playerRevision++;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(
                                      0xFFFFD700,
                                    ).withValues(alpha: 0.2)
                                  : const Color(0xFF221639),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCurrent
                                    ? const Color(0xFFFFD700)
                                    : Colors.white.withValues(alpha: 0.1),
                                width: isCurrent ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrent)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 5),
                                    child: Icon(
                                      Icons.graphic_eq_rounded,
                                      size: 14,
                                      color: Color(0xFFFFD700),
                                    ),
                                  ),
                                Text(
                                  label,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? const Color(0xFFFFD700)
                                        : Colors.white,
                                    fontSize: 11,
                                    fontWeight: isCurrent
                                        ? FontWeight.w900
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class InAppPlayerScreen extends StatefulWidget {
  final LiveStreamEventModel streamEvent;
  final List<LiveStreamEventModel> allEvents;
  final ValueChanged<LiveStreamEventModel>? onSelectEvent;
  final String apiBaseUrl;

  const InAppPlayerScreen({
    super.key,
    required this.streamEvent,
    this.allEvents = const [],
    this.onSelectEvent,
    this.apiBaseUrl = '',
  });

  static Future<void> open(
    BuildContext context, {
    required LiveStreamEventModel streamEvent,
    List<LiveStreamEventModel> allEvents = const [],
    ValueChanged<LiveStreamEventModel>? onSelectEvent,
    String apiBaseUrl = '',
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InAppPlayerScreen(
          streamEvent: streamEvent,
          allEvents: allEvents,
          onSelectEvent: onSelectEvent,
          apiBaseUrl: apiBaseUrl,
        ),
      ),
    );
  }

  @override
  State<InAppPlayerScreen> createState() => _InAppPlayerScreenState();
}

class _InAppPlayerScreenState extends State<InAppPlayerScreen> {
  late LiveStreamEventModel _currentEvent;
  SportsService? _sportsService;
  Timer? _streamRefreshTimer;
  bool _refreshingStream = false;
  Future<void>? _orientationTask;

  bool get _supportsMobileOrientation =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _currentEvent = widget.streamEvent;
    if (_supportsMobileOrientation) {
      _orientationTask = _enterLandscapeFullscreen();
    }
    if (widget.apiBaseUrl.trim().isNotEmpty) {
      _sportsService = SportsService(baseUrl: widget.apiBaseUrl);
    }
    _scheduleNativeStreamRefresh();
  }

  Future<void> _enterLandscapeFullscreen() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _restorePortraitMode() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _scheduleNativeStreamRefresh() {
    _streamRefreshTimer?.cancel();
    if (kIsWeb ||
        _currentEvent.playbackSources.isNotEmpty ||
        _sportsService == null) {
      return;
    }
    unawaited(_refreshStream());
    _streamRefreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_refreshStream()),
    );
  }

  Future<void> _refreshStream() async {
    if (_refreshingStream || _sportsService == null || !mounted) return;
    _refreshingStream = true;
    try {
      final refreshed = await _sportsService!.getStreamDetail(
        _currentEvent.id,
        timeout: const Duration(seconds: 12),
      );
      if (!mounted || refreshed == null) return;
      setState(() => _currentEvent = refreshed);
      if (refreshed.playbackSources.isNotEmpty) {
        _streamRefreshTimer?.cancel();
        _streamRefreshTimer = null;
      }
    } finally {
      _refreshingStream = false;
    }
  }

  @override
  void dispose() {
    _streamRefreshTimer?.cancel();
    if (_supportsMobileOrientation) {
      unawaited(
        (_orientationTask ?? Future<void>.value()).whenComplete(
          _restorePortraitMode,
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B12),
      body: SafeArea(
        child: InAppStreamPlayer(
          streamEvent: _currentEvent,
          allEvents: widget.allEvents,
          isFullscreen: true,
          apiBaseUrl: widget.apiBaseUrl,
          onRefreshStream: _refreshStream,
          onBack: () => Navigator.of(context).pop(),
          onSelectEvent: (ev) {
            setState(() => _currentEvent = ev);
            _scheduleNativeStreamRefresh();
            if (widget.onSelectEvent != null) {
              widget.onSelectEvent!(ev);
            }
          },
        ),
      ),
    );
  }
}
