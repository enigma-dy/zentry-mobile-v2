import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/models/notification_ticker.dart';

void main() {
  test('kickoff alerts are shown only once per fixture', () {
    final notifications = <Map<String, dynamic>>[
      {
        'id': 'newest',
        'type': 'fixture_starting',
        'message': 'Arsenal vs Chelsea is about to start',
        'data': {'fixture_id': 'fixture-1'},
      },
      {
        'id': 'duplicate',
        'type': 'kickoff_reminder',
        'message': 'Arsenal vs Chelsea starts in 5 minutes',
        'fixture_id': 'fixture-1',
      },
      {
        'id': 'other-fixture',
        'type': 'fixture_about_to_start',
        'payload': {
          'fixture': {'id': 'fixture-2'},
        },
      },
    ];

    expect(dedupeTickerNotifications(notifications).map((item) => item['id']), [
      'newest',
      'other-fixture',
    ]);
  });

  test('unrelated fixture notifications are not removed', () {
    final notifications = <Map<String, dynamic>>[
      {'id': 'result', 'type': 'match_result', 'fixture_id': 'fixture-1'},
      {'id': 'kickoff', 'type': 'match_starting', 'fixture_id': 'fixture-1'},
    ];

    expect(dedupeTickerNotifications(notifications), hasLength(2));
  });
}
