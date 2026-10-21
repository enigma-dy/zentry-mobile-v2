import 'fixture_model.dart';
import 'league_model.dart';

String homeFixtureDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

Map<String, int> homeFixtureCountries(List<FixtureModel> fixtures) {
  final countries = <String, int>{};
  for (final fixture in fixtures) {
    final country = fixture.country.trim();
    if (country.isEmpty ||
        ['international', 'world', 'europe'].contains(country.toLowerCase())) {
      continue;
    }
    countries[country] = (countries[country] ?? 0) + 1;
  }
  final sorted = countries.entries.toList()
    ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  return Map.fromEntries(sorted);
}

const _europeanCountries = {
  'albania',
  'andorra',
  'armenia',
  'austria',
  'azerbaijan',
  'belarus',
  'belgium',
  'bosnia and herzegovina',
  'bosnia & herzegovina',
  'bulgaria',
  'croatia',
  'cyprus',
  'czech republic',
  'czechia',
  'denmark',
  'england',
  'estonia',
  'faroe islands',
  'finland',
  'france',
  'georgia',
  'germany',
  'gibraltar',
  'greece',
  'hungary',
  'iceland',
  'ireland',
  'republic of ireland',
  'italy',
  'kosovo',
  'latvia',
  'liechtenstein',
  'lithuania',
  'luxembourg',
  'malta',
  'moldova',
  'monaco',
  'montenegro',
  'netherlands',
  'north macedonia',
  'northern ireland',
  'norway',
  'poland',
  'portugal',
  'romania',
  'russia',
  'san marino',
  'scotland',
  'serbia',
  'slovakia',
  'slovenia',
  'spain',
  'sweden',
  'switzerland',
  'turkey',
  'turkiye',
  'ukraine',
  'united kingdom',
  'great britain',
  'wales',
  'europe',
};

List<LeagueModel> homeTopEuropeanLeagues(
  List<FixtureModel> fixtures,
  int sportId,
) {
  final grouped = <String, List<FixtureModel>>{};
  for (final fixture in fixtures) {
    if (fixture.sportId != sportId) continue;
    final country = fixture.country.trim().toLowerCase();
    final european =
        _europeanCountries.contains(country) ||
        (['international', 'world', ''].contains(country) &&
            RegExp(
              r'\b(uefa|europe|european|euroleague|eurocup)\b',
              caseSensitive: false,
            ).hasMatch(fixture.leagueName));
    if (!european || fixture.leagueName.isEmpty) continue;
    final key = fixture.leagueId.isNotEmpty
        ? fixture.leagueId
        : '${fixture.country}|${fixture.leagueName}';
    grouped.putIfAbsent(key, () => []).add(fixture);
  }
  final leagues = grouped.values
      .map(
        (matches) => LeagueModel(
          id: matches.first.leagueId,
          sportId: sportId,
          name: matches.first.leagueName,
          country: matches.first.country,
          category: '',
          matchCount: matches.length,
        ),
      )
      .toList();
  leagues.sort((a, b) {
    final count = b.matchCount.compareTo(a.matchCount);
    return count != 0
        ? count
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return leagues.take(10).toList();
}
