import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/models/fixture_model.dart';
import 'package:predict/src/models/home_markets.dart';
import 'package:predict/src/models/ticket_bucket_model.dart';

void main() {
  test(
    'source price keeps a mapped prediction selectable without Sporty odds',
    () {
      final json = <String, dynamic>{
        'id': 'source-pick',
        'fixture_id': 'fixture',
        'sport_id': 1,
        'source': 'forebet',
        'home_team': 'Home',
        'away_team': 'Away',
        'match_time': '2099-01-01T15:00:00Z',
        'market': '1X2',
        'selection': 'W2',
        'odds': 1.65,
        'odds_source': 'forebet',
        'odds_phase': 'source',
        'sporty_event_id': 'sr:match:42',
        'sporty_market_id': '1',
        'sporty_outcome_id': '3',
        'sportybet_synced': false,
      };
      final prediction = PredictionModel.fromJson(json);
      final fixture = FixtureModel.fromJson({
        'id': 'fixture',
        'sport_id': 1,
        'match_time': json['match_time'],
        'status': 'prematch',
      });
      expect(prediction.hasApprovedPredictionPrice, isTrue);
      expect(homePredictionOdds(fixture, prediction, 'football'), '1.65');
      expect(
        homePredictionOption(fixture, prediction, 'football')?.sportyOutcomeId,
        '3',
      );
      final ticket = TicketSelectionModel.fromPrediction(json);
      expect(ticket.canAddToBucket, isTrue);
      expect(ticket.odds, 1.65);
      expect(ticket.sportyOutcomeId, '3');
      expect(
        TicketSelectionModel.fromPrediction({
          ...json,
          'match_time': '2020-01-01T15:00:00Z',
        }).canAddToBucket,
        isFalse,
      );
      expect(
        PredictionModel.fromJson({
          ...json,
          'odds_source': 'another-provider',
        }).hasApprovedPredictionPrice,
        isFalse,
      );
    },
  );
}
