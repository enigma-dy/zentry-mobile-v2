import 'betting_availability.dart';

String ticketOddsLabel(double odds) =>
    odds.isFinite && odds > 1 ? odds.toStringAsFixed(2) : '\u2014';

double ticketSelectionsTotalOdds(Iterable<TicketSelectionModel> selections) {
  if (selections.isEmpty || selections.any((selection) => !selection.hasOdds)) {
    return 0;
  }
  final total = selections.fold(
    1.0,
    (total, selection) => total * selection.odds,
  );
  return total.isFinite ? total : 0;
}

class TicketSelectionModel {
  final Map<String, dynamic> bookmakers;
  final String? fixtureId;
  final String? predictionId;
  final int? sportId;
  final String? sportyEventId;
  final String? sportyMarketId;
  final String? sportyOutcomeId;
  final String? sportySpecifier;
  final String homeTeam;
  final String awayTeam;
  final String leagueName;
  final String matchTime;
  final String marketType; // "1X2", "Double Chance", "Over/Under", "GG"
  final String selection; // "1", "X", "2", "1X", "12", "X2", "O25", "GG"
  final double odds;
  final int confidence;
  final String status; // "pending", "won", "lost", "void"
  final String matchStatus;
  final String? settledAt;

  String get prediction => selection;

  const TicketSelectionModel({
    this.bookmakers = const {},
    this.fixtureId,
    this.predictionId,
    this.sportId,
    this.sportyEventId,
    this.sportyMarketId,
    this.sportyOutcomeId,
    this.sportySpecifier,
    required this.homeTeam,
    required this.awayTeam,
    this.leagueName = '',
    this.matchTime = '',
    required this.marketType,
    String selection = '',
    String? prediction,
    required this.odds,
    this.confidence = 0,
    this.status = 'pending',
    this.matchStatus = '',
    this.settledAt,
  }) : selection = selection != '' ? selection : (prediction ?? '');

  /// One mapping for normal, ZAI, VIP and grouped prediction cards.
  factory TicketSelectionModel.fromPrediction(Map<String, dynamic> item) {
    final books = item['bookmakers'] is Map
        ? Map<String, dynamic>.from(item['bookmakers'])
        : <String, dynamic>{};
    final sporty = books['sporty'] is Map
        ? Map<String, dynamic>.from(books['sporty'])
        : <String, dynamic>{};
    String code(String flat, String nested) {
      final value = item[flat]?.toString().trim() ?? '';
      return value.isNotEmpty ? value : sporty[nested]?.toString().trim() ?? '';
    }

    final market = code('sporty_market_id', 'market_id');
    final outcome = code('sporty_outcome_id', 'outcome_id');
    final price = double.tryParse(sporty['odds']?.toString() ?? '');
    final sourcePrice = double.tryParse(item['odds']?.toString() ?? '') ?? 0;
    return TicketSelectionModel(
      bookmakers: books,
      fixtureId: item['fixture_id']?.toString(),
      predictionId: item['id']?.toString(),
      sportId: int.tryParse(item['sport_id']?.toString() ?? ''),
      sportyEventId: code('sporty_event_id', 'event_id'),
      sportyMarketId: market,
      sportyOutcomeId: outcome,
      sportySpecifier: code('sporty_specifier', 'specifier'),
      homeTeam: item['home_team']?.toString() ?? '',
      awayTeam: item['away_team']?.toString() ?? '',
      leagueName: (item['league'] ?? item['league_name'])?.toString() ?? '',
      matchTime: item['match_time']?.toString() ?? '',
      marketType: item['market']?.toString() ?? '',
      selection: item['selection']?.toString() ?? '',
      odds:
          market.isNotEmpty &&
              outcome.isNotEmpty &&
              price != null &&
              price.isFinite &&
              price > 1
          ? price
          : sourcePrice,
      confidence: (num.tryParse(item['confidence']?.toString() ?? '') ?? 0)
          .round(),
      status: item['status']?.toString() ?? 'pending',
      matchStatus: item['match_status']?.toString() ?? '',
    );
  }

