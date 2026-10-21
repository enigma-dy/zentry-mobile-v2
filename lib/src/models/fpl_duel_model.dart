class FplTeamModel {
  final int fplEntryId;
  final String teamName;
  final String playerName;
  final String verificationCode;
  final DateTime? verifiedAt;

  const FplTeamModel({
    required this.fplEntryId,
    required this.teamName,
    this.playerName = '',
    required this.verificationCode,
    this.verifiedAt,
  });

  bool get isVerified => verifiedAt != null;

  factory FplTeamModel.fromJson(Map<String, dynamic> json) {
    DateTime? vAt;
    if (json['verified_at'] != null) {
      vAt = DateTime.tryParse(json['verified_at'].toString());
    }
    return FplTeamModel(
      fplEntryId: json['fpl_entry_id'] is int
          ? json['fpl_entry_id'] as int
          : int.tryParse(json['fpl_entry_id']?.toString() ?? '0') ?? 0,
      teamName: json['team_name']?.toString() ?? 'My FPL Team',
      playerName: json['player_name']?.toString() ?? '',
      verificationCode: json['verification_code']?.toString() ?? '',
      verifiedAt: vAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'fpl_entry_id': fplEntryId,
    'team_name': teamName,
    'player_name': playerName,
    'verification_code': verificationCode,
    if (verifiedAt != null) 'verified_at': verifiedAt!.toIso8601String(),
  };
}

class FplDuelChallengeModel {
  final String id;
  final int gameweek;
  final String mode; // CLASSIC, CAPTAIN_DUEL, UNDERDOG
  final bool allowChips;
  final int stake; // in kobo
  final int rakeBps; // e.g. 1000 = 10%
  final String status; // OPEN, LOCKED, LIVE, AWAITING_FINAL, SETTLING, SETTLED, PUSHED, VOIDED, CANCELLED
  final String creatorId;
  final String? opponentId;
  final int creatorEntry;
  final int? opponentEntry;
  final String creatorTeamName;
  final String opponentTeamName;
  final int creatorScore;
  final int opponentScore;
  final String? winnerId;
  final String visibility;
  final String inviteCode;
  final DateTime acceptCutoff;
  final DateTime createdAt;

  const FplDuelChallengeModel({
    required this.id,
    required this.gameweek,
    required this.mode,
    this.allowChips = false,
    required this.stake,
    this.rakeBps = 1000,
    required this.status,
    required this.creatorId,
    this.opponentId,
    required this.creatorEntry,
    this.opponentEntry,
    this.creatorTeamName = '',
    this.opponentTeamName = '',
    this.creatorScore = 0,
    this.opponentScore = 0,
    this.winnerId,
    this.visibility = 'PUBLIC',
    this.inviteCode = '',
    required this.acceptCutoff,
    required this.createdAt,
  });

  double get stakeNaira => stake / 100.0;
  double get potNaira => (stake * 2) / 100.0;
  double get winPayoutNaira {
    final pot = stake * 2;
    final rake = (pot * rakeBps) ~/ 10000;
    return (pot - rake) / 100.0;
  }

  bool get isOpen => status == 'OPEN';
  bool get isLocked => status == 'LOCKED';
  bool get isLive => status == 'LIVE' || status == 'AWAITING_FINAL';
  bool get isSettled => status == 'SETTLED';
  bool get isPushed => status == 'PUSHED';
  bool get isCancelled => status == 'CANCELLED' || status == 'VOIDED';

  String get modeLabel {
    switch (mode) {
      case 'CAPTAIN_DUEL':
        return 'Captain Duel';
      case 'UNDERDOG':
        return 'Underdog 2X';
      case 'CLASSIC':
      default:
        return 'Classic 1v1';
    }
  }

  String get modeDescription {
    switch (mode) {
      case 'CAPTAIN_DUEL':
        return 'Head-to-head battle on Captain points only.';
      case 'UNDERDOG':
        return '2x bonus points for differential picks (<15% ownership).';
      case 'CLASSIC':
      default:
        return 'Full starting XI points minus transfer costs.';
    }
  }

  factory FplDuelChallengeModel.fromJson(Map<String, dynamic> json) {
    DateTime cutoff = DateTime.now().add(const Duration(hours: 24));
    if (json['accept_cutoff'] != null) {
      cutoff = DateTime.tryParse(json['accept_cutoff'].toString()) ?? cutoff;
    }
    DateTime created = DateTime.now();
    if (json['created_at'] != null) {
      created = DateTime.tryParse(json['created_at'].toString()) ?? created;
    }

    return FplDuelChallengeModel(
      id: json['id']?.toString() ?? '',
      gameweek: json['gameweek'] is int
          ? json['gameweek'] as int
          : int.tryParse(json['gameweek']?.toString() ?? '1') ?? 1,
      mode: json['mode']?.toString() ?? 'CLASSIC',
      allowChips: json['allow_chips'] == true,
      stake: json['stake'] is int
          ? json['stake'] as int
          : int.tryParse(json['stake']?.toString() ?? '100000') ?? 100000,
      rakeBps: json['rake_bps'] is int
          ? json['rake_bps'] as int
          : int.tryParse(json['rake_bps']?.toString() ?? '1000') ?? 1000,
      status: json['status']?.toString() ?? 'OPEN',
      creatorId: json['creator_id']?.toString() ?? '',
      opponentId: json['opponent_id']?.toString(),
      creatorEntry: json['creator_entry'] is int
          ? json['creator_entry'] as int
          : int.tryParse(json['creator_entry']?.toString() ?? '0') ?? 0,
      opponentEntry: json['opponent_entry'] == null
          ? null
          : int.tryParse(json['opponent_entry'].toString()),
      creatorTeamName: json['creator_team_name']?.toString() ?? 'Challenger',
      opponentTeamName: json['opponent_team_name']?.toString() ?? 'Opponent',
      creatorScore: json['creator_score'] is int
          ? json['creator_score'] as int
          : int.tryParse(json['creator_score']?.toString() ?? '0') ?? 0,
      opponentScore: json['opponent_score'] is int
          ? json['opponent_score'] as int
          : int.tryParse(json['opponent_score']?.toString() ?? '0') ?? 0,
      winnerId: json['winner_id']?.toString(),
      visibility: json['visibility']?.toString() ?? 'PUBLIC',
      inviteCode: json['invite_code']?.toString() ?? '',
      acceptCutoff: cutoff,
      createdAt: created,
    );
  }
}

class FplGameweekModel {
  final int gameweek;
  final String name;
  final DateTime deadlineTime;
  final bool isCurrent;
  final bool isNext;
  final bool finished;
  final bool dataChecked;

  const FplGameweekModel({
    required this.gameweek,
    required this.name,
    required this.deadlineTime,
    this.isCurrent = true,
    this.isNext = false,
    this.finished = false,
    this.dataChecked = false,
  });

  factory FplGameweekModel.fromJson(Map<String, dynamic> json) {
    DateTime dl = DateTime.now().add(const Duration(days: 2));
    if (json['deadline_time'] != null) {
      dl = DateTime.tryParse(json['deadline_time'].toString()) ?? dl;
    }
    return FplGameweekModel(
      gameweek: json['gameweek'] is int
          ? json['gameweek'] as int
          : int.tryParse(json['gameweek']?.toString() ?? '1') ?? 1,
      name: json['name']?.toString() ?? 'Gameweek',
      deadlineTime: dl,
      isCurrent: json['is_current'] == true,
      isNext: json['is_next'] == true,
      finished: json['finished'] == true,
      dataChecked: json['data_checked'] == true,
    );
  }
}

class FplWalletModel {
  final int depositBalance;  // in kobo
  final int winningsBalance; // in kobo
  final int totalBalance;    // in kobo
  final String currency;

  const FplWalletModel({
    this.depositBalance = 0,
    this.winningsBalance = 0,
    this.totalBalance = 0,
    this.currency = 'NGN',
  });

  double get depositNaira => depositBalance / 100.0;
  double get winningsNaira => winningsBalance / 100.0;
  double get totalNaira => totalBalance / 100.0;

  factory FplWalletModel.fromJson(Map<String, dynamic> json) {
    return FplWalletModel(
      depositBalance: json['deposit_balance'] is int
          ? json['deposit_balance'] as int
          : int.tryParse(json['deposit_balance']?.toString() ?? '0') ?? 0,
      winningsBalance: json['winnings_balance'] is int
          ? json['winnings_balance'] as int
          : int.tryParse(json['winnings_balance']?.toString() ?? '0') ?? 0,
      totalBalance: json['total_balance'] is int
          ? json['total_balance'] as int
          : int.tryParse(json['total_balance']?.toString() ?? '0') ?? 0,
      currency: json['currency']?.toString() ?? 'NGN',
    );
  }
}
