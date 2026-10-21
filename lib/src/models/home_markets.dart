import 'fixture_model.dart';

String normalizeSportKey(String key) =>
    key.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

List<String> sportHomeMarkets(String sport) {
  final key = normalizeSportKey(sport);
  final markets = switch (key) {
    'football' || 'soccer' => [
      '1X2',
      'Over/Under',
      'Double Chance',
      'GG/NG',
      'Draw No Bet',
      'Handicap',
      'Corners',
      'Cards',
    ],
    'icehockey' || 'hockey' => [
      '1X2',
      'Match Winner',
      'Over/Under',
      'Handicap',
      'Double Chance',
    ],
    'handball' => ['1X2', 'Over/Under', 'Handicap', 'Double Chance'],
    'tennis' || 'volleyball' => [
      'Match Winner',
      'Over/Under',
      'Handicap',
      'Total Sets',
      'Set Handicap',
    ],
    'baseball' => ['Match Winner', 'Over/Under', 'Run Line'],
    'cricket' => ['Match Winner', 'Over/Under', 'Handicap'],
    _ => ['Match Winner', 'Over/Under', 'Handicap'],
  };
  return ['All Markets', ...markets];
}

String defaultHomeMarket(String sport) => sportHomeMarkets(sport)[1];
String baseHomeMarket(String market) =>
    market.replaceFirst(RegExp(r' [+-]?\d+(?:\.\d+)?$'), '');

String? predictionHomeMarket(String selection, String sport) {
  final pick = selection.toUpperCase().trim();
  if (pick.contains('CORNER')) return 'Corners';
  if (pick.contains('CARD')) return 'Cards';
  if (pick.contains('SET') &&
      (pick.contains('HANDICAP') ||
          pick.startsWith('HOME') ||
          pick.startsWith('AWAY'))) {
    return 'Set Handicap';
  }
  if (pick.contains('SET') &&
      (pick.startsWith('OVER') || pick.startsWith('UNDER'))) {
    return 'Total Sets';
  }
  if (['1', 'X', '2', 'HOME', 'AWAY'].contains(pick)) {
    return defaultHomeMarket(sport);
  }
  if (['1X', '12', 'X2'].contains(pick)) return 'Double Chance';
  if (['GG', 'NG', 'BTTS', 'BTTS YES', 'BTTS NO', 'NO GG'].contains(pick)) {
    return 'GG/NG';
  }
  if (pick.contains('DNB') || pick.contains('DRAW NO BET')) {
    return 'Draw No Bet';
  }
  if (pick.contains('HANDICAP') ||
      RegExp(r'^(HOME|AWAY)\s+[+-]\d').hasMatch(pick)) {
    return normalizeSportKey(sport) == 'baseball' ? 'Run Line' : 'Handicap';
  }
  if (RegExp(r'^[OU]\d+(?:\.\d+)?$').hasMatch(pick) ||
      RegExp(r'^(OVER|UNDER)\s+\d+(?:\.\d+)?$').hasMatch(pick)) {
    return 'Over/Under';
  }
  return null;
}

double? predictionTotalLine(String selection) {
  final pick = selection.toUpperCase().trim();
  final short = RegExp(r'^[OU](\d+(?:\.\d+)?)$').firstMatch(pick);
  if (short != null) {
    return double.parse(short[1]!) / (short[1]!.contains('.') ? 1 : 10);
  }
  final full = RegExp(r'^(?:OVER|UNDER)\s+(\d+(?:\.\d+)?)').firstMatch(pick);
  return full == null ? null : double.parse(full[1]!);
}

double? _probabilityValue(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null || !number.isFinite || number <= 0 || number > 100) {
    return null;
  }
  return number;
}

String _probabilityKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

double? _probabilityFor(Map<String, dynamic> values, List<String> keys) {
  final normalized = {
    for (final entry in values.entries)
      _probabilityKey(entry.key): _probabilityValue(entry.value),
  };
  for (final key in keys) {
    final value = normalized[_probabilityKey(key)];
    if (value != null) return value;
  }
  return null;
}

Map<String, int> homeOneXTwoProbabilities(FixtureModel fixture) {
  final values = fixture.marketProbabilities;
  if (values.isEmpty) return const {};
  final result = <String, int>{};
  final home = _probabilityFor(values, const ['home', 'home_win', '1']);
  final draw = _probabilityFor(values, const ['draw', 'draw_win', 'x']);
  final away = _probabilityFor(values, const ['away', 'away_win', '2']);
  if (home != null) result['1'] = home.round();
  if (draw != null) result['X'] = draw.round();
  if (away != null) result['2'] = away.round();
  return result;
}

