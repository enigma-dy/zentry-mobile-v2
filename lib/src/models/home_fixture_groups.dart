import 'fixture_model.dart';

Map<String, List<FixtureModel>> groupHomeFixturesByLeague(
  List<FixtureModel> fixtures,
) {
  final Map<String, List<FixtureModel>> grouped = {};
  for (final fx in fixtures) {
    final leagueName = fx.leagueName.isNotEmpty
        ? fx.leagueName
        : 'Featured League';
    final key = fx.country.isNotEmpty
        ? '${fx.country} - $leagueName'
        : leagueName;
    grouped.putIfAbsent(key, () => []).add(fx);
  }

  bool fixtureHasPrediction(FixtureModel fx) {
    if (fx.prediction != null && fx.prediction!.prediction.trim().isNotEmpty) {
      return true;
    }
    if (fx.predictions.any((p) => p.prediction.trim().isNotEmpty)) {
      return true;
    }
    return false;
  }

  bool leagueHasPrediction(List<FixtureModel> matches) =>
      matches.any((fx) => fx.leagueHasPredictions || fixtureHasPrediction(fx));

  final entries = grouped.entries.toList();

  // 1. Sort fixtures inside each league: predicted fixtures first, then by matchTime
  for (final entry in entries) {
    entry.value.sort((a, b) {
      final aPred = fixtureHasPrediction(a) ? 1 : 0;
      final bPred = fixtureHasPrediction(b) ? 1 : 0;
      if (aPred != bPred) return bPred.compareTo(aPred);
      return a.matchTime.compareTo(b.matchTime);
    });
  }

  // 2. Sort leagues: leagues with predictions first, then alphabetically
  entries.sort((a, b) {
    final aHasPred = leagueHasPrediction(a.value);
    final bHasPred = leagueHasPrediction(b.value);
    if (aHasPred != bHasPred) {
      return bHasPred ? 1 : -1;
    }
    final byLeague = a.value.first.leagueName.toLowerCase().compareTo(
      b.value.first.leagueName.toLowerCase(),
    );
    return byLeague != 0
        ? byLeague
        : a.key.toLowerCase().compareTo(b.key.toLowerCase());
  });

  return Map.fromEntries(entries);
}
