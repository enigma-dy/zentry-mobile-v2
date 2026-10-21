import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/ace_channel_model.dart';

class AceStreamPlayerScreen extends StatefulWidget {
  final AceChannelModel channel;
  final String engineHost;
  final int enginePort;

  const AceStreamPlayerScreen({
    super.key,
    required this.channel,
    this.engineHost = '127.0.0.1',
    this.enginePort = 6878,
  });

  static Future<void> open(
    BuildContext context, {
    required AceChannelModel channel,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AceStreamPlayerScreen(channel: channel),
      ),
    );
  }

  @override
  State<AceStreamPlayerScreen> createState() => _AceStreamPlayerScreenState();
}

class _AceStreamPlayerScreenState extends State<AceStreamPlayerScreen> {
  VideoPlayerController? _controller;
  String? _error;
  bool _connecting = true;

  String get _localUrl => widget.channel.localStreamUrl(
    host: widget.engineHost,
    port: widget.enginePort,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    if (mounted) {
      setState(() {
        _connecting = true;
        _error = null;
      });
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(_localUrl));
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 35));
      await controller.play();
      if (mounted && identical(_controller, controller)) {
        setState(() => _connecting = false);
      }
    } catch (_) {
      await controller.dispose();
      if (mounted && identical(_controller, controller)) {
        setState(() {
          _controller = null;
          _connecting = false;
          _error = kIsWeb
              ? 'The local Ace Engine could not be reached. Browsers may also block localhost HTTP playback from an HTTPS page.'
              : 'Ace Stream Engine is not running or this channel currently has no peers.';
        });
      }
    }
  }

  Future<void> _openAcePlayer() async {
    final uri = Uri.parse(widget.channel.aceUri);
    final launched = await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No AceStream application was found.')),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E142B),
        foregroundColor: Colors.white,
        title: Text(
          widget.channel.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _connect,
            tooltip: 'Reconnect',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: controller != null && controller.value.isInitialized
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: controller.value.aspectRatio > 0
                          ? controller.value.aspectRatio
                          : 16 / 9,
                      child: VideoPlayer(controller),
                    ),
                    VideoProgressIndicator(
                      controller,
                      allowScrubbing: false,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFFFFD700),
                      ),
                    ),
                    IconButton(
                      iconSize: 42,
                      color: const Color(0xFFFFD700),
                      onPressed: () {
                        setState(() {
                          controller.value.isPlaying
                              ? controller.pause()
                              : controller.play();
                        });
                      },
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_connecting)
                        const CircularProgressIndicator(
                          color: Color(0xFFFFD700),
                        )
                      else
                        const Icon(
                          Icons.tv_off_rounded,
                          color: Color(0xFFFFD700),
                          size: 52,
                        ),
                      const SizedBox(height: 16),
                      Text(
                        _connecting
                            ? 'Connecting to the local Ace Engine…'
                            : (_error ?? 'Unable to start this channel.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (!_connecting) ...[
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _connect,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry Local Engine'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _openAcePlayer,
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('Open Ace Player'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
