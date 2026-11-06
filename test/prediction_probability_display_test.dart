import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/models/home_markets.dart';

void main() {
  test('Football 1X2 retains the pick without displaying a source rating', () {
    final item = {
      'source': 'stats24',
      'sport_id': 1,
      'market': 'Home Team To Win',
      'selection': 'Home Team To Win',
      'probability': 99,
      'confidence': 99,
      'extra': {'probability_display': 'prediction_only'},
    };
    expect(predictionConfidenceLabel(item), 'Prediction');
    expect(item['selection'], 'Home Team To Win');
  });
  test('Popular still displays its verified Forebet probability', () {
    expect(
      predictionConfidenceLabel({
        'source': 'betexplorer',
        'probability': 62,
        'extra': {'probability_source': 'forebet', 'probability_kind': 'model'},
      }),
      '62%',
    );
  });
  test(
    'Football result badge uses Forebet rather than the source confidence',
    () {
      expect(
        predictionConfidenceLabel({
          'source': 'stats24',
          'probability': 38,
          'confidence': 99,
          'extra': {
            'probability_display': 'forebet',
            'probability_source': 'forebet',
            'probability_kind': 'model',
          },
        }),
        '38% Forebet',
      );
      expect(
        predictionConfidenceLabel({
          'probability': 99,
          'extra': {'probability_display': 'forebet'},
        }),
        'Prediction',
      );
    },
  );
}
