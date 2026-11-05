import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:predict/src/match_detail_screen.dart';
import 'package:predict/src/models/fixture_model.dart';
import 'package:predict/src/models/home_markets.dart';
import 'package:predict/src/services/sports_service.dart';

void main() {
  for (final status in ['prematch', 'live', 'finished']) {
    testWidgets(
      'half-team prediction uses loaded fixture; $status selection availability',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const pick = 'Away not to score in 1st half';
        final loaded = <String, dynamic>{
          'id': 'fixture',
          'sport_id': 1,
          'home_team': 'Home',
          'away_team': 'Away',
          'match_time': '2099-01-01T15:00:00Z',
          'status': status,
          'sporty_event_id': 'sr:match:42',
          'prediction': {
            'id': 'p',
            'prediction': pick,
            'market': '1st Half - Away to score',
            'provider': 'stats24',
            'prediction_odds': '1.6',
            'probability': 70,
            'odds_source': 'sporty',
            'odds_phase': 'prematch',
            'odds_observed_at': '2099-01-01T14:00:00Z',
            'match_time': '2099-01-01T15:00:00Z',
            'sporty_market_id': 'away-first',
            'sporty_outcome_id': 'no',
          },
        };
        final service = SportsService(
          baseUrl: 'https://backend.example',
          client: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'success': true,
                'data': request.url.path.endsWith('/streams')
                    ? {}
                    : {'fixture': loaded},
              }),
              200,
            );
          }),
        );
        FixtureModel? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: MatchDetailScreen(
              fixtureId: 'fixture',
              sportsService: service,
              initialFixture: FixtureModel.fromJson({
                ...loaded,
                'prediction': null,
              }),
              onToggleOdd: (fixture, market, selection, odds) {
                selected = fixture;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.text('Prediction: $pick');
        expect(card, findsOneWidget);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        if (status == 'prematch') {
          expect(find.text('Tap to add to ticket bucket'), findsOneWidget);
          await tester.tap(card);
          expect(selected, isNotNull);
          final option = homePredictionOption(
            selected!,
            selected!.prediction!,
            'football',
          )!;
          expect(option.sportyMarketId, 'away-first');
          expect(option.sportyOutcomeId, 'no');
          expect(option.odd, '1.6');
        } else {
          expect(find.text('Tap to add to ticket bucket'), findsNothing);
          expect(find.text('Betting closed'), findsOneWidget);
          await tester.tap(card);
          expect(selected, isNull);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
