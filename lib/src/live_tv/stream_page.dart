import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'stream_resolver.dart';
import 'playback_recovery.dart';
import 'playback_health.dart';
import 'player_orientation.dart';

class StreamPage extends StatefulWidget {
  const StreamPage({
    super.key,
    this.initialUrl,
    this.displayTitle,
    this.sourceLabel,
    this.initialReferer,
    this.onSourceFailed,
    this.serverControl,
    this.manageOrientation = true,
  });
  final String? initialUrl;
  final String? displayTitle;
  final String? sourceLabel;
  final String? initialReferer;
  final VoidCallback? onSourceFailed;
  final Widget? serverControl;
  final bool manageOrientation;

  @override
  State<StreamPage> createState() => _StreamPageState();
}

class _StreamPageState extends State<StreamPage>
    with WidgetsBindingObserver, PlayerOrientation<StreamPage> {
  @override
  bool get managesPlayerOrientation => widget.manageOrientation;

  final _health = PlaybackHealth();
  bool _reportedFailure = false;
  void _fail() {
    if (!mounted || _resolutionCancelled || _reportedFailure) return;
    _reportedFailure = true;
    _wantsPlayback = false;
    widget.onSourceFailed?.call();
  }

  late final TextEditingController _input;
  VideoPlayerController? _player;
  bool _loading = false;
  bool _resolutionCancelled = false;
  bool _wantsPlayback = false;
  bool _browserPlayback = false;
  String? _activeInput;
  Timer? _playbackWatchdog;
  final _recovery = PlaybackRecovery();
  String? _error;
  String _status = 'Enter a webpage URL to extract and play its stream.';
  String? _title;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(
      text:
          widget.initialUrl ??
          'https://ntv.st/watch/kobra/illawarra-hawks-vs-sydney-kings-2487919',
    );
    _title = widget.displayTitle;
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _play();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _resolutionCancelled = true;
      _wantsPlayback = false;
      cancelStreamDetection().catchError((Object _) {});
      _player?.pause();
    }
  }

  void _checkPlayback() {
    final player = _player;
    if (!mounted || _loading || _resolutionCancelled || player == null) return;
    final value = player.value;
    final atEnd =
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying &&
        !value.isBuffering &&
        !value.hasError;
    if (widget.onSourceFailed != null) {
      if (_health.hasFailed(
        position: value.position,
        wantsPlayback: _wantsPlayback,
        hasError: value.hasError,
        atEnd: atEnd,
        now: DateTime.now(),
      )) {
        _fail();
      }
      return;
    }
    if (_recovery.shouldReconnect(
      position: value.position,
      wantsPlayback: _wantsPlayback,
      hasError: value.hasError,
      atEnd:
          value.duration > Duration.zero &&
          value.position >= value.duration &&
          !value.isPlaying &&
          !value.isBuffering &&
          !value.hasError,
      now: DateTime.now(),
    )) {
      unawaited(_play(reconnecting: true));
    }
  }

  Future<void> _play({bool reconnecting = false}) async {
    if (_loading) return;
    if (!reconnecting) {
      _recovery.reset();
      _activeInput = _input.text;
    }
    _wantsPlayback = false;
    _health.reset();
    _reportedFailure = false;
    _resolutionCancelled = false;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _status = reconnecting ? 'Reconnecting stream…' : 'Finding stream…';
    });
    VideoPlayerController? pending;
    var started = false;
    var retryInitialization = false;
    try {
      parsePageUrl(_activeInput!);
      started = true;
      await _player?.pause();
      if (!mounted || _resolutionCancelled) return;
      await cancelStreamDetection().catchError((Object _) {});
      if (!mounted || _resolutionCancelled) return;
      final stream = await resolvePage(
        _activeInput!,
        shouldContinue: () => mounted && !_resolutionCancelled,
        preferBrowser:
            widget.initialUrl != null || reconnecting && _browserPlayback,
        referer: widget.initialReferer,
      );
      if (!mounted || _resolutionCancelled) return;
      setState(() => _status = 'Opening video…');
      _browserPlayback = stream.usesBrowser;
      final next = VideoPlayerController.networkUrl(
        stream.url,
        httpHeaders: stream.headers,
      );
      pending = next;
      await next.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || _resolutionCancelled) return;
      await next.play();
      if (!mounted || _resolutionCancelled) return;
      await completeStreamHandoff().catchError((Object _) {});
      if (!mounted || _resolutionCancelled) return;
      final previous = _player;
      previous?.removeListener(_checkPlayback);
      next.addListener(_checkPlayback);
      _wantsPlayback = true;
      _browserPlayback = stream.usesBrowser;
      setState(() {
        _player = next;
        _title = widget.displayTitle ?? stream.title;
        _status = 'Stream ready';
      });
      pending = null;
      await previous?.dispose();
      _playbackWatchdog ??= Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkPlayback(),
      );
    } catch (error) {
      if (started && mounted && !_resolutionCancelled) {
        await cancelStreamDetection().catchError((Object _) {});
      }
      retryInitialization =
          mounted &&
          !_resolutionCancelled &&
          widget.onSourceFailed == null &&
          pending != null &&
          _recovery.shouldReconnect(
            position: Duration.zero,
            wantsPlayback: true,
            hasError: true,
            atEnd: false,
            now: DateTime.now(),
          );
      if (mounted && !retryInitialization) {
        setState(() {
          _error = error.toString();
          _status = 'Unable to play this page. Check the URL or try another.';
        });
      }
    } finally {
      await pending?.dispose();
      if (mounted) setState(() => _loading = false);
    }
    if (_error != null && widget.onSourceFailed != null) _fail();
    if (retryInitialization && mounted && !_resolutionCancelled) {
      await _play(reconnecting: true);
    }
  }

  @override
  void dispose() {
    _resolutionCancelled = true;
    _playbackWatchdog?.cancel();
    _player?.removeListener(_checkPlayback);
    cancelStreamDetection().catchError((Object _) {});
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (MediaQuery.orientationOf(context) == Orientation.landscape) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (player != null)
              Center(
                child: AspectRatio(
                  aspectRatio: player.value.aspectRatio > 0
                      ? player.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(player),
                ),
              )
            else
              Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : FilledButton(
                        onPressed: _play,
                        child: const Text('Retry playback'),
                      ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: Material(
                  color: Colors.black54,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.serverControl != null) widget.serverControl!,
                      rotationButton(context),
                    ],
                  ),
                ),
              ),
            ),
            if (player != null)
              Positioned(
                bottom: 8,
                left: 8,
                child: SafeArea(
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: player,
                    builder: (context, value, _) => Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: value.isPlaying ? 'Pause' : 'Play',
                        icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                        onPressed: () async {
                          _wantsPlayback = !value.isPlaying;
                          if (_wantsPlayback) {
                            await player.play();
                          } else {
                            await player.pause();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayTitle ?? 'Open a link'),
        actions: [
          if (widget.serverControl != null) widget.serverControl!,
          rotationButton(context),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.initialUrl == null) ...[
                TextField(
                  controller: _input,
                  enabled: !_loading,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Video webpage URL',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _play(),
                ),
              ] else ...[
                if (widget.sourceLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      widget.sourceLabel!,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),
                if (player == null)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: _loading
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.live_tv, size: 48),
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _play,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry playback'),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              if (widget.initialUrl == null)
                FilledButton.icon(
                  onPressed: _loading ? null : _play,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_loading ? 'Loading…' : 'Extract and play'),
                ),
              const SizedBox(height: 12),
              Text(_status),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SelectableText(
                    widget.initialUrl == null
                        ? _error!
                        : 'This stream couldn’t start. Retry playback or go back and choose another server.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_title != null) ...[
                const SizedBox(height: 20),
                Text(_title!, style: Theme.of(context).textTheme.titleLarge),
              ],
              if (player != null)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: player,
                  builder: (context, value, _) => Column(
                    children: [
                      const SizedBox(height: 12),
                      AspectRatio(
                        aspectRatio: value.aspectRatio > 0
                            ? value.aspectRatio
                            : 16 / 9,
                        child: ColoredBox(
                          color: Colors.black,
                          child: VideoPlayer(player),
                        ),
                      ),
                      if (value.isBuffering) const LinearProgressIndicator(),
                      if (value.hasError)
                        Text(
                          widget.initialUrl == null
                              ? value.errorDescription ?? 'Playback failed.'
                              : 'Playback was interrupted. Retry if it does not reconnect.',
                        ),
                      VideoProgressIndicator(player, allowScrubbing: !_loading),
                      IconButton(
                        tooltip: value.isPlaying ? 'Pause' : 'Play',
                        onPressed: _loading
                            ? null
                            : () async {
                                try {
                                  if (value.isPlaying) {
                                    _wantsPlayback = false;
                                    await player.pause();
                                  } else if (_resolutionCancelled) {
                                    await _play();
                                  } else {
                                    _wantsPlayback = true;
                                    await player.play();
                                  }
                                } catch (error) {
                                  if (mounted) {
                                    setState(() => _error = error.toString());
                                  }
                                }
                              },
                        icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
