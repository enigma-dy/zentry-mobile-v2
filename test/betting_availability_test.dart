import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/models/betting_availability.dart';
import 'package:predict/src/models/ticket_bucket_model.dart';

void main() {
  test('mapped unpriced picks remain addable with an unknown total', () {
    final item = <String, dynamic>{
      'sport_id': 1,
      'home_team': 'Milan',
      'away_team': 'Ferencvaros',
      'match_time': '2099-01-01T16:00:00Z',
      'market': 'Over/Under',
      'selection': 'Over 1.5',
      'odds': 0,
      'sporty_event_id': '',
      'bookmakers': {
        'sporty': {
          'event_id': 'sr:match:74173022',
          'market_id': '18',
          'outcome_id': '12',
          'specifier': 'total=1.5',
        },
      },
    };
    final pick = TicketSelectionModel.fromPrediction(item);
    expect(pick.canAddToBucket, isTrue);
    expect(pick.odds, 0);
    expect(pick.hasOdds, isFalse);
    expect(TicketSelectionModel.fromJson(pick.toJson()).canAddToBucket, isTrue);
    expect(ticketSelectionsTotalOdds([pick]), 0);
    expect(ticketOddsLabel(pick.odds), '\u2014');
    expect(
      TicketSelectionModel.fromPrediction({
        ...item,
        'bookmakers': {},
      }).canAddToBucket,
      isFalse,
    );
    expect(
      TicketSelectionModel.fromPrediction({
        ...item,
        'match_status': 'live',
      }).canAddToBucket,
      isFalse,
    );
    // An invalid source quote becomes an unknown price. A verified selection
    // remains bookable without odds, just like an absent source quote.
    final invalidPricePick = TicketSelectionModel.fromPrediction({
      ...item,
      'odds': double.nan,
    });
    expect(invalidPricePick.canAddToBucket, isTrue);
    expect(invalidPricePick.odds, 0);
    expect(invalidPricePick.toJson()['odds'], 0);
    final priced = TicketSelectionModel.fromPrediction({...item, 'odds': 1.5});
    expect(ticketSelectionsTotalOdds([priced, pick]), 0);
    expect(ticketSelectionsTotalOdds([priced, priced]), 2.25);
  });
  test('kickoff closes betting even when a stale response says pending', () {
    final now = DateTime.utc(2026, 11, 3, 15);
    for (final time in [
      '2026-11-03T15:00:00Z',
      '2026-11-03T14:00:00Z',
      'invalid',
    ]) {
      expect(
        isUpcomingBettingFixture(time, status: 'pending', now: now),
        isFalse,
      );
    }
    expect(
      isUpcomingBettingFixture(
        '2026-11-03T16:00:00Z',
        status: 'pending',
        now: now,
      ),
      isTrue,
    );
    for (final status in [
      'live',
      'finished',
      'won',
      'lost',
      'cancelled',
      'postponed',
    ]) {
      expect(
        isUpcomingBettingFixture(
          '2026-11-03T16:00:00Z',
          matchStatus: status,
          now: now,
        ),
        isFalse,
      );
    }
  });

  test('a verified price cannot make a live or settled pick addable', () {
    final item = <String, dynamic>{
      'fixture_id': 'fixture',
      'sport_id': 1,
      'home_team': 'Home',
      'away_team': 'Away',
      'match_time': '2099-01-01T16:00:00Z',
      'market': '1X2',
      'selection': '1',
      'odds': 1.5,
    };
    expect(TicketSelectionModel.fromPrediction(item).canAddToBucket, isTrue);
    expect(
      TicketSelectionModel.fromPrediction({
        ...item,
        'match_status': 'live',
      }).canAddToBucket,
      isFalse,
    );
    expect(
      TicketSelectionModel.fromPrediction({
        ...item,
        'status': 'won',
      }).canAddToBucket,
      isFalse,
    );
    expect(
      TicketSelectionModel.fromPrediction({
        ...item,
        'match_time': '2020-01-01T16:00:00Z',
      }).canAddToBucket,
      isFalse,
    );
  });
}