  bool get isUpcoming => isUpcomingBettingFixture(
    matchTime,
    status: status,
    matchStatus: matchStatus,
  );

  bool get hasOdds => odds.isFinite && odds > 1;

  bool get hasSportySelection =>
      sportyEventId?.isNotEmpty == true &&
      sportyMarketId?.isNotEmpty == true &&
      sportyOutcomeId?.isNotEmpty == true;

  bool get canAddToBucket =>
      isUpcoming &&
      (fixtureId?.isNotEmpty == true || hasSportySelection) &&
      (sportId ?? 0) > 0 &&
      homeTeam.isNotEmpty &&
      awayTeam.isNotEmpty &&
      DateTime.tryParse(matchTime) != null &&
      marketType.isNotEmpty &&
      selection.isNotEmpty &&
      odds.isFinite &&
      (hasOdds || odds == 0 && hasSportySelection);

  String get uniqueKey =>
      (sportyEventId?.isNotEmpty == true &&
          sportyMarketId?.isNotEmpty == true &&
          sportyOutcomeId?.isNotEmpty == true)
      ? '${sportyEventId}_${sportyMarketId}_${sportyOutcomeId}_${sportySpecifier ?? ''}'
      : '${fixtureId ?? homeTeam}_${marketType}_$selection';

  factory TicketSelectionModel.fromJson(Map<String, dynamic> json) {
    return TicketSelectionModel(
      bookmakers: json['bookmakers'] is Map
          ? Map<String, dynamic>.from(json['bookmakers'])
          : const {},
      fixtureId: json['fixture_id']?.toString(),
      predictionId: json['prediction_id']?.toString(),
      sportId: int.tryParse(json['sport_id']?.toString() ?? ''),
      sportyEventId: json['sporty_event_id']?.toString(),
      sportyMarketId: json['sporty_market_id']?.toString(),
      sportyOutcomeId: json['sporty_outcome_id']?.toString(),
      sportySpecifier: json['sporty_specifier']?.toString(),
      homeTeam: json['home_team']?.toString() ?? '',
      awayTeam: json['away_team']?.toString() ?? '',
      leagueName: json['league_name']?.toString() ?? '',
      matchTime: json['match_time']?.toString() ?? '',
      marketType: json['market_type']?.toString() ?? '1X2',
      selection:
          json['selection']?.toString() ??
          json['prediction']?.toString() ??
          '1',
      odds: json['odds'] is num
          ? (json['odds'] as num).toDouble()
          : double.tryParse(json['odds']?.toString() ?? '') ?? 0,
      confidence: json['confidence'] is int
          ? json['confidence'] as int
          : int.tryParse(json['confidence']?.toString() ?? '0') ?? 0,
      status: json['status']?.toString() ?? 'pending',
      matchStatus: json['match_status']?.toString() ?? '',
      settledAt: json['settled_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (bookmakers.isNotEmpty) 'bookmakers': bookmakers,
    if (fixtureId != null) 'fixture_id': fixtureId,
    if (predictionId != null) 'prediction_id': predictionId,
    if (sportId != null) 'sport_id': sportId,
    if (sportyEventId?.isNotEmpty ?? false) 'sporty_event_id': sportyEventId,
    if (sportyMarketId?.isNotEmpty ?? false) 'sporty_market_id': sportyMarketId,
    if (sportyOutcomeId?.isNotEmpty ?? false)
      'sporty_outcome_id': sportyOutcomeId,
    if (sportySpecifier?.isNotEmpty ?? false)
      'sporty_specifier': sportySpecifier,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'league_name': leagueName,
    'match_time': matchTime,
    'market_type': marketType,
    'selection': selection,
    'prediction': selection,
    'odds': odds,
    'confidence': confidence,
    'status': status,
    if (matchStatus.isNotEmpty) 'match_status': matchStatus,
    if (settledAt != null) 'settled_at': settledAt,
  };
}

class BookingCodeResult {
  final String bookingCode;
  final String platform;
  final String shareUrl;
  final double totalOdds;
  final int itemCount;
  final String? bucketId;
  final int coinsCharged;
  final int coinsBalance;

  const BookingCodeResult({
    required this.bookingCode,
    required this.platform,
    required this.shareUrl,
    required this.totalOdds,
    required this.itemCount,
    this.bucketId,
    this.coinsCharged = 0,
    this.coinsBalance = 0,
  });

  factory BookingCodeResult.fromJson(Map<String, dynamic> json) {
    return BookingCodeResult(
      bookingCode: json['booking_code']?.toString() ?? '',
      platform: json['platform']?.toString() ?? 'sportybetng',
      shareUrl: json['share_url']?.toString() ?? '',
      totalOdds: json['total_odds'] is num
          ? (json['total_odds'] as num).toDouble()
          : double.tryParse(json['total_odds']?.toString() ?? '') ?? 0,
      itemCount: json['item_count'] is int
          ? json['item_count'] as int
          : int.tryParse(json['item_count']?.toString() ?? '0') ?? 0,
      bucketId: json['bucket_id']?.toString(),
      coinsCharged: (json['coins_charged'] as num?)?.toInt() ?? 0,
      coinsBalance: (json['coins_balance'] as num?)?.toInt() ?? 0,
    );
  }
}

class TicketBucketModel {
  final String id;
  final String title;
  final String platform;
  final String bookingCode;
  final String shareUrl;
  final double totalOdds;
  final int itemCount;
  final String status; // "pending", "booked", "won", "lost", "void"
  final String? settledAt;
  final String createdAt;
  final List<TicketSelectionModel> selections;

  const TicketBucketModel({
    required this.id,
    required this.title,
    required this.platform,
    required this.bookingCode,
    required this.shareUrl,
    required this.totalOdds,
    required this.itemCount,
    required this.status,
    this.settledAt,
    this.createdAt = '',
    required this.selections,
  });

  factory TicketBucketModel.fromJson(Map<String, dynamic> json) {
    List<TicketSelectionModel> items = [];
    if (json['selections'] is List) {
      items = (json['selections'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => TicketSelectionModel.fromJson(m))
          .toList();
    }
    return TicketBucketModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'AI Prediction Slip',
      platform: json['platform']?.toString() ?? 'sportybetng',
      bookingCode: json['booking_code']?.toString() ?? '',
      shareUrl: json['share_url']?.toString() ?? '',
      totalOdds: json['total_odds'] is num
          ? (json['total_odds'] as num).toDouble()
          : double.tryParse(json['total_odds']?.toString() ?? '') ?? 0,
      itemCount: json['item_count'] is int
          ? json['item_count'] as int
          : items.length,
      status: json['status']?.toString() ?? 'pending',
      settledAt: json['settled_at']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      selections: items,
    );
  }
}

/// UserPickFeedItemModel represents an individual user pick in the community feed
class UserPickFeedItemModel {
  final String id;
  final String bucketId;
  final String bookingCode;
  final String platform;
  final String homeTeam;
  final String awayTeam;
  final String leagueName;
  final String matchTime;
  final String marketType;
  final String selection;
  final double odds;
  final int confidence;
  final String status; // "pending", "won", "lost", "void"
  final String? settledAt;
  final String createdAt;

  const UserPickFeedItemModel({
    required this.id,
    required this.bucketId,
    this.bookingCode = '',
    this.platform = 'sportybetng',
    required this.homeTeam,
    required this.awayTeam,
    this.leagueName = '',
    this.matchTime = '',
    required this.marketType,
    required this.selection,
    required this.odds,
    this.confidence = 0,
    this.status = 'pending',
    this.settledAt,
    this.createdAt = '',
  });

  TicketSelectionModel toSelectionModel() {
    return TicketSelectionModel(
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      leagueName: leagueName,
      matchTime: matchTime,
      marketType: marketType,
      selection: selection,
      odds: odds,
      confidence: confidence,
      status: status,
      settledAt: settledAt,
    );
  }

  factory UserPickFeedItemModel.fromJson(Map<String, dynamic> json) {
    return UserPickFeedItemModel(
      id: json['id']?.toString() ?? '',
      bucketId: json['bucket_id']?.toString() ?? '',
      bookingCode: json['booking_code']?.toString() ?? '',
      platform: json['platform']?.toString() ?? 'sportybetng',
      homeTeam: json['home_team']?.toString() ?? '',
      awayTeam: json['away_team']?.toString() ?? '',
      leagueName: json['league_name']?.toString() ?? '',
      matchTime: json['match_time']?.toString() ?? '',
      marketType: json['market_type']?.toString() ?? '1X2',
      selection: json['selection']?.toString() ?? '1',
      odds: json['odds'] is num
          ? (json['odds'] as num).toDouble()
          : double.tryParse(json['odds']?.toString() ?? '') ?? 0,
      confidence: json['confidence'] is int
          ? json['confidence'] as int
          : int.tryParse(json['confidence']?.toString() ?? '0') ?? 0,
      status: json['status']?.toString() ?? 'pending',
      settledAt: json['settled_at']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

/// Response wrapper for community tickets feed
class TicketBucketFeedResponseModel {
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;
  final List<TicketBucketModel> tickets;

  const TicketBucketFeedResponseModel({
    required this.total,
    required this.page,
    required this.pageSize,
    this.totalPages = 0,
    required this.tickets,
  });

  factory TicketBucketFeedResponseModel.fromJson(Map<String, dynamic> json) {
    List<TicketBucketModel> items = [];
    if (json['tickets'] is List) {
      items = (json['tickets'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => TicketBucketModel.fromJson(m))
          .toList();
    }
    return TicketBucketFeedResponseModel(
      total: json['total'] is int ? json['total'] as int : 0,
      page: json['page'] is int ? json['page'] as int : 1,
      pageSize: json['page_size'] is int ? json['page_size'] as int : 20,
      totalPages: json['total_pages'] is int ? json['total_pages'] as int : 0,
      tickets: items,
    );
  }
}

/// Response wrapper for ticket settlement execution metrics
class TicketSettlementStatsModel {
  final int ticketsEvaluated;
  final int ticketsSettled;
  final int ticketsWon;
  final int ticketsLost;
  final int ticketsVoid;
  final int picksSettled;
  final String settledAt;

  const TicketSettlementStatsModel({
    required this.ticketsEvaluated,
    required this.ticketsSettled,
    required this.ticketsWon,
    required this.ticketsLost,
    required this.ticketsVoid,
    required this.picksSettled,
    required this.settledAt,
  });

  factory TicketSettlementStatsModel.fromJson(Map<String, dynamic> json) {
    return TicketSettlementStatsModel(
      ticketsEvaluated: json['tickets_evaluated'] is int
          ? json['tickets_evaluated'] as int
          : 0,
      ticketsSettled: json['tickets_settled'] is int
          ? json['tickets_settled'] as int
          : 0,
      ticketsWon: json['tickets_won'] is int ? json['tickets_won'] as int : 0,
      ticketsLost: json['tickets_lost'] is int
          ? json['tickets_lost'] as int
          : 0,
      ticketsVoid: json['tickets_void'] is int
          ? json['tickets_void'] as int
          : 0,
      picksSettled: json['picks_settled'] is int
          ? json['picks_settled'] as int
          : 0,
      settledAt: json['settled_at']?.toString() ?? '',
    );
  }
}
