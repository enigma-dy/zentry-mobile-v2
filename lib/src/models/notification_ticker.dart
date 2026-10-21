String? _notificationValue(
  Map<String, dynamic> notification,
  List<String> keys,
) {
  for (final key in keys) {
    final value = notification[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  for (final containerKey in const ['data', 'metadata', 'payload', 'fixture']) {
    final nested = notification[containerKey];
    if (nested is Map) {
      if (containerKey == 'fixture') {
        final fixtureId = nested['id']?.toString().trim() ?? '';
        if (fixtureId.isNotEmpty) return fixtureId;
      }
      final value = _notificationValue(Map<String, dynamic>.from(nested), keys);
      if (value != null) return value;
    }
  }
  return null;
}

/// A stable fixture key for pre-kickoff alerts, regardless of how the API
/// nests its notification metadata.
String? kickoffNotificationFixtureKey(Map<String, dynamic> notification) {
  final type = (notification['type']?.toString() ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  final message = (notification['message']?.toString() ?? '').toLowerCase();
  final isKickoffAlert =
      type.contains('kickoff') ||
      type.contains('starting') ||
      type.contains('about to start') ||
      type.contains('start reminder') ||
      message.contains('about to start') ||
      message.contains('starts in') ||
      message.contains('starting soon') ||
      message.contains('kickoff');
  if (!isKickoffAlert) return null;

  final fixtureId = _notificationValue(notification, const [
    'fixture_id',
    'fixtureId',
    'match_id',
    'matchId',
    'event_id',
    'eventId',
  ]);
  return fixtureId == null ? null : 'fixture:$fixtureId';
}

/// Keeps the newest entry returned for each fixture kickoff alert. Other
/// notification types remain untouched.
List<Map<String, dynamic>> dedupeTickerNotifications(
  Iterable<Map<String, dynamic>> notifications,
) {
  final seenFixtures = <String>{};
  return notifications.where((notification) {
    final fixtureKey = kickoffNotificationFixtureKey(notification);
    return fixtureKey == null || seenFixtures.add(fixtureKey);
  }).toList();
}