int? homeOutcomeProbability(
  FixtureModel fixture,
  String market,
  String selection,
) {
  final base = baseHomeMarket(market);
  final pick = _probabilityKey(selection);
  final values = fixture.marketProbabilities;
  double? probability;
  if (base == '1X2' || base == 'Match Winner') {
    probability = switch (pick) {
      '1' || 'home' => _probabilityFor(values, const ['home', 'home_win', '1']),
      'x' || 'draw' => _probabilityFor(values, const ['draw', 'draw_win', 'x']),
      '2' || 'away' => _probabilityFor(values, const ['away', 'away_win', '2']),
      _ => null,
    };
  } else if (base == 'Double Chance') {
    final result = homeOneXTwoProbabilities(fixture);
    probability = switch (pick) {
      '1x' => _probabilityFor(values, const ['1x', 'home_draw']) ??
          (result.containsKey('1') && result.containsKey('X')
              ? (result['1']! + result['X']!).clamp(0, 100).toDouble()
              : null),
      '12' => _probabilityFor(values, const ['12', 'home_away']) ??
          (result.containsKey('1') && result.containsKey('2')
              ? (result['1']! + result['2']!).clamp(0, 100).toDouble()
              : null),
      'x2' => _probabilityFor(values, const ['x2', 'draw_away']) ??
          (result.containsKey('X') && result.containsKey('2')
              ? (result['X']! + result['2']!).clamp(0, 100).toDouble()
              : null),
      _ => null,
    };
  } else if (base == 'GG/NG') {
    probability = pick == 'gg' || pick == 'yes'
        ? _probabilityFor(values, const ['gg', 'btts', 'btts_yes'])
        : pick == 'ng' || pick == 'no'
        ? _probabilityFor(values, const ['ng', 'btts_no'])
        : null;
  } else {
    final marketLine = RegExp(r' ([+-]?\d+(?:\.\d+)?)$').firstMatch(market);
    final expectedLine = predictionTotalLine(selection) ??
        double.tryParse(marketLine?.group(1) ?? '');
    final expectedDirection = pick.startsWith('o') ? 'over' :
        pick.startsWith('u') ? 'under' : '';
    final token = switch (base) {
      'Corners' => 'corner',
      'Cards' => 'card',
      'Total Sets' => 'set',
      _ => '',
    };
    for (final entry in values.entries) {
      final key = _probabilityKey(entry.key);
      if (key == pick) {
        probability = _probabilityValue(entry.value);
        break;
      }
      if (expectedLine == null || expectedDirection.isEmpty ||
          !key.contains(expectedDirection) ||
          _marketLineFromProbabilityKey(entry.key) != expectedLine) continue;
      if (token.isNotEmpty && !key.contains(token)) continue;
      if (token.isEmpty && (key.contains('corner') ||
          key.contains('card') || key.contains('set'))) continue;
      probability = _probabilityValue(entry.value);
      break;
    }
  }
  if (probability == null) {
    for (final prediction in [
      if (fixture.prediction != null) fixture.prediction!,
      ...fixture.predictions,
    ]) {
      if (_probabilityKey(prediction.prediction) == pick &&
          predictionHomeMarket(prediction.prediction, 'football') == base &&
          prediction.probability > 0) {
        probability = prediction.probability.toDouble();
        break;
      }
    }
  }
  return probability?.round();
}

int zaiPredictionConfidence(Map<String, dynamic> item) {
  int percent(dynamic value) {
    final parsed = value is num
        ? value.round()
        : int.tryParse(value?.toString().replaceAll('%', '').trim() ?? '') ?? 0;
    return parsed.clamp(0, 100).toInt();
  }

  final confidence = percent(item['confidence']);
  if (item['market']?.toString().toLowerCase() != 'safe') return confidence;
  final extra = item['extra'];
  if (extra is! Map) return confidence;
  final actual = percent(extra['one_x_two_probability']);
  return actual > 0 ? actual : confidence;
}

double? _marketLineFromProbabilityKey(String key) {
  final separated = RegExp(r'(\d+)[._](\d+)').firstMatch(key);
  if (separated != null) {
    return double.tryParse('${separated[1]}.${separated[2]}');
  }
  final digits = RegExp(r'\d+').firstMatch(key)?.group(0);
  if (digits == null) return null;
  final number = double.tryParse(digits);
  if (number == null) return null;
  // Betmines uses compact total keys such as over85Corner/under105Corner.
  return number >= 15 ? number / 10 : number;
}

class HomeMarketProbabilityItem {
  final String market;
  final String selection;
  final int probability;
  final bool supported;
  final HomeOddsOption? option;

  const HomeMarketProbabilityItem({
    required this.market,
    required this.selection,
    required this.probability,
    required this.supported,
    this.option,
  });
}

