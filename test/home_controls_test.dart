import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:predict/src/home_screen.dart';
import 'package:predict/src/game_center.dart';
import 'package:predict/src/models/fixture_model.dart';
import 'package:predict/src/models/home_markets.dart';
import 'package:predict/src/models/home_fixture_filters.dart';
import 'package:predict/src/services/sports_service.dart';

Map<String, dynamic> matchJson(
  String id, {
  int sport = 1,
  String country = 'England',
  String league = 'Premier League',
  String pick = '1',
  Map<String, dynamic>? markets,
}) => {
  'id': id,
  'sport_id': sport,
  'league_id': '$sport-$country-$league',
  'league_name': league,
  'country': country,
  'home_team': '$id Home',
  'away_team': '$id Away',
  'match_time': '2026-10-05T16:00:00Z',
  'provider_mappings': [
    {'provider': 'sporty', 'last_synced_at': '2026-10-05T15:00:00Z'},
  ],
  'status': 'finished',
  'markets':
      markets ??
      {
        '1x2': {'home': '2.10', 'draw': '3.40', 'away': '3.20'},
        'over_under': {'line': '2.5', 'over': '1.91', 'under': '1.83'},
        'winordraw': {'1X': '1.40', '12': '1.20', 'X2': '1.70'},
      },
  'predictions': [
    {
      'id': '$id-p',
      'prediction': pick,
      'prediction_odds': '1.32',
      'probability': 80,
    },
    if (id == 'London') {'id': '$id-dc', 'prediction': '1X', 'probability': 75},
    if (id == 'London')
      {'id': '$id-ou', 'prediction': 'O25', 'probability': 70},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Sandviken model and market disagreement is visibly marked for review',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = matchJson(
        'Sandviken',
        pick: 'O15',
        markets: {
          'over_under': {'line': '1.5', 'over': '1.08', 'under': '7.30'},
        },
      );
      fixture['status'] = 'prematch';
      fixture['home_team'] = 'IL Sandviken';
      fixture['away_team'] = 'Bjarg';
      fixture['predictions'] = [
        {
          'id': 'tf-sandviken',
          'provider': 'talkfootball',
          'prediction_odds': '1.08',
          'odds_source': 'sporty',
          'odds_phase': 'prematch',
          'odds_observed_at': '2026-10-05T15:00:00Z',
          'match_time': '2026-10-05T16:00:00Z',
          'prediction': 'O15',
          'probability': 65,
        },
      ];
      final service = SportsService(
        client: MockClient((request) async {
          dynamic data = [];
          if (request.url.path == '/api/v1/fixtures') {
            return http.Response(
              jsonEncode({
                'success': true,
                'page': 1,
                'total_pages': 1,
                'data': [fixture],
              }),
              200,
            );
          }
          if (request.url.path == '/api/v1/sports')
            data = [
              {'id': 1, 'name': 'Football', 'key': 'football'},
            ];
          return http.Response(
            jsonEncode({'success': true, 'data': data}),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(sportsService: service)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-probability-review-Sandviken')),
        findsOneWidget,
      );
      expect(find.text('Estimate under review'), findsOneWidget);
      expect(find.text('65%'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'goals start at 1.5 and every outcome keeps its probability when lines switch',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final json = matchJson(
        'Goals',
        pick: 'O15',
        markets: {
          '1x2': {'home': '2.10', 'draw': '3.40', 'away': '3.20'},
          'over_under': {
            '1.5': {'over': '1.30', 'under': '3.50'},
            '2.5': {'over': '1.91', 'under': '1.83'},
          },
        },
      );
      (json['predictions'] as List).first['probabilities'] = jsonEncode({
        'home': 60,
        'draw': 25,
        'away': 15,
        'over_1_5': 86,
        'under_1_5': 14,
        'over_2_5': 65,
        'under_2_5': 35,
      });
      final service = SportsService(
        client: MockClient((request) async {
          dynamic data = [];
          if (request.url.path == '/api/v1/fixtures') {
            return http.Response(
              jsonEncode({
                'success': true,
                'page': 1,
                'total_pages': 1,
                'data': [json],
              }),
              200,
            );
          }
          if (request.url.path == '/api/v1/sports')
            data = [
              {'id': 1, 'name': 'Football', 'key': 'football'},
            ];
          return http.Response(
            jsonEncode({'success': true, 'data': data}),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(sportsService: service)),
      );
      await tester.pumpAndSettle();
      for (final (pick, probability) in [('1', 60), ('X', 25), ('2', 15)]) {
        final option = find.byKey(ValueKey('home-odds-Goals-$pick'));
        expect(
          find.descendant(
            of: option,
            matching: find.text('$probability% probability'),
          ),
          findsOneWidget,
        );
      }
      final dropdown = find.byKey(
        const ValueKey('league-market-England - Premier League'),
      );
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(PopupMenuItem<String>, 'Over/Under'),
      );
      await tester.pumpAndSettle();
      expect(find.text('1.5'), findsWidgets);
      expect(find.text('86% probability'), findsWidgets);
      expect(find.text('14% probability'), findsWidgets);
      final lineDropdown = find.byKey(
        const ValueKey('league-line-England - Premier League'),
      );
      await tester.ensureVisible(lineDropdown);
      await tester.tap(lineDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<double>, '2.5'));
      await tester.pumpAndSettle();
      expect(find.text('65% probability'), findsWidgets);
      expect(find.text('35% probability'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'markets follow sport and keep football-only options out of other sports',
    () {
      expect(
        sportHomeMarkets('football'),
        containsAll(['1X2', 'Double Chance', 'GG/NG']),
      );
      for (final sport in [
        'basketball',
        'tennis',
        'baseball',
        'cricket',
        'volleyball',
      ]) {
        expect(defaultHomeMarket(sport), 'Match Winner');
        expect(sportHomeMarkets(sport), isNot(contains('GG/NG')));
        expect(sportHomeMarkets(sport), isNot(contains('Double Chance')));
      }
      expect(sportHomeMarkets('ice_hockey'), contains('1X2'));
      expect(sportHomeMarkets('handball'), contains('1X2'));
      expect(sportHomeMarkets('baseball'), contains('Run Line'));
      expect(sportHomeMarkets('tennis'), contains('Total Sets'));
    },
  );
  test(
    'market filtering chooses the matching prediction and excludes unrelated matches',
    () {
      final london = FixtureModel.fromJson(matchJson('London'));
      final paris = FixtureModel.fromJson(
        matchJson(
          'Paris',
          pick: 'O15',
          markets: {
            'over_under': {'line': '1.5', 'over': '1.24', 'under': '3.90'},
          },
        ),
      );
      final filtered = filterHomeFixtures(
        [london, paris],
        'Double Chance',
        'football',
      );
      expect(filtered.map((fixture) => fixture.id), ['London']);
      expect(filtered.single.prediction!.prediction, '1X');
      expect(
        homePredictionOdds(
          filtered.single,
          filtered.single.prediction!,
          'football',
        ),
        '1.40',
      );
      expect(
        filterHomeFixtures([london, paris], 'Over/Under', 'football').length,
        2,
      );
      expect(
        filterHomeFixtures([london, paris], 'All Markets', 'football').length,
        2,
      );
    },
  );
  test('market dropdown prices preserve market, selection and total line', () {
    final fixture = FixtureModel.fromJson(matchJson('London'));
    final dc = homeMarketOdds(fixture, 'Double Chance', 'football');
    expect(dc.map((option) => option.selection), ['1X', '12', 'X2']);
    expect(dc.first.marketKey, 'Double Chance');
    expect(dc.first.odd, '1.40');
    final totals = homeMarketOdds(fixture, 'Over/Under 2.5', 'football');
    expect(totals.map((option) => option.selection), ['O25', 'U25']);
    expect(totals.first.odd, '1.91');
    expect(
      homeMarketOdds(
        fixture,
        'Over/Under 1.5',
        'football',
      ).every((option) => option.odd.isEmpty),
      isTrue,
    );
    expect(
      homeMarketChoices('football', [fixture]),
      contains('Over/Under 2.5'),
    );
  });
  test('line dropdown choices and 1X2 probabilities stay independent', () {
    final json = matchJson(
      'Lines',
      markets: {
        '1x2': {'home': '2.10', 'draw': '3.40', 'away': '3.20'},
        'over_under': {
          '1.5': {'over': '1.30', 'under': '3.50'},
          '2.5': {'over': '1.91', 'under': '1.83'},
        },
        'corners': {
          '8.5': {'over': '1.80', 'under': '1.95'},
          '10.5': {'over': '2.20', 'under': '1.65'},
        },
      },
    );
    json['probability'] = {'home': 45, 'draw': '25', 'away_win': 30};
    final fixture = FixtureModel.fromJson(json);

    expect(homeMarketLineChoices([fixture], 'Over/Under'), [1.5, 2.5]);
    expect(homeMarketLineChoices([fixture], 'Corners'), [8.5, 10.5]);
    expect(homeMarketWithLine('Corners', 10.5), 'Corners 10.5');
    expect(homeOneXTwoProbabilities(fixture), {'1': 45, 'X': 25, '2': 30});
  });
  test('ZAI Safe confidence prefers the actual 1X2 outcome percentage', () {
    expect(
      zaiPredictionConfidence({
        'market': 'Safe',
        'confidence': 38,
        'extra': {
          'derived_market_probability': 38,
          'one_x_two_probability': 61,
        },
      }),
      61,
    );
    expect(zaiPredictionConfidence({'market': '1x2', 'confidence': 72}), 72);
  });
  test(
    'market probability carousel resolves supported markets and leaves unavailable ones neutral',
    () {
      final json = matchJson('Probability');
      json['probability'] = {
        'home': 45,
        'draw': 25,
        'away': 30,
        'over_25': 61,
        'under_25': 39,
        'over85Corner': 64,
      };
      json['predictions'] = [
        {'id': 'p-1x2', 'prediction': '1', 'probability': 76},
        {'id': 'p-ou', 'prediction': 'O25', 'probability': 72},
      ];

      final items = homeMarketProbabilityCarousel(
        FixtureModel.fromJson(json),
        'football',
      );
      final byMarket = {for (final item in items) item.market: item};

      expect(items.length, 7);
      expect(byMarket.containsKey('1X2'), isFalse);
      expect(byMarket['Over/Under']!.selection, 'O25');
      expect(byMarket['Over/Under']!.probability, 72);
      expect(byMarket['Double Chance']!.supported, isTrue);
      expect(byMarket['Corners']!.selection, 'Over 8.5 Corners');
      expect(byMarket['Corners']!.probability, 64);
      expect(byMarket['GG/NG']!.supported, isFalse);
      expect(byMarket['GG/NG']!.probability, 0);
      expect(byMarket['Cards']!.supported, isFalse);
    },
  );
  test(
    'two-way winner and sets do not use football draw odds or goals prices',
    () {
      final fixture = FixtureModel.fromJson(
        matchJson(
          'Tennis',
          sport: 3,
          pick: '2',
          markets: {
            'winner': {'home': '1.62', 'away': '2.25'},
            'total_sets': {'line': '2.5', 'over': '2.05', 'under': '1.78'},
            'over_under': {'line': '22.5', 'over': '1.90', 'under': '1.80'},
          },
        ),
      );
      final winner = homeMarketOdds(fixture, 'Match Winner', 'tennis');
      expect(winner.map((option) => option.label), ['1', '2']);
      expect(
        homePredictionOdds(fixture, fixture.prediction!, 'tennis'),
        '2.25',
      );
      expect(
        homeMarketOdds(fixture, 'Total Sets', 'tennis').first.selection,
        'Over 2.5 Sets',
      );
      expect(homeMarketOdds(fixture, 'Total Sets', 'tennis').first.odd, '2.05');
      expect(homeMarketOdds(fixture, 'Over/Under', 'tennis').first.odd, '1.90');
    },
  );
  test(
    'countries and top leagues use actual fixtures for the selected sport',
    () {
      final fixtures = [
        for (var i = 0; i < 12; i++)
          FixtureModel.fromJson(
            matchJson('league-$i', country: 'England', league: 'League $i'),
          ),
        FixtureModel.fromJson(
          matchJson('extra', country: 'England', league: 'League 11'),
        ),
        FixtureModel.fromJson(
          matchJson('usa', country: 'USA', league: 'American League'),
        ),
        FixtureModel.fromJson(
          matchJson(
            'other-sport',
            sport: 2,
            country: 'France',
            league: 'Basketball',
          ),
        ),
      ];
      final leagues = homeTopEuropeanLeagues(fixtures, 1);
      expect(leagues.length, 10);
      expect(leagues.first.name, 'League 11');
      expect(leagues.first.matchCount, 2);
      expect(
        leagues.any((league) => league.country == 'USA' || league.sportId != 1),
        isFalse,
      );
      expect(homeFixtureCountries(fixtures)['England'], 13);
      expect(homeFixtureDate(DateTime(2026, 1, 2)), '2026-01-02');
    },
  );
  test(
    'daily fixture catalogue follows pagination and includes completed matches',
    () async {
      final pages = <String>[];
      final client = MockClient((request) async {
        pages.add(request.url.queryParameters['page']!);
        expect(request.url.queryParameters['date'], '2026-09-01');
        expect(request.url.queryParameters['sport_id'], '3');
        expect(request.url.queryParameters.containsKey('status'), isFalse);
        final page = request.url.queryParameters['page'];
        return http.Response(
          jsonEncode({
            'success': true,
            'page': int.parse(page!),
            'page_size': 200,
            'total_pages': 2,
            'data': [matchJson('page-$page', sport: 3)],
          }),
          200,
        );
      });
      final fixtures = await SportsService(
        client: client,
      ).getDailyFixtures(sportId: 3, date: '2026-09-01');
      expect(pages, ['1', '2']);
      expect(fixtures.length, 2);
      expect(fixtures.every((fixture) => fixture.status == 'finished'), isTrue);
    },
  );
  testWidgets('Game Center opens Fan Duel and Fixture Duel', (tester) async {
    var opened = false;
    var fixtureOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameCenter(
            onFanDuel: () => opened = true,
            onFixtureDuel: () => fixtureOpened = true,
          ),
        ),
      ),
    );
    expect(find.text('Fan Duel'), findsOneWidget);
    expect(find.byKey(const Key('game-bet-machine')), findsNothing);
    expect(find.byKey(const Key('game-code-converter')), findsNothing);
    expect(find.byKey(const Key('game-value-odds')), findsNothing);
    expect(find.textContaining('Advanced Stats'), findsNothing);
    await tester.tap(find.byKey(const Key('game-fan-duel')));
    expect(opened, isTrue);
    await tester.ensureVisible(find.byKey(const Key('game-fixture-duel')));
    await tester.tap(find.byKey(const Key('game-fixture-duel')));
    expect(fixtureOpened, isTrue);
  });

  test('winner and regulation result selections use different ticket keys', () {
    final fixture = FixtureModel.fromJson(
      matchJson(
        'Hockey',
        sport: 5,
        markets: {
          '1x2': {'home': '2.50', 'draw': '3.00', 'away': '2.75'},
          'winner': {'home': '1.80', 'away': '2.00'},
        },
      ),
    );
    final regulation = homeMarketOdds(fixture, '1X2', 'ice_hockey').first;
    final winner = homeMarketOdds(fixture, 'Match Winner', 'ice_hockey').first;
    expect(regulation.selection, winner.selection);
    expect(
      homeOddsSelectionKey(
        fixture.id,
        regulation.marketKey,
        regulation.selection,
      ),
      isNot(
        homeOddsSelectionKey(fixture.id, winner.marketKey, winner.selection),
      ),
    );
  });

  test('goals and draw-no-bet aliases resolve the exact market outcome', () {
    final dnb = FixtureModel.fromJson(
      matchJson(
        'DNB',
        pick: '1 DNB',
        markets: {
          'dnb': {'home': '1.48', 'away': '2.80'},
        },
      ),
    );
    expect(homePredictionOdds(dnb, dnb.prediction!, 'football'), '1.48');
    final goals = FixtureModel.fromJson(
      matchJson(
        'Goals',
        pick: 'O05',
        markets: {
          'over_under': {'line': '0.5', 'over': '1.12', 'under': '6.0'},
        },
      ),
    );
    expect(
      homeMarketOdds(goals, 'Over/Under', 'football').first.selection,
      'O05',
    );
    expect(homePredictionOdds(goals, goals.prediction!, 'football'), '1.12');
  });

  Future<void> pumpHome(WidgetTester tester, List<Uri> requests) async {
    final client = MockClient((request) async {
      requests.add(request.url);
      final path = request.url.path;
      dynamic data = <String, dynamic>{};
      if (path == '/api/v1/sports') {
        data = [
          {'id': 1, 'name': 'Football', 'key': 'football'},
          {'id': 2, 'name': 'Basketball', 'key': 'basketball'},
          {'id': 3, 'name': 'Tennis', 'key': 'tennis'},
        ];
      } else if (path == '/api/v1/fixtures') {
        final sport = int.parse(request.url.queryParameters['sport_id'] ?? '1');
        final basketball = sport == 2;
        final country = request.url.queryParameters['country'];
        var fixtures = basketball
            ? [
                matchJson(
                  'Basket',
                  sport: 2,
                  markets: {
                    'winner': {'home': '1.75', 'away': '2.10'},
                    'over_under': {
                      'line': '163.5',
                      'over': '1.88',
                      'under': '1.92',
                    },
                  },
                ),
              ]
            : [
                matchJson('London'),
                matchJson(
                  'Paris',
                  country: 'France',
                  league: 'Ligue 1',
                  pick: 'O15',
                  markets: {
                    'over_under': {
                      'line': '1.5',
                      'over': '1.24',
                      'under': '3.90',
                    },
                  },
                ),
              ];
        if (request.url.queryParameters['page'] == '2') {
          fixtures = [
            matchJson('Berlin', country: 'Germany', league: 'Bundesliga'),
          ];
        }
        if (country != null) {
          fixtures = [matchJson('Selected', country: country)];
        }
        return http.Response(
          jsonEncode({
            'success': true,
            'page': int.parse(request.url.queryParameters['page'] ?? '1'),
            'page_size': int.parse(
              request.url.queryParameters['page_size'] ?? '20',
            ),
            'total_pages': country == null && !basketball ? 2 : 1,
            'data': fixtures,
          }),
          200,
        );
      } else if (path == '/api/v1/fixtures/live' || path == '/api/v1/leagues') {
        data = [];
      } else if (path == '/api/v1/predictions') {
        data = {'data': []};
      } else if (path.startsWith('/api/v1/fixtures/')) {
        final id = path.split('/').last;
        data = {
          'fixture': id == 'Paris'
              ? matchJson(
                  'Paris',
                  country: 'France',
                  league: 'Ligue 1',
                  pick: 'O15',
                  markets: {
                    'over_under': {
                      'line': '1.5',
                      'over': '1.24',
                      'under': '3.90',
                    },
                  },
                )
              : matchJson(id),
        };
      }
      return http.Response(jsonEncode({'success': true, 'data': data}), 200);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(sportsService: SportsService(client: client)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home filters and league dropdown change real odds rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Uri>[];
    await pumpHome(tester, requests);
    expect(find.text('Highlights'), findsNothing);
    expect(find.text('Aviator'), findsNothing);
    final dropdown = find.byKey(
      const ValueKey('league-market-England - Premier League'),
    );
    // Revealing the last league can fetch another page and insert a group
    // above it. Reveal again after that page settles, away from the floating slip.
    await Scrollable.ensureVisible(tester.element(dropdown), alignment: 0.25);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(dropdown), alignment: 0.25);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(PopupMenuItem<String>, 'Double Chance'),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('home-odds-London-1X'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('1.40')),
      findsOneWidget,
    );
    final filter = find.byKey(const ValueKey('home-market-Double Chance'));
    // Scroll the recycled filter bar back into view after visiting a league.
    await tester.scrollUntilVisible(
      filter,
      -200,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-match-London')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-match-Paris')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-match-London')),
        matching: find.text('FINISHED'),
      ),
      findsOneWidget,
    );
    final badge = find.byKey(const ValueKey('home-prediction-London'));
    await tester.ensureVisible(badge);
    await tester.pumpAndSettle();
    await tester.tap(badge);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-match-London')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('home-odds-London-1X')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-match-London')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('home quick actions place ZAI after chat and calendar', (
    tester,
  ) async {
    await pumpHome(tester, []);
    final chat = find.byKey(const ValueKey('home-category-Chat'));
    final calendar = find.byKey(const ValueKey('home-category-Calendar'));
    final zai = find.byKey(const ValueKey('home-category-ZAI'));
    expect(chat, findsOneWidget);
    expect(calendar, findsOneWidget);
    expect(zai, findsOneWidget);
    expect(
      tester.getTopLeft(chat).dx,
      lessThan(tester.getTopLeft(calendar).dx),
    );
    expect(tester.getTopLeft(calendar).dx, lessThan(tester.getTopLeft(zai).dx));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('sport switch replaces football markets with winner markets', (
    tester,
  ) async {
    await pumpHome(tester, []);
    final basketball = find.byKey(const ValueKey('home-sport-basketball'));
    await tester.ensureVisible(basketball);
    await tester.pumpAndSettle();
    await tester.tap(basketball);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('home-market-Match Winner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-market-Double Chance')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('home-market-GG/NG')), findsNothing);
    expect(find.byKey(const ValueKey('home-match-Basket')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'date controls send the chosen date to fixtures for a free user',
    (tester) async {
      final requests = <Uri>[];
      await pumpHome(tester, requests);
      final initial = requests
          .firstWhere((uri) => uri.path == '/api/v1/fixtures')
          .queryParameters['date']!;
      final previous = DateTime.parse(
        initial,
      ).subtract(const Duration(days: 1));
      final button = find.byKey(const Key('home-previous-date'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        requests
            .lastWhere((uri) => uri.path == '/api/v1/fixtures')
            .queryParameters['date'],
        homeFixtureDate(previous),
      );
      expect(
        requests.where((uri) => uri.path == '/api/v1/predictions'),
        isEmpty,
      );
      expect(
        requests
            .lastWhere((uri) => uri.path == '/api/v1/fixtures')
            .queryParameters
            .containsKey('status'),
        isFalse,
      );
      await tester.tap(find.byKey(const Key('home-next-date')));
      await tester.pumpAndSettle();
      expect(
        requests
            .lastWhere((uri) => uri.path == '/api/v1/fixtures')
            .queryParameters['date'],
        initial,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'country picker includes later pages and loads the chosen country',
    (tester) async {
      final requests = <Uri>[];
      await pumpHome(tester, requests);
      final countries = find.byKey(const ValueKey('home-filter-Countries'));
      await tester.ensureVisible(countries);
      await tester.pumpAndSettle();
      await tester.tap(countries);
      await tester.pumpAndSettle();
      expect(find.text('Germany'), findsOneWidget);
      await tester.tap(find.text('Germany'));
      await tester.pumpAndSettle();
      expect(
        requests
            .lastWhere((uri) => uri.path == '/api/v1/fixtures')
            .queryParameters['country'],
        'Germany',
      );
      expect(find.text('Country: Germany'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
