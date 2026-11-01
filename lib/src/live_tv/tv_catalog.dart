class TvSource {
  const TvSource(this.name, this.url, {this.referer});
  final String name;
  final Uri url;
  final Uri? referer;
  // This provider's HLS player decodes image-wrapped segments in JavaScript.
  // Its raw playlist cannot be handed directly to the native video player.
  bool get needsProviderPlayer =>
      ['www.90minutes.pro', '90minutes.pro'].contains(url.host.toLowerCase()) &&
      (url.path == '/embed' ||
          url.path.startsWith('/embed/') ||
          url.path == '/player/hls' ||
          url.path.startsWith('/player/hls/'));
}

class TvListing {
  const TvListing({
    required this.id,
    required this.name,
    required this.category,
    required this.league,
    required this.status,
    required this.sources,
    this.poster,
    this.startsAt,
    this.alwaysLive = false,
  });

  final String id;
  final String name;
  final String category;
  final String league;
  final String status;
  final List<TvSource> sources;
  final Uri? poster;
  final DateTime? startsAt;
  final bool alwaysLive;
  bool get isLive => alwaysLive || status == 'live';
  bool get isUpcoming => !isLive && status == 'upcoming';
  bool get canWatch => isLive && sources.isNotEmpty;
}

Uri? _webUrl(Object? value, Uri origin) {
  if (value is! String || value.trim().isEmpty) return null;
  final parsed = Uri.tryParse(value.trim());
  if (parsed == null) return null;
  final url = origin.resolveUri(parsed);
  return ['http', 'https'].contains(url.scheme) && url.host.isNotEmpty
      ? url
      : null;
}

List<TvListing> parseTvCatalog(Map<String, dynamic> data, Uri origin) {
  if (data['success'] != true || data['streams'] is! List) {
    throw const FormatException(
      'The guide provider returned an invalid catalog.',
    );
  }
  final listings = <String, TvListing>{};
  for (final group in data['streams'] as List) {
    if (group is! Map || group['streams'] is! List) continue;
    for (final item in group['streams'] as List) {
      if (item is! Map) continue;
      final id = item['id']?.toString().trim() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final sources = <TvSource>[];
      final urls = <String>{};
      final rawSources = item['sources'];
      if (rawSources is List) {
        for (final source in rawSources) {
          if (source is! Map) continue;
          final url = _webUrl(source['embed'], origin);
          if (url == null || !urls.add(url.toString())) continue;
          sources.add(
            TvSource(
              source['name']?.toString() ?? 'Server ${sources.length + 1}',
              url,
              referer: _webUrl(source['referer'], origin) ?? origin,
            ),
          );
        }
      }
      if (sources.isEmpty) {
        final url = _webUrl(item['embed'] ?? item['iframe'], origin);
        if (url != null) {
          sources.add(TvSource('Main stream', url, referer: origin));
        }
      }
      final seconds = num.tryParse(item['starts_at']?.toString() ?? '');
      listings.putIfAbsent(
        id,
        () => TvListing(
          id: id,
          name: name,
          category: (item['category_name'] ?? group['category'] ?? 'other')
              .toString(),
          league: item['league']?.toString() ?? '',
          status: item['status']?.toString().toLowerCase() ?? 'unknown',
          sources: List.unmodifiable(sources),
          poster: _webUrl(item['poster'], origin),
          startsAt: seconds == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (seconds * 1000).round(),
                  isUtc: true,
                ),
          alwaysLive:
              item['always_live'] == true ||
              item['always_live']?.toString() == '1',
        ),
      );
    }
  }
  final result = listings.values.toList();
  result.sort((a, b) {
    if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
    if (a.isUpcoming &&
        b.isUpcoming &&
        a.startsAt != null &&
        b.startsAt != null) {
      final order = a.startsAt!.compareTo(b.startsAt!);
      if (order != 0) return order;
    }
    return a.name.compareTo(b.name);
  });
  return result;
}

class CatalogUnavailable implements Exception {
  const CatalogUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

String categoryLabel(String category) => switch (category) {
  '24/7-streams' => '24/7 TV',
  'american-football' => 'American football',
  'motor-sports' => 'Motorsport',
  'afl' => 'AFL',
  _ =>
    category
        .split('-')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' '),
};
