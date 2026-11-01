import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ads/pre_watch_ad.dart';
import '../ads/watch_ad_gate.dart';
import '../services/sports_service.dart';
import 'catalog_page.dart';
import 'tv_catalog.dart';
import 'watch_page.dart';

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key, required this.service});
  final SportsService service;

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  final _watchGate = WatchAdGate();
  bool get _canPlay =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_canPlay) unawaited(preparePreWatchAd());
  }

  Future<void> _watch(TvListing listing, TvSource source) async {
    if (!_canPlay) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Live TV playback is available in the Android app.'),
        ),
      );
      return;
    }
    try {
      await _watchGate.open(
        showAd: showPreWatchAd,
        openPlayer: () async {
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  WatchPage(listing: listing, initialSource: source),
            ),
          );
        },
      );
    } finally {
      if (mounted) unawaited(preparePreWatchAd());
    }
  }

  @override
  Widget build(BuildContext context) => CatalogPage(
    loadCatalog: () async {
      final data = await widget.service.getTvCatalog();
      final origin = Uri.parse(
        data['origin']?.toString() ?? 'https://www.90minutes.pro/',
      );
      return parseTvCatalog(data, origin);
    },
    onWatch: _watch,
  );
}
