import 'dart:convert';
import 'stream_model.dart';

export 'stream_model.dart';

String _string(dynamic value) => value?.toString() ?? '';
String _validOdds(dynamic value) {
  final text = _string(value).trim();
  final price = double.tryParse(text);
  return price != null && price.isFinite && price > 1 ? text : '';
}

String _oddsSelectionKey(String value) {
  final pick = value.toUpperCase().trim();
  final short = RegExp(r'^([OU])(\d+(?:\.\d+)?)$').firstMatch(pick);
  final full = RegExp(r'^(OVER|UNDER)\s+(\d+(?:\.\d+)?)$').firstMatch(pick);
  if (short != null || full != null) {
    final line = short != null
        ? double.parse(short[2]!) / (short[2]!.contains('.') ? 1 : 10)
        : double.parse(full![2]!);
    final direction = short != null ? short[1]! : full![1]![0];
    return '$direction$line';
  }
  return switch (pick) {
    'HOME' => '1',
    'AWAY' => '2',
    'BTTS' || 'BTTS YES' => 'GG',
    'BTTS NO' || 'NO GG' => 'NG',
    _ => pick,
  };
}

Map<String, dynamic> _mergeMarketPrices(
  Map<String, dynamic> preferred,
  Map<String, dynamic> fallback,
) {
  Map<String, dynamic> totals(dynamic raw) {
    final value = _map(raw);
    final line = double.tryParse(_string(value['line']));
    if (line == null) return value;
    if (_validOdds(value['over']).isEmpty &&
        _validOdds(value['under']).isEmpty) {
      return {};
    }
    return {
      line.toString(): {'over': value['over'], 'under': value['under']},
    };
  }

  final result = <String, dynamic>{...fallback};
  for (final entry in preferred.entries) {
    final old = entry.key == 'over_under'
        ? totals(result[entry.key])
        : result[entry.key];
    final incoming = entry.key == 'over_under'
        ? totals(entry.value)
        : entry.value;
    if (incoming is Map) {
      result[entry.key] = _mergeMarketPrices(_map(incoming), _map(old));
    } else if (incoming is List) {
      // Preserve exact provider market/outcome arrays while merging the
      // compact prediction odds into the same fixture market payload.
      result[entry.key] = incoming;
    } else if (entry.key == 'line' || _validOdds(incoming).isNotEmpty) {
      result[entry.key] = incoming;
    }
  }
  if (result.containsKey('over_under')) {
    result['over_under'] = totals(result['over_under']);
  }
  return result;
}

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(_string(value)) ?? 0;
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
Map<String, dynamic> _predictionProbabilities(dynamic raw) {
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } on FormatException {
      return const {};
    }
  }
  final result = <String, dynamic>{};
  for (final entry in _map(raw).entries) {
    if (const {
      'extra',
      'probabilities',
      'probability',
      'market_probabilities',
    }.contains(entry.key)) {
      result.addAll(_predictionProbabilities(entry.value));
    } else if (entry.value is num || entry.value is String) {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

String _jsonString(dynamic value) =>
    value is String ? value : jsonEncode(value ?? <String, dynamic>{});

class ProviderMappingModel {
  final String id;
  final String fixtureId;
  final String provider;
  final String sourceFixtureId;
  final String sourceLeagueId;
  const ProviderMappingModel({
    this.id = '',
    this.fixtureId = '',
    this.provider = '',
    this.sourceFixtureId = '',
    this.sourceLeagueId = '',
  });
  factory ProviderMappingModel.fromJson(Map<String, dynamic> json) =>
      ProviderMappingModel(
        id: _string(json['id']),
        fixtureId: _string(json['fixture_id']),
        provider: _string(json['provider']),
        sourceFixtureId: _string(json['source_fixture_id']),
        sourceLeagueId: _string(json['source_league_id']),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'fixture_id': fixtureId,
    'provider': provider,
    'source_fixture_id': sourceFixtureId,
    'source_league_id': sourceLeagueId,
  };
}

class Market1X2Model {
  final String home;
  final String draw;
  final String away;
  const Market1X2Model({this.home = '', this.draw = '', this.away = ''});
  factory Market1X2Model.fromJson(Map<String, dynamic> json) => Market1X2Model(
    home: _string(json['home']),
    draw: _string(json['draw']),
    away: _string(json['away']),
  );
  Map<String, dynamic> toJson() => {'home': home, 'draw': draw, 'away': away};
}

class FixtureMarketsModel {
  final Market1X2Model? oneXTwo;
  final Map<String, String> bothTeamsToScore;
  final Map<String, String> winOrDraw;
  final Map<String, String> overUnder;
  final Map<String, dynamic> rawMarkets;
  const FixtureMarketsModel({
    this.oneXTwo,
    this.bothTeamsToScore = const {},
    this.winOrDraw = const {},
    this.overUnder = const {},
    this.rawMarkets = const {},
  });
  static Map<String, String> _strings(dynamic value) =>
      _map(value).map((key, value) => MapEntry(key, _string(value)));
  factory FixtureMarketsModel.fromJson(Map<String, dynamic> json) =>
      FixtureMarketsModel(
        oneXTwo: json['1x2'] is Map
            ? Market1X2Model.fromJson(_map(json['1x2']))
            : null,
        bothTeamsToScore: _strings(json['gg']),
        winOrDraw: _strings(json['winordraw']),
        overUnder: _strings(json['over_under']),
        rawMarkets: Map<String, dynamic>.from(json),
      );
  Map<String, dynamic> toJson() => {
    ...rawMarkets,
    if (oneXTwo != null) '1x2': oneXTwo!.toJson(),
    'gg': bothTeamsToScore,
    'winordraw': winOrDraw,
    'over_under': rawMarkets['over_under'] ?? overUnder,
  };

  String oddsFor(String selection) {
    final pick = selection.toUpperCase().trim();
    String valid(dynamic value) {
      final text = _string(value).trim();
      final price = double.tryParse(text);
      return price != null && price.isFinite && price > 1 ? text : '';
    }

    if (pick == '1') return valid(oneXTwo?.home);
    if (pick == 'X') return valid(oneXTwo?.draw);
    if (pick == '2') return valid(oneXTwo?.away);
    if (const ['1X', '12', 'X2'].contains(pick)) {
      return valid(winOrDraw[pick]);
    }
    if (const ['GG', 'BTTS', 'BTTS YES'].contains(pick)) {
      return valid(bothTeamsToScore['yes']);
    }
    if (const ['NG', 'NO GG', 'BTTS NO'].contains(pick)) {
      return valid(bothTeamsToScore['no']);
    }
    final short = RegExp(r'^([OU])(\d+(?:\.\d+)?)$').firstMatch(pick);
    final total = RegExp(r'^(OVER|UNDER)\s+(\d+(?:\.\d+)?)$').firstMatch(pick);
    if (short != null || total != null) {
      final direction = short != null
          ? (short[1] == 'O' ? 'over' : 'under')
          : total![1]!.toLowerCase();
      final line = short != null
          ? double.parse(short[2]!) / (short[2]!.contains('.') ? 1 : 10)
          : double.parse(total![2]!);
      if (double.tryParse(overUnder['line'] ?? '') == line) {
        return valid(overUnder[direction]);
      }
      final totals = rawMarkets['over_under'];
      if (totals is Map) {
        final prices = totals[line.toString()];
        if (prices is Map) return valid(prices[direction]);
        for (final entry in totals.entries) {
          if (entry.key.toString().toUpperCase().trim() == pick) {
            return valid(entry.value);
          }
        }
      }
      return '';
    }
    // Match explicit selection keys for additional markets without substituting
    // a different market or total line.
    for (final market in rawMarkets.values) {
      if (market is Map) {
        for (final entry in market.entries) {
          if (entry.key.toString().toUpperCase().trim() == pick) {
            final price = valid(entry.value);
            if (price.isNotEmpty) return price;
          }
        }
      }
    }
    return '';
  }
}

class PredictionModel {
  final Map<String, dynamic> marketProbabilities;
  final Map<String, dynamic> bookmakers;
  final String id;
  final String? fixtureId;
  final int sportId;
  final String sportyEventId;
  final String sportyMarketId;
  final String sportyOutcomeId;
  final String sportySpecifier;
  final String provider;
  final String market;
  final String tag;
  final bool isPlayerProp;
  final String prediction;
  final String predictionOdds;
  final String oddsSource;
  final int probability;
  final String status;
  final int? suggestionResult;
  final String odd1;
  final String oddX;
  final String odd2;
  final Map<String, String> marketOdds;
  final String homeTeam;
  final String awayTeam;
  final String leagueName;
  final DateTime? matchTime;
  const PredictionModel({
    this.marketProbabilities = const {},
    this.bookmakers = const {},
    required this.id,
    this.fixtureId,
    this.sportId = 1,
    this.sportyEventId = '',
    this.sportyMarketId = '',
    this.sportyOutcomeId = '',
    this.sportySpecifier = '',
    this.provider = '',
    this.market = '',
    this.tag = '',
    this.isPlayerProp = false,
    required this.prediction,
    this.predictionOdds = '',
    this.oddsSource = '',
    this.probability = 0,
    this.status = 'pending',
    this.suggestionResult,
    this.odd1 = '',
    this.oddX = '',
    this.odd2 = '',
    this.marketOdds = const {},
    this.homeTeam = '',
    this.awayTeam = '',
    this.leagueName = '',
    this.matchTime,
  });
  bool get isWon => status.toLowerCase() == 'won' || suggestionResult == 1;
  bool get isLost => status.toLowerCase() == 'lost' || suggestionResult == 2;
  bool get isPending => !isWon && !isLost;
  String get selection => prediction;
  bool get hasApprovedPredictionPrice =>
      sportId != 1 ||
      provider.isEmpty ||
      provider == 'betmines' ||
      provider == 'sporty' ||
      oddsSource == 'betmines' ||
      oddsSource == 'sporty' ||
      (sportyMarketId.isNotEmpty && sportyOutcomeId.isNotEmpty);

  String get effectiveOdds {
    if (!hasApprovedPredictionPrice) return '';
    if ((oddsSource == 'sporty' ||
            oddsSource == 'betmines' ||
            (sportyMarketId.isNotEmpty && sportyOutcomeId.isNotEmpty)) &&
        _validOdds(predictionOdds).isNotEmpty)
      return predictionOdds;
    final p = prediction.toUpperCase().trim();
    if (p == '1' && _validOdds(odd1).isNotEmpty) return odd1;
    if (p == 'X' && _validOdds(oddX).isNotEmpty) return oddX;
    if (p == '2' && _validOdds(odd2).isNotEmpty) return odd2;
    if (p == '1X' && _validOdds(marketOdds['odd_1x']).isNotEmpty) {
      return marketOdds['odd_1x']!;
    }
    if (p == '12' && _validOdds(marketOdds['odd_12']).isNotEmpty) {
      return marketOdds['odd_12']!;
    }
    if (p == 'X2' && _validOdds(marketOdds['odd_x2']).isNotEmpty) {
      return marketOdds['odd_x2']!;
    }
    if ((p == 'O25' || p == 'OVER 2.5') &&
        _validOdds(marketOdds['odd_over_25']).isNotEmpty) {
      return marketOdds['odd_over_25']!;
    }
    if ((p == 'U25' || p == 'UNDER 2.5') &&
        _validOdds(marketOdds['odd_under_25']).isNotEmpty) {
      return marketOdds['odd_under_25']!;
    }
    if ((p == 'GG' || p == 'BTTS' || p == 'BTTS YES') &&
        _validOdds(marketOdds['odd_goal']).isNotEmpty) {
      return marketOdds['odd_goal']!;
    }
    if ((p == 'NG' || p == 'NO GG' || p == 'BTTS NO') &&
        _validOdds(marketOdds['odd_no_goal']).isNotEmpty) {
      return marketOdds['odd_no_goal']!;
    }
    if (predictionOdds.isNotEmpty && _validOdds(predictionOdds).isNotEmpty) {
      return predictionOdds;
    }
    return '';
  }

  factory PredictionModel.fromJson(
    Map<String, dynamic> json,
  ) => PredictionModel(
    marketProbabilities: _predictionProbabilities(
      json['probabilities'] ?? json['market_probabilities'] ?? json['extra'],
    ),
    bookmakers: _map(json['bookmakers']),
    oddsSource: _string(json['odds_source']),
    id: _string(json['id']),
    fixtureId: json['fixture_id'] == null ? null : _string(json['fixture_id']),
    sportId: _int(json['sport_id']) == 0 ? 1 : _int(json['sport_id']),
    sportyEventId: _string(json['sporty_event_id']),
    sportyMarketId: _string(json['sporty_market_id']),
    sportyOutcomeId: _string(json['sporty_outcome_id']),
    sportySpecifier: _string(json['sporty_specifier']),
    provider: _string(json['provider']).isNotEmpty
        ? _string(json['provider'])
        : _string(json['source']),
    market: _string(json['market']),
    tag: _string(json['tag']),
    isPlayerProp: json['is_player_prop'] == true,
    prediction: _string(json['prediction']).isNotEmpty
        ? _string(json['prediction'])
        : _string(json['selection']),
    predictionOdds: _string(json['prediction_odds']).isNotEmpty
        ? _string(json['prediction_odds'])
        : _string(json['odds']),
    probability: _int(json['probability']) > 0
        ? _int(json['probability'])
        : _int(json['confidence']),
    status: _string(json['status']).isEmpty
        ? 'pending'
        : _string(json['status']),
    suggestionResult: json['suggestion_result'] == null
        ? null
        : _int(json['suggestion_result']),
    odd1: _string(json['odd_1']),
    oddX: _string(json['odd_x']),
    odd2: _string(json['odd_2']),
    marketOdds: {
      for (final key in [
        'odd_1x',
        'odd_12',
        'odd_x2',
        'odd_over_25',
        'odd_under_25',
        'odd_goal',
        'odd_no_goal',
      ])
        key: _string(json[key]),
    },
    homeTeam: _string(json['home_team']),
    awayTeam: _string(json['away_team']),
    leagueName: _string(json['league_name']).isNotEmpty
        ? _string(json['league_name'])
        : _string(json['league']),
    matchTime: DateTime.tryParse(_string(json['match_time'])),
  );
  Map<String, dynamic> toJson() => {
    if (marketProbabilities.isNotEmpty) 'probabilities': marketProbabilities,
    if (bookmakers.isNotEmpty) 'bookmakers': bookmakers,
    'id': id,
    if (fixtureId != null) 'fixture_id': fixtureId,
    'sport_id': sportId,
    if (sportyEventId.isNotEmpty) 'sporty_event_id': sportyEventId,
    if (sportyMarketId.isNotEmpty) 'sporty_market_id': sportyMarketId,
    if (sportyOutcomeId.isNotEmpty) 'sporty_outcome_id': sportyOutcomeId,
    if (sportySpecifier.isNotEmpty) 'sporty_specifier': sportySpecifier,
    'provider': provider,
    if (market.isNotEmpty) 'market': market,
    if (tag.isNotEmpty) 'tag': tag,
    'is_player_prop': isPlayerProp,
    'prediction': prediction,
    'prediction_odds': predictionOdds,
    'odds_source': oddsSource,
    'probability': probability,
    'status': status,
    if (suggestionResult != null) 'suggestion_result': suggestionResult,
    'odd_1': odd1,
    'odd_x': oddX,
    'odd_2': odd2,
    ...marketOdds,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'league_name': leagueName,
    if (matchTime != null) 'match_time': matchTime!.toIso8601String(),
  };
}

class FixtureModel {
  final String id;
  final int sportId;
  final String leagueId;
  final String leagueName;
  final String country;
  final String homeTeam;
  final String awayTeam;
  final String normalizedHome;
  final String normalizedAway;
  final DateTime matchTime;
  final String status;
  final int homeScore;
  final int awayScore;
  final String periodScores;
  final String stats;
  final Map<String, dynamic> marketProbabilities;
  final List<ProviderMappingModel> providerMappings;
  final bool sportyBetAvailable;
  final bool sportyBetSynced;
  final String sportyEventId;
  final FixtureMarketsModel? markets;
  final bool leagueHasPredictions;
  final PredictionModel? prediction;
  final List<PredictionModel> predictions;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const FixtureModel({
    required this.id,
    required this.sportId,
    required this.leagueId,
    required this.leagueName,
    required this.country,
    required this.homeTeam,
    required this.awayTeam,
    required this.normalizedHome,
    required this.normalizedAway,
    required this.matchTime,
    required this.status,
    required this.homeScore,
    required this.awayScore,
    required this.periodScores,
    required this.stats,
    this.marketProbabilities = const {},
    this.providerMappings = const [],
    this.sportyBetAvailable = false,
    this.sportyBetSynced = false,
    this.sportyEventId = '',
    this.markets,
    this.leagueHasPredictions = false,
    this.prediction,
    this.predictions = const [],
    this.createdAt,
    this.updatedAt,
  });

  FixtureMarketsModel get effectiveMarkets {
    var prices = markets?.toJson() ?? <String, dynamic>{};
    for (final p in [?prediction, ...predictions]) {
      if (!p.hasApprovedPredictionPrice) continue;
      final pick = p.prediction.toUpperCase().trim();
      final odd = p.effectiveOdds;
      prices = _mergeMarketPrices(prices, {
        '1x2': {
          'home': pick == '1' && odd.isNotEmpty ? odd : p.odd1,
          'draw': pick == 'X' && odd.isNotEmpty ? odd : p.oddX,
          'away': pick == '2' && odd.isNotEmpty ? odd : p.odd2,
        },
        'winordraw': {
          '1X': pick == '1X' && odd.isNotEmpty ? odd : p.marketOdds['odd_1x'],
          '12': pick == '12' && odd.isNotEmpty ? odd : p.marketOdds['odd_12'],
          'X2': pick == 'X2' && odd.isNotEmpty ? odd : p.marketOdds['odd_x2'],
        },
        'gg': {
          'yes': (pick == 'GG' || pick == 'BTTS') && odd.isNotEmpty
              ? odd
              : p.marketOdds['odd_goal'],
          'no': (pick == 'NG' || pick == 'NO GG') && odd.isNotEmpty
              ? odd
              : p.marketOdds['odd_no_goal'],
        },
        'over_under': {
          'line': '2.5',
          'over': (pick == 'O25' || pick == 'OVER 2.5') && odd.isNotEmpty
              ? odd
              : p.marketOdds['odd_over_25'],
          'under': (pick == 'U25' || pick == 'UNDER 2.5') && odd.isNotEmpty
              ? odd
              : p.marketOdds['odd_under_25'],
        },
      });
      for (final line in const ['1.5', '3.5']) {
        final over =
            pick == 'O${line.replaceAll('.', '')}' || pick == 'OVER $line'
            ? odd
            : '';
        final under =
            pick == 'U${line.replaceAll('.', '')}' || pick == 'UNDER $line'
            ? odd
            : '';
        if (over.isNotEmpty || under.isNotEmpty) {
          prices = _mergeMarketPrices(prices, {
            'over_under': {'line': line, 'over': over, 'under': under},
          });
        }
      }
    }
    return FixtureMarketsModel.fromJson(prices);
  }

  String oddsForSelection(String selection) {
    final market = effectiveMarkets.oddsFor(selection);
    if (market.isNotEmpty) return market;
    for (final p in [?prediction, ...predictions]) {
      if (_oddsSelectionKey(p.prediction) == _oddsSelectionKey(selection)) {
        final price = _validOdds(p.effectiveOdds);
        if (price.isNotEmpty) return price;
      }
    }
    return '';
  }

  String oddsForPrediction(PredictionModel value) {
    final market = oddsForSelection(value.prediction);
    return market.isNotEmpty ? market : _validOdds(value.effectiveOdds);
  }

  String get odd1 => effectiveMarkets.oddsFor('1');
  String get oddX => effectiveMarkets.oddsFor('X');
  String get odd2 => effectiveMarkets.oddsFor('2');

  List<String> get displayOdds => [odd1, oddX, odd2];
  bool get isLive => status.toLowerCase() == 'live';
  bool get isPrematch => status.toLowerCase() == 'prematch';
  bool get isFinished => const {
    'ended',
    'finished',
    'ft',
    'completed',
    'full_time',
    'final',
  }.contains(status.toLowerCase().trim().replaceAll(' ', '_'));

  FixtureModel withPrediction(PredictionModel value) => FixtureModel(
    id: id,
    sportId: sportId,
    leagueId: leagueId,
    leagueName: leagueName,
    country: country,
    homeTeam: homeTeam,
    awayTeam: awayTeam,
    normalizedHome: normalizedHome,
    normalizedAway: normalizedAway,
    matchTime: matchTime,
    status: status,
    homeScore: homeScore,
    awayScore: awayScore,
    periodScores: periodScores,
    stats: stats,
    marketProbabilities: marketProbabilities,
    providerMappings: providerMappings,
    sportyBetAvailable: sportyBetAvailable,
    sportyBetSynced: sportyBetSynced,
    sportyEventId: sportyEventId,
    markets: markets,
    leagueHasPredictions: leagueHasPredictions,
    prediction: value,
    predictions: [value, ...predictions.where((item) => item.id != value.id)],
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  FixtureModel withMarkets(FixtureMarketsModel value) => FixtureModel(
    id: id,
    sportId: sportId,
    leagueId: leagueId,
    leagueName: leagueName,
    country: country,
    homeTeam: homeTeam,
    awayTeam: awayTeam,
    normalizedHome: normalizedHome,
    normalizedAway: normalizedAway,
    matchTime: matchTime,
    status: status,
    homeScore: homeScore,
    awayScore: awayScore,
    periodScores: periodScores,
    stats: stats,
    marketProbabilities: marketProbabilities,
    providerMappings: providerMappings,
    sportyBetAvailable: sportyBetAvailable,
    sportyBetSynced: sportyBetSynced,
    sportyEventId: sportyEventId,
    markets: value,
    leagueHasPredictions: leagueHasPredictions,
    prediction: prediction,
    predictions: predictions,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  factory FixtureModel.fromJson(Map<String, dynamic> json) {
    final mappings = json['provider_mappings'] is List
        ? (json['provider_mappings'] as List)
              .whereType<Map>()
              .map((item) => ProviderMappingModel.fromJson(_map(item)))
              .toList()
        : <ProviderMappingModel>[];
    final predictions = json['predictions'] is List
        ? (json['predictions'] as List)
              .whereType<Map>()
              .map((item) => PredictionModel.fromJson(_map(item)))
              .where((item) => item.prediction.isNotEmpty)
              .toList()
        : <PredictionModel>[];
    final direct = json['prediction'] is Map
        ? PredictionModel.fromJson(_map(json['prediction']))
        : null;
    PredictionModel? primary;
    if (predictions.isNotEmpty) {
      bool isDummyFallback(PredictionModel p) =>
          p.prediction.toUpperCase().trim() == 'O15' &&
          (p.predictionOdds == '1.32' || p.predictionOdds.isEmpty);

      final validCandidates = predictions
          .where((p) => !isDummyFallback(p))
          .toList();
      final pool = validCandidates.isNotEmpty ? validCandidates : predictions;

      final sorted = List<PredictionModel>.from(pool)
        ..sort((a, b) {
          final probCmp = b.probability.compareTo(a.probability);
          if (probCmp != 0) return probCmp;
          final aHasOdds = a.effectiveOdds.isNotEmpty ? 1 : 0;
          final bHasOdds = b.effectiveOdds.isNotEmpty ? 1 : 0;
          return bHasOdds.compareTo(aHasOdds);
        });

      if (direct != null &&
          direct.prediction.isNotEmpty &&
          !isDummyFallback(direct) &&
          direct.probability >= sorted.first.probability) {
        primary = direct;
      } else {
        primary = sorted.first;
      }
    } else if (direct?.prediction.isNotEmpty == true) {
      primary = direct;
    }
    return FixtureModel(
      id: _string(json['id']),
      sportId: _int(json['sport_id']),
      leagueId: _string(json['league_id']),
      leagueName: _string(json['league_name']),
      country: _string(json['country']),
      homeTeam: _string(json['home_team']),
      awayTeam: _string(json['away_team']),
      normalizedHome: _string(json['normalized_home']),
      normalizedAway: _string(json['normalized_away']),
      matchTime:
          DateTime.tryParse(_string(json['match_time'])) ?? DateTime.now(),
      status: _string(json['status']).isEmpty
          ? 'prematch'
          : _string(json['status']),
      homeScore: _int(json['home_score']),
      awayScore: _int(json['away_score']),
      periodScores: _jsonString(json['period_scores']),
      stats: _jsonString(json['stats']),
      marketProbabilities: _map(json['probability']),
      providerMappings: mappings,
      sportyBetAvailable: json['sportybet_available'] == true,
      sportyBetSynced: json['sportybet_synced'] == true,
      sportyEventId: _string(json['sporty_event_id']),
      markets: json['markets'] is Map
          ? FixtureMarketsModel.fromJson(_map(json['markets']))
          : null,
      leagueHasPredictions: json['league_has_predictions'] == true,
      prediction: primary,
      predictions: predictions,
      createdAt: DateTime.tryParse(_string(json['created_at'])),
      updatedAt: DateTime.tryParse(_string(json['updated_at'])),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'sport_id': sportId,
    'league_id': leagueId,
    'league_name': leagueName,
    'country': country,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'normalized_home': normalizedHome,
    'normalized_away': normalizedAway,
    'match_time': matchTime.toIso8601String(),
    'status': status,
    'home_score': homeScore,
    'away_score': awayScore,
    'period_scores': periodScores,
    'stats': stats,
    if (marketProbabilities.isNotEmpty) 'probability': marketProbabilities,
    'provider_mappings': providerMappings.map((item) => item.toJson()).toList(),
    'sportybet_available': sportyBetAvailable,
    'sportybet_synced': sportyBetSynced,
    if (sportyEventId.isNotEmpty) 'sporty_event_id': sportyEventId,
    if (markets != null) 'markets': markets!.toJson(),
    if (prediction != null) 'prediction': prediction!.toJson(),
    'league_has_predictions': leagueHasPredictions,
    'predictions': predictions.map((item) => item.toJson()).toList(),
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
  };
  @override
  bool operator ==(Object other) => other is FixtureModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class MatchStatsModel {
  final int possessionHome, possessionAway;
  final int shotsOnTargetHome, shotsOnTargetAway;
  final int totalShotsHome, totalShotsAway;
  final int cornersHome, cornersAway;
  final int yellowCardsHome, yellowCardsAway;
  final int redCardsHome, redCardsAway;
  final int foulsHome, foulsAway;
  final int offsidesHome, offsidesAway;
  const MatchStatsModel({
    this.possessionHome = 0,
    this.possessionAway = 0,
    this.shotsOnTargetHome = 0,
    this.shotsOnTargetAway = 0,
    this.totalShotsHome = 0,
    this.totalShotsAway = 0,
    this.cornersHome = 0,
    this.cornersAway = 0,
    this.yellowCardsHome = 0,
    this.yellowCardsAway = 0,
    this.redCardsHome = 0,
    this.redCardsAway = 0,
    this.foulsHome = 0,
    this.foulsAway = 0,
    this.offsidesHome = 0,
    this.offsidesAway = 0,
  });
  factory MatchStatsModel.fromJson(Map<String, dynamic> json) =>
      MatchStatsModel(
        possessionHome: _int(json['possession_home']),
        possessionAway: _int(json['possession_away']),
        shotsOnTargetHome: _int(json['shots_on_target_home']),
        shotsOnTargetAway: _int(json['shots_on_target_away']),
        totalShotsHome: _int(json['total_shots_home']),
        totalShotsAway: _int(json['total_shots_away']),
        cornersHome: _int(json['corners_home']),
        cornersAway: _int(json['corners_away']),
        yellowCardsHome: _int(json['yellow_cards_home']),
        yellowCardsAway: _int(json['yellow_cards_away']),
        redCardsHome: _int(json['red_cards_home']),
        redCardsAway: _int(json['red_cards_away']),
        foulsHome: _int(json['fouls_home']),
        foulsAway: _int(json['fouls_away']),
        offsidesHome: _int(json['offsides_home']),
        offsidesAway: _int(json['offsides_away']),
      );
}

class H2HMatchModel {
  final String homeTeam, awayTeam, leagueName;
  final int homeScore, awayScore;
  final DateTime date;
  const H2HMatchModel({
    this.homeTeam = '',
    this.awayTeam = '',
    this.leagueName = '',
    this.homeScore = 0,
    this.awayScore = 0,
    required this.date,
  });
  factory H2HMatchModel.fromJson(Map<String, dynamic> json) => H2HMatchModel(
    homeTeam: _string(json['home_team']),
    awayTeam: _string(json['away_team']),
    leagueName: _string(json['league_name']),
    homeScore: _int(json['home_score']),
    awayScore: _int(json['away_score']),
    date:
        DateTime.tryParse(_string(json['date'] ?? json['match_time'])) ??
        DateTime.now(),
  );
}

class H2HSummaryModel {
  final int totalMatches, homeWins, awayWins, draws;
  final List<H2HMatchModel> matches;
  const H2HSummaryModel({
    this.totalMatches = 0,
    this.homeWins = 0,
    this.awayWins = 0,
    this.draws = 0,
    this.matches = const [],
  });
  factory H2HSummaryModel.fromJson(Map<String, dynamic> json) =>
      H2HSummaryModel(
        totalMatches: _int(json['total_matches']),
        homeWins: _int(json['home_wins']),
        awayWins: _int(json['away_wins']),
        draws: _int(json['draws']),
        matches: json['matches'] is List
            ? (json['matches'] as List)
                  .whereType<Map<String, dynamic>>()
                  .map(H2HMatchModel.fromJson)
                  .toList()
            : const [],
      );
}

class MatchEventModel {
  final int minute;
  final String type, team, playerName, detail, currentScore;
  const MatchEventModel({
    this.minute = 0,
    this.type = '',
    this.team = '',
    this.playerName = '',
    this.detail = '',
    this.currentScore = '',
  });
  factory MatchEventModel.fromJson(Map<String, dynamic> json) =>
      MatchEventModel(
        minute: _int(json['minute']),
        type: _string(json['type']),
        team: _string(json['team']),
        playerName: _string(json['player_name']),
        detail: _string(json['detail']),
        currentScore: _string(json['current_score']),
      );
}

class EnrichedFixtureDetailModel {
  final FixtureModel fixture;
  final Map<String, dynamic> periodScores;
  final MatchStatsModel stats;
  final H2HSummaryModel h2h;
  final List<MatchEventModel> timeline;
  final FixtureStreamsModel? streams;

  const EnrichedFixtureDetailModel({
    required this.fixture,
    this.periodScores = const {},
    this.stats = const MatchStatsModel(),
    this.h2h = const H2HSummaryModel(),
    this.timeline = const [],
    this.streams,
  });

  EnrichedFixtureDetailModel copyWithStreams(FixtureStreamsModel streams) {
    return EnrichedFixtureDetailModel(
      fixture: fixture,
      periodScores: periodScores,
      stats: stats,
      h2h: h2h,
      timeline: timeline,
      streams: streams,
    );
  }

  factory EnrichedFixtureDetailModel.fromJson(Map<String, dynamic> json) {
    final fixtureJson = json['fixture'] is Map ? _map(json['fixture']) : json;
    final streamsJson = json['streams'] is Map
        ? FixtureStreamsModel.fromJson(_map(json['streams']))
        : null;
    return EnrichedFixtureDetailModel(
      fixture: FixtureModel.fromJson(fixtureJson),
      periodScores: _map(json['period_scores']),
      stats: MatchStatsModel.fromJson(_map(json['stats'])),
      h2h: H2HSummaryModel.fromJson(_map(json['h2h'])),
      timeline: json['timeline'] is List
          ? (json['timeline'] as List)
                .whereType<Map>()
                .map((m) => MatchEventModel.fromJson(_map(m)))
                .toList()
          : const [],
      streams: streamsJson,
    );
  }
}
