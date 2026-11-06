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
