import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:predict/src/match_detail_screen.dart';
import 'package:predict/src/models/fixture_model.dart';
import 'package:predict/src/services/sports_service.dart';

Map<String, dynamic> predictionPick() => {
  'id': 'provider-pick-not-a-fixture-uuid',
  'fixture_id': '88204714-9636-4a3f-a6ed-24f31d1a3a6c',
  'sport_id': 1,
  'sport': 'Football',
  'home_team': 'Atlante W',
  'away_team': 'Tigres UANL W',
  'league': 'League',
  'match_time': '2099-11-05T21:45:00Z',
  'status': 'upcoming',
  'market': '1X2',
  'selection': '2',
  'source': 'betmines',
  'probability': 84,
  'odds': 0,
  'sporty_event_id': 'sr:match:42',
  'sporty_market_id': '1',
  'sporty_outcome_id': '3',
};

void main() {
  test(
    'prediction snapshot uses fixture UUID and preserves the selected market',
    () {
      final snapshot = FixtureModel.fromPredictionFeed(predictionPick());
      expect(snapshot.id, predictionPick()['fixture_id']);
      expect(snapshot.id, isNot(predictionPick()['id']));
      expect(snapshot.leagueName, 'League');
      expect(snapshot.prediction!.prediction, '2');
      expect(snapshot.prediction!.sportyOutcomeId, '3');
      expect(snapshot.sportyEventId, 'sr:match:42');
      expect(snapshot.status, 'prematch');
      final settledPick = FixtureModel.fromPredictionFeed({
        ...predictionPick(),
        'status': 'won',
      });
      expect(settledPick.status, 'unknown');
      expect(settledPick.isFinished, isFalse);
      expect(settledPick.prediction!.isWon, isTrue);
    },
  );

  test('snapshot retains fixture scores and nested Sporty mapping', () {
    final snapshot = FixtureModel.fromPredictionFeed({
      ...predictionPick(),
      'sport_id': 2,
      'sport': 'Basketball',
      'match_status': 'live',
      'home_score': 31,
      'away_score': 28,
      'sporty_event_id': '',
      'bookmakers': {
        'sporty': {'event_id': 'sr:match:43'},
      },
    });
    expect(snapshot.sportId, 2);
    expect(snapshot.isLive, isTrue);
    expect(snapshot.homeScore, 31);
    expect(snapshot.awayScore, 28);
    expect(snapshot.sportyEventId, 'sr:match:43');
  });

  testWidgets(
    'match data is visible while details load and streams never block it',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detail = Completer<http.Response>();
      final streams = Completer<http.Response>();
      final requests = <Uri>[];
      final initial = FixtureModel.fromPredictionFeed(predictionPick());
      final loaded = http.Response(
        jsonEncode({
          'success': true,
          'data': {'fixture': initial.toJson()},
        }),
        200,
      );
      final service = SportsService(
        baseUrl: 'https://backend.example',
        client: MockClient((request) {
          requests.add(request.url);
          if (request.url.path.endsWith('/streams')) return streams.future;
          return requests
                      .where((uri) => !uri.path.endsWith('/streams'))
                      .length ==
                  1
              ? detail.future
              : Future.value(loaded);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MatchDetailScreen(
            fixtureId: initial.id,
            initialFixture: initial,
            sportsService: service,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Atlante W'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(requests.single.path, '/api/v1/fixtures/${initial.id}');
      expect(requests.single.queryParameters['refresh'], isNull);
      detail.complete(loaded);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Atlante W'), findsOneWidget);
      expect(
        requests.where((uri) => uri.path.endsWith('/streams')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      streams.complete(http.Response('{"success":true,"data":{}}', 200));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh Match Data'));
      await tester.pumpAndSettle();
      expect(
        requests.where((uri) => uri.queryParameters['refresh'] == 'true'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final error in [404, 503, 408]) {
    testWidgets(
      'prediction data remains visible when fixture loading fails with $error',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final initial = FixtureModel.fromPredictionFeed(predictionPick());
        final service = SportsService(
          baseUrl: 'https://backend.example',
          client: MockClient((_) async {
            if (error == 408) throw TimeoutException('fixture refresh stalled');
            return http.Response(
              jsonEncode({'error': 'Fixture unavailable'}),
              error,
            );
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MatchDetailScreen(
              fixtureId: initial.id,
              initialFixture: initial,
              sportsService: service,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Atlante W'), findsOneWidget);
        expect(find.text('Failed to load match details'), findsNothing);
        expect(find.textContaining('Using cached match data'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'unlinked prediction opens its known data without using a provider ID as a UUID',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initial = FixtureModel.fromPredictionFeed({
        ...predictionPick(),
        'fixture_id': null,
      });
      var calls = 0;
      final service = SportsService(
        baseUrl: 'https://backend.example',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 404);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MatchDetailScreen(
            fixtureId: initial.id,
            initialFixture: initial,
            sportsService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(initial.id, isEmpty);
      expect(calls, 0);
      expect(find.text('Atlante W'), findsOneWidget);
      expect(
        find.textContaining('Additional match details are still syncing'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('optional captured live fixture response parses correctly', () {
    final path = Platform.environment['ZENTRY_CARD_DETAIL_REPLAY'];
    if (path == null || path.isEmpty) return;
    final payload =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final detail = EnrichedFixtureDetailModel.fromJson(
      payload['data'] as Map<String, dynamic>,
    );
    expect(detail.fixture.id, '01c5849f-2583-4036-be2b-53bfbd59d8de');
    expect(detail.fixture.homeTeam, isNotEmpty);
    expect(detail.fixture.awayTeam, isNotEmpty);
  });
}