List<HomeMarketProbabilityItem> homeMarketProbabilityCarousel(
  FixtureModel fixture,
  String sport,
) {
  final predictions = <PredictionModel>[
    if (fixture.prediction != null) fixture.prediction!,
    ...fixture.predictions,
  ];
  final primaryMarket = fixture.prediction == null
      ? null
      : predictionHomeMarket(fixture.prediction!.prediction, sport);

  return sportHomeMarkets(sport)
      .where(
        (market) =>
            market != 'All Markets' && baseHomeMarket(market) != primaryMarket,
      )
      .map((market) {
        final base = baseHomeMarket(market);
        final matching =
            predictions
                .where(
                  (prediction) =>
                      prediction.probability > 0 &&
                      predictionHomeMarket(prediction.prediction, sport) ==
                          base,
                )
                .toList()
              ..sort((a, b) => b.probability.compareTo(a.probability));
        final prediction = matching.isNotEmpty
            ? matching.first
            : homeMarketProbabilityPrediction(fixture, market, sport);
        final supported = prediction != null && prediction.probability > 0;
        final option = prediction == null
            ? null
            : homePredictionOption(fixture, prediction, sport);
        return HomeMarketProbabilityItem(
          market: market,
          selection: supported ? prediction.prediction : 'Unavailable',
          probability: supported ? prediction.probability : 0,
          supported: supported,
          option: option,
        );
      })
      .toList(growable: false);
}

PredictionModel? homeMarketProbabilityPrediction(
  FixtureModel fixture,
  String market,
  String sport,
) {
  final values = fixture.marketProbabilities;
  if (values.isEmpty) return null;
  final base = baseHomeMarket(market);
  final source =
      fixture.prediction ??
      (fixture.predictions.isEmpty ? null : fixture.predictions.first);
  if (source == null) return null;

  String selection = '';
  double probability = 0;
  void choose(String candidate, double? value) {
    if (value != null && value > probability) {
      selection = candidate;
      probability = value;
    }
  }

  if (base == '1X2' || base == 'Match Winner') {
    choose('1', _probabilityFor(values, const ['home', 'home_win', '1']));
    if (base == '1X2') {
      choose('X', _probabilityFor(values, const ['draw', 'draw_win', 'x']));
    }
    choose('2', _probabilityFor(values, const ['away', 'away_win', '2']));
  } else if (base == 'Double Chance') {
    final home = _probabilityFor(values, const ['home', 'home_win', '1']);
    final draw = _probabilityFor(values, const ['draw', 'draw_win', 'x']);
    final away = _probabilityFor(values, const ['away', 'away_win', '2']);
    choose(
      '1X',
      _probabilityFor(values, const ['home_draw', 'homeDraw', '1x']) ??
          (home != null && draw != null
              ? (home + draw).clamp(0, 100).toDouble()
              : null),
    );
    choose(
      '12',
      _probabilityFor(values, const ['home_away', 'homeAway', '12']) ??
          (home != null && away != null
              ? (home + away).clamp(0, 100).toDouble()
              : null),
    );
    choose(
      'X2',
      _probabilityFor(values, const ['draw_away', 'drawAway', 'x2']) ??
          (draw != null && away != null
              ? (draw + away).clamp(0, 100).toDouble()
              : null),
    );
  } else if (base == 'GG/NG') {
    choose(
      'GG',
      _probabilityFor(values, const [
        'gg',
        'btts',
        'btts_yes',
        'both_teams_to_score_yes',
      ]),
    );
    choose(
      'NG',
      _probabilityFor(values, const [
        'ng',
        'btts_no',
        'both_teams_to_score_no',
      ]),
    );
  } else if (base == 'Over/Under' || base == 'Total Sets') {
    final token = base == 'Total Sets' ? 'set' : '';
    for (final entry in values.entries) {
      final key = _probabilityKey(entry.key);
      if (!key.contains('over') && !key.contains('under')) continue;
      if (token.isNotEmpty && !key.contains(token)) continue;
      if (token.isEmpty &&
          (key.contains('corner') ||
              key.contains('card') ||
              key.contains('set'))) {
        continue;
      }
      final line = _marketLineFromProbabilityKey(entry.key);
      if (line == null) continue;
      final direction = key.contains('under') ? 'Under' : 'Over';
      final compact =
          normalizeSportKey(sport) == 'football' ||
          normalizeSportKey(sport) == 'soccer';
      final selection = compact && base == 'Over/Under'
          ? '${direction == 'Under' ? 'U' : 'O'}${(line * 10).round().toString().padLeft(2, '0')}'
          : '$direction ${_lineLabel(line)}${base == 'Total Sets' ? ' Sets' : ''}';
      choose(selection, _probabilityValue(entry.value));
    }
  } else if (base == 'Draw No Bet') {
    final home = _probabilityFor(values, const [
      'home_dnb',
      'dnb_home',
      'home_draw_no_bet',
    ]);
    final away = _probabilityFor(values, const [
      'away_dnb',
      'dnb_away',
      'away_draw_no_bet',
    ]);
    if (home != null || away != null) {
      choose('Home DNB', home);
      choose('Away DNB', away);
    } else {
      final homeWin = _probabilityFor(values, const ['home']);
      final awayWin = _probabilityFor(values, const ['away']);
      final decided = (homeWin ?? 0) + (awayWin ?? 0);
      if (decided > 0) {
        choose('Home DNB', (homeWin ?? 0) * 100 / decided);
        choose('Away DNB', (awayWin ?? 0) * 100 / decided);
      }
    }
  } else if (base == 'Handicap' || base == 'Run Line') {
    for (final entry in values.entries) {
      final key = _probabilityKey(entry.key);
      if (!key.contains('handicap')) continue;
      final value = _probabilityValue(entry.value);
      final side = key.contains('away') || key.contains('visitor')
          ? 'Away'
          : 'Home';
      final line = _marketLineFromProbabilityKey(entry.key);
      choose(
        line == null ? '$side Handicap' : '$side +${_lineLabel(line)} Handicap',
        value,
      );
    }
    // +0.5 handicap is equivalent to the team-or-draw probability.
    if (selection.isEmpty) {
      choose(
        'Home +0.5 Handicap',
        _probabilityFor(values, const ['home_draw', 'homeDraw']),
      );
      choose(
        'Away +0.5 Handicap',
        _probabilityFor(values, const ['draw_away', 'drawAway']),
      );
    }
  } else if (base == 'Corners' || base == 'Cards') {
    final token = base == 'Corners' ? 'corner' : 'card';
    for (final entry in values.entries) {
      final key = _probabilityKey(entry.key);
      if (!key.contains(token) ||
          (!key.contains('over') && !key.contains('under'))) {
        continue;
      }
      final line = _marketLineFromProbabilityKey(entry.key);
      if (line == null) continue;
      final direction = key.contains('under') ? 'Under' : 'Over';
      choose(
        '$direction ${_lineLabel(line)} $base',
        _probabilityValue(entry.value),
      );
    }
  }

  if (selection.isEmpty || probability <= 0) return null;
  return PredictionModel(
    id: source.id,
    fixtureId: source.fixtureId ?? fixture.id,
    sportId: source.sportId,
    sportyEventId: source.sportyEventId,
    sportyMarketId: source.sportyMarketId,
    sportyOutcomeId: source.sportyOutcomeId,
    sportySpecifier: source.sportySpecifier,
    provider: source.provider,
    prediction: selection,
    probability: probability.round(),
    status: source.status,
    suggestionResult: source.suggestionResult,
    odd1: source.odd1,
    oddX: source.oddX,
    odd2: source.odd2,
    marketOdds: source.marketOdds,
    homeTeam: source.homeTeam,
    awayTeam: source.awayTeam,
    leagueName: source.leagueName,
    matchTime: source.matchTime,
  );
}

