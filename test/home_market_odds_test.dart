import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/models/fixture_model.dart';
import 'package:predict/src/models/home_fixture_groups.dart';
import 'package:predict/src/models/home_markets.dart';

FixtureModel prematchFixture(Map<String, dynamic> json) =>
    FixtureModel.fromJson({'match_time': '2099-01-01T15:00:00Z', ...json});
const prematchPrice = <String, dynamic>{
  'odds_phase': 'prematch',
  'odds_observed_at': '2026-10-31T14:00:00Z',
  'match_time': '2026-10-31T15:00:00Z',
};

FixtureModel fixture(
  String league, {
  String country = '',
  String? pick,
  Map<String, dynamic>? markets,
}) => prematchFixture({
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
    'Esbjerg live fixture odds never replace a prematch prediction price',
    () {
      final match = FixtureModel.fromJson({
        'id': 'esbjerg-hvidovre',
        'sport_id': 1,
        'home_team': 'Esbjerg FB',
        'away_team': 'Hvidovre IF',
        'status': 'live',
        'match_time': '2026-10-31T15:00:00Z',
        'provider_mappings': [
          {'provider': 'sporty', 'last_synced_at': '2026-10-31T16:26:40Z'},
        ],
        'markets': {
          'over_under': {'line': '1.5', 'over': '1.92'},
          'sporty': [
            {
              'id': '18',
              'specifier': 'total=1.5',
              'outcomes': [
                {'id': '12', 'name': 'Over 1.5', 'odds': '1.92'},
              ],
            },
          ],
        },
      });
      for (final provider in ['betmines', 'talkfootball']) {
        final raw = <String, dynamic>{
          'id': 'p',
          'provider': provider,
          'prediction': 'O15',
          'prediction_odds': '1.92',
          'match_time': '2026-10-31T15:00:00Z',
        };
        final unknown = PredictionModel.fromJson(raw);
        expect(homePredictionOdds(match, unknown, 'football'), isEmpty);
        expect(homePredictionOption(match, unknown, 'football'), isNull);
        expect(match.oddsForPrediction(unknown), isEmpty);
        expect(
          homeMarketOdds(
            match,
            'Over/Under 1.5',
            'football',
          ).every((o) => o.odd.isEmpty),
          isTrue,
        );
        final saved = PredictionModel.fromJson({
          ...raw,
          ...prematchPrice,
          'odds_source': 'betmines',
          'prediction_odds': '1.22',
        });
        expect(homePredictionOdds(match, saved, 'football'), '1.22');
        expect(homePredictionOption(match, saved, 'football')!.odd, '1.22');
        final roundTrip = PredictionModel.fromJson(saved.toJson());
        expect(
          homePredictionOdds(
            FixtureModel.fromJson(match.toJson()),
            roundTrip,
            'football',
          ),
          '1.22',
        );
        final late = PredictionModel.fromJson({
          ...saved.toJson(),
          'odds_observed_at': '2026-10-31T15:00:00Z',
        });
        expect(homePredictionOdds(match, late, 'football'), isEmpty);
      }
    },
  );

  test(
    'Popular threshold uses preferences while Forebet supplies the quote',
    () {
      final item = <String, dynamic>{
        'source': 'betexplorer',
        'votes_percent': 95,
        'probability': 38,
        'confidence': 38,
        'extra': {
          'probability_source': 'forebet',
          'probability_kind': 'model',
        },
        'probability_review': {'reason': 'model_market_disagreement'},
      };
      expect(predictionConfidenceLabel(item), '38%');
      expect(
        predictionConfidenceLabel({
          ...item,
          'extra': {'probability_kind': 'unavailable'},
        }),
        isEmpty,
      );
      expect(predictionConfidenceLabel({...item, 'probability': 0}), '0%');
    },
  );

  test(
    'prediction feed cards flag disagreements with old and new backend payloads',
    () {
      final item = <String, dynamic>{
        'id': 'sandviken',
        'sport_id': 1,
        'source': 'talkfootball',
        'odds_source': 'sporty',
        ...prematchPrice,
        'selection': 'Over 1.5',
        'probability': 65,
        'confidence': 65,
        'odds': 1.08,
        'sporty_market_id': '18',
        'sporty_outcome_id': '12',
        'sporty_specifier': 'total=1.5',
      };
      expect(predictionConfidenceLabel(item), 'Estimate under review');
      expect(predictionConfidenceLabel({...item, 'odds': 1.50}), '65%');
      expect(
        predictionConfidenceLabel({
          ...item,
          'odds': 1.50,
          'probability_review': {'reason': 'model_market_disagreement'},
        }),
        'Estimate under review',
      );
      expect(item['probability'], 65);
    },
  );
  test(
    'Sandviken Bjarg O15 1.08 and model 65 triggers review without rewriting either',
    () {
      final match = prematchFixture({
        'id': 'sandviken-bjarg',
        'sport_id': 1,
        'status': 'prematch',
        'home_team': 'IL Sandviken',
        'away_team': 'Bjarg',
        'prediction': {
          'id': 'tf-sandviken',
          'provider': 'talkfootball',
          'prediction': 'O15',
          'probability': 65,
        },
        'markets': {
          'sporty': [
            {
              'id': '18',
              'name': 'Over/Under',
              'specifier': 'total=1.5',
              'outcomes': [
                {'id': '12', 'name': 'Over 1.5', 'odds': '1.08'},
                {'id': '13', 'name': 'Under 1.5', 'odds': '7.30'},
              ],
            },
          ],
        },
      });
      final review = homePredictionProbabilityReview(
        match,
        match.prediction!,
        'football',
      );
      expect(review, isNotNull);
      expect(review!.modelProbability, 65);
      expect(review.rawImpliedProbability, closeTo(92.5926, 0.001));
      expect(review.gap, greaterThan(25));
      expect(homePredictionOdds(match, match.prediction!, 'football'), '1.08');
      expect(match.prediction!.probability, 65);
      final live = prematchFixture({...match.toJson(), 'status': 'live'});
      expect(
        homePredictionProbabilityReview(live, live.prediction!, 'football'),
        isNull,
      );
      expect(
        homeOutcomeProbabilityReview(
          match,
          'Over/Under',
          'Over 2',
          '1.08',
          probability: 65,
        ),
        isNull,
      );
    },
  );

  test('prediction probability uses its exact source selection breakdown', () {
    final match = prematchFixture({
      'sport_id': 1,
      'prediction': {
        'id': 'stale-tip',
        'prediction': 'O15',
        'probability': 65,
        'probabilities': {'over_1_5': 93, 'over_2_5': 65},
      },
      'markets': {
        'over_under': {'line': '1.5', 'over': '1.08'},
      },
    });
    expect(homePredictionProbability(match, match.prediction!, 'football'), 93);
    expect(
      homePredictionProbabilityReview(match, match.prediction!, 'football'),
      isNull,
    );
  });
  test(
    'all outcome probabilities survive prediction metadata and JSON copies',
    () {
      final match = prematchFixture({
        'id': 'full-probabilities',
        'sport_id': 1,
        'prediction': {
          'id': 'betmines-pick',
          'provider': 'betmines',
          'prediction': 'O15',
          'probability': 86,
          'probabilities':
              '{"home":60,"draw":25,"away":15,"over_1_5":86,"under_1_5":14,"over_2_5":65,"under_2_5":35}',
        },
      });
      for (final fixture in [
        match,
        prematchFixture(match.toJson()),
        match.withPrediction(match.prediction!),
        filterHomeFixtures([match], '1X2', 'football').single,
      ]) {
        expect(homeOneXTwoProbabilities(fixture), {'1': 60, 'X': 25, '2': 15});
        expect(homeOutcomeProbability(fixture, '1X2', '1'), 60);
        expect(homeOutcomeProbability(fixture, '1X2', 'X'), 25);
        expect(homeOutcomeProbability(fixture, '1X2', '2'), 15);
        expect(homeOutcomeProbability(fixture, 'Over/Under 1.5', 'O15'), 86);
        expect(homeOutcomeProbability(fixture, 'Over/Under 1.5', 'U15'), 14);
        expect(homeOutcomeProbability(fixture, 'Over/Under 2.5', 'U25'), 35);
      }
      final nested = prematchFixture({
        'prediction': {
          'id': 'nested',
          'prediction': '1',
          'probabilities': {
            'extra': {
              'probabilities': {'home': 55, 'draw': 30, 'away': 15},
            },
          },
        },
      });
      expect(homeOneXTwoProbabilities(nested), {'1': 55, 'X': 30, '2': 15});
    },
  );

  test('half-goal totals complete the missing side without guessing 1X2', () {
    final match = prematchFixture({
      'prediction': {'id': 'o15', 'prediction': 'O15', 'probability': 86},
      'probability': {
        'over25': 100,
        'over20': 60,
        'over225': 65,
        'home': 70,
        'over05': 95,
      },
    });
    expect(homeOutcomeProbability(match, 'Over/Under 1.5', 'U15'), 14);
    expect(homeOutcomeProbability(match, 'Over/Under 2.5', 'U25'), 0);
    expect(homeOutcomeProbability(match, 'Over/Under 0.5', 'U05'), 5);
    expect(homeMarketLines(match, 'Over/Under'), contains(0.5));
    expect(homeOutcomeProbability(match, 'Over/Under 2', 'Under 2'), isNull);
    expect(
      homeOutcomeProbability(match, 'Over/Under 2.25', 'Under 2.25'),
      isNull,
    );
    expect(homeOutcomeProbability(match, '1X2', 'X'), isNull);
    expect(homeOutcomeProbability(match, '1X2', '2'), isNull);
  });

  test('Riga O15 never uses a team or half total at the same line', () {
    Map<String, dynamic> total(
      String id,
      String name,
      String line,
      String odd,
    ) => {
      'id': id,
      'name': name,
      'specifier': 'total=$line',
      'outcomes': [
        {'id': '12', 'name': 'Over $line', 'odds': odd},
        {'id': '13', 'name': 'Under $line', 'odds': '1.51'},
      ],
    };
    final wrongMarkets = [
      total('20', 'JDFS Alberts Over/Under', '1.5', '2.26'),
      total('68', '1st Half - Over/Under', '1.5', '1.82'),
      total('90', '2nd Half - Over/Under', '1.5', '1.51'),
      total('19', 'Riga Mariners Over/Under', '2.5', '2.05'),
      total('18', 'Over/Under', '2.5', '1.31'),
    ];
    for (final hasFullMatch in [false, true]) {
      final match = prematchFixture({
        'id': 'riga-mariners-alberts',
        'sport_id': 1,
        'home_team': 'Riga Mariners',
        'away_team': 'Alberts',
        'probability': {'over15': 86, 'under15': 14},
        'prediction': {
          'id': 'source-1x2',
          'prediction': '1',
          'probability': 60,
          'prediction_odds': '1.56',
          'sporty_market_id': '1',
          'sporty_outcome_id': '1',
        },
        'markets': {
          'sporty': [
            ...wrongMarkets,
            if (hasFullMatch) total('18', 'Over/Under', '1.5', '1.12'),
          ],
        },
      });
      final derived = homeMarketProbabilityPrediction(
        match,
        'Over/Under 1.5',
        'football',
      )!;
      expect(derived.probability, 86);
      expect(derived.sportyMarketId, isEmpty);
      expect(derived.sportyOutcomeId, isEmpty);
      final option = homePredictionOption(match, derived, 'football');
      expect(
        homePredictionOdds(match, derived, 'football'),
        hasFullMatch ? '1.12' : '',
      );
      expect(option?.sportyMarketId ?? '', hasFullMatch ? '18' : '');
      expect(option?.sportySpecifier ?? '', hasFullMatch ? 'total=1.5' : '');
    }
    final onlyScoped = prematchFixture({
      'markets': {'sporty': wrongMarkets.take(4).toList()},
    });
    expect(homeMarketLines(onlyScoped, 'Over/Under'), isEmpty);
  });

  test(
    'synced alternate totals use their own line even when labels are missing',
    () {
      final match = prematchFixture({
        'id': 'synced-total',
        'sport_id': 1,
        'home_team': 'Home',
        'away_team': 'Away',
        'probability': {
          'home': 55,
          'draw': 25,
          'away': 20,
          'over15': 88,
          'under15': 12,
          'gg': 71,
          'ng': 29,
        },
        'prediction': {
          'id': 'o15',
          'provider': 'betmines',
          'prediction': 'O15',
          'probability': 88,
          'prediction_odds': '1.32',
        },
        'markets': {
          'sporty': [
            {
              'id': '18',
              'specifier': 'total=2.5',
              'outcomes': [
                {'id': '12', 'odds': '1.90'},
                {'id': '13', 'odds': '1.80'},
              ],
            },
            {
              'id': '18',
              'specifier': 'total=1.5',
              'outcomes': [
                {'id': '12', 'odds': '1.35'},
                {'id': '13', 'odds': '3.10'},
              ],
            },
            {
              'id': '1',
              'outcomes': [
                {'id': '1', 'odds': '2.10'},
                {'id': '2', 'odds': '3.40'},
                {'id': '3', 'odds': '3.20'},
              ],
            },
          ],
        },
      });
      final option = homePredictionOption(match, match.prediction!, 'football');
      expect(option, isNotNull);
      expect(option!.odd, '1.35');
      expect(option.sportySpecifier, 'total=1.5');
      expect(homeMarketOdds(match, '1X2', 'football').map((e) => e.odd), [
        '2.10',
        '3.40',
        '3.20',
      ]);
      expect(homeOneXTwoProbabilities(match), {'1': 55, 'X': 25, '2': 20});
      expect(homeOutcomeProbability(match, 'Over/Under 1.5', 'O15'), 88);
      expect(homeOutcomeProbability(match, 'Over/Under 1.5', 'U15'), 12);
      final btts = filterHomeFixtures([match], 'GG/NG', 'football').single;
      expect(btts.prediction!.probability, 71);
      expect(homeOutcomeProbability(btts, '1X2', 'X'), 25);
      expect(
        match.prediction!.effectiveOdds,
        isEmpty,
      ); // Undated source price is not verified.
    },
  );

  test(
    'available provider odds are selected per outcome and survive JSON copies',
    () {
      final match = prematchFixture({
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
            'odds_source': 'betmines',
            ...prematchPrice,
            'prediction': 'GG',
            'prediction_odds': '1.80',
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
        prematchFixture(match.toJson()),
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
    final match = prematchFixture({
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
    final match = prematchFixture({
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
    final match = prematchFixture({
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
      final prioritized = prematchFixture({
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
        prematchFixture(prioritized.toJson()).leagueHasPredictions,
        isTrue,
      );
    },
  );

  test(
    'market filtering keeps odds supplied by a different prediction market',
    () {
      final match = prematchFixture({
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
    final match = prematchFixture({
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
  test(
    'TalkFootball predictions keep probabilities but require approved prices',
    () {
      final prediction = PredictionModel.fromJson({
        'id': 'tf',
        'provider': 'talkfootball',
        'prediction': 'O15',
        'prediction_odds': '2.35',
        'probability': 86,
      });
      final match = prematchFixture({
        'id': 'brisbane',
        'sport_id': 1,
        'markets': {
          'over_under': {'line': '1.5', 'over': '2.35'},
        },
        'predictions': [prediction.toJson()],
      });
      expect(prediction.effectiveOdds, isEmpty);
      expect(homePredictionOdds(match, prediction, 'football'), isEmpty);
      expect(prediction.probability, 86);
      final fallback = PredictionModel.fromJson({
        ...prediction.toJson(),
        'prediction_odds': '1.23',
        'odds_source': 'betmines',
        ...prematchPrice,
      });
      expect(homePredictionOdds(match, fallback, 'football'), '1.23');
      expect(
        PredictionModel.fromJson(fallback.toJson()).oddsSource,
        'betmines',
      );
      expect(fallback.probability, 86);
    },
  );
  test('Sporty selected price overrides the models per-market column', () {
    final p = PredictionModel.fromJson({
      'id': 'p',
      'provider': 'betmines',
      'prediction': '1',
      'prediction_odds': '1.43',
      'odd_1': '2.35',
      'odds_source': 'sporty',
      ...prematchPrice,
    });
    expect(p.effectiveOdds, '1.43');
  });
  test(
    'approved Betmines prediction price wins over a later fixture snapshot',
    () {
      final match = prematchFixture({
        'id': 'brisbane',
        'sport_id': 1,
        'markets': {
          'sporty': [
            {
              'id': '18',
              'specifier': 'total=1.5',
              'outcomes': [
                {'id': '12', 'name': 'Over 1.5', 'odds': '2.35'},
              ],
            },
          ],
        },
      });
      final p = PredictionModel.fromJson({
        'id': 'tf',
        'provider': 'talkfootball',
        'prediction': 'O15',
        'probability': 86,
        'prediction_odds': '1.12',
        'odds_source': 'betmines',
        ...prematchPrice,
      });
      expect(homePredictionOdds(match, p, 'football'), '1.12');
      final unavailable = PredictionModel.fromJson({
        ...p.toJson(),
        'prediction_odds': '0',
        'odds_source': 'unavailable',
      });
      expect(homePredictionOdds(match, unavailable, 'football'), isEmpty);
    },
  );
}
