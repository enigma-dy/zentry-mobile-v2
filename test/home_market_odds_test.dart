import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/models/fixture_model.dart';
import 'package:predict/src/models/home_fixture_groups.dart';
import 'package:predict/src/models/home_markets.dart';

FixtureModel fixture(
  String league, {
  String country = '',
  String? pick,
  Map<String, dynamic>? markets,
}) => FixtureModel.fromJson({
  'id': '$country-$league',
  'league_name': league,
  'country': country,
  'predictions': [
    if (pick != null)
      {'id': 'prediction', 'prediction': pick, 'prediction_odds': '1.32'},
  ],
  'markets': ?markets,
});

void main() {
  test(
    'available provider odds are selected per outcome and survive JSON copies',
    () {
      final match = FixtureModel.fromJson({
        ...fixture('League').toJson(),
        'markets': {
          '1x2': {'home': '2.10', 'draw': '0', 'away': ''},
          'winordraw': {'1X': 'NaN'},
          'over_under': {'line': '1.5', 'over': '1.24', 'under': '3.90'},
        },
        'predictions': [
          {
            'id': 'betmines',
            'provider': 'betmines',
            'prediction': 'GG',
            'prediction_odds': '1.85',
            'odd_1': '2.40',
            'odd_x': '3.20',
            'odd_2': '4.0',
            'odd_1x': '1.40',
            'odd_goal': '1.80',
            'odd_no_goal': '2.1',
            'odd_over_25': '1.91',
            'odd_under_25': '1.83',
          },
        ],
      });
      for (final value in [
        match,
        FixtureModel.fromJson(match.toJson()),
        match.withPrediction(match.prediction!),
      ]) {
        expect(value.displayOdds, ['2.10', '3.20', '4.0']);
        expect(
          homeMarketOdds(value, 'Double Chance', 'football').first.odd,
          '1.40',
        );
        expect(homeMarketOdds(value, 'GG/NG', 'football').first.odd, '1.80');
        expect(
          homeMarketOdds(value, 'Over/Under 1.5', 'football').first.odd,
          '1.24',
        );
        expect(
          homeMarketOdds(value, 'Over/Under 2.5', 'football').first.odd,
          '1.91',
        );
        expect(
          homeMarketOdds(value, 'Over/Under 3.5', 'football').first.odd,
          isEmpty,
        );
      }
    },
  );
  test('a prediction price only fills its exact selection and line', () {
    final match = FixtureModel.fromJson({
      ...fixture('League').toJson(),
      'predictions': [
        {'id': 'p', 'prediction': 'Over 1.5', 'prediction_odds': '1.24'},
        {'id': 'gg', 'prediction': 'BTTS YES', 'prediction_odds': '1.80'},
      ],
    });
    expect(homeMarketOdds(match, 'Over/Under', 'football').first.odd, '1.24');
    expect(homeMarketOdds(match, 'Over/Under', 'football').last.odd, isEmpty);
    expect(
      homeMarketOdds(match, 'Over/Under 2.5', 'football').first.odd,
      isEmpty,
    );
    expect(homeMarketOdds(match, 'GG/NG', 'football').first.odd, '1.80');
    expect(homePredictionOdds(match, match.prediction!, 'football'), '1.24');
  });

  test('Betmines probability maps feed non-primary market filters', () {
    final match = FixtureModel.fromJson({
      ...fixture('Probability League', pick: 'U35').toJson(),
      'probability': {
        'home': 50,
        'away': 25,
        'home_draw': 74,
        'draw_away': 51,
        'over85Corner': 71,
        'under85Corner': 29,
        'over_4_5_cards': 42,
        'under_4_5_cards': 58,
      },
    });

    final dnb = filterHomeFixtures([match], 'Draw No Bet', 'football');
    expect(dnb.single.prediction!.prediction, 'Home DNB');
    expect(dnb.single.prediction!.probability, 67);

    final handicap = filterHomeFixtures([match], 'Handicap', 'football');
    expect(handicap.single.prediction!.prediction, 'Home +0.5 Handicap');
    expect(handicap.single.prediction!.probability, 74);

    final corners = filterHomeFixtures([match], 'Corners', 'football');
    expect(corners.single.prediction!.prediction, 'Over 8.5 Corners');
    expect(corners.single.prediction!.probability, 71);

    final cards = filterHomeFixtures([match], 'Cards', 'football');
    expect(cards.single.prediction!.prediction, 'Under 4.5 Cards');
    expect(cards.single.prediction!.probability, 58);
  });

  test('filtered probability picks retain exact SportyBet outcomes', () {
    final match = FixtureModel.fromJson({
      ...fixture('Exact Market', pick: 'U35').toJson(),
      'probability': {'over85Corner': 71, 'under85Corner': 29},
      'markets': {
        'sporty': [
          {
            'id': '18',
            'name': 'Total Corners',
            'specifier': 'total=8.5',
            'outcomes': [
              {'id': '12', 'name': 'Over', 'odds': '1.72'},
              {'id': '13', 'name': 'Under', 'odds': '2.02'},
            ],
          },
        ],
      },
    });

    final filtered = filterHomeFixtures([match], 'Corners', 'football').single;
    final option = homePredictionOption(
      filtered,
      filtered.prediction!,
      'football',
    );
    expect(filtered.prediction!.prediction, 'Over 8.5 Corners');
    expect(
      homePredictionOdds(filtered, filtered.prediction!, 'football'),
      '1.72',
    );
    expect(option!.sportyMarketId, '18');
    expect(option.sportyOutcomeId, '12');
    expect(option.sportySpecifier, 'total=8.5');
  });

  test(
    'league priority from the API survives pagination and market filtering',
    () {
      final prioritized = FixtureModel.fromJson({
        ...fixture(
          'Zulu',
          markets: {
            '1x2': {'home': '2.1'},
          },
        ).toJson(),
        'league_has_predictions': true,
      });
      final filtered = filterHomeFixtures(
        [fixture('Alpha'), prioritized],
        '1X2',
        'football',
      );
      expect(groupHomeFixturesByLeague(filtered).keys.first, 'Zulu');
      expect(
        FixtureModel.fromJson(prioritized.toJson()).leagueHasPredictions,
        isTrue,
      );
    },
  );

  test(
    'market filtering keeps odds supplied by a different prediction market',
    () {
      final match = FixtureModel.fromJson({
        ...fixture('League').toJson(),
        'predictions': [
          {
            'id': 'goals',
            'prediction': 'O25',
            'odd_1': '2.10',
            'odd_x': '3.40',
            'odd_2': '3.20',
          },
        ],
      });
      final filtered = filterHomeFixtures([match], '1X2', 'football').single;
      expect(filtered.prediction, isNull);
      expect(
        homeMarketOdds(filtered, '1X2', 'football').map((option) => option.odd),
        ['2.10', '3.40', '3.20'],
      );
      expect(filtered.leagueHasPredictions, isTrue);
    },
  );
  test(
    'prediction uses matching market instead of prediction-provider price',
    () {
      final match = fixture(
        'League',
        pick: '1X',
        markets: {
          'winordraw': {'1X': '1.47', '12': '1.20', 'X2': '1.80'},
        },
      );
      expect(match.oddsForPrediction(match.prediction!), '1.47');
      expect(match.effectiveMarkets.oddsFor('12'), '1.20');
      expect(match.effectiveMarkets.oddsFor('X2'), '1.80');
      expect(match.odd1, isEmpty);
    },
  );
  test('goals prices match the direction and exact line', () {
    final markets = FixtureMarketsModel.fromJson({
      'over_under': {'line': '2.5', 'over': '1.91', 'under': '1.83'},
    });
    expect(markets.oddsFor('O25'), '1.91');
    expect(markets.oddsFor('Under 2.5'), '1.83');
    expect(markets.oddsFor('O15'), isEmpty);
    expect(markets.oddsFor('Over 2.5 Corners'), isEmpty);
  });
  test('multiple goals lines survive fixture detail hydration', () {
    final markets = FixtureMarketsModel.fromJson({
      'over_under': {
        '1.5': {'over': '1.24', 'under': '3.90'},
        '2.5': {'over': '1.81', 'under': '1.95'},
      },
    });
    final match = fixture('League', pick: 'O15').withMarkets(markets);
    expect(match.oddsForPrediction(match.prediction!), '1.24');
    expect(match.effectiveMarkets.oddsFor('U25'), '1.95');
  });
  test('match result, BTTS and explicit other market selections', () {
    final markets = FixtureMarketsModel.fromJson({
      '1x2': {'home': '2.10', 'draw': '3.40', 'away': '3.20'},
      'gg': {'yes': '1.75', 'no': '2.05'},
      'corners': {'Over 9.5 Corners': '1.90'},
      'cards': {'Over 4.5 Total Cards': '2.20'},
    });
    expect(markets.oddsFor('1'), '2.10');
    expect(markets.oddsFor('X'), '3.40');
    expect(markets.oddsFor('2'), '3.20');
    expect(markets.oddsFor('GG'), '1.75');
    expect(markets.oddsFor('NG'), '2.05');
    expect(markets.oddsFor('Over 9.5 Corners'), '1.90');
    expect(markets.oddsFor('Over 4.5 Total Cards'), '2.20');
    expect(markets.oddsFor('Over 8.5 Corners'), isEmpty);
  });
  test('missing or invalid odds never generate a price', () {
    final match = FixtureModel.fromJson({
      ...fixture('League').toJson(),
      'prediction': {'id': 'no-odds', 'prediction': '1X'},
    });
    expect(match.oddsForPrediction(match.prediction!), isEmpty);
    expect(match.displayOdds, everyElement(isEmpty));
    expect(
      const PredictionModel(id: 'p', prediction: '1X').effectiveOdds,
      isEmpty,
    );
    for (final price in ['0', '1', 'NaN', 'Infinity', 'suspended', '']) {
      final markets = FixtureMarketsModel.fromJson({
        'winordraw': {'1X': price},
      });
      expect(markets.oddsFor('1X'), isEmpty);
    }
  });
  test(
    'prediction leagues come first alphabetically by league, not country',
    () {
      final matches = [
        fixture('Alpha'),
        fixture('Zulu', country: 'Argentina', pick: '1X'),
        fixture('beta', country: 'Zimbabwe', pick: 'O25'),
        fixture('Delta'),
      ];
      final groups = groupHomeFixturesByLeague(matches);
      expect(groups.keys.toList(), [
        'Zimbabwe - beta',
        'Argentina - Zulu',
        'Alpha',
        'Delta',
      ]);
      expect(matches.first.leagueName, 'Alpha');
    },
  );
  test('a league is prioritized if any of its matches has a prediction', () {
    final groups = groupHomeFixturesByLeague([
      fixture('Alpha'),
      fixture('Zulu'),
      fixture('Zulu', pick: 'GG'),
    ]);
    expect(groups.keys.toList(), ['Zulu', 'Alpha']);
    expect(groups['Zulu']!.length, 2);
  });
}