String marketPrice(dynamic value) {
  final text = value?.toString().trim() ?? '';
  final number = double.tryParse(text);
  return number != null && number.isFinite && number > 1 ? text : '';
}

class HomeOddsOption {
  final String label;
  final String selection;
  final String odd;
  final String marketKey;
  final String sportyMarketId;
  final String sportyOutcomeId;
  final String sportySpecifier;
  const HomeOddsOption(
    this.label,
    this.selection,
    this.odd,
    this.marketKey, {
    this.sportyMarketId = '',
    this.sportyOutcomeId = '',
    this.sportySpecifier = '',
  });
}

List<HomeOddsOption> _sportyMarketOptions(
  FixtureModel fixture,
  String base, [
  double? requestedLine,
]) {
  final raw = fixture.effectiveMarkets.rawMarkets['sporty'];
  if (raw is! List) return const [];
  bool matches(String value) {
    final name = value.toLowerCase();
    return switch (base) {
      'Draw No Bet' => name.contains('draw no bet') || name.contains('dnb'),
      'Handicap' =>
        name.contains('handicap') &&
            !name.contains('corner') &&
            !name.contains('card') &&
            !name.contains('set'),
      'Run Line' => name.contains('run line') || name.contains('handicap'),
      'Set Handicap' => name.contains('set') && name.contains('handicap'),
      'Corners' => name.contains('corner'),
      'Cards' => name.contains('card') || name.contains('booking'),
      'Over/Under' =>
        (name.contains('over') || name.contains('total')) &&
            !name.contains('corner') &&
            !name.contains('card') &&
            !name.contains('set'),
      'Total Sets' => name.contains('set') && name.contains('total'),
      _ => false,
    };
  }

  for (final value in raw) {
    if (value is! Map) continue;
    final market = Map<String, dynamic>.from(value);
    final name = market['name']?.toString().trim() ?? '';
    if (!matches(name) || market['outcomes'] is! List) continue;
    final specifier = market['specifier']?.toString() ?? '';
    final lineMatch = RegExp(
      r'(?:total|line|hcp)=([+-]?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(specifier);
    final marketLine = double.tryParse(lineMatch?.group(1) ?? '');
    if (requestedLine != null && marketLine != requestedLine) continue;
    final lineText = marketLine == null ? '' : _lineLabel(marketLine);
    final marketKey = lineText.isEmpty
        ? (name.isEmpty ? base : name)
        : base == 'Over/Under'
        ? 'OU$lineText'
        : '$base $lineText';
    final options = <HomeOddsOption>[];
    for (final rawOutcome in market['outcomes'] as List) {
      if (rawOutcome is! Map) continue;
      final outcome = Map<String, dynamic>.from(rawOutcome);
      final odd = marketPrice(outcome['odds']);
      if (odd.isEmpty) continue;
      final label = outcome['name']?.toString().trim() ?? '';
      if (label.isEmpty) continue;
      options.add(
        HomeOddsOption(
          label,
          label,
          odd,
          marketKey,
          sportyMarketId: market['id']?.toString() ?? '',
          sportyOutcomeId: outcome['id']?.toString() ?? '',
          sportySpecifier: market['specifier']?.toString() ?? '',
        ),
      );
    }
    if (options.isNotEmpty) return options;
  }
  return const [];
}

Map<dynamic, dynamic> _marketMap(FixtureModel fixture, List<String> keys) {
  for (final key in keys) {
    final market = fixture.effectiveMarkets.rawMarkets[key];
    if (market is Map && market.isNotEmpty) return market;
  }
  if (keys.contains('over_under')) return fixture.effectiveMarkets.overUnder;
  return const {};
}

List<String> _rawKeys(String market) => switch (market) {
  'Match Winner' => ['winner', 'match_winner', 'moneyline'],
  'Draw No Bet' => ['dnb', 'draw_no_bet'],
  'Handicap' => ['handicap', 'asian_handicap'],
  'Run Line' => ['run_line', 'handicap'],
  'Set Handicap' => ['set_handicap'],
  'Total Sets' => ['total_sets'],
  'Corners' => ['corners', 'over_under_corners'],
  'Cards' => ['cards', 'over_under_cards'],
  'Over/Under' => ['over_under'],
  _ => const [],
};

List<double> homeMarketLines(FixtureModel fixture, String market) {
  final base = baseHomeMarket(market);
  if (!const {
    'Over/Under', 'Total Sets', 'Corners', 'Cards', 'Handicap',
    'Run Line', 'Set Handicap',
  }.contains(base)) return const [];
  final raw = _marketMap(fixture, _rawKeys(base));
  final lines = <double>{};
  final line = double.tryParse(raw['line']?.toString() ?? '');
  if (line != null) lines.add(line);
  for (final entry in raw.entries) {
    final line = double.tryParse(entry.key.toString());
    if (line != null && entry.value is Map) lines.add(line);
    if (base == 'Corners' || base == 'Cards') {
      final line = predictionTotalLine(entry.key.toString());
      if (line != null) lines.add(line);
    }
  }
  if (base == 'Over/Under') {
    final line = double.tryParse(
      fixture.effectiveMarkets.overUnder['line'] ?? '',
    );
    if (line != null) lines.add(line);
    for (final prediction in [
      if (fixture.prediction != null) fixture.prediction!,
      ...fixture.predictions,
    ]) {
      if (predictionHomeMarket(prediction.prediction, 'football') != base ||
          prediction.effectiveOdds.isEmpty) continue;
      final line = predictionTotalLine(prediction.prediction);
      if (line != null) lines.add(line);
    }
  }
  if (const {'Over/Under', 'Total Sets', 'Corners', 'Cards'}.contains(base)) {
    for (final key in fixture.marketProbabilities.keys) {
      final normalized = _probabilityKey(key);
      if (!normalized.contains('over') && !normalized.contains('under')) continue;
      if (base == 'Over/Under' &&
          (normalized.contains('corner') || normalized.contains('card') ||
              normalized.contains('set'))) continue;
      if (base == 'Corners' && !normalized.contains('corner')) continue;
      if (base == 'Cards' && !normalized.contains('card')) continue;
      if (base == 'Total Sets' && !normalized.contains('set')) continue;
      final line = _marketLineFromProbabilityKey(key);
      if (line != null) lines.add(line);
    }
  }
  final sporty = fixture.effectiveMarkets.rawMarkets['sporty'];
  if (sporty is List) {
    for (final value in sporty) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final name = item['name']?.toString().toLowerCase() ?? '';
      final matches = switch (base) {
        'Over/Under' =>
          (name.contains('over') || name.contains('total')) &&
              !name.contains('corner') &&
              !name.contains('card') &&
              !name.contains('set'),
        'Total Sets' => name.contains('set') && name.contains('total'),
        'Corners' => name.contains('corner'),
        'Cards' => name.contains('card') || name.contains('booking'),
        'Handicap' =>
          name.contains('handicap') &&
              !name.contains('corner') &&
              !name.contains('card') &&
              !name.contains('set'),
        'Run Line' => name.contains('run line') || name.contains('handicap'),
        'Set Handicap' => name.contains('set') && name.contains('handicap'),
        _ => false,
      };
      if (!matches) continue;
      final specifier = item['specifier']?.toString() ?? '';
      final match = RegExp(
        r'(?:total|line|hcp)=([+-]?\d+(?:\.\d+)?)',
        caseSensitive: false,
      ).firstMatch(specifier);
      final sportyLine = double.tryParse(match?.group(1) ?? '');
      if (sportyLine != null) lines.add(sportyLine);
    }
  }
  return lines.toList()..sort();
}

