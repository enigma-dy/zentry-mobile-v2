import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:predict/src/models/sport_model.dart';
import 'package:predict/src/models/league_model.dart';
import 'package:predict/src/models/fixture_model.dart';
import 'package:predict/src/models/stream_model.dart';
import 'package:predict/src/services/sports_service.dart';

void main() {
  group('Sports & Fixtures Models Tests', () {
    test('finished fixture statuses are normalized', () {
      for (final status in [
        'finished',
        'ended',
        'FT',
        'completed',
        'full time',
      ]) {
        final fixture = FixtureModel.fromJson({
          'id': status,
          'status': status,
          'match_time': '2026-10-15T12:00:00Z',
        });
        expect(fixture.isFinished, isTrue, reason: status);
      }
    });

    test('BinTV playback sources are permanently excluded', () {
      final event = LiveStreamEventModel.fromJson({
        'id': 'stream-1',
        'streams': [
          {'url': 'https://media.example.com/live.m3u8'},
          {'url': 'https://bintv.example/live.m3u8'},
        ],
        'players': [
          {'embed_url': 'https://bintv-sources.pages.dev/player/1'},
          {'embed_url': 'https://player.example.com/embed/1'},
        ],
      });

      expect(event.playbackSources.map((source) => source.url), [
        'https://media.example.com/live.m3u8',
        'https://player.example.com/embed/1',
      ]);
    });

    test('SportModel deserialization with key and is_active', () {
      final jsonSample = {
        "id": 1,
        "name": "Football",
        "key": "football",
        "is_active": true,
        "icon_url": "http://example.com/football.png",
      };

      final sport = SportModel.fromJson(jsonSample);
      expect(sport.id, equals(1));
      expect(sport.name, equals("Football"));
      expect(sport.key, equals("football"));
      expect(sport.slug, equals("football"));
      expect(sport.active, isTrue);
      expect(sport.iconUrl, equals("http://example.com/football.png"));

      final jsonOut = sport.toJson();
      expect(jsonOut['id'], equals(1));
      expect(jsonOut['key'], equals("football"));
      expect(jsonOut['is_active'], isTrue);
    });

    test('LeagueModel deserialization and serialization', () {
      final jsonSample = {
        "id": "2d8f99e4-8a4b-47e1-8d2a-112233445566",
        "sport_id": 1,
        "name": "Premier League",
        "country": "England",
        "category": "Top Tier",
        "match_count": 10,
      };

      final league = LeagueModel.fromJson(jsonSample);
      expect(league.id, equals("2d8f99e4-8a4b-47e1-8d2a-112233445566"));
      expect(league.sportId, equals(1));
      expect(league.name, equals("Premier League"));
      expect(league.matchCount, equals(10));
    });

    test('FixtureModel deserialization', () {
      final jsonSample = {
        "id": "ddeaa7cc-459f-473d-9e08-96ef09245949",
        "sport_id": 1,
        "league_name": "Premier League",
        "country": "England",
        "home_team": "Arsenal FC",
        "away_team": "Chelsea FC",
        "normalized_home": "arsenal fc",
        "normalized_away": "chelsea fc",
        "match_time": "2026-09-20T16:30:00Z",
        "status": "prematch",
        "home_score": 0,
        "away_score": 0,
        "period_scores": "{}",
        "stats": "{}",
      };

      final fixture = FixtureModel.fromJson(jsonSample);
      expect(fixture.id, equals("ddeaa7cc-459f-473d-9e08-96ef09245949"));
      expect(fixture.homeTeam, equals("Arsenal FC"));
      expect(fixture.awayTeam, equals("Chelsea FC"));
      expect(fixture.status, equals("prematch"));
    });

    test('PredictionModel maps source-backed feed fields without defaults', () {
      final prediction = PredictionModel.fromJson({
        'id': '9edd0bf4-ce69-4d3f-ae6d-9a86631834b5',
        'selection': 'Over 2.5',
        'market': 'Totals',
        'tag': '2+ Odds',
        'odds': 2.15,
        'probability': 61,
        'source': 'betmines',
        'is_player_prop': false,
      });

      expect(prediction.prediction, 'Over 2.5');
      expect(prediction.effectiveOdds, '2.15');
      expect(prediction.probability, 61);
      expect(prediction.provider, 'betmines');
      expect(prediction.market, 'Totals');
      expect(prediction.tag, '2+ Odds');
      expect(prediction.isPlayerProp, isFalse);

      final missing = PredictionModel.fromJson({'id': 'missing'});
      expect(missing.effectiveOdds, isEmpty);
      expect(missing.probability, 0);
      expect(missing.provider, isEmpty);
    });
  });

  group('SportsService API Tests', () {
    test('getSports parses list with new keys schema', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/sports'));
        return http.Response(
          jsonEncode({
            "success": true,
            "data": [
              {
                "id": 1,
                "name": "Football",
                "key": "football",
                "is_active": true,
                "icon_url": "",
              },
              {
                "id": 2,
                "name": "Basketball",
                "key": "basketball",
                "is_active": true,
                "icon_url": "",
              },
            ],
          }),
          200,
        );
      });

      final service = SportsService(baseUrl: 'http://localhost:8080');
      final sports = await service.getSports(client: mockClient);

      expect(sports.length, equals(2));
      expect(sports[0].name, equals('Football'));
      expect(sports[0].key, equals('football'));
      expect(sports[1].key, equals('basketball'));
    });

    test('getFixturesPaginated parses metadata & data list', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/fixtures'));
        expect(request.url.queryParameters['sport_id'], equals('1'));
        expect(request.url.queryParameters['page'], equals('1'));
        expect(request.url.queryParameters['page_size'], equals('20'));
        expect(request.url.queryParameters['query'], equals('Arsenal'));

        return http.Response(
          jsonEncode({
            "success": true,
            "count": 1,
            "total": 415,
            "page": 1,
            "page_size": 20,
            "total_pages": 21,
            "data": [
              {
                "id": "ddeaa7cc-459f-473d-9e08-96ef09245949",
                "sport_id": 1,
                "league_name": "Premier League",
                "country": "England",
                "home_team": "Arsenal FC",
                "away_team": "Chelsea FC",
                "match_time": "2026-09-20T16:30:00Z",
                "status": "prematch",
              },
            ],
          }),
          200,
        );
      });

      final service = SportsService(baseUrl: 'http://localhost:8080');
      final res = await service.getFixturesPaginated(
        sportId: 1,
        page: 1,
        pageSize: 20,
        query: 'Arsenal',
        client: mockClient,
      );

      expect(res.success, isTrue);
      expect(res.total, equals(415));
      expect(res.data.length, equals(1));
      expect(res.data.first.homeTeam, equals('Arsenal FC'));
    });

    test('getFixtureDetail can force an on-demand refresh', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/fixtures/fixture-1');
        expect(request.url.queryParameters['refresh'], 'true');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'fixture': {
                'id': 'fixture-1',
                'sport_id': 1,
                'home_team': 'Arsenal',
                'away_team': 'Chelsea',
                'match_time': '2026-10-16T18:00:00Z',
                'status': 'finished',
                'home_score': 2,
                'away_score': 1,
              },
            },
          }),
          200,
        );
      });

      final detail = await SportsService(baseUrl: 'http://localhost:8080')
          .getFixtureDetail(
            'fixture-1',
            refresh: true,
            includeStreams: false,
            client: mockClient,
          );
      expect(detail.fixture.homeScore, 2);
      expect(detail.fixture.status, 'finished');
    });

    test('getFixturesBySport fetches path-based sport fixtures', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/sports/4/fixtures'));
        expect(request.url.queryParameters['page'], equals('1'));

        return http.Response(
          jsonEncode({
            "success": true,
            "count": 1,
            "total": 34,
            "page": 1,
            "page_size": 10,
            "total_pages": 4,
            "data": [
              {
                "id": "c8765432-10fe-dcba-9876-543210fedcba",
                "sport_id": 4,
                "league_name": "Indian Premier League",
                "country": "India",
                "home_team": "Mumbai Indians",
                "away_team": "Chennai Super Kings",
                "match_time": "2026-09-20T14:00:00Z",
                "status": "prematch",
              },
            ],
          }),
          200,
        );
      });

      final service = SportsService(baseUrl: 'http://localhost:8080');
      final res = await service.getFixturesBySport(
        sportId: 4,
        page: 1,
        client: mockClient,
      );

      expect(res.data.length, equals(1));
      expect(res.data.first.homeTeam, equals('Mumbai Indians'));
    });

    test('getLiveStreams returns selectable live fixture catalogue', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/live-streams'));
        expect(request.url.queryParameters['live'], equals('true'));
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'provider': 'cs3-cricify',
              'refresh_interval_seconds': 300,
              'fixtures': [
                {
                  'id': 'arsenal-chelsea',
                  'title': 'Arsenal vs Chelsea',
                  'category': 'football',
                  'live': true,
                  'players': <Map<String, dynamic>>[],
                  'streams': [
                    {
                      'url': 'https://media.example.test/live.m3u8',
                      'format': 'hls',
                      'headers': <String, String>{},
                      'master': true,
                      'status': 'extracted',
                    },
                  ],
                },
              ],
            },
          }),
          200,
        );
      });

      final snapshot = await SportsService(
        baseUrl: 'http://localhost:8080',
      ).getLiveStreams(client: mockClient);
      expect(snapshot.fixtures, hasLength(1));
      expect(snapshot.fixtures.single.displayTitle, 'Arsenal vs Chelsea');
      expect(snapshot.fixtures.single.hasStreams, isTrue);
    });

    test(
      'getRatingBetPredictions sends market and preserves server tabs',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.url.path, '/api/v1/predictions/ratingbet');
          expect(request.url.queryParameters['market'], 'win-to-nil');
          expect(request.url.queryParameters['date'], '2026-10-15');
          expect(request.url.queryParameters['page_size'], '100');
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'items': [
                  {
                    'id': 'prediction-1',
                    'selection': 'Arsenal Win to Nil',
                    'confidence': 42,
                  },
                ],
                'markets': [
                  {'key': 'safe', 'label': 'Safe'},
                  {'key': 'math', 'label': 'Math'},
                ],
                'safe_visible': true,
                'total': 1,
              },
            }),
            200,
          );
        });

        final result = await SportsService(baseUrl: 'http://localhost:8080')
            .getRatingBetPredictions(
              market: 'win-to-nil',
              date: '2026-10-15',
              pageSize: 100,
              client: mockClient,
            );

        expect(result['safe_visible'], isTrue);
        expect(result['items'], hasLength(1));
        expect(result['markets'], hasLength(2));
      },
    );

    test(
      'getLiveStreams surfaces backend errors instead of an empty list',
      () async {
        final mockClient = MockClient(
          (_) async => http.Response(
            jsonEncode({'success': false, 'message': 'Catalogue warming up'}),
            503,
          ),
        );
        final service = SportsService(baseUrl: 'http://localhost:8080');
        await expectLater(
          service.getLiveStreams(client: mockClient),
          throwsA(isA<SportsException>()),
        );
      },
    );
  });
}
