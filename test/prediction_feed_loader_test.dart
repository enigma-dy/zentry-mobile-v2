import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/services/prediction_feed_loader.dart';

void main() {
  Future<void> noWait(Duration _) async {}
  test(
    'a ready empty sport returns immediately without inventing loading',
    () async {
      var calls = 0;
      final result = await loadPredictionFeed(() async {
        calls++;
        return {'items': [], 'loading': false};
      }, wait: noWait);
      expect(calls, 1);
      expect(result['loading'], false);
    },
  );
  test('a warming response returns promptly for background polling', () async {
    var calls = 0;
    final result = await loadPredictionFeed(() async {
      calls++;
      return {'items': [], 'loading': true};
    }, wait: (_) async => fail('must not hold the page open'));
    expect(calls, 1);
    expect(result['loading'], true);
  });
  test('a legacy empty response is not treated as permanent warming', () async {
    final result = await loadPredictionFeed(() async => {'items': []});
    expect(result['loading'], isNot(true));
  });
  test('one transient failure retries without a manual Retry tap', () async {
    var calls = 0;
    final result = await loadPredictionFeed(() async {
      if (++calls == 1) throw StateError('Starting');
      return {
        'groups': [
          {
            'items': [
              {'id': 'saved'},
            ],
          },
        ],
      };
    }, wait: noWait);
    expect(calls, 2);
    expect(predictionFeedHasContent(result), true);
  });
  test('terminal access errors surface immediately without retries', () async {
    var calls = 0;
    await expectLater(
      loadPredictionFeed(
        () async {
          calls++;
          throw StateError('Access denied');
        },
        shouldRetryError: (_) => false,
        wait: noWait,
      ),
      throwsStateError,
    );
    expect(calls, 1);
  });
  test('changing tabs cancels the retry before another request', () async {
    var calls = 0, active = true;
    await loadPredictionFeed(
      () async {
        calls++;
        throw StateError('Offline');
      },
      shouldContinue: () => active,
      wait: (_) async {
        active = false;
      },
    );
    expect(calls, 1);
  });
  test('repeated network errors stop after one retry', () async {
    var calls = 0;
    await expectLater(
      loadPredictionFeed(() async {
        calls++;
        throw StateError('Offline');
      }, wait: noWait),
      throwsStateError,
    );
    expect(calls, 2);
  });
  test(
    'ready general results never wait for a slow optional Top section',
    () async {
      final top = Completer<Map<String, dynamic>>();
      Map<String, dynamic>? arrived;
      final result = await loadPredictionSections(
        general: Future.value({
          'items': [
            {'id': 'general'},
          ],
          'loading': false,
        }),
        top: top.future,
        onTopReady: (data) => arrived = data,
      );
      expect((result['items'] as List).first['id'], 'general');
      expect(result['top_loading'], true);
      expect(arrived, isNull);
      top.complete({
        'items': [
          {'id': 'top'},
        ],
        'loading': false,
      });
      await Future<void>.delayed(Duration.zero);
      expect(arrived, isNotNull);
      final merged = mergePredictionSections(result, arrived, hasTop: true);
      expect((merged['top_items'] as List).first['id'], 'top');
      expect(merged['loading'], false);
      expect(merged['retry_pending'], false);
      expect((merged['items'] as List).first['id'], 'general');
    },
  );
  test(
    'Top errors keep valid general predictions and clear the warming state',
    () async {
      final top = Completer<Map<String, dynamic>>();
      Map<String, dynamic>? arrived;
      final result = await loadPredictionSections(
        general: Future.value({
          'items': [
            {'id': 'saved'},
          ],
          'loading': false,
        }),
        top: top.future,
        onTopReady: (data) => arrived = data,
      );
      top.completeError(StateError('Unavailable'));
      await Future<void>.delayed(Duration.zero);
      final merged = mergePredictionSections(result, arrived, hasTop: true);
      expect((merged['items'] as List).length, 1);
      expect(merged['top_load_error'], isNotNull);
      expect(merged['top_loading'], false);
      expect(merged['loading'], false);
      expect(merged['retry_pending'], true);
    },
  );
  test('a successful Top refresh clears a previous section error', () {
    final result = mergePredictionSections(
      {
        'items': [],
        'general_loading': false,
        'loading': true,
        'top_load_error': 'old',
      },
      {
        'items': [
          {'id': 'ready'},
        ],
        'loading': false,
      },
      hasTop: true,
    );
    expect(result['top_load_error'], isNull);
    expect(result['loading'], false);
  });
}