List<double> homeMarketLineChoices(List<FixtureModel> fixtures, String market) {
  final lines = <double>{};
  for (final fixture in fixtures) {
    lines.addAll(homeMarketLines(fixture, market));
  }
  return lines.toList()..sort();
}

String homeMarketWithLine(String market, double line) =>
    '${baseHomeMarket(market)} ${_lineLabel(line)}';

List<String> homeMarketChoices(String sport, List<FixtureModel> fixtures) {
  final choices = sportHomeMarkets(
    sport,
  ).where((market) => market != 'All Markets').toList();
  for (final market in [
    'Over/Under',
    'Total Sets',
    'Corners',
    'Cards',
    'Handicap',
    'Run Line',
    'Set Handicap',
  ]) {
    if (!choices.contains(market)) continue;
    final lines = <double>{};
    for (final fixture in fixtures) {
      lines.addAll(homeMarketLines(fixture, market));
    }
    final sorted = lines.toList()..sort();
    choices.addAll(sorted.map((line) => '$market ${_lineLabel(line)}'));
  }
  return choices;
}

String _lineLabel(double line) =>
    line == line.roundToDouble() ? line.toInt().toString() : line.toString();

List<HomeOddsOption> homeMarketOdds(
  FixtureModel fixture,
  String market,
  String sport,
) {
  final base = baseHomeMarket(market);
  final markets = fixture.effectiveMarkets;
  final explicitLine = RegExp(r' ([+-]?\d+(?:\.\d+)?)$').firstMatch(market);
  final requestedLine = explicitLine == null
      ? null
      : double.parse(explicitLine[1]!);
  if (const {
    'Draw No Bet',
    'Handicap',
    'Run Line',
    'Set Handicap',
    'Corners',
    'Cards',
    'Over/Under',
    'Total Sets',
  }.contains(base)) {
    final sporty = _sportyMarketOptions(fixture, base, requestedLine);
    if (sporty.isNotEmpty) return sporty;
  }
  HomeOddsOption option(
    String label,
    String selection,
    dynamic price,
    String key,
  ) {
    final supplied = marketPrice(price);
    return HomeOddsOption(
      label,
      selection,
      supplied.isNotEmpty ? supplied : fixture.oddsForSelection(selection),
      key,
    );
  }

  if (base == '1X2') {
    return [
      option('1', '1', markets.oneXTwo?.home, '1X2'),
      option('X', 'X', markets.oneXTwo?.draw, '1X2'),
      option('2', '2', markets.oneXTwo?.away, '1X2'),
    ];
  }
  if (base == 'Double Chance') {
    return ['1X', '12', 'X2']
        .map(
          (pick) =>
              option(pick, pick, markets.winOrDraw[pick], 'Double Chance'),
        )
        .toList();
  }
  if (base == 'GG/NG') {
    return [
      option('GG', 'GG', markets.bothTeamsToScore['yes'], 'GG'),
      option('NG', 'NG', markets.bothTeamsToScore['no'], 'GG'),
    ];
  }
  final raw = _marketMap(fixture, _rawKeys(base));
  if (base == 'Match Winner' || base == 'Draw No Bet') {
    final key = base == 'Draw No Bet' ? 'DNB' : 'Match Winner';
    final hasTwoWay =
        markets.oneXTwo != null && marketPrice(markets.oneXTwo!.draw).isEmpty;
    final home =
        raw['home'] ??
        raw['1'] ??
        (base == 'Match Winner' && hasTwoWay ? markets.oneXTwo!.home : null);
    final away =
        raw['away'] ??
        raw['2'] ??
        (base == 'Match Winner' && hasTwoWay ? markets.oneXTwo!.away : null);
    return [
      option('1', base == 'Draw No Bet' ? 'Home DNB' : '1', home, key),
      if (base == 'Match Winner' &&
          marketPrice(raw['draw'] ?? raw['X']).isNotEmpty)
        option('X', 'X', raw['draw'] ?? raw['X'], key),
      option('2', base == 'Draw No Bet' ? 'Away DNB' : '2', away, key),
    ];
  }
  final prediction = fixture.prediction;
  final predictionLine =
      prediction != null &&
          predictionHomeMarket(prediction.prediction, sport) == base
      ? predictionTotalLine(prediction.prediction)
      : null;
  final lines = homeMarketLines(fixture, base);
  final line = explicitLine != null
      ? double.parse(explicitLine[1]!)
      : predictionLine ?? (lines.isNotEmpty ? lines.first : null);
  Map<dynamic, dynamic> prices = raw;
  if (line != null) {
    for (final entry in raw.entries) {
      if (double.tryParse(entry.key.toString()) == line && entry.value is Map) {
        prices = entry.value as Map;
      }
    }
    if (prices['line'] != null &&
        double.tryParse(prices['line'].toString()) != line) {
      prices = const {};
    }
  }
  if (['Over/Under', 'Total Sets', 'Corners', 'Cards'].contains(base)) {
    if (line == null) {
      return [
        option('Over', 'Over', null, base),
        option('Under', 'Under', null, base),
      ];
    }
    final lineText = _lineLabel(line);
    final suffix = switch (base) {
      'Total Sets' => ' Sets',
      'Corners' => ' Corners',
      'Cards' => ' Total Cards',
      _ => '',
    };
    final over = 'Over $lineText$suffix';
    final under = 'Under $lineText$suffix';
    final marketKey = base == 'Over/Under' ? 'OU$lineText' : '$base $lineText';
    // Compact goals picks retain the same selection keys as prediction badges.
    final compact =
        normalizeSportKey(sport) == 'football' ||
        normalizeSportKey(sport) == 'soccer';
    return [
      option(
        'O$lineText',
        compact && base == 'Over/Under'
            ? 'O${(line * 10).round().toString().padLeft(2, '0')}'
            : over,
        prices['over'] ?? prices[over],
        marketKey,
      ),
      option(
        'U$lineText',
        compact && base == 'Over/Under'
            ? 'U${(line * 10).round().toString().padLeft(2, '0')}'
            : under,
        prices['under'] ?? prices[under],
        marketKey,
      ),
    ];
  }
  // Handicaps require a supplied line: a bare home/away price is ambiguous.
  if (['Handicap', 'Run Line', 'Set Handicap'].contains(base)) {
    final suppliedLine =
        prices['line']?.toString() ?? (line == null ? '' : _lineLabel(line));
    if (suppliedLine.isEmpty) {
      return [
        option('1', 'Home Handicap', null, base),
        option('2', 'Away Handicap', null, base),
      ];
    }
    final number = double.tryParse(suppliedLine);
    if (number == null) return const [];
    final homeLine = number > 0 ? '+${_lineLabel(number)}' : _lineLabel(number);
    final awayLine = -number > 0
        ? '+${_lineLabel(-number)}'
        : _lineLabel(-number);
    final suffix = base == 'Set Handicap' ? ' Sets' : '';
    return [
      option(
        '1 $homeLine',
        'Home $homeLine$suffix',
        prices['home'] ?? prices['1'],
        base,
      ),
      option(
        '2 $awayLine',
        'Away $awayLine$suffix',
        prices['away'] ?? prices['2'],
        base,
      ),
    ];
  }
  return const [];
}

