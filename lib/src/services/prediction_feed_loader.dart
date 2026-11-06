import 'dart:async';

bool predictionFeedHasContent(Map<String, dynamic> data) => [
  'items',
  'groups',
  'top_items',
].any((key) => data[key] is List && (data[key] as List).isNotEmpty);

/// Keep each visited tab's successful response while a transient refresh fails.
/// Callers scope keys by date/market and clear this history on session changes.
class PredictionTabHistory {
  final _tabs = <String, Map<String, dynamic>>{};

  void clear() => _tabs.clear();

  Map<String, dynamic>? read(String key) {
    final value = _tabs[key];
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  Map<String, dynamic>? failure(String key, Object error) {
    final previous = read(key);
    if (previous == null || !predictionFeedHasContent(previous)) return null;
    return {
      ...previous,
      'retry_pending': true,
      'refresh_error': error.toString(),
    };
  }

  Map<String, dynamic> accept(String key, Map<String, dynamic> incoming) {
    final previous = read(key);
    if (!predictionFeedHasContent(incoming) &&
        incoming['loading'] == true &&
        previous != null &&
        predictionFeedHasContent(previous)) {
      return {...previous, 'retry_pending': true};
    }
    final data = preservePredictionBookingIds(previous, incoming);
    if (predictionFeedHasContent(data)) {
      if (_tabs.length >= 32 && !_tabs.containsKey(key)) {
        _tabs.remove(_tabs.keys.first);
      }
      _tabs[key] = data;
    } else {
      _tabs.remove(key);
    }
    return data;
  }
}

Map<String, dynamic> preservePredictionBookingIds(
  Map<String, dynamic>? previous,
  Map<String, dynamic> incoming,
) {
  if (previous == null) return incoming;
  String identity(Map row) {
    final fixture = row['fixture_id']?.toString() ?? '';
    final kickoff = DateTime.tryParse(row['match_time']?.toString() ?? '');
    // IDs and providers can change when the same pick is deduplicated. Keep
    // event, date and complete selection as the identity instead.
    return [
      row['sport_id'],
      if (fixture.isNotEmpty) fixture else row['home_team'],
      if (fixture.isEmpty) row['away_team'],
      kickoff?.toUtc().toIso8601String() ?? row['match_time'],
      row['market'],
      row['selection'],
    ].map((value) => (value?.toString() ?? '').trim().toLowerCase()).join('|');
  }

  String code(Map row, String field) {
    final flat = row['sporty_$field']?.toString() ?? '';
    if (flat.isNotEmpty) return flat;
    final bookmakers = row['bookmakers'];
    final sporty = bookmakers is Map ? bookmakers['sporty'] : null;
    return sporty is Map ? sporty[field]?.toString() ?? '' : '';
  }

  Iterable<Map> rows(Map data) sync* {
    for (final field in ['items', 'top_items']) {
      if (data[field] is List) yield* (data[field] as List).whereType<Map>();
    }
    for (final group
        in (data['groups'] as List? ?? const []).whereType<Map>()) {
      if (group['items'] is List)
        yield* (group['items'] as List).whereType<Map>();
    }
  }

  final known = {for (final row in rows(previous)) identity(row): row};
  Map<String, dynamic> retain(Map row) {
    final current = Map<String, dynamic>.from(row);
    final old = known[identity(row)];
    final kickoff = DateTime.tryParse(row['match_time']?.toString() ?? '');
    if (old == null || kickoff == null || !kickoff.isAfter(DateTime.now())) {
      return current;
    }
    final reason = row['sporty_sync_reason'];
    final sameEvent =
        code(row, 'event_id').isNotEmpty &&
        code(row, 'event_id') == code(old, 'event_id');
    if (reason != 'fixture_snapshot_unavailable' &&
        !(sameEvent &&
            {
              'outcome_not_in_current_snapshot',
              'prematch_price_not_verified',
            }.contains(reason))) {
      return current;
    }
    final status = (row['match_status'] ?? '').toString().trim().toLowerCase();
    if (!{
      '',
      'prematch',
      'pending',
      'upcoming',
      'scheduled',
      'ns',
      'not started',
    }.contains(status))
      return current;
    const fields = ['event_id', 'market_id', 'outcome_id'];
    if (fields.any((field) => code(old, field).isEmpty)) return current;
    if (fields.any(
      (field) =>
          code(row, field).isNotEmpty && code(row, field) != code(old, field),
    )) {
      return current;
    }
    if (code(row, 'specifier').isNotEmpty &&
        code(row, 'specifier') != code(old, 'specifier')) {
      return current;
    }
    for (final field in [...fields, 'specifier']) {
      current['sporty_$field'] = code(old, field);
    }
    if ((current['fixture_id']?.toString() ?? '').isEmpty) {
      current['fixture_id'] = old['fixture_id'];
    }
    current['sportybet_available'] = true;
    return current;
  }

  return {
    ...incoming,
    for (final field in ['items', 'top_items'])
      if (incoming[field] is List)
        field: (incoming[field] as List).whereType<Map>().map(retain).toList(),
    if (incoming['groups'] is List)
      'groups': (incoming['groups'] as List)
          .whereType<Map>()
          .map(
            (group) => {
              ...group,
              if (group['items'] is List)
                'items': (group['items'] as List)
                    .whereType<Map>()
                    .map(retain)
                    .toList(),
            },
          )
          .toList(),
  };
}

/// Empty is a valid response. The server's loading flag controls background
/// polling; do not turn a sport without predictions into an endless spinner.
Future<Map<String, dynamic>> loadPredictionFeed(
  Future<Map<String, dynamic>> Function() request, {
  bool Function()? shouldContinue,
  bool Function(Object)? shouldRetryError,
  Future<void> Function(Duration)? wait,
}) async {
  final delay = wait ?? Future<void>.delayed;
  for (var attempt = 0; attempt < 2; attempt++) {
    if (shouldContinue?.call() == false) {
      return {'items': <dynamic>[], 'loading': false};
    }
    try {
      return await request();
    } catch (error) {
      if (attempt == 1 ||
          shouldContinue?.call() == false ||
          shouldRetryError?.call(error) == false) {
        rethrow;
      }
    }
    await delay(const Duration(milliseconds: 300));
  }
  return {'items': <dynamic>[], 'loading': false};
}

Map<String, dynamic> mergePredictionSections(
  Map<String, dynamic> general,
  Map<String, dynamic>? top, {
  required bool hasTop,
}) {
  final generalLoading =
      general['general_loading'] == true ||
      !general.containsKey('general_loading') && general['loading'] == true;
  final topLoading = hasTop && (top == null || top['loading'] == true);
  return {
    ...general,
    'general_loading': generalLoading,
    'top_items': top?['items'] ?? <dynamic>[],
    'top_loading': topLoading,
    'top_load_error': top?['top_load_error'] ?? top?['message'],
    'loading': generalLoading || topLoading,
    'retry_pending':
        generalLoading ||
        topLoading ||
        hasTop &&
            (top?['top_load_error'] != null ||
                top?['message'] != null && top?['message'] != ''),
  };
}

/// Optional Top data never delays or discards the general prediction list.
Future<Map<String, dynamic>> loadPredictionSections({
  required Future<Map<String, dynamic>> general,
  Future<Map<String, dynamic>>? top,
  void Function(Map<String, dynamic>)? onTopReady,
}) async {
  Map<String, dynamic>? topData;
  if (top != null) {
    final safeTop = top.then(
      (value) => value,
      onError: (Object error) => <String, dynamic>{
        'items': <dynamic>[],
        'loading': false,
        'top_load_error': error.toString(),
      },
    );
    unawaited(
      safeTop.then((value) {
        topData = value;
        onTopReady?.call(value);
      }),
    );
  }
  final data = await general;
  return mergePredictionSections(data, topData, hasTop: top != null);
}
