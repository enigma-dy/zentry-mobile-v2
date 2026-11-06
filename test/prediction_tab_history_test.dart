import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/models/ticket_bucket_model.dart';
import 'package:predict/src/services/prediction_feed_loader.dart';

Map<String, dynamic> pick() => {
  'id': 'pick',
  'fixture_id': 'fixture',
  'source': 'ratingbet',
  'sport_id': 1,
  'home_team': 'Home',
  'away_team': 'Away',
  'match_time': '2099-11-06T18:00:00Z',
  'market': 'Over/Under',
  'selection': 'Over 1.5',
  'odds': 0,
  'sporty_event_id': 'sr:match:1',
  'sporty_market_id': '18',
  'sporty_outcome_id': '12',
  'sporty_specifier': 'total=1.5',
};

void main() {
  test(
    'an invalid optional price cannot disable a complete SportyBet selection',
    () {
      for (final price in [1, 0.5, -1, 'NaN', 'Infinity', null]) {
        final item = TicketSelectionModel.fromPrediction({
          ...pick(),
          'odds': price,
        });
        expect(item.canAddToBucket, true);
        expect(item.odds, 0);
      }
    },
  );
  test('returning to each tab keeps its successful list after a timeout', () {
    final history = PredictionTabHistory();
    for (final tab in ['popular', 'best', 'props']) {
      history.accept(tab, {
        'items': [
          {...pick(), 'home_team': tab},
        ],
      });
    }
    for (final tab in ['props', 'popular', 'best', 'popular']) {
      final result = history.failure(tab, StateError('timeout'))!;
      expect((result['items'] as List).single['home_team'], tab);
      expect(result['retry_pending'], true);
      expect(result['load_error'], isNull);
    }
    expect(history.failure('different-date', StateError('timeout')), isNull);
  });
  test(
    'a warming refresh retains rows but a final empty result clears them',
    () {
      final history = PredictionTabHistory();
      history.accept('popular', {
        'items': [pick()],
      });
      expect(
        history.accept('popular', {'items': [], 'loading': true})['items'],
        isNotEmpty,
      );
      expect(
        history.accept('popular', {'items': [], 'loading': false})['items'],
        isEmpty,
      );
      expect(history.read('popular'), isNull);
    },
  );
  test(
    'transient mapping failure preserves the add button without a price',
    () {
      final history = PredictionTabHistory();
      history.accept('football', {
        'items': [pick()],
      });
      final incoming = {
        ...pick(),
        'sporty_event_id': '',
        'sporty_market_id': '',
        'sporty_outcome_id': '',
        'sportybet_synced': false,
        'sporty_sync_reason': 'fixture_snapshot_unavailable',
      };
      final result = history.accept('football', {
        'items': [incoming],
      });
      final row = Map<String, dynamic>.from((result['items'] as List).single);
      expect(TicketSelectionModel.fromPrediction(row).canAddToBucket, true);
      expect(row['odds'], 0);
      expect(row['sportybet_synced'], false);
      expect(incoming['sporty_event_id'], '');
    },
  );
  test(
    'mapping continuity cannot reuse another outcome or replace a conflict',
    () {
      final history = PredictionTabHistory();
      history.accept('football', {
        'items': [pick()],
      });
      for (final change in [
        {'selection': 'Under 1.5', 'sporty_event_id': ''},
        {'sporty_event_id': 'sr:match:different'},
      ]) {
        final incoming = {
          ...pick(),
          ...change,
          'sporty_market_id': '',
          'sporty_outcome_id': '',
          'sporty_sync_reason': 'fixture_snapshot_unavailable',
        };
        final result = preservePredictionBookingIds(history.read('football'), {
          'items': [incoming],
        });
        expect((result['items'] as List).single['sporty_outcome_id'], '');
      }
    },
  );
  test(
    'provider replacement and a missing quote keep the same booking identity',
    () {
      final previous = pick();
      final incoming = {
        ...pick(),
        'id': 'replacement-source-pick',
        'source': 'stats24',
        'match_time': '2099-11-06T19:00:00+01:00',
        'match_status': 'scheduled',
        'sporty_market_id': '',
        'sporty_outcome_id': '',
        'sporty_sync_reason': 'outcome_not_in_current_snapshot',
      };
      final result = preservePredictionBookingIds(
        {
          'items': [previous],
        },
        {
          'items': [incoming],
        },
      );
      final row = Map<String, dynamic>.from((result['items'] as List).single);
      expect(TicketSelectionModel.fromPrediction(row).canAddToBucket, true);
      expect(row['odds'], 0);
      expect(row['source'], 'stats24');
    },
  );
  test('nested booking IDs survive without copying a stale price', () {
    final previous = {
      ...pick(),
      'sporty_event_id': '',
      'sporty_market_id': '',
      'sporty_outcome_id': '',
      'bookmakers': {
        'sporty': {
          'event_id': 'sr:match:1',
          'market_id': '18',
          'outcome_id': '12',
          'specifier': 'total=1.5',
          'odds': 1.8,
        },
      },
    };
    final incoming = {
      ...pick(),
      'sporty_event_id': '',
      'sporty_market_id': '',
      'sporty_outcome_id': '',
      'sporty_sync_reason': 'fixture_snapshot_unavailable',
    };
    final result = preservePredictionBookingIds(
      {
        'items': [previous],
      },
      {
        'items': [incoming],
      },
    );
    final row = Map<String, dynamic>.from((result['items'] as List).single);
    expect(TicketSelectionModel.fromPrediction(row).canAddToBucket, true);
    expect(row['odds'], 0);
    for (final conflict in [
      {'fixture_id': 'different'},
      {'sporty_specifier': 'total=2.5'},
    ]) {
      final result = preservePredictionBookingIds(
        {
          'items': [previous],
        },
        {
          'items': [
            {...incoming, ...conflict},
          ],
        },
      );
      expect((result['items'] as List).single['sporty_outcome_id'], '');
    }
  });
  test(
    'started matches remain unaddable and session changes clear all rows',
    () {
      final history = PredictionTabHistory();
      history.accept('football', {
        'items': [pick()],
      });
      final result = history.accept('football', {
        'items': [
          {
            ...pick(),
            'match_status': 'live',
            'sporty_event_id': '',
            'sporty_market_id': '',
            'sporty_outcome_id': '',
            'sporty_sync_reason': 'fixture_snapshot_unavailable',
          },
        ],
      });
      final row = Map<String, dynamic>.from((result['items'] as List).single);
      expect(TicketSelectionModel.fromPrediction(row).canAddToBucket, false);
      history.clear();
      expect(history.read('football'), isNull);
    },
  );
}
