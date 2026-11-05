import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:predict/src/services/sports_service.dart';

http.Response feed({bool loading = false}) => http.Response(
  jsonEncode({
    'success': true,
    'data': {'items': [], 'total': 0, 'loading': loading},
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('temporary mapping failures are retried rather than cached', () async {
    var calls = 0;
    final service = SportsService(
      baseUrl: 'https://api.test',
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'items': [
                if (calls == 1)
                  {'sporty_sync_reason': 'fixture_snapshot_unavailable'}
                else
                  {'sporty_event_id': 'sr:match:74173022'},
              ],
              'total': 1,
              'loading': false,
            },
          }),
          200,
        );
      }),
    );
    await service.getPredictionFeed(sport: 'Football');
    final recovered = await service.getPredictionFeed(sport: 'Football');
    expect(
      (recovered['items'] as List).single['sporty_event_id'],
      'sr:match:74173022',
    );
    await service.getPredictionFeed(sport: 'Football');
    expect(calls, 2);
  });
  test('all sport tabs retain their own sport/date query', () async {
    final requests = <Uri>[];
    final service = SportsService(
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        requests.add(request.url);
        return feed();
      }),
    );
    for (final sport in [
      'Football',
      'Basketball',
      'Ice Hockey',
      'American Football',
      'Tennis',
      'Baseball',
      'Volleyball',
      'Handball',
      'Cricket',
    ]) {
      await service.getPredictionFeed(sport: sport, date: '2026-11-02');
      expect(requests.last.path, '/api/v1/predictions/feed');
      expect(requests.last.queryParameters['sport'], sport);
      expect(requests.last.queryParameters['date'], '2026-11-02');
    }
    expect(requests.length, 9);
  });
  test('Best Picks and Player Props use their dedicated routes', () async {
    final requests = <Uri>[];
    final service = SportsService(
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        requests.add(request.url);
        return feed();
      }),
    );
    await service.getBestPicks(date: '2026-11-02');
    await service.getPlayerProps(date: '2026-11-02');
    expect(requests.map((uri) => uri.path), [
      '/api/v1/predictions/best-picks',
      '/api/v1/predictions/player-props',
    ]);
    expect(
      requests.every((uri) => uri.queryParameters['date'] == '2026-11-02'),
      true,
    );
  });
  test(
    'concurrent duplicate requests share one call and completed tabs are reused',
    () async {
      final response = Completer<http.Response>();
      var calls = 0;
      final service = SportsService(
        baseUrl: 'https://api.test',
        client: MockClient((_) {
          calls++;
          return response.future;
        }),
      );
      final first = service.getPredictionFeed(sport: 'Football');
      final second = service.getPredictionFeed(sport: 'Football');
      response.complete(feed());
      await Future.wait([first, second]);
      await service.getPredictionFeed(sport: 'Football');
      expect(calls, 1);
      service.clearPredictionCache();
      await service.getPredictionFeed(sport: 'Football');
      expect(calls, 2);
    },
  );
  test('warming responses are not pinned in the client cache', () async {
    var calls = 0;
    final service = SportsService(
      baseUrl: 'https://api.test',
      client: MockClient((_) async {
        calls++;
        return feed(loading: true);
      }),
    );
    await service.getBestPicks();
    await service.getBestPicks();
    expect(calls, 2);
  });
  test(
    'a stalled prediction request has a deadline and can be retried',
    () async {
      var calls = 0;
      final service = SportsService(
        baseUrl: 'https://api.test',
        predictionTimeout: const Duration(milliseconds: 20),
        client: MockClient((_) {
          calls++;
          return Completer<http.Response>().future;
        }),
      );
      await expectLater(
        service.getPredictionFeed(sport: 'Football'),
        throwsA(
          isA<SportsException>().having((e) => e.statusCode, 'status', 408),
        ),
      );
      await expectLater(
        service.getPredictionFeed(sport: 'Football'),
        throwsA(
          isA<SportsException>().having((e) => e.statusCode, 'status', 408),
        ),
      );
      expect(calls, 2);
    },
  );
  test(
    'Cloudflare blocks and authentication errors are surfaced, never cached',
    () async {
      var calls = 0;
      final service = SportsService(
        baseUrl: 'https://api.test',
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('error code: 1010', 403)
              : http.Response(
                  jsonEncode({'message': 'Missing Authorization header'}),
                  401,
                );
        }),
      );
      await expectLater(
        service.getPlayerProps(),
        throwsA(
          isA<SportsException>()
              .having((e) => e.statusCode, 'status', 403)
              .having(
                (e) => e.message,
                'message',
                contains('security service'),
              ),
        ),
      );
      await expectLater(
        service.getPlayerProps(),
        throwsA(
          isA<SportsException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
      expect(calls, 2);
    },
  );
}
