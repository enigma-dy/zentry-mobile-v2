import 'fixture_model.dart';

class FixtureDuelModel {
  final String id;
  final String fixtureId;
  final FixtureModel fixture;
  final String creatorId;
  final String? opponentId;
  final String creatorPick;
  final int stake;
  final String status;
  final DateTime kickoff;
  final DateTime acceptCutoff;
  final String? winnerId;
  final int homeScore;
  final int awayScore;

  const FixtureDuelModel({
    required this.id,
    required this.fixtureId,
    required this.fixture,
    required this.creatorId,
    required this.opponentId,
    required this.creatorPick,
    required this.stake,
    required this.status,
    required this.kickoff,
    required this.acceptCutoff,
    required this.winnerId,
    required this.homeScore,
    required this.awayScore,
  });

  factory FixtureDuelModel.fromJson(Map<String, dynamic> json) {
    final rawFixture = json['fixture'];
    final fixture = rawFixture is Map
        ? Map<String, dynamic>.from(rawFixture)
        : <String, dynamic>{};
    return FixtureDuelModel(
      id: json['id']?.toString() ?? '',
      fixtureId: json['fixture_id']?.toString() ?? '',
      fixture: FixtureModel.fromJson(fixture),
      creatorId: json['creator_id']?.toString() ?? '',
      opponentId: json['opponent_id']?.toString(),
      creatorPick: json['creator_pick']?.toString() ?? 'HOME',
      stake: (json['stake'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? '',
      kickoff:
          DateTime.tryParse(json['kickoff']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      acceptCutoff:
          DateTime.tryParse(json['accept_cutoff']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      winnerId: json['winner_id']?.toString(),
      homeScore: (json['home_score'] as num?)?.toInt() ?? 0,
      awayScore: (json['away_score'] as num?)?.toInt() ?? 0,
    );
  }

  String get creatorTeam =>
      creatorPick == 'HOME' ? fixture.homeTeam : fixture.awayTeam;
  String get opponentTeam =>
      creatorPick == 'HOME' ? fixture.awayTeam : fixture.homeTeam;
  double get stakeNaira => stake / 100;
}
