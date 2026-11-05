/// A stale prematch status must not keep a started fixture bookable.
bool isUpcomingBettingFixture(
  String matchTime, {
  String status = '',
  String matchStatus = '',
  DateTime? now,
}) {
  final kickoff = DateTime.tryParse(matchTime);
  const upcoming = {
    '',
    'prematch',
    'pending',
    'upcoming',
    'scheduled',
    'ns',
    'not started',
  };
  return kickoff != null &&
      kickoff.isAfter(now ?? DateTime.now()) &&
      upcoming.contains(status.trim().toLowerCase()) &&
      upcoming.contains(matchStatus.trim().toLowerCase());
}
