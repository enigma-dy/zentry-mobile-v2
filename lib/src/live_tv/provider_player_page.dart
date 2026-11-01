import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_catalog.dart';
import 'player_orientation.dart';

/// Hosts only the provider's dedicated video embed, not the guide website.
class ProviderPlayerPage extends StatefulWidget {
  const ProviderPlayerPage({
    super.key,
    required this.title,
    required this.source,
    this.onSourceFailed,
    this.serverControl,
    this.manageOrientation = true,
  });
  final String title;
  final TvSource source;
  final VoidCallback? onSourceFailed;
  final Widget? serverControl;
  final bool manageOrientation;

  @override
  State<ProviderPlayerPage> createState() => _ProviderPlayerPageState();
}

class _ProviderPlayerPageState extends State<ProviderPlayerPage>
    with WidgetsBindingObserver, PlayerOrientation<ProviderPlayerPage> {
  @override
  bool get managesPlayerOrientation => widget.manageOrientation;
  bool _reportedFailure = false;
  bool _background = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _background = true;
      _timeout?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _background = false;
      if (!_playing && !_failed) _armTimeout();
    }
  }

  void _fail() {
    if (!mounted || _background || _reportedFailure) return;
    _reportedFailure = true;
    _timeout?.cancel();
    setState(() {
      _loading = false;
      _failed = true;
      _playing = false;
    });
    widget.onSourceFailed?.call();
  }

  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 45), () {
      if (!_playing) _fail();
    });
  }

  MethodChannel? _channel;
  Timer? _timeout;
  bool _loading = true;
  bool _failed = false;
  bool _playing = false;
  int _generation = 0;

  void _created(int id) {
    final channel = MethodChannel('provider_player/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted || _channel != channel || _reportedFailure) return;
      if (call.method == 'playing') {
        _timeout?.cancel();
        setState(() {
          _loading = false;
          _failed = false;
          _playing = true;
        });
      } else if (call.method == 'ready') {
        // A loaded document is not proof that the video has started.
        setState(() => _loading = false);
      } else if (call.method == 'error') {
        _fail();
      } else if (call.method == 'fullscreen') {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    });
    _armTimeout();
    unawaited(
      channel.invokeMethod<void>('start').catchError((Object _) {
        if (_channel == channel) _fail();
      }),
    );
  }

  void _retry() {
    _timeout?.cancel();
    _channel?.setMethodCallHandler(null);
    _channel = null;
    setState(() {
      _generation++;
      _reportedFailure = false;
      _loading = true;
      _failed = false;
      _playing = false;
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _channel?.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: landscape
          ? null
          : AppBar(
              title: Text(widget.title),
              actions: [
                if (widget.serverControl != null) widget.serverControl!,
                rotationButton(context),
              ],
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final height = landscape
              ? constraints.maxHeight
              : constraints.maxWidth * 9 / 16;
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AndroidView(
                      key: ValueKey(_generation),
                      viewType: 'provider_player',
                      creationParams: {
                        'url': widget.source.url.toString(),
                        if (widget.source.referer != null)
                          'referer': widget.source.referer.toString(),
                      },
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: _created,
                    ),
                    if (_loading)
                      const ColoredBox(
                        color: Colors.black,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_failed)
                      ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: FilledButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry playback'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!landscape)
                Positioned(
                  top: height,
                  left: 20,
                  right: 20,
                  bottom: 0,
                  child: ListView(
                    children: [
                      const SizedBox(height: 16),
                      Text(widget.source.name),
                      const SizedBox(height: 16),
                      Text(
                        _failed
                            ? 'This server could not load. Retry or choose another server.'
                            : _loading
                            ? 'Connecting to the stream...'
                            : _playing
                            ? 'Live'
                            : 'Use the player controls to start watching.',
                      ),
                    ],
                  ),
                ),
              if (landscape)
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
                          if (widget.serverControl != null)
                            widget.serverControl!,
                          rotationButton(context),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
