import 'package:flutter/material.dart';

import 'player_orientation.dart';
import 'provider_player_page.dart';
import 'server_playback_session.dart';
import 'stream_page.dart';
import 'tv_catalog.dart';

typedef WatchPlayerBuilder =
    Widget Function(
      BuildContext context,
      TvSource source,
      VoidCallback onFailed,
      Widget serverControl,
    );

/// Owns server selection inside one route, after the single pre-watch ad.
class WatchPage extends StatefulWidget {
  const WatchPage({
    super.key,
    required this.listing,
    required this.initialSource,
    this.playerBuilder,
  });
  final TvListing listing;
  final TvSource initialSource;
  final WatchPlayerBuilder? playerBuilder;

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage>
    with PlayerOrientation<WatchPage> {
  late final _session = ServerPlaybackSession(
    widget.listing.sources,
    widget.initialSource,
  );

  void _failed(int generation) {
    if (!mounted) return;
    if (_session.fail(generation)) setState(() {});
  }

  Widget _serverControl() => PopupMenuButton<int>(
    tooltip: 'Switch server',
    icon: const Icon(Icons.dns_outlined),
    onSelected: (index) {
      if (_session.select(index)) setState(() {});
    },
    itemBuilder: (_) => [
      for (var i = 0; i < _session.sources.length; i++)
        CheckedPopupMenuItem<int>(
          value: i,
          checked: i == _session.currentIndex,
          child: Text(_session.sources[i].name),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final generation = _session.generation;
    final source = _session.current;
    final control = _serverControl();
    if (_session.exhausted) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.listing.name),
          actions: [control, rotationButton(context)],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('None of the servers could play this stream.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => setState(_session.retry),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry servers'),
              ),
            ],
          ),
        ),
      );
    }
    void onFailed() => _failed(generation);
    return KeyedSubtree(
      key: ValueKey(generation),
      child:
          widget.playerBuilder?.call(context, source, onFailed, control) ??
          (source.needsProviderPlayer
              ? ProviderPlayerPage(
                  title: widget.listing.name,
                  source: source,
                  onSourceFailed: onFailed,
                  serverControl: control,
                  manageOrientation: false,
                )
              : StreamPage(
                  initialUrl: source.url.toString(),
                  displayTitle: widget.listing.name,
                  sourceLabel: source.name,
                  initialReferer: source.referer?.toString(),
                  onSourceFailed: onFailed,
                  serverControl: control,
                  manageOrientation: false,
                )),
    );
  }
}