List<FixtureModel> filterHomeFixtures(
  List<FixtureModel> fixtures,
  String market,
  String sport,
) {
  if (market == 'All Markets') {
    return fixtures.map((fixture) {
      if (fixture.predictions.isEmpty) return fixture;
      final pred = fixture.prediction;
      final isDummy =
          pred != null &&
          pred.prediction.toUpperCase().trim() == 'O15' &&
          (pred.predictionOdds == '1.32' || pred.predictionOdds.isEmpty);
      if (pred == null || isDummy) {
        final nonDummy = fixture.predictions
            .where(
              (p) =>
                  !(p.prediction.toUpperCase().trim() == 'O15' &&
                      (p.predictionOdds == '1.32' || p.predictionOdds.isEmpty)),
            )
            .toList();
        final pool = nonDummy.isNotEmpty ? nonDummy : fixture.predictions;
        final sorted = List<PredictionModel>.from(pool)
          ..sort((a, b) {
            final probCmp = b.probability.compareTo(a.probability);
            if (probCmp != 0) return probCmp;
            return (b.effectiveOdds.isNotEmpty ? 1 : 0).compareTo(
              a.effectiveOdds.isNotEmpty ? 1 : 0,
            );
          });
        return fixture.withPrediction(sorted.first);
      }
      return fixture;
    }).toList();
  }
  final base = baseHomeMarket(market);
  final result = <FixtureModel>[];
  for (final fixture in fixtures) {
    final predictions = [
      if (fixture.prediction != null) fixture.prediction!,
      ...fixture.predictions,
    ];
    final matching =
        predictions
            .where(
              (prediction) =>
                  predictionHomeMarket(prediction.prediction, sport) == base,
            )
            .toList()
          ..sort((a, b) => b.probability.compareTo(a.probability));
    final probabilityPrediction = homeMarketProbabilityPrediction(
      fixture,
      market,
      sport,
    );
    if (matching.isNotEmpty) {
      result.add(
        fixture.prediction?.id == matching.first.id
            ? fixture
            : fixture.withPrediction(matching.first),
      );
    } else if (probabilityPrediction != null) {
      result.add(fixture.withPrediction(probabilityPrediction));
    } else if (homeMarketOdds(
      fixture,
      market,
      sport,
    ).any((option) => option.odd.isNotEmpty)) {
      // A prediction for a different market should not appear under this filter.
      result.add(
        FixtureModel.fromJson({
          ...fixture.toJson(),
          'markets': fixture.effectiveMarkets.toJson(),
          'prediction': null,
          'predictions': [],
          'league_has_predictions':
              fixture.leagueHasPredictions ||
              fixture.prediction != null ||
              fixture.predictions.isNotEmpty,
        }),
      );
    }
  }
  return result;
}

