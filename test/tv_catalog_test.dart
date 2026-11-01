import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/live_tv/tv_catalog.dart';

void main() {
  final origin = Uri.parse('https://www.90minutes.pro/');

  test('uses the provider renderer for 90minutes embeds and HLS pages', () {
    expect(
      TvSource(
        'TV',
        origin.resolve('/player/hls/?url=%2Fdl%2F3.m3u8'),
      ).needsProviderPlayer,
      isTrue,
    );
    expect(
      TvSource('TV', origin.resolve('/embed/?id=nhl')).needsProviderPlayer,
      isTrue,
    );
    expect(
      TvSource(
        'TV',
        Uri.parse('https://ntv.st/player/hls/'),
      ).needsProviderPlayer,
      isFalse,
    );
    expect(
      TvSource(
        'TV',
        Uri.parse('https://www.90minutes.pro.example/player/hls/'),
      ).needsProviderPlayer,
      isFalse,
    );
  });

  test(
    'reads grouped guide, epoch seconds, relative embeds and alternate servers',
    () {
      final listings = parseTvCatalog({
        'success': true,
        'streams': [
          {
            'category': 'hockey',
            'streams': [
              {
                'id': 'nhl-network',
                'name': 'NHL Network',
                'league': 'NHL',
                'status': 'live',
                'always_live': 1,
                'starts_at': 1792763060,
                'sources': [
                  {'name': 'HD', 'embed': '/embed/?id=nhl%2Fnetwork'},
                  {'name': 'SD', 'embed': 'https://embed.example/nhl'},
                  {'name': 'Duplicate', 'embed': '/embed/?id=nhl%2Fnetwork'},
                  {'name': 'Unsafe', 'embed': 'javascript:alert(1)'},
                ],
              },
              {
                'id': 'match',
                'name': 'Tomorrow’s match',
                'status': 'upcoming',
                'embed': '/embed/?id=match',
              },
              {'id': 'invalid', 'name': ''},
            ],
          },
        ],
      }, origin);
      expect(listings, hasLength(2));
      final channel = listings.first;
      expect(channel.name, 'NHL Network');
      expect(channel.category, 'hockey');
      expect(channel.isLive, isTrue);
      expect(channel.canWatch, isTrue);
      expect(channel.startsAt!.millisecondsSinceEpoch, 1792763060000);
      expect(channel.sources, hasLength(2));
      expect(
        channel.sources.first.url.toString(),
        'https://www.90minutes.pro/embed/?id=nhl%2Fnetwork',
      );
      expect(channel.sources.first.referer, origin);
      expect(listings.last.isUpcoming, isTrue);
      expect(listings.last.canWatch, isFalse);
    },
  );

  test(
    'rejects unsuccessful feeds and does not play unsafe or offline entries',
    () {
      expect(
        () => parseTvCatalog({'success': false, 'streams': []}, origin),
        throwsFormatException,
      );
      final listings = parseTvCatalog({
        'success': true,
        'streams': [
          {
            'category': 'football',
            'streams': [
              {
                'id': 'unsafe',
                'name': 'Unsafe',
                'status': 'live',
                'embed': 'file:///private/video',
              },
              {
                'id': 'offline',
                'name': 'Offline',
                'status': 'offline',
                'embed': '/embed/offline',
              },
            ],
          },
        ],
      }, origin);
      expect(listings.every((listing) => !listing.canWatch), isTrue);
    },
  );
}