String homeOddsSelectionKey(
  String fixtureId,
  String marketKey,
  String selection,
) => marketKey.toUpperCase() == '1X2'
    ? '$fixtureId-$selection'
    : '$fixtureId-$marketKey-$selection';

HomeOddsOption? homePredictionOption(
  FixtureModel fixture,
  PredictionModel prediction,
  String sport,
) {
  final market = predictionHomeMarket(prediction.prediction, sport);
  if (market == null) return null;
  final options = homeMarketOdds(
    fixture.withPrediction(prediction),
    market,
    sport,
  );
  final rawPick = prediction.prediction.toUpperCase().trim();
  final dnbPick =
      market == 'Draw No Bet' &&
          RegExp(
            r'^(?:HOME|1)\b|^DNB\s*1$',
            caseSensitive: false,
          ).hasMatch(rawPick)
      ? 'HOME DNB'
      : market == 'Draw No Bet' &&
            RegExp(
              r'^(?:AWAY|2)\b|^DNB\s*2$',
              caseSensitive: false,
            ).hasMatch(rawPick)
      ? 'AWAY DNB'
      : rawPick;
  final pick = switch (dnbPick) {
    'HOME' => '1',
    'AWAY' => '2',
    'BTTS' || 'BTTS YES' => 'GG',
    'BTTS NO' || 'NO GG' => 'NG',
    _ => dnbPick,
  };
  for (final option in options) {
    if (option.selection.toUpperCase() == pick) return option;
  }
  if (market == 'Draw No Bet') {
    final wantsAway = pick.contains('AWAY') || pick.startsWith('2');
    final wantsHome = pick.contains('HOME') || pick.startsWith('1');
    for (final option in options) {
      final candidate = option.selection.toUpperCase();
      if (wantsHome && (candidate.contains('HOME') || candidate == '1')) {
        return option;
      }
      if (wantsAway && (candidate.contains('AWAY') || candidate == '2')) {
        return option;
      }
    }
  }
  if (const {'Corners', 'Cards'}.contains(market)) {
    final predictionLine = predictionTotalLine(prediction.prediction);
    final wantsUnder = pick.startsWith('UNDER') || pick.startsWith('U');
    for (final option in options) {
      final candidate = option.selection.toUpperCase();
      final sameDirection = wantsUnder
          ? candidate.startsWith('UNDER') || candidate == 'U'
          : candidate.startsWith('OVER') || candidate == 'O';
      if (!sameDirection) continue;
      final optionLine =
          predictionTotalLine(option.selection) ??
          double.tryParse(
            RegExp(
                  r'(?:total|line)=([+-]?\d+(?:\.\d+)?)',
                  caseSensitive: false,
                ).firstMatch(option.sportySpecifier)?.group(1) ??
                '',
          );
      if (predictionLine == null ||
          optionLine == null ||
          predictionLine == optionLine) {
        return option;
      }
    }
  }
  if (market == 'Over/Under') {
    final line = predictionTotalLine(prediction.prediction);
    final over = pick.startsWith('O');
    if (line != null) {
      for (final option in options) {
        if (predictionTotalLine(option.selection) == line &&
            option.selection.toUpperCase().startsWith(over ? 'O' : 'U')) {
          return option;
        }
      }
    }
  }
  return null;
}

String homePredictionOdds(
  FixtureModel fixture,
  PredictionModel prediction,
  String sport,
) {
  final price = homePredictionOption(fixture, prediction, sport)?.odd ?? '';
  return price.isNotEmpty ? price : fixture.oddsForPrediction(prediction);
}
