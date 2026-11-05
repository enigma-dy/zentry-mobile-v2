import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_screen.dart';
import 'services/prediction_feed_loader.dart';
import 'ads/ad_slot.dart';
import 'live_tv/live_tv_screen.dart';
import 'brand.dart';
import 'slip_agent_screen.dart';
import 'profile_screen.dart';
import 'coin_shop_screen.dart';
import 'contact_us_dialog.dart';
import 'help_screen.dart';
import 'services/session_manager.dart';
import 'services/sports_service.dart';
import 'services/fpl_duel_service.dart';
import 'services/fixture_duel_service.dart';
import 'services/chat_service.dart';
import 'services/app_config.dart';
import 'models/sport_model.dart';
import 'models/league_model.dart';
import 'models/fixture_model.dart';
import 'models/fixture_duel_model.dart';
import 'models/fpl_duel_model.dart';
import 'models/home_fixture_groups.dart';
import 'models/home_fixture_filters.dart';
import 'models/home_markets.dart';
import 'models/notification_ticker.dart';
import 'game_center.dart';
import 'fixture_duel_view.dart';
import 'models/paginated_response.dart';
import 'models/ticket_bucket_model.dart';
import 'models/betting_availability.dart';
import 'models/ace_channel_model.dart';
import 'match_detail_screen.dart';
import 'fpl_duel_view.dart';
import 'live_stream_sheet.dart';
import 'widgets/in_app_stream_player.dart';
import 'widgets/ace_stream_player.dart';
import 'bet_machine_sheet.dart';
import 'value_odds_sheet.dart';
import 'advanced_stats_sheet.dart';
import 'chat_screen.dart';
import 'bookings_screen.dart';

class HomeScreen extends StatefulWidget {
  final SportsService? sportsService;
  const HomeScreen({super.key, this.sportsService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final SportsService _sportsService =
      widget.sportsService ?? SportsService();
  final FplDuelService _fplDuelService = FplDuelService();
  final FixtureDuelService _fixtureDuelService = FixtureDuelService();
  final ChatService _notificationService = ChatService();
  final ScrollController _homeScrollController = ScrollController();
  Timer? _refreshTimer;
  bool _backgroundRefreshRunning = false;
  List<Map<String, dynamic>> _notifications = [];
  bool _notificationsMuted = false;
  bool _notificationPreferenceLoaded = false;
  final Set<String> _seenNotificationIds = {};
  final Set<String> _seenKickoffFixtureKeys = {};
  String? _lastPromptedVersion;

  bool get _hasPredictionAccess =>
      SessionManager.instance.currentUser?.hasPredictionAccess ?? false;
  int get _unreadNotificationCount =>
      _notifications.where((item) => item['read_at'] == null).length;

  static const List<SportModel> _defaultSports = [
    SportModel(
      id: 1,
      name: 'Football',
      key: 'football',
      slug: 'football',
      active: true,
    ),
    SportModel(
      id: 2,
      name: 'Basketball',
      key: 'basketball',
      slug: 'basketball',
      active: true,
    ),
    SportModel(
      id: 3,
      name: 'Tennis',
      key: 'tennis',
      slug: 'tennis',
      active: true,
    ),
    SportModel(
      id: 4,
      name: 'Cricket',
      key: 'cricket',
      slug: 'cricket',
      active: true,
    ),
    SportModel(
      id: 5,
      name: 'Ice Hockey',
      key: 'ice_hockey',
      slug: 'ice_hockey',
      active: true,
    ),
    SportModel(
      id: 6,
      name: 'Table Tennis',
      key: 'table_tennis',
      slug: 'table_tennis',
      active: true,
    ),
    SportModel(
      id: 7,
      name: 'Baseball',
      key: 'baseball',
      slug: 'baseball',
      active: true,
    ),
    SportModel(
      id: 8,
      name: 'Volleyball',
      key: 'volleyball',
      slug: 'volleyball',
      active: true,
    ),
    SportModel(id: 9, name: 'Rugby', key: 'rugby', slug: 'rugby', active: true),
    SportModel(
      id: 10,
      name: 'Darts',
      key: 'darts',
      slug: 'darts',
      active: true,
    ),
  ];

  List<SportModel> get _currentSports =>
      _apiSports.isNotEmpty ? _apiSports : _defaultSports;

  List<SportModel> _apiSports = [];
  List<LeagueModel> _apiLeagues = [];
  List<FixtureModel> _apiPrematchFixtures = [];
  List<FixtureModel> _apiLiveFixtures = [];
  List<PredictionModel> _homePredictions = [];
  FixtureDuelModel? _bannerFixtureCampaign;
  FplDuelChallengeModel? _bannerFplCampaign;
  FixtureModel? _bannerFeaturedFixture;
  DateTime? _lastBannerRefresh;

  bool _isLoadingSportsData = true;
  bool _isLoadingMoreFixtures = false;
  bool _hasMoreFixtures = true;
  int _currentPage = 1;
  int _totalPages = 1;
  int get totalPages => _totalPages;
  String? _sportsDataError;
  String? _liveDataError;

  int _popularFilterIndex = 0;
  int _popularPredictionPage = 1;
  final ScrollController _predictionScrollController = ScrollController();
  Map<String, dynamic>? _predictionSnapshot;
  bool _predictionLoadingMore = false;
  String? _predictionMoreError;
  int _predictionGeneration = 0;
  bool _predictionRefreshing = false;
  Timer? _predictionRetryTimer;
  bool _predictionAccessAtLoad = false;
  String? _predictionTokenAtLoad;

  void _onPredictionSessionChanged() {
    final access = _hasPredictionAccess;
    if (!mounted ||
        access == _predictionAccessAtLoad &&
            SessionManager.instance.accessToken == _predictionTokenAtLoad) {
      return;
    }
    _predictionTokenAtLoad = SessionManager.instance.accessToken;
    _predictionAccessAtLoad = access;
    _loadPopularPredictions(_popularFilterIndex);
  }

  void _schedulePredictionRetry(int version) {
    if (!mounted || !_hasPredictionAccess || version != _predictionGeneration) {
      return;
    }
    _predictionRetryTimer?.cancel();
    _predictionRetryTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && version == _predictionGeneration) {
        _loadPopularPredictions(_popularFilterIndex, true);
      }
    });
  }

  int _footballMarketIndex = 0;

  bool get _hasFootballTopPredictions => const {
    'Over 1.5 Goals',
    'Over 2.5 Goals',
    '1X2',
    'BTTS',
    'Corners Market',
    'First Half Goals',
    'Second Half Goals',
  }.contains(_footballMarketTags[_footballMarketIndex]);
  int _otherSportSubTabIndex = 0;
  int _ratingBetMarketIndex = 0;
  Future<Map<String, dynamic>>? _popularPredictionsFuture;
  static const List<String> _popularFilterLabels = [
    'Popular',
    'Best Picks',
    'Player Props',
    'Football',
    'Zai Pick',
    'Ice Hockey',
    'Basketball',
    'Tennis',
    'American Football',
    'Baseball',
    'Volleyball',
    'Handball',
    'Accumulators',
  ];
  static const int _ratingBetFilterIndex = 4;
  static const int _accumulatorFilterIndex = 12;
  static const List<String> _footballMarketTags = [
    '1X2',
    'Draw Predictions',
    'Over 1.5 Goals',
    'Over 2.5 Goals',
    'Over 3.5 Goals',
    'Under 2.5 Goals',
    'Under 3.5 Goals',
    'Under 4.5 Goals',
    'BTTS',
    'Double Chance',
    'Corners Market',
    'Cards Market',
    'First Half Goals',
    'Second Half Goals',
    'Goal Timing',
    'Goal Ranges',
    'Half-Time Result',
    'Team To Score',
    'BTTS By Half',
    'Booking Points',
    'Totals',
    'Handicap',
    'Draw No Bet',
    'Team Totals',
    'Period Markets',
  ];
  static const List<String> _footballMarketLabels = [
    '1X2',
    'Draw Predictions',
    'Over 1.5',
    'Over 2.5',
    'Over 3.5',
    'Under 2.5',
    'Under 3.5',
    'Under 4.5',
    'Both Teams to Score',
    'Double Chance',
    'Corners',
    'Cards',
    '1st Half Goals',
    '2nd Half Goals',
    'Goal Timing',
    'Goal Ranges',
    'Half-Time Result',
    'Team To Score',
    'BTTS By Half',
    'Booking Points',
    'All Totals',
    'Handicap',
    'Draw No Bet',
    'Team Totals',
    'Period Markets',
  ];
  static const List<String> _otherSportSubTabLabels = [
    'All',
    'Over',
    'Under',
    'Handicap',
  ];
  static const List<Map<String, String>> _ratingBetBaseMarkets = [
    {'key': 'math', 'label': 'Math'},
    {'key': '1x2', 'label': '1x2'},
    {'key': 'goals-over-under', 'label': 'O/U Goals'},
    {'key': 'goals-over-under-1-5', 'label': 'O/U 1.5'},
    {'key': 'goals-over-under-3-5', 'label': 'O/U 3.5'},
    {'key': 'goals-over-under-4-5', 'label': 'O/U 4.5'},
    {'key': 'btts', 'label': 'BTTS'},
    {'key': 'half-full-time', 'label': 'HT/FT'},
    {'key': 'asian-handicap', 'label': 'Asian Handicap'},
    {'key': 'double-chance', 'label': 'Double Chance'},
    {'key': 'correct-score', 'label': 'Correct Score'},
    {'key': 'corners-over-under', 'label': 'Corners'},
    {'key': 'cards-over-under', 'label': 'Cards'},
    {'key': 'draw-no-bet', 'label': 'Draw No Bet'},
    {'key': 'team-clean-sheet', 'label': 'Clean Sheet'},
    {'key': 'win-to-nil', 'label': 'Win to Nil'},
    {'key': 'ht-btts', 'label': 'HT/BTTS'},
    {'key': 'result-btts', 'label': 'Result/BTTS'},
    {'key': 'result-and-over-under', 'label': 'Result/Total Goals'},
    {'key': 'first-team-to-score', 'label': 'First Team To Score'},
    {'key': 'own-goal', 'label': 'Own Goal'},
    {'key': 'odd-even', 'label': 'Odd/Even'},
  ];
  static const List<Map<String, String>> _zaiFeaturedMarkets = [
    {'key': 'zai-2-odds', 'label': '2 Odds VIP'},
    {'key': 'zai-accumulators', 'label': 'Accumulators'},
    {'key': 'safe', 'label': 'Safe'},
  ];
  late List<Map<String, String>> _ratingBetMarkets = _initialRatingBetMarkets;
  List<Map<String, String>> get _initialRatingBetMarkets => [
    ..._zaiFeaturedMarkets,
    ..._ratingBetBaseMarkets,
  ];
  final Map<String, TicketSelectionModel> _selectedTicketItems = {};

  // Community Slips & User Picks Feed State
  List<TicketBucketModel> _communityTickets = [];
  List<UserPickFeedItemModel> _userPicksStream = [];
  bool _loadingCommunityTickets = false;
  bool _loadingUserPicksStream = false;
  String _communityTicketStatusFilter = 'all';
  String _userPickStatusFilter = 'all';

  Future<void> _loadCommunityTickets([String status = 'all']) async {
    setState(() {
      _communityTicketStatusFilter = status;
      _loadingCommunityTickets = true;
    });
    try {
      final res = await _sportsService.getTicketsFeed(
        status: status,
        pageSize: 30,
      );
      if (mounted) {
        setState(() {
          _communityTickets = res.tickets;
          _loadingCommunityTickets = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingCommunityTickets = false);
      }
    }
  }

  Future<void> _loadUserPicksStream([String status = 'all']) async {
    setState(() {
      _userPickStatusFilter = status;
      _loadingUserPicksStream = true;
    });
    try {
      final res = await _sportsService.getUserPicksFeed(
        status: status,
        pageSize: 50,
      );
      if (mounted) {
        setState(() {
          _userPicksStream = res;
          _loadingUserPicksStream = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingUserPicksStream = false);
      }
    }
  }

  void _loadPopularPredictions([int filterIndex = 0, bool background = false]) {
    _predictionRetryTimer?.cancel();
    final version = ++_predictionGeneration;
    setState(() {
      _popularFilterIndex = filterIndex.clamp(
        0,
        _popularFilterLabels.length - 1,
      );
      _popularPredictionPage = 1;
      if (!background) _predictionSnapshot = null;
      _predictionLoadingMore = false;
      _predictionMoreError = null;
      _popularPredictionsFuture = _requestPredictionPage(1).then(
        (data) {
          if (mounted && version == _predictionGeneration) {
            _predictionSnapshot = data;
            if (data['loading'] == true || data['retry_pending'] == true) {
              _schedulePredictionRetry(version);
            }
          }
          return data;
        },
        onError: (Object error, StackTrace stack) {
          if (background && _predictionSnapshot != null) {
            _schedulePredictionRetry(version);
            return {..._predictionSnapshot!, 'retry_pending': true};
          }
          return <String, dynamic>{
            'items': <dynamic>[],
            'loading': false,
            'load_error': error.toString(),
          };
        },
      );
    });
    if (!background && _predictionScrollController.hasClients) {
      _predictionScrollController.jumpTo(0);
    }
  }

  Future<Map<String, dynamic>> _requestPredictionPage(int page) {
    if (!_hasPredictionAccess) {
      return Future.value({'items': [], 'groups': [], 'total_pages': 1});
    }
    final index = _popularFilterIndex;
    if (index == _ratingBetFilterIndex) {
      if (_ratingBetMarkets.isEmpty) {
        _ratingBetMarkets = _initialRatingBetMarkets;
      }
      _ratingBetMarketIndex = _ratingBetMarketIndex.clamp(
        0,
        _ratingBetMarkets.length - 1,
      );
      return _retryPredictionLoad(
        () => _loadZaiMarket(
          _ratingBetMarkets[_ratingBetMarketIndex]['key']!,
          page,
        ),
      );
    }
    if (index == 1) {
      return _retryPredictionLoad(
        () => _sportsService.getBestPicks(
          date: _homeDate,
          page: page,
          pageSize: 20,
        ),
      );
    }
    if (index == 2) {
      return _retryPredictionLoad(
        () => _sportsService.getPlayerProps(
          date: _homeDate,
          page: page,
          pageSize: 20,
        ),
      );
    }
    if (index == 3) {
      return _retryPredictionLoad(
        () => _loadFootballMarket(_footballMarketIndex, page),
      );
    }
    if (index == _accumulatorFilterIndex) {
      return _retryPredictionLoad(
        () => _sportsService.getAccumulatorPredictions(date: _homeDate),
      );
    }
    if (index >= 5) {
      return _retryPredictionLoad(
        () => _loadOtherSportMarket(index, _otherSportSubTabIndex, page),
      );
    }
    return _retryPredictionLoad(
      () => _sportsService.getPopularPredictions(
        date: _homeDate,
        page: page,
        pageSize: 20,
      ),
    );
  }

  List<Map<String, dynamic>> _predictionRows(dynamic value) =>
      (value is List ? value : const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  List<Map<String, dynamic>> _mergePredictionRows(
    dynamic first,
    dynamic second,
  ) {
    final rows = <String, Map<String, dynamic>>{};
    for (final item in [
      ..._predictionRows(first),
      ..._predictionRows(second),
    ]) {
      final key =
          '${item['source']}|${item['id'] ?? item['fixture_id']}|${item['market']}|${item['selection']}';
      rows[key] = item;
    }
    return rows.values.toList();
  }

  void _onPredictionScroll() {
    if (_predictionScrollController.hasClients &&
        _predictionScrollController.position.extentAfter < 600) {
      unawaited(_loadMorePredictions());
    }
  }

  Future<void> _loadMorePredictions() async {
    final current = _predictionSnapshot;
    if (!mounted ||
        current == null ||
        _predictionLoadingMore ||
        _predictionMoreError != null) {
      return;
    }
    final pages = int.tryParse('${current['total_pages'] ?? 1}') ?? 1;
    if (_popularPredictionPage >= pages) return;
    final version = _predictionGeneration;
    final next = _popularPredictionPage + 1;
    setState(() => _predictionLoadingMore = true);
    try {
      final incoming = await _requestPredictionPage(next);
      if (!mounted || version != _predictionGeneration) return;
      final groups = <String, Map<String, dynamic>>{};
      for (final group in [
        ..._predictionRows(current['groups']),
        ..._predictionRows(incoming['groups']),
      ]) {
        final key = '${group['id'] ?? group['market']}';
        final previous = groups[key];
        groups[key] = {
          ...group,
          'items': _mergePredictionRows(previous?['items'], group['items']),
        };
      }
      final merged = {
        ...current,
        ...incoming,
        'items': _mergePredictionRows(current['items'], incoming['items']),
        'groups': groups.values.toList(),
        'top_items': current['top_items'] ?? const [],
      };
      if (_predictionRows(incoming['items']).isEmpty &&
          _predictionRows(incoming['groups']).isEmpty) {
        merged['total_pages'] = next;
      }
      setState(() {
        _popularPredictionPage = next;
        _predictionSnapshot = merged;
        _popularPredictionsFuture = Future.value(merged);
      });
    } catch (error) {
      if (mounted && version == _predictionGeneration) {
        setState(() => _predictionMoreError = error.toString());
      }
    } finally {
      if (mounted && version == _predictionGeneration) {
        setState(() => _predictionLoadingMore = false);
      }
    }
  }

  Future<void> _refreshLoadedPredictionResults() async {
    if (!_predictionScrollController.hasClients ||
        _predictionSnapshot == null ||
        _predictionLoadingMore ||
        _predictionRefreshing) {
      return;
    }
    _predictionRefreshing = true;
    final version = _predictionGeneration;
    try {
      final pages = await Future.wait([
        for (var page = 1; page <= _popularPredictionPage; page++)
          _requestPredictionPage(page),
      ]);
      if (!mounted || version != _predictionGeneration) return;
      var items = <Map<String, dynamic>>[];
      final groups = <String, Map<String, dynamic>>{};
      for (final data in pages) {
        items = _mergePredictionRows(items, data['items']);
        for (final group in _predictionRows(data['groups'])) {
          final key = '${group['id'] ?? group['market']}';
          groups[key] = {
            ...group,
            'items': _mergePredictionRows(
              groups[key]?['items'],
              group['items'],
            ),
          };
        }
      }
      final updated = {
        ...pages.first,
        'items': items,
        'groups': groups.values.toList(),
        'page': _popularPredictionPage,
      };
      setState(
        () => _popularPredictionsFuture = Future.value(
          _predictionSnapshot = updated,
        ),
      );
    } catch (_) {
      /* Keep the loaded list on a transient refresh failure. */
    } finally {
      _predictionRefreshing = false;
    }
  }

  Future<Map<String, dynamic>> _loadFootballMarket(
    int marketIndex,
    int page,
  ) async {
    final index = marketIndex.clamp(0, _footballMarketTags.length - 1);
    _footballMarketIndex = index;
    final tag = _footballMarketTags[index];
    if (tag == 'Draw Predictions') {
      return _sportsService.getRatingBetPredictions(
        market: 'draw',
        date: _homeDate,
        page: page,
        pageSize: 20,
      );
    }
    final generation = _predictionGeneration;
    final needsTop = page == 1 && _hasFootballTopPredictions;
    final data = await loadPredictionSections(
      general: _sportsService.getPredictionFeed(
        section: 'general',
        sport: 'Football',
        tag: tag,
        date: _homeDate,
        page: page,
        pageSize: 20,
      ),
      top: needsTop
          ? _sportsService.getPredictionFeed(
              section: 'top',
              sport: 'Football',
              tag: tag,
              date: _homeDate,
              page: 1,
              pageSize: 50,
            )
          : null,
      onTopReady: (top) {
        // Let the initial general response install its snapshot first.
        unawaited(
          Future<void>.delayed(Duration.zero, () {
            if (!mounted ||
                generation != _predictionGeneration ||
                _popularFilterIndex != 3 ||
                _footballMarketIndex != index) {
              return;
            }
            final current = _predictionSnapshot;
            if (current == null) return;
            final updated = mergePredictionSections(current, top, hasTop: true);
            setState(() {
              _predictionSnapshot = updated;
              _popularPredictionsFuture = Future.value(updated);
            });
            if (updated['retry_pending'] == true) {
              _schedulePredictionRetry(generation);
            }
          }),
        );
      },
    );
    return {
      ...data,
      'general_title': _footballMarketLabels[index],
      'has_top_section': _hasFootballTopPredictions,
    };
  }

  Future<Map<String, dynamic>> _loadOtherSportMarket(
    int filterIndex,
    int subTabIndex,
    int page,
  ) {
    const sports = <int, String>{
      5: 'Ice Hockey',
      6: 'Basketball',
      7: 'Tennis',
      8: 'American Football',
      9: 'Baseball',
      10: 'Volleyball',
      11: 'Handball',
    };
    final sport = sports[filterIndex] ?? 'Ice Hockey';
    final safeSubIndex = subTabIndex.clamp(
      0,
      _otherSportSubTabLabels.length - 1,
    );
    _otherSportSubTabIndex = safeSubIndex;
    return _sportsService.getPredictionFeed(
      sport: sport,
      market: safeSubIndex == 0 ? null : _otherSportSubTabLabels[safeSubIndex],
      date: _homeDate,
      page: page,
      pageSize: 20,
    );
  }

  Future<Map<String, dynamic>> _loadRatingBetMarket(
    String marketKey,
    int page,
  ) async {
    final response = await _sportsService.getRatingBetPredictions(
      market: marketKey,
      date: _homeDate,
      page: page,
      pageSize: 20,
    );
    final rawMarkets = response['markets'];
    if (rawMarkets is List && rawMarkets.isNotEmpty && mounted) {
      final providerMarkets = rawMarkets
          .whereType<Map>()
          .map(
            (item) => {
              'key': item['key']?.toString() ?? '',
              'label': item['label']?.toString() ?? '',
            },
          )
          .where((item) => item['key']!.isNotEmpty && item['label']!.isNotEmpty)
          .toList();
      final featuredKeys = _zaiFeaturedMarkets
          .map((market) => market['key'])
          .toSet();
      final markets = <Map<String, String>>[
        ..._zaiFeaturedMarkets,
        ...providerMarkets.where(
          (market) =>
              !featuredKeys.contains(market['key']) && market['key'] != 'draw',
        ),
      ];
      if (markets.isNotEmpty) {
        final selectedIndex = markets.indexWhere(
          (item) => item['key'] == marketKey,
        );
        setState(() {
          _ratingBetMarkets = markets;
          if (selectedIndex >= 0) _ratingBetMarketIndex = selectedIndex;
        });
      }
    }
    return response;
  }

  Future<Map<String, dynamic>> _loadZaiMarket(String marketKey, int page) {
    switch (marketKey) {
      case 'zai-2-odds':
        return _sportsService.getZaiVipPredictions(date: _homeDate);
      case 'zai-accumulators':
        return _sportsService.getZaiMarketLists(
          date: _homeDate,
          page: page,
          pageSize: 20,
        );
      default:
        return _loadRatingBetMarket(marketKey, page);
    }
  }

  Future<Map<String, dynamic>> _retryPredictionLoad(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    final generation = _predictionGeneration;
    return loadPredictionFeed(
      request,
      shouldContinue: () => mounted && generation == _predictionGeneration,
      shouldRetryError: (error) =>
          error is! SportsException ||
          error.statusCode == 408 ||
          error.statusCode == 429 ||
          error.statusCode >= 500,
    );
  }

  @override
  void initState() {
    super.initState();
    _predictionAccessAtLoad = _hasPredictionAccess;
    _predictionTokenAtLoad = SessionManager.instance.accessToken;
    SessionManager.instance.addListener(_onPredictionSessionChanged);
    _homeScrollController.addListener(_onScroll);
    _predictionScrollController.addListener(_onPredictionScroll);
    _loadSportsData();
    unawaited(_loadHomeBanner());
    _loadPopularPredictions(0);
    _loadCommunityTickets();
    _loadUserPicksStream();
    unawaited(_pollNotifications());
    unawaited(_checkForAppUpdate());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_backgroundRefresh()),
    );
  }

  Future<void> _backgroundRefresh() async {
    if (!mounted || _backgroundRefreshRunning) return;
    _backgroundRefreshRunning = true;
    try {
      await Future.wait([
        _loadSportsData(silent: true),
        _loadLiveSportsData(),
        _pollNotifications(),
        _checkForAppUpdate(),
        _loadHomeBanner(),
        _refreshLoadedPredictionResults(),
      ]);
    } finally {
      _backgroundRefreshRunning = false;
    }
  }

  Future<void> _pollNotifications() async {
    if (!SessionManager.instance.isLoggedIn) return;
    try {
      if (!_notificationPreferenceLoaded) {
        _notificationsMuted = await _notificationService.notificationMuted();
        _notificationPreferenceLoaded = true;
      }
      final items = dedupeTickerNotifications(
        await _notificationService.loadNotifications(),
      );
      if (!mounted) return;
      final unread = items.where((item) => item['read_at'] == null).toList();
      final fresh = unread.where((item) {
        final id = item['id']?.toString() ?? '';
        final fixtureKey = kickoffNotificationFixtureKey(item);
        return id.isNotEmpty &&
            !_seenNotificationIds.contains(id) &&
            (fixtureKey == null ||
                !_seenKickoffFixtureKeys.contains(fixtureKey));
      }).toList();
      setState(() => _notifications = items);
      _seenNotificationIds.addAll(
        items
            .map((item) => item['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty),
      );
      _seenKickoffFixtureKeys.addAll(
        items.map(kickoffNotificationFixtureKey).whereType<String>(),
      );
      if (fresh.isNotEmpty && mounted && !_notificationsMuted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fresh.first['message']?.toString() ?? 'New notification',
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _checkForAppUpdate() async {
    try {
      final status = await _sportsService.checkAppVersion(AppConfig.appVersion);
      if (!mounted || status['update_available'] != true) return;
      final latest = status['latest_version']?.toString() ?? '';
      if (latest.isEmpty || latest == _lastPromptedVersion) return;
      _lastPromptedVersion = latest;
      final mandatory = status['mandatory'] == true;
      final updateUrl = status['update_url']?.toString() ?? '';
      await showDialog<void>(
        context: context,
        barrierDismissible: !mandatory,
        builder: (dialogContext) => PopScope(
          canPop: !mandatory,
          child: AlertDialog(
            title: Text(status['title']?.toString() ?? 'Update available'),
            content: Text(
              status['message']?.toString() ??
                  'A new app version is available.',
            ),
            actions: [
              if (!mandatory)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Later'),
                ),
              FilledButton(
                onPressed: updateUrl.isEmpty
                    ? null
                    : () => launchUrl(
                        Uri.parse(updateUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                child: const Text('Update'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _showNotifications() async {
    await _pollNotifications();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF191126),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Notifications',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _notifications.isEmpty
                          ? null
                          : () async {
                              await _notificationService.clearNotifications();
                              if (!mounted) return;
                              setState(() => _notifications = []);
                              setSheetState(() {});
                            },
                      icon: const Icon(Icons.clear_all_rounded, size: 18),
                      label: const Text('Clear'),
                    ),
                    IconButton(
                      tooltip: _notificationsMuted
                          ? 'Unmute notifications'
                          : 'Mute notifications',
                      onPressed: () async {
                        final muted = !_notificationsMuted;
                        await _notificationService.setNotificationMuted(muted);
                        if (!mounted) return;
                        setState(() => _notificationsMuted = muted);
                        setSheetState(() {});
                      },
                      icon: Icon(
                        _notificationsMuted
                            ? Icons.notifications_off_rounded
                            : Icons.notifications_active_rounded,
                        color: _notificationsMuted
                            ? Colors.white54
                            : const Color(0xFFFFD700),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _notifications.isEmpty
                    ? const Center(
                        child: Text(
                          'No notifications yet.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView(
                        children: _notifications.map((notification) {
                          final id = notification['id']?.toString() ?? '';
                          final unread = notification['read_at'] == null;
                          return ListTile(
                            leading: Icon(
                              unread
                                  ? Icons.notifications_active
                                  : Icons.notifications,
                              color: unread
                                  ? const Color(0xFFFFD700)
                                  : Colors.white38,
                            ),
                            title: Text(
                              notification['message']?.toString() ?? '',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              notification['type']?.toString().replaceAll(
                                    '_',
                                    ' ',
                                  ) ??
                                  '',
                              style: const TextStyle(color: Colors.white54),
                            ),
                            onTap: id.isEmpty
                                ? null
                                : () async {
                                    if (unread) {
                                      await _notificationService
                                          .markNotificationRead(id);
                                    }
                                    if (sheetContext.mounted)
                                      Navigator.pop(sheetContext);
                                    unawaited(_pollNotifications());
                                  },
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadDrawerSportLeagues(int sportId) async {
    setState(() {
      _drawerIsLoading = true;
      _drawerSelectedSportId = sportId;
      _drawerSportLeagues = [];
    });
    try {
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      var leagues = await _sportsService.getLeagues(
        sportId: sportId,
        date: todayStr,
      );
      if (leagues.isEmpty) {
        leagues = await _sportsService.getLeagues(sportId: sportId);
      }
      if (mounted) {
        leagues.sort((a, b) {
          if (a.matchCount != b.matchCount) {
            return b.matchCount.compareTo(a.matchCount);
          }
          return a.name.compareTo(b.name);
        });
        setState(() {
          _drawerSportLeagues = leagues;
          _drawerIsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _drawerIsLoading = false);
      }
    }
  }

  Future<void> _loadDrawerLive() async {
    if (_drawerIsLoading) return;
    setState(() {
      _drawerIsLoading = true;
      _drawerLiveFixtures = [];
    });
    try {
      final live = await _sportsService.getLiveFixtures();
      if (mounted) {
        setState(() {
          _drawerLiveFixtures = live;
          _apiLiveFixtures = live;
          _drawerIsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _drawerIsLoading = false);
      }
    }
  }

  Future<void> _loadDrawerCountries() async {
    if (_drawerIsLoading) return;
    setState(() {
      _drawerIsLoading = true;
    });
    try {
      final leagues = await _sportsService.getLeagues();
      if (mounted) {
        setState(() {
          _drawerAllLeagues = leagues;
          _drawerIsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _drawerIsLoading = false);
      }
    }
  }

  Future<void> _loadLiveSportsData() async {
    try {
      final live = await _sportsService.getLiveFixtures();
      if (mounted) {
        setState(() {
          _apiLiveFixtures = live;
          _drawerLiveFixtures = live;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _predictionRetryTimer?.cancel();
    SessionManager.instance.removeListener(_onPredictionSessionChanged);
    _refreshTimer?.cancel();
    unawaited(_notificationService.close());
    _predictionScrollController.removeListener(_onPredictionScroll);
    _predictionScrollController.dispose();
    _homeScrollController.removeListener(_onScroll);
    _homeScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_homeScrollController.position.pixels >=
            _homeScrollController.position.maxScrollExtent - 400 &&
        !_isLoadingMoreFixtures &&
        _hasMoreFixtures &&
        _currentPage < _totalPages &&
        !_isLoadingSportsData) {
      _loadMoreFixtures();
    }
  }

  Future<void> _loadSportsData({
    int? sportId,
    String? league,
    String? country,
    bool silent = false,
  }) async {
    // A silent timer refresh belongs to the current filter/date request. It
    // must not invalidate an in-flight pagination request or reset the list to
    // page one while the user is scrolling.
    final requestVersion = silent
        ? _sportsRequestVersion
        : ++_sportsRequestVersion;
    _dayFixturesFuture = null;
    _homeMarketDetails.clear();
    final activeLeague = league ?? _selectedLeague;
    final activeCountry = country ?? _selectedCountry;

    setState(() {
      if (!silent) {
        _isLoadingSportsData = true;
        _isLoadingMoreFixtures = false;
        _apiPrematchFixtures = [];
        _homePredictions = [];
        _sportsDataError = null;
        _liveDataError = null;
        _currentPage = 1;
        _totalPages = 1;
        _hasMoreFixtures = true;
      }
      if (league != null) _selectedLeague = league;
      if (country != null) _selectedCountry = country;
    });

    try {
      final todayStr = _homeDate;

      final targetSportId =
          sportId ??
          (_currentSports.isNotEmpty &&
                  _sportsTabNavIndex < _currentSports.length
              ? _currentSports[_sportsTabNavIndex].id
              : 1);

      Future<PaginatedResponse<FixtureModel>> loadPrematchWithRetry() async {
        String? lastErr;
        final maxAttempts = silent ? 1 : 4;
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
          try {
            final res = await _sportsService.getFixturesPaginated(
              sportId: targetSportId,
              page: 1,
              pageSize: 20,
              date: todayStr,
              league: activeLeague,
              country: activeCountry,
              timeout: const Duration(seconds: 45),
            );
            if (res.success && res.data.isNotEmpty) {
              return res;
            }
            if (res.success && res.data.isEmpty && attempt < maxAttempts) {
              debugPrint(
                'Initial fixtures empty on attempt $attempt, waiting for backend response...',
              );
              await Future.delayed(const Duration(milliseconds: 2500));
              continue;
            }
            return res;
          } catch (e) {
            lastErr = e.toString();
            debugPrint('getFixturesPaginated attempt $attempt failed: $e');
            if (attempt < maxAttempts) {
              await Future.delayed(const Duration(milliseconds: 2000));
            }
          }
        }
        throw SportsException(
          lastErr ?? 'Unable to load matches for the selected date',
        );
      }

      final prematchPaginatedFuture = loadPrematchWithRetry();
      final sportsFuture = _apiSports.isNotEmpty
          ? Future.value(_apiSports)
          : _sportsService.getSports();
      final leaguesFuture = _sportsService.getLeagues(
        sportId: targetSportId,
        date: todayStr,
      );
      final liveFixturesFuture = _sportsService.getLiveFixtures();
      final predictionsFuture = _hasPredictionAccess
          ? _sportsService.getPredictions(
              sportId: targetSportId,
              date: todayStr,
            )
          : Future.value(<PredictionModel>[]);
      final liveStreamsFuture = _sportsService.getLiveStreams(live: false);

      // Await the primary match fixtures first so the list renders immediately
      final paginatedPrematch = await prematchPaginatedFuture;
      if (!paginatedPrematch.success) {
        throw SportsException('Unable to load matches for the selected date');
      }
      List<FixtureModel> prematch = List.from(paginatedPrematch.data);
      final totalPages = paginatedPrematch.totalPages;

      if (mounted && requestVersion == _sportsRequestVersion) {
        setState(() {
          if (silent) {
            final refreshed = {for (final item in prematch) item.id: item};
            final existingIds = _apiPrematchFixtures
                .map((item) => item.id)
                .toSet();
            _apiPrematchFixtures = _apiPrematchFixtures
                .map((item) => refreshed[item.id] ?? item)
                .toList();
            _apiPrematchFixtures.insertAll(
              0,
              prematch.where((item) => !existingIds.contains(item.id)),
            );
          } else {
            _apiPrematchFixtures = prematch;
            _currentPage = paginatedPrematch.page;
          }
          _totalPages = totalPages;
          _hasMoreFixtures = _currentPage < totalPages && prematch.isNotEmpty;
          if (!silent) _isLoadingSportsData = false;
        });
        unawaited(_refreshHomeMarketOdds(prematch));
      }

      // Secondary futures resolve asynchronously without blocking fixture display
      sportsFuture
          .then((sports) {
            if (!mounted || requestVersion != _sportsRequestVersion) return;
            setState(() {
              _apiSports = sports;
              final index = _currentSports.indexWhere(
                (sport) => sport.id == targetSportId,
              );
              if (index >= 0) _sportsTabNavIndex = index;
            });
          })
          .catchError((e) {
            debugPrint('getSports error: $e');
          });

      leaguesFuture
          .then((leagues) {
            if (!mounted || requestVersion != _sportsRequestVersion) return;
            setState(() => _apiLeagues = leagues);
          })
          .catchError((e) {
            debugPrint('getLeagues error: $e');
          });

      liveFixturesFuture
          .then((live) {
            if (!mounted || requestVersion != _sportsRequestVersion) return;
            setState(() => _apiLiveFixtures = live);
          })
          .catchError((e) {
            debugPrint('getLiveFixtures error: $e');
            if (mounted && requestVersion == _sportsRequestVersion) {
              setState(() => _liveDataError = e.toString());
            }
          });

      predictionsFuture
          .then((persistedPredictions) {
            if (!mounted || requestVersion != _sportsRequestVersion) return;
            setState(() {
              _homePredictions = persistedPredictions;
              _apiPrematchFixtures = _mergeHomePredictions(
                _apiPrematchFixtures,
                persistedPredictions,
              );
            });
          })
          .catchError((e) {
            debugPrint('getPredictions error: $e');
          });

      liveStreamsFuture
          .then((streams) {
            if (!mounted || requestVersion != _sportsRequestVersion) return;
            setState(() => _liveStreamsSnapshot = _sortLiveStreams(streams));
          })
          .catchError((e) {
            debugPrint('getLiveStreams error: $e');
            if (mounted && requestVersion == _sportsRequestVersion) {
              setState(() => _liveStreamsError = e.toString());
            }
          });
    } catch (e) {
      if (mounted && requestVersion == _sportsRequestVersion) {
        setState(() {
          _sportsDataError = e.toString();
          _isLoadingSportsData = false;
        });
      }
    }
  }

  Future<void> _refreshHomeMarketOdds(
    List<FixtureModel> fixtures, {
    String? market,
  }) async {
    try {
      final current = {
        for (final fixture in _apiPrematchFixtures) fixture.id: fixture,
      };
      final original = fixtures
          .map((fixture) => current[fixture.id] ?? fixture)
          .toList();
      final hydrated = await _loadHomeMarketOdds(original, market: market);
      if (!mounted) return;
      final updates = <String, FixtureModel>{};
      for (var i = 0; i < original.length && i < hydrated.length; i++) {
        if (!identical(original[i], hydrated[i])) {
          updates[original[i].id] = hydrated[i];
        }
      }
      if (updates.isEmpty) return;
      setState(() {
        _apiPrematchFixtures = _apiPrematchFixtures.map((fixture) {
          final unchanged = original.any((item) => identical(item, fixture));
          return unchanged ? updates[fixture.id] ?? fixture : fixture;
        }).toList();
      });
    } catch (e) {
      debugPrint('Error refreshing home market odds: $e');
    }
  }

  Future<FixtureMarketsModel?> _getHomeFixtureMarkets(String id) async {
    try {
      final detail = await _sportsService
          .getFixtureDetail(
            id,
            includeStreams: false,
            timeout: const Duration(seconds: 4),
          )
          .timeout(const Duration(seconds: 4));
      return detail.fixture.markets;
    } catch (_) {
      return null;
    }
  }

  Future<List<FixtureModel>> _loadHomeMarketOdds(
    List<FixtureModel> fixtures, {
    String? market,
  }) async {
    final result = List<FixtureModel>.from(fixtures);
    final version = _sportsRequestVersion;
    final sport = _activeSportKey;
    final selectedMarket =
        market ??
        (_selectedMarket == 'All Markets'
            ? defaultHomeMarket(sport)
            : _selectedMarket);

    // Missing selected-market odds need repair even without a prediction.
    final needHydration = <int>[];
    for (var i = 0; i < result.length; i++) {
      final fixture = result[i];
      final hasMarket = homeMarketOdds(
        fixture,
        selectedMarket,
        sport,
      ).any((option) => option.odd.isNotEmpty);
      final hasPrediction =
          fixture.prediction == null ||
          homePredictionOdds(fixture, fixture.prediction!, sport).isNotEmpty;
      if (!hasMarket || !hasPrediction) {
        needHydration.add(i);
      }
    }

    if (needHydration.isEmpty) return result;

    // Limit to at most 4 fixtures to prevent browser socket pool exhaustion
    for (final i in needHydration.take(4)) {
      if (!mounted || version != _sportsRequestVersion) break;
      final fixture = result[i];
      final markets = await _homeMarketDetails.putIfAbsent(
        fixture.id,
        () => _getHomeFixtureMarkets(fixture.id),
      );
      if (markets != null) {
        result[i] = fixture.withMarkets(markets);
      } else {
        _homeMarketDetails.remove(fixture.id);
      }
    }
    return result;
  }

  List<FixtureModel> _mergeHomePredictions(
    List<FixtureModel> fixtures,
    List<PredictionModel> predictions,
  ) {
    if (fixtures.isEmpty || predictions.isEmpty) return fixtures;
    final byFixtureId = <String, List<PredictionModel>>{};
    for (final prediction in predictions) {
      final id = prediction.fixtureId?.trim() ?? '';
      if (id.isNotEmpty) {
        byFixtureId.putIfAbsent(id, () => []).add(prediction);
      }
    }
    return fixtures.map((fixture) {
      final hasRealPred =
          fixture.prediction?.prediction.isNotEmpty == true &&
          !(fixture.prediction!.prediction.toUpperCase() == 'O15' &&
              (fixture.prediction!.predictionOdds == '1.32' ||
                  fixture.prediction!.predictionOdds.isEmpty));
      if (hasRealPred) return fixture;

      var candidates = List<PredictionModel>.from(
        byFixtureId[fixture.id] ?? const <PredictionModel>[],
      );
      if (candidates.isEmpty) {
        candidates = predictions.where((prediction) {
          if (_homeTeamKey(prediction.homeTeam) !=
                  _homeTeamKey(fixture.homeTeam) ||
              _homeTeamKey(prediction.awayTeam) !=
                  _homeTeamKey(fixture.awayTeam)) {
            return false;
          }
          final predictionTime = prediction.matchTime;
          return predictionTime == null ||
              predictionTime.difference(fixture.matchTime).abs() <=
                  const Duration(hours: 3);
        }).toList();
      }
      if (candidates.isEmpty) return fixture;
      candidates.sort((a, b) => b.probability.compareTo(a.probability));
      return fixture.withPrediction(candidates.first);
    }).toList();
  }

  String _homeTeamKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\b(fc|ac|sc|fk|cd|club|women|w|u21|u19)\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  Future<void> _loadMoreFixtures() async {
    if (_isLoadingMoreFixtures || !_hasMoreFixtures || _isLoadingSportsData) {
      return;
    }
    final requestVersion = _sportsRequestVersion;
    setState(() {
      _isLoadingMoreFixtures = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final todayStr = _homeDate;
      final targetSportId =
          _currentSports.isNotEmpty &&
              _sportsTabNavIndex < _currentSports.length
          ? _currentSports[_sportsTabNavIndex].id
          : 1;

      final res = await _sportsService.getFixturesPaginated(
        sportId: targetSportId,
        page: nextPage,
        pageSize: 20,
        date: todayStr,
        league: _selectedLeague,
        country: _selectedCountry,
        timeout: const Duration(seconds: 45),
      );

      if (!res.success) {
        throw SportsException(
          'Unable to load more fixtures. Please try again.',
        );
      }
      final fixtures = _mergeHomePredictions(res.data, _homePredictions);
      if (mounted && requestVersion == _sportsRequestVersion) {
        setState(() {
          _currentPage = res.page;
          _totalPages = res.totalPages;
          _hasMoreFixtures = res.page < res.totalPages && res.data.isNotEmpty;
          // Deduplicate by ID to prevent duplicate keys breaking the UI
          final existingIds = _apiPrematchFixtures.map((f) => f.id).toSet();
          final newFixtures = fixtures
              .where((f) => !existingIds.contains(f.id))
              .toList();
          _apiPrematchFixtures.addAll(newFixtures);
          _sportsDataError = null;
          _isLoadingMoreFixtures = false;
        });
      }
    } catch (e) {
      if (mounted && requestVersion == _sportsRequestVersion) {
        setState(() {
          _isLoadingMoreFixtures = false;
          _sportsDataError = e.toString();
        });
      }
    }
  }

  int _bottomNavIndex = 0;
  int _topTabNavIndex = 0;
  int _sportsTabNavIndex = 0;
  int _filterPillIndex = 0;
  int _feedFilterIndex = 0;
  int _drawerSegmentIndex = 0;
  int? _drawerSelectedSportId;
  List<LeagueModel> _drawerSportLeagues = [];
  List<LeagueModel> _drawerAllLeagues = [];
  List<FixtureModel> _drawerLiveFixtures = [];
  bool _drawerIsLoading = false;
  String? _selectedLeague;
  String? _selectedCountry;
  String _selectedMarket = 'All Markets';
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  int _sportsRequestVersion = 0;
  Future<List<FixtureModel>>? _dayFixturesFuture;
  final Map<String, String> _leagueMarkets = {};
  final Map<String, double> _leagueLines = {};
  final Map<String, Future<FixtureMarketsModel?>> _homeMarketDetails = {};

  // Start in catalogue mode. The player appears only after a fixture is
  // selected, so the available-match list is visible when Live TV opens.
  int _selectedStreamIndex = -1;
  int _streamPlayerRevision = 0;
  LiveStreamSnapshotModel _liveStreamsSnapshot =
      const LiveStreamSnapshotModel();
  bool _isLoadingLiveStreams = false;
  String? _liveStreamsError;
  final Set<String> _resolvingStreamIds = {};
  Future<List<AceChannelModel>>? _aceChannelsFuture;
  String _aceChannelQuery = '';

  List<LiveStreamEventModel> get _liveStreamEvents =>
      _liveStreamsSnapshot.fixtures;

  LiveStreamSnapshotModel _sortLiveStreams(LiveStreamSnapshotModel snapshot) {
    final fixtures = List<LiveStreamEventModel>.from(snapshot.fixtures);
    int rank(LiveStreamEventModel event) => switch (event.phase) {
      LiveStreamPhase.live => 0,
      LiveStreamPhase.upcoming => 1,
      LiveStreamPhase.ended => 2,
    };
    fixtures.sort((left, right) {
      final phaseComparison = rank(left).compareTo(rank(right));
      if (phaseComparison != 0) return phaseComparison;
      final leftTime = left.kickoffUtc?.millisecondsSinceEpoch ?? 0;
      final rightTime = right.kickoffUtc?.millisecondsSinceEpoch ?? 0;
      return left.phase == LiveStreamPhase.ended
          ? rightTime.compareTo(leftTime)
          : leftTime.compareTo(rightTime);
    });
    return LiveStreamSnapshotModel(
      provider: snapshot.provider,
      refreshIntervalSeconds: snapshot.refreshIntervalSeconds,
      lastRefreshAt: snapshot.lastRefreshAt,
      lastSuccessAt: snapshot.lastSuccessAt,
      stale: snapshot.stale,
      refreshError: snapshot.refreshError,
      fixtures: fixtures,
    );
  }

  LiveStreamEventModel? _findMatchingStream(FixtureModel fx) {
    if (_liveStreamEvents.isEmpty) return null;
    final normFxHome = fx.normalizedHome.isNotEmpty
        ? fx.normalizedHome.replaceAll(RegExp(r'[^a-z0-9]'), '')
        : fx.homeTeam.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normFxAway = fx.normalizedAway.isNotEmpty
        ? fx.normalizedAway.replaceAll(RegExp(r'[^a-z0-9]'), '')
        : fx.awayTeam.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    for (final stream in _liveStreamEvents) {
      if (!stream.live || !stream.hasStreams) continue;
      final sHome = stream.homeTeam.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      final sAway = stream.awayTeam.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      if (sHome.isNotEmpty &&
          sAway.isNotEmpty &&
          normFxHome.isNotEmpty &&
          normFxAway.isNotEmpty) {
        if ((sHome.contains(normFxHome) || normFxHome.contains(sHome)) &&
            (sAway.contains(normFxAway) || normFxAway.contains(sAway))) {
          return stream;
        }
      }
    }
    return null;
  }

  Future<void> _loadLiveStreams() async {
    final selectedID =
        _selectedStreamIndex >= 0 &&
            _selectedStreamIndex < _liveStreamEvents.length
        ? _liveStreamEvents[_selectedStreamIndex].id
        : '';
    setState(() {
      _isLoadingLiveStreams = true;
      _liveStreamsError = null;
    });
    try {
      final snapshot = _sortLiveStreams(
        await _sportsService.getLiveStreams(live: false),
      );
      if (mounted) {
        setState(() {
          _liveStreamsSnapshot = snapshot;
          _selectedStreamIndex = selectedID.isEmpty
              ? -1
              : snapshot.fixtures.indexWhere((event) => event.id == selectedID);
          _streamPlayerRevision++;
          _isLoadingLiveStreams = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _liveStreamsError = e.toString();
          _isLoadingLiveStreams = false;
        });
      }
    }
  }

  Future<void> _playLiveStreamEvent(
    int index, {
    bool fullscreen = false,
  }) async {
    if (index < 0 || index >= _liveStreamEvents.length) return;
    final event = _liveStreamEvents[index];
    if (!event.live || _resolvingStreamIds.contains(event.id)) return;
    setState(() => _resolvingStreamIds.add(event.id));
    try {
      final resolved = await _sportsService.getStreamDetail(event.id);
      if (!mounted) return;
      if (resolved == null || !resolved.hasStreams) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              resolved?.resolutionError.isNotEmpty == true
                  ? resolved!.resolutionError
                  : 'No playable channel is available for this fixture yet.',
            ),
          ),
        );
        return;
      }
      final fixtures = List<LiveStreamEventModel>.from(_liveStreamEvents);
      final currentIndex = fixtures.indexWhere((item) => item.id == event.id);
      if (currentIndex < 0) return;
      fixtures[currentIndex] = resolved;
      setState(() {
        _liveStreamsSnapshot = LiveStreamSnapshotModel(
          provider: _liveStreamsSnapshot.provider,
          refreshIntervalSeconds: _liveStreamsSnapshot.refreshIntervalSeconds,
          lastRefreshAt: _liveStreamsSnapshot.lastRefreshAt,
          lastSuccessAt: _liveStreamsSnapshot.lastSuccessAt,
          stale: _liveStreamsSnapshot.stale,
          refreshError: _liveStreamsSnapshot.refreshError,
          fixtures: fixtures,
        );
        _selectedStreamIndex = currentIndex;
        _streamPlayerRevision++;
      });
      if (fullscreen && mounted) {
        await InAppPlayerScreen.open(
          context,
          streamEvent: resolved,
          apiBaseUrl: _sportsService.baseUrl,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open this broadcast: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _resolvingStreamIds.remove(event.id));
    }
  }

  String _convertSourcePlatform = 'SportyBet';
  String _convertTargetPlatform = 'MSport';
  String _convertCodeText = '';
  bool _isConvertingCode = false;
  Map<String, dynamic>? _codeConvertResult;

  final Set<String> _selectedOddsKeys = {};
  final Set<String> _selectedLeagues = {};

  final List<String> _topTabs = [
    'Home',

    'Live',
    'Sports',
    'Game Center',
    'Predictions',
    'Feeds',
    'Live TV',
    'SlipIQ',
    'Code Convert',
  ];
  final List<String> _filterPills = ['Today', 'Top Leagues', 'Countries'];
  SportModel get _activeSport =>
      _currentSports[_sportsTabNavIndex.clamp(0, _currentSports.length - 1)];
  String get _activeSportKey =>
      _activeSport.key.isNotEmpty ? _activeSport.key : _activeSport.name;
  List<String> get _marketOptions => sportHomeMarkets(_activeSportKey);
  String get _homeDate => homeFixtureDate(_selectedDate);

  void _selectHomeSport(int index) {
    setState(() {
      _sportsTabNavIndex = index;
      _selectedLeague = null;
      _selectedCountry = null;
      _selectedMarket = 'All Markets';
      _leagueMarkets.clear();
      _leagueLines.clear();
      _filterPillIndex = DateUtils.isSameDay(_selectedDate, DateTime.now())
          ? 0
          : -1;
    });
    unawaited(_loadSportsData(sportId: _activeSport.id));
  }

  void _selectHomeMarket(String market) {
    setState(() {
      _selectedMarket = market;
      _leagueMarkets.clear();
      _leagueLines.clear();
    });
    unawaited(_refreshHomeMarketOdds(_apiPrematchFixtures));
  }

  Future<void> _selectHomeDate(DateTime date) async {
    setState(() {
      _selectedDate = DateUtils.dateOnly(date);
      _selectedLeague = null;
      _selectedCountry = null;
      _leagueMarkets.clear();
      _leagueLines.clear();
      _filterPillIndex = DateUtils.isSameDay(date, DateTime.now()) ? 0 : -1;
    });
    _loadPopularPredictions(_popularFilterIndex);
    await _loadSportsData();
  }

  Future<void> _showHomeCalendar() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 10, 12, 31),
      helpText: 'Choose prediction date',
    );
    if (date != null && mounted) await _selectHomeDate(date);
  }

  Future<void> _showFixtureSearch() async {
    final controller = TextEditingController();
    Timer? debounce;
    var loading = false;
    String? error;
    var results = <FixtureModel>[];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171221),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> search(String value) async {
            final query = value.trim();
            if (query.length < 2) {
              setSheetState(() {
                loading = false;
                error = null;
                results = <FixtureModel>[];
              });
              return;
            }
            setSheetState(() {
              loading = true;
              error = null;
            });
            try {
              final response = await _sportsService.getFixturesPaginated(
                query: query,
                page: 1,
                pageSize: 50,
              );
              if (!sheetContext.mounted || controller.text.trim() != query) {
                return;
              }
              setSheetState(() {
                results = response.data;
                loading = false;
              });
            } catch (e) {
              if (!sheetContext.mounted) return;
              setSheetState(() {
                loading = false;
                error = e.toString();
              });
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.72,
                child: Column(
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search team, league or country',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Color(0xFFFFD700),
                        ),
                        suffixIcon: IconButton(
                          onPressed: () {
                            controller.clear();
                            search('');
                          },
                          icon: const Icon(Icons.close, color: Colors.white54),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF231B32),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        debounce?.cancel();
                        debounce = Timer(
                          const Duration(milliseconds: 350),
                          () => search(value),
                        );
                      },
                      onSubmitted: search,
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const LinearProgressIndicator(color: Color(0xFFFFD700)),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Color(0xFFFF6B6B)),
                        ),
                      ),
                    Expanded(
                      child: results.isEmpty && !loading && error == null
                          ? const Center(
                              child: Text(
                                'Search past and upcoming matches',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                color: Color(0xFF2F2445),
                              ),
                              itemBuilder: (_, index) {
                                final fixture = results[index];
                                final local = fixture.matchTime.toLocal();
                                final date =
                                    '${local.day.toString().padLeft(2, '0')}/'
                                    '${local.month.toString().padLeft(2, '0')}/${local.year} '
                                    '${local.hour.toString().padLeft(2, '0')}:'
                                    '${local.minute.toString().padLeft(2, '0')}';
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  title: Text(
                                    '${fixture.homeTeam}  vs  ${fixture.awayTeam}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${fixture.leagueName} • $date',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFFFFD700),
                                  ),
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => MatchDetailScreen(
                                          fixtureId: fixture.id,
                                          initialFixture: fixture,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    debounce?.cancel();
    controller.dispose();
  }

  Future<List<FixtureModel>> _dailyHomeFixtures() =>
      _dayFixturesFuture ??= _sportsService.getDailyFixtures(
        sportId: _activeSport.id,
        date: _homeDate,
      );

  Future<void> _showHomeFixturePicker({required bool countries}) async {
    final sport = _activeSport;
    final date = _homeDate;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171221),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.65,
          child: StatefulBuilder(
            builder: (context, sheetSetState) => Column(
              children: [
                ListTile(
                  title: Text(
                    countries ? 'Countries' : 'Top European Leagues',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${sport.name} ? $date${countries ? '' : ' ? Ranked by matches'}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<FixtureModel>>(
                    future: _dailyHomeFixtures(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFFD700),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Could not load matches for this date.',
                                style: TextStyle(color: Colors.white70),
                              ),
                              TextButton(
                                onPressed: () => sheetSetState(
                                  () => _dayFixturesFuture = null,
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }
                      final fixtures = snapshot.data ?? const <FixtureModel>[];
                      final countryEntries = homeFixtureCountries(
                        fixtures,
                      ).entries.toList();
                      final leagues = homeTopEuropeanLeagues(
                        fixtures,
                        sport.id,
                      );
                      final count = countries
                          ? countryEntries.length
                          : leagues.length;
                      if (count == 0) {
                        return Center(
                          child: Text(
                            countries
                                ? 'No countries have matches on this date.'
                                : 'No European leagues have matches on this date.',
                            style: const TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: count,
                        itemBuilder: (context, index) {
                          final league = countries ? null : leagues[index];
                          final country = countries
                              ? countryEntries[index].key
                              : league!.country;
                          final matches = countries
                              ? countryEntries[index].value
                              : league!.matchCount;
                          return ListTile(
                            leading: Icon(
                              countries
                                  ? Icons.flag_rounded
                                  : Icons.emoji_events_rounded,
                              color: const Color(0xFFFFD700),
                            ),
                            title: Text(
                              countries ? country : league!.name,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: countries
                                ? null
                                : Text(
                                    country,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                  ),
                            trailing: Text(
                              '$matches ${matches == 1 ? 'match' : 'matches'}',
                              style: const TextStyle(color: Colors.white54),
                            ),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              setState(() {
                                _selectedCountry = country.isEmpty
                                    ? null
                                    : country;
                                _selectedLeague = league?.name;
                                _filterPillIndex = countries ? 2 : 1;
                                _leagueMarkets.clear();
                                _leagueLines.clear();
                              });
                              unawaited(_loadSportsData());
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectHomeFilter(int index) {
    if (index == 0) {
      unawaited(_selectHomeDate(DateTime.now()));
    } else {
      unawaited(_showHomeFixturePicker(countries: index == 2));
    }
  }

  Widget _buildHomeDateBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(
      children: [
        IconButton(
          key: const Key('home-previous-date'),
          tooltip: 'Previous date',
          onPressed: () => _selectHomeDate(
            DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day - 1,
            ),
          ),
          icon: const Icon(Icons.chevron_left, color: Colors.white70),
        ),
        Expanded(
          child: TextButton.icon(
            key: const Key('home-selected-date'),
            onPressed: _showHomeCalendar,
            icon: const Icon(
              Icons.calendar_month,
              size: 16,
              color: Color(0xFFFFD700),
            ),
            label: Text(
              _homeDate,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('home-next-date'),
          tooltip: 'Next date',
          onPressed: () => _selectHomeDate(
            DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day + 1,
            ),
          ),
          icon: const Icon(Icons.chevron_right, color: Colors.white70),
        ),
      ],
    ),
  );

  String _mapPredictionToMarketType(String pick) {
    final market = predictionHomeMarket(pick, _activeSportKey);
    return market == 'GG/NG' ? 'GG' : market ?? 'Prediction';
  }

  Map<String, dynamic> _fixtureBookmakers(FixtureModel fixture) => {
    for (final mapping in fixture.providerMappings)
      if (mapping.provider == 'sporty' || mapping.provider == '1xbet')
        mapping.provider: {
          'provider': mapping.provider,
          'available': mapping.sourceFixtureId.isNotEmpty,
          'event_id': mapping.sourceFixtureId,
          'league_id': mapping.sourceLeagueId,
        },
    ...?fixture.prediction?.bookmakers,
  };

  void _toggleFixtureOddsSelection(
    FixtureModel fx,
    String option,
    String oddStr, {
    String marketKey = '1X2',
    String sportyMarketId = '',
    String sportyOutcomeId = '',
    String sportySpecifier = '',
  }) {
    if (!isUpcomingBettingFixture(
      fx.matchTime.toIso8601String(),
      status: fx.status,
    )) {
      return;
    }
    final key = homeOddsSelectionKey(fx.id, marketKey, option);
    final prediction = fx.prediction;
    final predictionOption = prediction == null
        ? null
        : homePredictionOption(fx, prediction, _activeSportKey);
    final linked =
        predictionOption != null &&
        homeOddsSelectionKey(
              fx.id,
              predictionOption.marketKey,
              predictionOption.selection,
            ) ==
            key;
    final String? predKey = linked
        ? 'pred_${fx.id}_${prediction!.prediction}'
        : null;
    setState(() {
      if (_selectedOddsKeys.contains(key) ||
          _selectedTicketItems.containsKey(key)) {
        _selectedOddsKeys.remove(key);
        _selectedTicketItems.remove(key);
        _selectedOddsKeys.remove(predKey);
        _selectedTicketItems.remove(predKey);
      } else {
        final oddVal = double.tryParse(oddStr);
        if (oddVal == null || !oddVal.isFinite || oddVal <= 1) return;
        _selectedOddsKeys.add(key);
        _selectedTicketItems[key] = TicketSelectionModel(
          bookmakers: _fixtureBookmakers(fx),
          fixtureId: fx.id,
          sportId: fx.sportId,
          sportyEventId: fx.sportyEventId,
          sportyMarketId: sportyMarketId,
          sportyOutcomeId: sportyOutcomeId,
          sportySpecifier: sportySpecifier,
          predictionId: fx.prediction?.id ?? fx.id,
          homeTeam: fx.homeTeam,
          awayTeam: fx.awayTeam,
          leagueName: fx.leagueName,
          matchTime: fx.matchTime.toIso8601String(),
          marketType: marketKey,
          selection: option,
          odds: oddVal,
          confidence: fx.prediction?.probability ?? 0,
        );
      }
    });
  }

  void _toggleFixturePredictionSelection(
    FixtureModel fx,
    PredictionModel pred,
  ) {
    if (!isUpcomingBettingFixture(
      fx.matchTime.toIso8601String(),
      status: fx.status,
    )) {
      return;
    }
    final oddVal = double.tryParse(
      homePredictionOdds(fx, pred, _activeSportKey),
    );
    if (oddVal == null) return;
    final key = 'pred_${fx.id}_${pred.prediction}';
    final option = homePredictionOption(fx, pred, _activeSportKey);
    final oddKey = homeOddsSelectionKey(
      fx.id,
      option?.marketKey ?? _mapPredictionToMarketType(pred.prediction),
      option?.selection ?? pred.prediction,
    );
    setState(() {
      if (_selectedTicketItems.containsKey(key) ||
          _selectedTicketItems.containsKey(oddKey) ||
          _selectedOddsKeys.contains(key) ||
          _selectedOddsKeys.contains(oddKey)) {
        _selectedTicketItems.remove(key);
        _selectedTicketItems.remove(oddKey);
        _selectedOddsKeys.remove(key);
        _selectedOddsKeys.remove(oddKey);
      } else {
        _selectedOddsKeys.add(key);
        _selectedOddsKeys.add(oddKey);
        _selectedTicketItems[key] = TicketSelectionModel(
          bookmakers: _fixtureBookmakers(fx),
          fixtureId: fx.id,
          sportId: fx.sportId,
          sportyEventId: fx.sportyEventId,
          sportyMarketId: option?.sportyMarketId,
          sportyOutcomeId: option?.sportyOutcomeId,
          sportySpecifier: option?.sportySpecifier,
          predictionId: pred.id,
          homeTeam: fx.homeTeam,
          awayTeam: fx.awayTeam,
          leagueName: fx.leagueName,
          matchTime: fx.matchTime.toIso8601String(),
          marketType:
              option?.marketKey ?? _mapPredictionToMarketType(pred.prediction),
          selection: pred.prediction,
          odds: oddVal,
          confidence: pred.probability > 0 ? pred.probability : 0,
        );
      }
    });
  }

  void _toggleDetailOddSelection(
    FixtureModel fx,
    String marketKey,
    String selection,
    double odds,
  ) {
    if (!isUpcomingBettingFixture(
      fx.matchTime.toIso8601String(),
      status: fx.status,
    )) {
      return;
    }
    final key = _detailSelectionKey(fx, marketKey, selection);
    final predictionOption = fx.prediction == null
        ? null
        : homePredictionOption(fx, fx.prediction!, _activeSportKey);
    final linked =
        marketKey.toUpperCase() == 'PREDICTION' ||
        predictionOption != null &&
            homeOddsSelectionKey(
                  fx.id,
                  predictionOption.marketKey,
                  predictionOption.selection,
                ) ==
                key;
    final String? predKey = linked ? 'pred_${fx.id}_$selection' : null;
    setState(() {
      if (_selectedOddsKeys.contains(key) ||
          _selectedOddsKeys.contains(predKey) ||
          _selectedTicketItems.containsKey(key) ||
          _selectedTicketItems.containsKey(predKey)) {
        _selectedOddsKeys.remove(key);
        _selectedOddsKeys.remove(predKey);
        _selectedTicketItems.remove(key);
        _selectedTicketItems.remove(predKey);
      } else {
        if (!odds.isFinite || odds <= 1) return;
        _selectedOddsKeys.add(key);
        if (marketKey.toUpperCase() == 'PREDICTION' && predKey != null) {
          _selectedOddsKeys.add(predKey);
        }
        _selectedTicketItems[key] = TicketSelectionModel(
          bookmakers: _fixtureBookmakers(fx),
          fixtureId: fx.id,
          sportId: fx.sportId,
          sportyEventId: fx.sportyEventId,
          sportyMarketId: linked ? predictionOption?.sportyMarketId : null,
          sportyOutcomeId: linked ? predictionOption?.sportyOutcomeId : null,
          sportySpecifier: linked ? predictionOption?.sportySpecifier : null,
          predictionId: fx.prediction?.id,
          homeTeam: fx.homeTeam,
          awayTeam: fx.awayTeam,
          leagueName: fx.leagueName,
          matchTime: fx.matchTime.toIso8601String(),
          marketType: marketKey.toUpperCase() == 'PREDICTION'
              ? predictionOption?.marketKey ??
                    _mapPredictionToMarketType(selection)
              : marketKey,
          selection: selection,
          odds: odds,
          confidence: fx.prediction?.probability ?? 0,
        );
      }
    });
  }

  PredictionModel fxPrediction(FixtureModel fixture, String selection) =>
      fixture.prediction?.prediction == selection
      ? fixture.prediction!
      : PredictionModel(id: '', prediction: selection);

  String _detailSelectionKey(
    FixtureModel fixture,
    String marketKey,
    String selection,
  ) {
    if (marketKey.toUpperCase() == 'PREDICTION') {
      final prediction = fxPrediction(fixture, selection);
      final option = homePredictionOption(fixture, prediction, _activeSportKey);
      return homeOddsSelectionKey(
        fixture.id,
        option?.marketKey ?? _mapPredictionToMarketType(selection),
        option?.selection ?? selection,
      );
    }
    return homeOddsSelectionKey(fixture.id, marketKey, selection);
  }

  bool _isDetailOddSelected(
    FixtureModel fixture,
    String marketKey,
    String selection,
  ) {
    final key = _detailSelectionKey(fixture, marketKey, selection);
    return _selectedOddsKeys.contains(key) ||
        _selectedTicketItems.containsKey(key);
  }

  Widget _buildMarketProbabilityCarousel(FixtureModel fixture) {
    final items = homeMarketProbabilityCarousel(fixture, _activeSportKey);
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.insights_rounded, size: 10, color: Colors.white54),
            const SizedBox(width: 4),
            const Text(
              'OTHER MARKET PROBABILITIES',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 52,
          child: ListView.separated(
            key: ValueKey('home-market-probabilities-${fixture.id}'),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 5),
            itemBuilder: (context, index) {
              final item = items[index];
              final supported = item.supported;
              final option = item.option;
              final addable =
                  option != null &&
                  (double.tryParse(option.odd)?.compareTo(1) ?? 0) > 0;
              final selected =
                  addable &&
                  _isDetailOddSelected(
                    fixture,
                    option.marketKey,
                    option.selection,
                  );
              return GestureDetector(
                onTap: !addable
                    ? null
                    : () => _toggleFixtureOddsSelection(
                        fixture,
                        option.selection,
                        option.odd,
                        marketKey: option.marketKey,
                        sportyMarketId: option.sportyMarketId,
                        sportyOutcomeId: option.sportyOutcomeId,
                        sportySpecifier: option.sportySpecifier,
                      ),
                child: Container(
                  width: 94,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: supported
                        ? const Color(0xFFFFD700).withValues(alpha: 0.07)
                        : const Color(0xFF24212A),
                    borderRadius: BorderRadius.circular(8),
                    border: supported
                        ? Border.all(
                            color: const Color(
                              0xFFFFD700,
                            ).withValues(alpha: 0.28),
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.market,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: supported ? Colors.white70 : Colors.white38,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              supported ? item.selection : 'Unavailable',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: supported
                                    ? const Color(0xFFFFD700)
                                    : Colors.white30,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            supported ? '${item.probability}%' : '--',
                            style: TextStyle(
                              color: supported
                                  ? const Color(0xFF69F0AE)
                                  : Colors.white24,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (addable) ...[
                            const SizedBox(width: 3),
                            Icon(
                              selected ? Icons.check_circle : Icons.add_circle,
                              size: 11,
                              color: selected
                                  ? const Color(0xFF69F0AE)
                                  : const Color(0xFFFFD700),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _toggleLeagueSelection(String leagueName) {
    setState(() {
      if (_selectedLeagues.contains(leagueName)) {
        _selectedLeagues.remove(leagueName);
      } else {
        _selectedLeagues.add(leagueName);
      }
    });
  }

  void _openAuth(AuthMode mode) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AuthScreen(initialMode: mode)));
  }

  void _openProfile() {
    final user = SessionManager.instance.currentUser;
    if (user != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            user: user,
            onLogout: () {
              setState(() {});
            },
            onUserUpdated: (updated) {
              setState(() {});
            },
          ),
        ),
      );
    } else {
      _openAuth(AuthMode.signIn);
    }
  }

  void _openCoinShop() {
    final user = SessionManager.instance.currentUser;
    if (user != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CoinShopScreen(
            user: user,
            onUserUpdated: (updated) {
              setState(() {});
            },
          ),
        ),
      );
    } else {
      _openAuth(AuthMode.signIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0D0B12),
      drawer: LayoutBuilder(
        builder: (context, constraints) => _buildSidebarDrawer(constraints),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Column(
                  children: [
                    // 1. Top Header Bar
                    _buildTopHeader(constraints),

                    // 2. Top Nav Bar Tabs
                    _buildTopNavTabs(),

                    // Main Dynamic Tab Content
                    Expanded(child: _buildBodyContent(constraints)),
                    if ({0, 1, 4, 9}.contains(_topTabNavIndex))
                      AdSlot(
                        key: ValueKey('page-ad-$_topTabNavIndex'),
                        placement: {4, 9}.contains(_topTabNavIndex)
                            ? AdPlacement.prediction
                            : _topTabNavIndex == 1
                            ? AdPlacement.match
                            : AdPlacement.home,
                      ),
                  ],
                ),

                // Floating Action Button (Betslip or Selector Apply Bar)
                if (_topTabNavIndex == 2)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 76,
                    child: _buildSportsSelectorFloatingBar(),
                  )
                else
                  Positioned(
                    right: 16,
                    bottom: 84,
                    child: _buildFloatingBetslip(),
                  ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // --- SIDEBAR DRAWER MENU ---
  Widget _buildSidebarDrawer(BoxConstraints constraints) {
    final drawerWidth = (constraints.maxWidth * 0.84).clamp(280.0, 360.0);
    return Drawer(
      width: drawerWidth,
      backgroundColor: const Color(0xFF140F1D),
      child: SafeArea(
        child: Column(
          children: [
            const AdPrivacyButton(),
            // Drawer Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Menu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  // User Profile Status Card (When Logged In)
                  ListenableBuilder(
                    listenable: SessionManager.instance,
                    builder: (context, _) {
                      final user = SessionManager.instance.currentUser;
                      if (SessionManager.instance.isLoggedIn && user != null) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop();
                            _openProfile();
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF231B32),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(
                                  0xFFFFD700,
                                ).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Color(0xFFFFD700),
                                  child: Icon(
                                    Icons.person,
                                    color: Color(0xFF0D0B12),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.username,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        user.email,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Log Out',
                                  onPressed: () async {
                                    await SessionManager.instance.logout();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Logged out successfully.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.logout_rounded,
                                    color: Color(0xFFFF5252),
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                  // 1. Search Box
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _showFixtureSearch();
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E162B),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFF382954)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            color: Colors.white54,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Search by Team/League/Country/Games',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. Quick Action Grid (4 Icons)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDrawerQuickAction(
                        'Coin Shop',
                        Icons.monetization_on_rounded,
                        onTap: () {
                          Navigator.of(context).pop();
                          _openCoinShop();
                        },
                      ),
                      _buildDrawerQuickAction(
                        'My Profile',
                        Icons.person_rounded,
                        onTap: () {
                          Navigator.of(context).pop();
                          _openProfile();
                        },
                      ),
                      _buildDrawerQuickAction(
                        'Best Picks',
                        Icons.stars_rounded,
                        onTap: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _bottomNavIndex = 1;
                            _topTabNavIndex = 4;
                          });
                          _loadPopularPredictions(1);
                        },
                      ),
                      _buildDrawerQuickAction(
                        'Accumulators',
                        Icons.layers_rounded,
                        onTap: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _bottomNavIndex = 1;
                            _topTabNavIndex = 4;
                          });
                          _loadPopularPredictions(_accumulatorFilterIndex);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 3. Segmented Tab Switcher (Sport, Live, Countries)
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F172E),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        _buildDrawerSegmentTab('Sport', 0),
                        _buildDrawerSegmentTab('Live', 1),
                        _buildDrawerSegmentTab('Countries', 2),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 4. Dynamic Drawer Content (Sport / Live / Countries)
                  _buildDrawerContent(),

                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Drawer Footer Bar (Contact Us & Help)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF140F1D),
                border: Border(
                  top: BorderSide(color: Color(0xFF2C2042), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        ContactUsDialog.show(context);
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.headset_mic_rounded,
                            size: 18,
                            color: Colors.white70,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Contact Us',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: const Color(0xFF382954),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        HelpScreen.show(context);
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.help_outline_rounded,
                            size: 18,
                            color: Colors.white70,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Help',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerQuickAction(
    String label,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFFFD700), size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerSegmentTab(String label, int index) {
    final isSelected = index == _drawerSegmentIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _drawerSegmentIndex = index);
          if (index == 1) {
            _loadDrawerLive();
          } else if (index == 2) {
            _loadDrawerCountries();
          } else {
            // Sport tab: reset drawer sport selection
            setState(() {
              _drawerSelectedSportId = null;
              _drawerSportLeagues = [];
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3A2B56) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  // ---- Drawer dynamic content based on segment tab ----

  Widget _buildDrawerContent() {
    if (_drawerIsLoading) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1227),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF352752), width: 1),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFFFD700),
            ),
          ),
        ),
      );
    }

    switch (_drawerSegmentIndex) {
      case 1:
        return _buildDrawerLiveContent();
      case 2:
        return _buildDrawerCountriesContent();
      default:
        return _buildDrawerSportContent();
    }
  }

  Widget _buildDrawerSportContent() {
    final sports = _currentSports;
    if (sports.isEmpty) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1227),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF352752), width: 1),
        ),
        child: const Center(
          child: Text(
            'No sports available',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      );
    }

    if (_drawerSelectedSportId != null) {
      // Show leagues for selected sport
      final sport = sports.firstWhere(
        (s) => s.id == _drawerSelectedSportId,
        orElse: () => sports.first,
      );
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1227),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF352752), width: 1),
        ),
        child: Column(
          children: [
            // Back button
            InkWell(
              onTap: () => setState(() {
                _drawerSelectedSportId = null;
                _drawerSportLeagues = [];
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 14,
                      color: Color(0xFFFFD700),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      sport.name,
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_drawerSportLeagues.length} leagues',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(color: Color(0xFF2E2247), height: 1),
            if (_drawerSportLeagues.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No leagues found',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              )
            else
              ...(_drawerSportLeagues
                  .take(12)
                  .map((league) => _buildDrawerLeagueItem(league))),
            if (_drawerSportLeagues.length > 12)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '+${_drawerSportLeagues.length - 12} more leagues',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    // Show sport list
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1227),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF352752), width: 1),
      ),
      child: Column(
        children: [
          ...sports.map((sport) {
            final isSelected =
                _sportsTabNavIndex < _currentSports.length &&
                _currentSports[_sportsTabNavIndex].id == sport.id;
            final leagueCount = _apiLeagues
                .where((l) => l.sportId == sport.id)
                .length;
            final matchCount = sport.matchCount > 0
                ? sport.matchCount
                : leagueCount;
            return _buildDrawerApiSportItem(
              sport: sport,
              matchCount: matchCount,
              isActive: isSelected,
              onTap: () {
                final idx = _currentSports.indexWhere((s) => s.id == sport.id);
                if (idx != -1) {
                  _selectHomeSport(idx);
                }
                _loadDrawerSportLeagues(sport.id);
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDrawerLiveContent() {
    final liveFixtures = _drawerLiveFixtures.isNotEmpty
        ? _drawerLiveFixtures
        : _apiLiveFixtures;

    if (liveFixtures.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1227),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF352752), width: 1),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sports_score_rounded, color: Colors.white24, size: 28),
              SizedBox(height: 8),
              Text(
                'No live fixtures now',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Group by league
    final Map<String, List<FixtureModel>> byLeague = {};
    for (final f in liveFixtures) {
      byLeague
          .putIfAbsent(
            f.leagueName.isNotEmpty ? f.leagueName : 'Other',
            () => [],
          )
          .add(f);
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1227),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF352752), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              setState(() => _topTabNavIndex = 1);
              _loadLiveSportsData();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF3D3D),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${liveFixtures.length} LIVE',
                    style: const TextStyle(
                      color: Color(0xFFFF3D3D),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFF2E2247), height: 1),
          ...byLeague.entries.take(8).map((entry) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() => _topTabNavIndex = 1);
                    _loadLiveSportsData();
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_rounded,
                          size: 13,
                          color: Color(0xFFFFD700),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${entry.value.length}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ...entry.value
                    .take(3)
                    .map(
                      (f) => InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          setState(() => _topTabNavIndex = 1);
                          _loadLiveSportsData();
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(32, 4, 16, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${f.homeTeam} vs ${f.awayTeam}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFF3D3D,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${f.homeScore}-${f.awayScore}',
                                  style: const TextStyle(
                                    color: Color(0xFFFF5555),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                if (entry.value.length > 3)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 16, 4),
                    child: Text(
                      '+${entry.value.length - 3} more',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ),
                const Divider(color: Color(0xFF2E2247), height: 1),
              ],
            );
          }),
          if (byLeague.length > 8)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '+${byLeague.length - 8} more leagues',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawerCountriesContent() {
    final leagues = _drawerAllLeagues.isNotEmpty
        ? _drawerAllLeagues
        : (_apiLeagues.isNotEmpty ? _apiLeagues : _drawerSportLeagues);
    final countriesMap = <String, int>{};
    for (final l in leagues) {
      final c = l.country.trim();
      if (c.isNotEmpty) {
        countriesMap[c] =
            (countriesMap[c] ?? 0) + (l.matchCount > 0 ? l.matchCount : 1);
      }
    }
    final entries = countriesMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1227),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF352752), width: 1),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.flag_rounded, color: Colors.white24, size: 28),
              SizedBox(height: 8),
              Text(
                'No countries found',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1227),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF352752), width: 1),
      ),
      child: Column(
        children: [
          ...entries.take(15).map((entry) {
            return InkWell(
              onTap: () {
                Navigator.of(context).pop();
                setState(() {
                  _topTabNavIndex = 0;
                  _selectedCountry = entry.key;
                  _selectedLeague = null;
                });
                _loadSportsData(country: entry.key);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.flag_rounded,
                      size: 14,
                      color: Color(0xFF8B6CC2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '${entry.value}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Colors.white38,
                    ),
                  ],
                ),
              ),
            );
          }),
          if (entries.length > 15)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '+${entries.length - 15} more countries',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawerApiSportItem({
    required SportModel sport,
    required int matchCount,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (isActive)
              Container(
                width: 3,
                height: 14,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            else
              const SizedBox(width: 11),
            Expanded(
              child: Text(
                sport.name,
                style: TextStyle(
                  color: isActive ? const Color(0xFFFFD700) : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            if (matchCount > 0)
              Text(
                '$matchCount',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerLeagueItem(LeagueModel league) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        setState(() {
          _topTabNavIndex = 0;
          _selectedLeague = league.name;
          _selectedCountry = null;
        });
        _loadSportsData(sportId: league.sportId, league: league.name);
      },
      child: Padding(
        padding: const EdgeInsets.only(
          left: 28,
          right: 16,
          top: 10,
          bottom: 10,
        ),
        child: Row(
          children: [
            const Icon(Icons.sports_outlined, size: 13, color: Colors.white38),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                league.name,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (league.matchCount > 0)
              Text(
                '${league.matchCount}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }

  // --- DYNAMIC BODY CONTENT ---
  Widget _buildBodyContent(BoxConstraints constraints) {
    switch (_topTabNavIndex) {
      case 1:
        return _buildLiveSportsScreen(constraints);
      case 2:
        return _buildSportsSelectorScreen(constraints);
      case 3:
        return _buildGamesScreen(constraints);
      case 4:
        return _buildPredictionsScreen(constraints);
      case 5:
        return _buildFeedsScreen(constraints);
      case 6:
        return LiveTvScreen(service: _sportsService);
      case 7:
        return SlipAgentScreen(baseUrl: _sportsService.baseUrl);
      case 8:
        return _buildCodeConvertScreen(constraints);
      case 9:
        return _buildPopularPredictionsScreen(constraints);
      default:
        return _buildHomeSportsbookScreen(constraints);
    }
  }

  // --- 1. TOP HEADER BAR ---
  Widget _buildTopHeader(BoxConstraints constraints) {
    final isVerySmall = constraints.maxWidth < 360;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isVerySmall ? 10 : 16,
        vertical: 10,
      ),
      color: const Color(0xFF140F1D),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF231B32),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF3B2E54)),
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                size: 16,
                color: Color(0xFFFFD700),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const BrandLogo(size: 34),
          if (!isVerySmall) ...[
            const SizedBox(width: 6),
            const Flexible(
              child: Text(
                'ZENTRY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _showFixtureSearch,
            icon: const Icon(Icons.search, color: Colors.white70, size: 22),
          ),
          const SizedBox(width: 8),
          if (SessionManager.instance.isLoggedIn) ...[
            Badge(
              isLabelVisible: _unreadNotificationCount > 0,
              label: Text(
                _unreadNotificationCount > 9
                    ? '9+'
                    : '$_unreadNotificationCount',
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _showNotifications,
                tooltip: 'Notifications',
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: Colors.white70,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          ListenableBuilder(
            listenable: SessionManager.instance,
            builder: (context, _) {
              final user = SessionManager.instance.currentUser;
              if (SessionManager.instance.isLoggedIn && user != null) {
                return GestureDetector(
                  onTap: _openProfile,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF261D36),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFFFD700),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 10,
                          backgroundColor: Color(0xFFFFD700),
                          child: Icon(
                            Icons.person,
                            size: 13,
                            color: Color(0xFF0D0B12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          user.username,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Row(
                children: [
                  InkWell(
                    onTap: () => _openAuth(AuthMode.register),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isVerySmall ? 10 : 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Join',
                        style: TextStyle(
                          color: Color(0xFF0D0B12),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _openAuth(AuthMode.signIn),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isVerySmall ? 10 : 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF261D36),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF453563)),
                      ),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms);
  }

  // --- 2. TOP NAV TABS ---
  Widget _buildTopNavTabs() {
    return Container(
      height: 44,
      color: const Color(0xFF140F1D),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _topTabs.length,
        itemBuilder: (context, index) {
          final isSelected = index == _topTabNavIndex;
          final tabName = _topTabs[index];
          return GestureDetector(
            onTap: () {
              setState(() => _topTabNavIndex = index);
              if (index == 1) {
                _loadLiveSportsData();
              } else if (index == 4 || index == 9) {
                _loadPopularPredictions(_popularFilterIndex);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected
                        ? const Color(0xFFFFD700)
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (tabName == 'Game Center' || tabName == 'GAMES') ...[
                    Container(
                      padding: const EdgeInsets.all(4),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FF87),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.sports_soccer_rounded,
                        size: 14,
                        color: Color(0xFF38003C),
                      ),
                    ),
                  ],
                  if (tabName == 'Popular') ...[
                    Container(
                      padding: const EdgeInsets.all(3),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF5252), Color(0xFFFF7A00)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.local_fire_department_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  Text(
                    tabName,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFFFFD700)
                          : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.w900
                          : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // VIEW 1: HOME SPORTSBOOK SCREEN (Tab 0)
  Widget _buildHomeSportsbookScreen(BoxConstraints constraints) {
    return RefreshIndicator(
      onRefresh: _loadSportsData,
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1E142B),
      child: ListView(
        controller: _homeScrollController,
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          if (_isLoadingSportsData)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(
                color: Color(0xFFFFD700),
                backgroundColor: Color(0xFF231B32),
              ),
            )
          else if (_sportsDataError != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF33161C),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8C1D2F)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFFFF8A80),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Unable to refresh fixtures. Pull down to retry.',
                      style: TextStyle(
                        color: Colors.red.shade100,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _buildPromoBanner(constraints),
          const SizedBox(height: 16),
          _buildQuickCategoryIcons(),
          const SizedBox(height: 16),
          _buildSportsFilterBar(),
          _buildHomeDateBar(),
          if (_selectedLeague != null || _selectedCountry != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2042),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _selectedLeague != null
                                ? Icons.emoji_events_rounded
                                : Icons.flag_rounded,
                            size: 14,
                            color: const Color(0xFFFFD700),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _selectedLeague != null
                                  ? 'League: $_selectedLeague'
                                  : 'Country: $_selectedCountry',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedLeague = null;
                                _selectedCountry = null;
                              });
                              _loadSportsData();
                              _loadPopularPredictions(0);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _buildMatchList(constraints),
          if (_isLoadingMoreFixtures)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFFD700),
                  strokeWidth: 2.5,
                ),
              ),
            )
          else if (_hasMoreFixtures && !_isLoadingSportsData)
            TextButton(
              onPressed: _loadMoreFixtures,
              child: const Text(
                'Load more matches',
                style: TextStyle(color: Color(0xFFFFD700)),
              ),
            ),
        ],
      ),
    );
  }

  // VIEW 2: LIVE SPORTS SCREEN (Tab 1)
  Widget _buildLiveSportsScreen(BoxConstraints constraints) {
    return RefreshIndicator(
      onRefresh: _loadSportsData,
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1E142B),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          if (_isLoadingSportsData)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(
                color: Color(0xFFFFD700),
                backgroundColor: Color(0xFF231B32),
              ),
            ),
          const SizedBox(height: 12),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 130,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF1F0D42), Color(0xFF4A1078)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'FREE LUCKY DRAW',
                          style: TextStyle(
                            color: Color(0xFF0D0B12),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'WIN IPHONE 17',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'LIVE MATCHES & BOOSTED ODDS',
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 10,
                  top: 10,
                  child:
                      const Icon(
                            Icons.phone_iphone_rounded,
                            size: 80,
                            color: Color(0xFFFFD700),
                          )
                          .animate()
                          .scale(
                            begin: const Offset(0.95, 0.95),
                            end: const Offset(1.05, 1.05),
                            duration: 2.seconds,
                          )
                          .shimmer(
                            delay: 1.seconds,
                            duration: 2.seconds,
                            color: const Color(0xFFFFEA79),
                          ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),

          const SizedBox(height: 16),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: List.generate(_currentSports.length, (index) {
                final item = _currentSports[index];
                final isSelected = index == _sportsTabNavIndex;
                final liveCount = _apiLiveFixtures
                    .where((f) => f.sportId == item.id)
                    .length;
                return GestureDetector(
                  onTap: () {
                    _selectHomeSport(index);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF2C1E45)
                          : const Color(0xFF171221),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF2F2445),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getSportIcon(item.name),
                          color: isSelected
                              ? const Color(0xFFFFD700)
                              : Colors.white70,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.name,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFFFD700)
                                : Colors.white70,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        if (liveCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFFFD700)
                                  : const Color(0xFFFF3D3D),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$liveCount',
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF0D0B12)
                                    : Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 14),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: List.generate(_marketOptions.length, (index) {
                final market = _marketOptions[index];
                final isSelected = market == _selectedMarket;
                return GestureDetector(
                  onTap: () => _selectHomeMarket(market),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF231B32),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF3E2F59),
                      ),
                    ),
                    child: Text(
                      market,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF0D0B12)
                            : Colors.white70,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Live Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF231B32),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF392B54)),
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Expand All',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.aspect_ratio_rounded,
                        size: 13,
                        color: Color(0xFFFFD700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          _buildLiveMatchCards(constraints),
        ],
      ),
    );
  }

  Widget _buildLiveMatchCards(BoxConstraints constraints) {
    if (_isLoadingSportsData && _apiLiveFixtures.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700)),
        ),
      );
    }

    final selectedSportId =
        _currentSports.isNotEmpty && _sportsTabNavIndex < _currentSports.length
        ? _currentSports[_sportsTabNavIndex].id
        : 1;
    final currentSportName =
        _currentSports.isNotEmpty && _sportsTabNavIndex < _currentSports.length
        ? _currentSports[_sportsTabNavIndex].name
        : 'this sport';
    final visibleLiveFixtures = _apiLiveFixtures
        .where((fixture) => fixture.sportId == selectedSportId)
        .toList();

    if (visibleLiveFixtures.isEmpty) {
      final otherSportsWithLive = _currentSports.where((s) {
        return s.id != selectedSportId &&
            _apiLiveFixtures.any((f) => f.sportId == s.id);
      }).toList();

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFF171221),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2F2445)),
        ),
        child: Column(
          children: [
            Icon(
              _liveDataError == null
                  ? Icons.podcasts_rounded
                  : Icons.cloud_off_rounded,
              size: 40,
              color: Colors.white38,
            ),
            const SizedBox(height: 10),
            Text(
              _liveDataError == null
                  ? (_apiLiveFixtures.isNotEmpty
                        ? 'No Live $currentSportName Matches Right Now'
                        : 'No Live Matches Currently')
                  : 'Could Not Load Live Matches',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _liveDataError == null
                  ? (_apiLiveFixtures.isNotEmpty
                        ? 'Matches are currently live in other sports:'
                        : 'Live scores will update automatically when games start.')
                  : 'Check your connection and pull down to retry.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            if (otherSportsWithLive.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: otherSportsWithLive.map((sport) {
                  final count = _apiLiveFixtures
                      .where((f) => f.sportId == sport.id)
                      .length;
                  return ActionChip(
                    backgroundColor: const Color(0xFF2C1E45),
                    side: const BorderSide(color: Color(0xFFFFD700), width: 1),
                    avatar: Icon(
                      _getSportIcon(sport.name),
                      size: 15,
                      color: const Color(0xFFFFD700),
                    ),
                    label: Text(
                      '${sport.name} ($count)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () {
                      final idx = _currentSports.indexWhere(
                        (s) => s.id == sport.id,
                      );
                      if (idx != -1) {
                        _selectHomeSport(idx);
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      );
    }

    final liveMatches = visibleLiveFixtures.map((fx) {
      return (
        league: fx.leagueName.isNotEmpty
            ? fx.leagueName
            : '${fx.country} League',
        time: 'LIVE',
        home: fx.homeTeam,
        away: fx.awayTeam,
        homeScore: fx.homeScore.toString(),
        awayScore: fx.awayScore.toString(),
        odds: fx.displayOdds,
      );
    }).toList();

    final oddsColumnWidth = (constraints.maxWidth * 0.45).clamp(130.0, 170.0);
    final oddsButtonWidth = ((oddsColumnWidth - 12) / 3).clamp(38.0, 52.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: List.generate(liveMatches.length, (index) {
          final m = liveMatches[index];
          final fx = index < visibleLiveFixtures.length
              ? visibleLiveFixtures[index]
              : null;
          final matchingStream = fx != null ? _findMatchingStream(fx) : null;
          return InkWell(
            onTap: () {
              if (fx != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MatchDetailScreen(
                      fixtureId: fx.id,
                      initialFixture: fx,
                      onToggleOdd: (id, mkt, sel, val) =>
                          _toggleDetailOddSelection(fx, mkt, sel, val),
                      isOddSelected: (id, mkt, sel) =>
                          _isDetailOddSelected(fx, mkt, sel),
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF171221),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2F2445), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.public_rounded,
                        size: 14,
                        color: Color(0xFFFFD700),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          m.league,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (matchingStream != null &&
                          matchingStream.hasStreams) ...[
                        GestureDetector(
                          onTap: () {
                            LiveStreamSheet.show(
                              context,
                              streamEvent: matchingStream,
                              matchTitle: '${m.home} vs ${m.away}',
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.35,
                                  ),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.live_tv_rounded,
                                  color: Colors.white,
                                  size: 11,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'WATCH LIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Icon(
                        Icons.star_border_rounded,
                        size: 18,
                        color: Colors.white38,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.time,
                              style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m.home,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  m.homeScore,
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m.away,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  m.awayScore,
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: oddsColumnWidth,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(3, (i) {
                            final isLocked = m.odds[i].trim().isEmpty;
                            final labels = ['1', 'X', '2'];
                            final label = labels[i];
                            final key = fx != null ? '${fx.id}-$label' : '';
                            final isSelected =
                                key.isNotEmpty &&
                                (_selectedOddsKeys.contains(key) ||
                                    _selectedTicketItems.containsKey(key));
                            return GestureDetector(
                              onTap: (!isLocked && fx != null)
                                  ? () => _toggleFixtureOddsSelection(
                                      fx,
                                      label,
                                      m.odds[i],
                                    )
                                  : null,
                              child: Container(
                                width: oddsButtonWidth,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFFFD700)
                                      : const Color(0xFF231B32),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFFFFD700)
                                        : const Color(0xFF392A54),
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: isLocked
                                    ? const Icon(
                                        Icons.lock_rounded,
                                        size: 16,
                                        color: Colors.white38,
                                      )
                                    : Text(
                                        m.odds[i],
                                        style: TextStyle(
                                          color: isSelected
                                              ? const Color(0xFF0D0B12)
                                              : const Color(0xFFFFD700),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: (index * 80).ms);
        }),
      ),
    );
  }

  IconData _getSportIcon(String sportName) {
    final name = sportName.toLowerCase();
    if (name.contains('soccer') || name.contains('football')) {
      return Icons.sports_soccer_rounded;
    } else if (name.contains('basketball')) {
      return Icons.sports_basketball_rounded;
    } else if (name.contains('tennis')) {
      return Icons.sports_tennis_rounded;
    } else if (name.contains('baseball')) {
      return Icons.sports_baseball_rounded;
    } else if (name.contains('hockey')) {
      return Icons.sports_hockey_rounded;
    } else if (name.contains('handball')) {
      return Icons.sports_handball_rounded;
    } else if (name.contains('cricket')) {
      return Icons.sports_cricket_rounded;
    }
    return Icons.sports_rounded;
  }

  // VIEW 3: SPORTS SELECTOR SCREEN (Tab 2)
  Widget _buildSportsSelectorScreen(BoxConstraints constraints) {
    final sportsList = _currentSports;

    final leaguesList = List<LeagueModel>.from(_apiLeagues);
    leaguesList.sort((a, b) {
      if (a.matchCount != b.matchCount) {
        return b.matchCount.compareTo(a.matchCount);
      }
      return a.name.compareTo(b.name);
    });
    final leagues = leaguesList
        .map(
          (l) => ($1: '${l.name} (${l.country})', $2: l.matchCount.toString()),
        )
        .toList();

    return RefreshIndicator(
      onRefresh: _loadSportsData,
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1E142B),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          if (_isLoadingSportsData)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(
                color: Color(0xFFFFD700),
                backgroundColor: Color(0xFF231B32),
              ),
            ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: List.generate(sportsList.length, (index) {
                final item = sportsList[index];
                final isSelected = index == _sportsTabNavIndex;
                final iconData = _getSportIcon(item.name);
                return GestureDetector(
                  onTap: () {
                    _selectHomeSport(index);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(10),
                    width: 72,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF2C1E45)
                          : const Color(0xFF171221),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF2F2445),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          iconData,
                          color: isSelected
                              ? const Color(0xFFFFD700)
                              : Colors.white54,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFFFD700)
                                : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 16),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildCountFilterBadge(
                  'Live',
                  '39',
                  Icons.videocam_rounded,
                  Colors.redAccent,
                ),
                const SizedBox(width: 10),
                _buildCountFilterBadge(
                  'Today',
                  '129',
                  Icons.calendar_today_rounded,
                  const Color(0xFF42A5F5),
                ),
                const SizedBox(width: 10),
                _buildCountFilterBadge(
                  'Best Odds',
                  '187',
                  Icons.emoji_events_rounded,
                  const Color(0xFFFFD700),
                ),
                const SizedBox(width: 10),
                _buildCountFilterBadge(
                  'AI Best Odds',
                  '🔥',
                  Icons.smart_toy_rounded,
                  const Color(0xFF66BB6A),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Selector',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                _buildSmallDropdownPill('Start Time ∨'),
                const SizedBox(width: 8),
                _buildSmallDropdownPill('Odds Range ∨'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF140F1D),
            child: Row(
              children: [
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: Colors.white70,
                  size: 22,
                ),
                const Text(
                  'Top Leagues 🏆',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '${leagues.length}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          if (leagues.isEmpty && !_isLoadingSportsData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No leagues found for this sport',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),

          ...List.generate(leagues.length, (index) {
            final l = leagues[index];
            final isChecked = _selectedLeagues.contains(l.$1);
            return GestureDetector(
              onTap: () => _toggleLeagueSelection(l.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF1E172B), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.star_border_rounded,
                      color: Colors.white38,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.$1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      l.$2,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isChecked
                              ? const Color(0xFFFFD700)
                              : Colors.white38,
                          width: 1.5,
                        ),
                        color: isChecked
                            ? const Color(0xFFFFD700)
                            : Colors.transparent,
                      ),
                      child: isChecked
                          ? const Icon(
                              Icons.check,
                              size: 13,
                              color: Color(0xFF0D0B12),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCountFilterBadge(
    String label,
    String count,
    IconData icon,
    Color iconColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF352752)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              count,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallDropdownPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF231B32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF392B54)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }

  Widget _buildSportsSelectorFloatingBar() {
    final count = _selectedLeagues.length;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedLeagues.clear()),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF1D162B),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0xFFFFD700), width: 1.2),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Clear',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Applied $count league filter(s)'),
                  backgroundColor: const Color(0xFFFFD700),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              setState(() => _topTabNavIndex = 0);
            },
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700),
                borderRadius: BorderRadius.circular(99),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                'Apply ($count)',
                style: const TextStyle(
                  color: Color(0xFF0D0B12),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ],
    ).animate().scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1));
  }

  // VIEW 4: FPL DUEL ARENA & GAME CENTER (Tab 3)
  Widget _buildGamesScreen(BoxConstraints constraints) {
    return GameCenter(onFanDuel: _openFanDuel, onFixtureDuel: _openFixtureDuel);
  }

  void _openFixtureDuel({int initialTab = 0}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FixtureDuelView(onOpenWallet: _openFanDuel, initialTab: initialTab),
      ),
    );
  }

  void _openFanDuel() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFF0D0B12),
          appBar: AppBar(
            title: const Text('Fan Duel Arena'),
            backgroundColor: const Color(0xFF171221),
            foregroundColor: Colors.white,
          ),
          body: const FplDuelView(),
        ),
      ),
    );
  }

  Future<void> _loadHomeBanner() async {
    if (!SessionManager.instance.isLoggedIn) {
      _lastBannerRefresh = null;
      if (mounted &&
          (_bannerFixtureCampaign != null ||
              _bannerFplCampaign != null ||
              _bannerFeaturedFixture != null)) {
        setState(() {
          _bannerFixtureCampaign = null;
          _bannerFplCampaign = null;
          _bannerFeaturedFixture = null;
        });
      }
      return;
    }
    final requestedAt = DateTime.now();
    if (_lastBannerRefresh != null &&
        requestedAt.difference(_lastBannerRefresh!) <
            const Duration(minutes: 1)) {
      return;
    }
    _lastBannerRefresh = requestedAt;

    Future<List<FixtureDuelModel>> fixtureCampaigns() async {
      try {
        return await _fixtureDuelService.lobby();
      } catch (_) {
        return const <FixtureDuelModel>[];
      }
    }

    Future<List<FplDuelChallengeModel>> fplCampaigns() async {
      try {
        return await _fplDuelService.getLobbyChallenges();
      } catch (_) {
        return const <FplDuelChallengeModel>[];
      }
    }

    Future<List<FixtureModel>> topFixtures() async {
      try {
        return await _fixtureDuelService.eligibleFixtures();
      } catch (_) {
        return const <FixtureModel>[];
      }
    }

    final results = await Future.wait<dynamic>([
      fixtureCampaigns(),
      fplCampaigns(),
      topFixtures(),
    ]);
    if (!mounted) return;

    final now = DateTime.now();
    final fixtureDuels = (results[0] as List<FixtureDuelModel>)
        .where(
          (duel) => duel.status == 'OPEN' && duel.acceptCutoff.isAfter(now),
        )
        .toList();
    final fplDuels = (results[1] as List<FplDuelChallengeModel>)
        .where((duel) => duel.isOpen && duel.acceptCutoff.isAfter(now))
        .toList();
    final fixtures =
        (results[2] as List<FixtureModel>)
            .where(
              (fixture) =>
                  fixture.isPrematch &&
                  fixture.matchTime.isAfter(now) &&
                  _isTopFiveEuropeanFixture(fixture),
            )
            .toList()
          ..sort((a, b) => a.matchTime.compareTo(b.matchTime));

    setState(() {
      _bannerFixtureCampaign = fixtureDuels.isEmpty ? null : fixtureDuels.first;
      _bannerFplCampaign = fplDuels.isEmpty ? null : fplDuels.first;
      _bannerFeaturedFixture = fixtures.isEmpty ? null : fixtures.first;
    });
  }

  bool _isTopFiveEuropeanFixture(FixtureModel fixture) {
    final league = fixture.leagueName
        .toLowerCase()
        .replaceAll(RegExp(r'[-_.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final country = fixture.country.toLowerCase().trim();
    return ((league == 'premier league' ||
                league == 'english premier league' ||
                league == 'epl') &&
            (country.isEmpty || country == 'england')) ||
        ((league == 'la liga' ||
                league == 'laliga' ||
                league == 'primera division' ||
                league == 'spanish la liga') &&
            (country.isEmpty || country == 'spain')) ||
        (league == 'bundesliga' && (country.isEmpty || country == 'germany')) ||
        ((league == 'serie a' || league == 'italian serie a') &&
            (country.isEmpty || country == 'italy')) ||
        ((league == 'ligue 1' || league == 'french ligue 1') &&
            (country.isEmpty || country == 'france'));
  }

  String _bannerMoney(int kobo) {
    final amount = kobo / 100;
    return '\u20A6${amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2)}';
  }

  String _bannerKickoff(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month} $hour:$minute';
  }

  // --- PROMO BANNER ---
  Widget _buildPromoBanner(BoxConstraints constraints) {
    final isCompact = constraints.maxWidth < 380;
    final fixtureCampaign = _bannerFixtureCampaign;
    final fplCampaign = _bannerFplCampaign;
    final featuredFixture = _bannerFeaturedFixture;

    late final String badge;
    late final String title;
    late final String subtitle;
    late final IconData icon;
    late final VoidCallback onTap;

    if (fixtureCampaign != null) {
      badge = 'OPEN FIXTURE DUEL';
      title =
          '${fixtureCampaign.creatorTeam} vs ${fixtureCampaign.opponentTeam}';
      subtitle =
          '${_bannerMoney(fixtureCampaign.stake)} each • Join before ${_bannerKickoff(fixtureCampaign.acceptCutoff)}';
      icon = Icons.sports_soccer_rounded;
      onTap = () => _openFixtureDuel(initialTab: 1);
    } else if (fplCampaign != null) {
      badge = 'OPEN FANTASY DUEL';
      title = '${fplCampaign.creatorTeamName} • ${fplCampaign.modeLabel}';
      subtitle =
          'GW${fplCampaign.gameweek} • ${_bannerMoney(fplCampaign.stake)} stake • Join now';
      icon = Icons.sports_esports_rounded;
      onTap = _openFanDuel;
    } else if (featuredFixture != null) {
      badge = 'TOP EUROPEAN FIXTURE';
      title = '${featuredFixture.homeTeam} vs ${featuredFixture.awayTeam}';
      subtitle =
          '${featuredFixture.leagueName} • ${_bannerKickoff(featuredFixture.matchTime)}';
      icon = Icons.emoji_events_rounded;
      onTap = () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MatchDetailScreen(
              fixtureId: featuredFixture.id,
              initialFixture: featuredFixture,
              onToggleOdd: (id, market, selection, value) =>
                  _toggleDetailOddSelection(
                    featuredFixture,
                    market,
                    selection,
                    value,
                  ),
              isOddSelected: (id, market, selection) =>
                  _isDetailOddSelected(featuredFixture, market, selection),
            ),
          ),
        );
      };
    } else {
      badge = 'GAME CENTER';
      title = 'PLAY. COMPETE. WIN.';
      subtitle = 'Create or join a head-to-head campaign';
      icon = Icons.sports_esports_rounded;
      onTap = () => setState(() => _topTabNavIndex = 3);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: isCompact ? 148 : 152,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF4A1078), Color(0xFF1F0735)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A1078).withValues(alpha: 0.4),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 12, isCompact ? 86 : 108, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Color(0xFF0D0B12),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isCompact ? 17 : 20,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: const Color(0xFFFFD700),
                      fontSize: isCompact ? 14 : 16,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              top: 8,
              child:
                  Icon(
                        icon,
                        size: isCompact ? 76 : 92,
                        color: const Color(0xFFFFD700),
                      )
                      .animate()
                      .scale(
                        begin: const Offset(0.95, 0.95),
                        end: const Offset(1.05, 1.05),
                        duration: 2.seconds,
                      )
                      .shimmer(
                        delay: 1.seconds,
                        duration: 2.seconds,
                        color: const Color(0xFFFFEA79),
                      ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.08, end: 0);
  }

  // --- QUICK CATEGORY ICONS ---
  Widget _buildQuickCategoryIcons() {
    final categories = [
      ('Chat', Icons.chat_bubble_rounded),
      ('Calendar', Icons.calendar_month_rounded),
      ('ZAI', Icons.psychology_alt_rounded),
      ('BetMachine', Icons.auto_awesome_rounded),
      ('Value Odds', Icons.query_stats_rounded),
      ('Advance Stat', Icons.analytics_rounded),
      ('Bookings', Icons.confirmation_number_rounded),
      ('Game Center', Icons.sports_esports_rounded),
      ('ALL', Icons.grid_view_rounded),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(categories.length, (index) {
          final item = categories[index];
          return InkWell(
            key: ValueKey('home-category-${item.$1}'),
            onTap: () {
              if (item.$1 == 'Chat') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatScreen(
                      fixtures: [..._apiLiveFixtures, ..._apiPrematchFixtures],
                      predictions: _homePredictions,
                      onCreateChallenge: _openFanDuel,
                    ),
                  ),
                );
              } else if (item.$1 == 'Calendar') {
                unawaited(_showHomeCalendar());
              } else if (item.$1 == 'ZAI') {
                setState(() => _topTabNavIndex = 4);
                _loadPopularPredictions(_ratingBetFilterIndex);
              } else if (item.$1 == 'BetMachine') {
                BetMachineSheet.show(
                  context,
                  onAddToBetslip: (selections) {
                    setState(() {
                      for (final sel in selections) {
                        final key = sel.uniqueKey;
                        _selectedOddsKeys.add(key);
                        _selectedTicketItems[key] = sel;
                      }
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${selections.length} BetMachine picks added to Betslip!',
                        ),
                        backgroundColor: const Color(0xFF00FF87),
                      ),
                    );
                  },
                );
              } else if (item.$1 == 'Value Odds') {
                ValueOddsSheet.show(
                  context,
                  onAddToBetslip: (selection) {
                    setState(() {
                      final key = selection.uniqueKey;
                      _selectedOddsKeys.add(key);
                      _selectedTicketItems[key] = selection;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Value Odds pick added to Betslip!'),
                        backgroundColor: Color(0xFF00FF87),
                      ),
                    );
                  },
                );
              } else if (item.$1 == 'Advance Stat') {
                AdvancedStatsSheet.show(context);
              } else if (item.$1 == 'Bookings') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        BookingsScreen(sportsService: _sportsService),
                  ),
                );
              } else if (item.$1 == 'Game Center') {
                setState(() => _topTabNavIndex = 3);
              } else {
                setState(() {
                  _selectedLeague = null;
                  _selectedCountry = null;
                  _selectedMarket = 'All Markets';
                  _leagueMarkets.clear();
                  _leagueLines.clear();
                });
                _loadSportsData();
                _loadPopularPredictions(0);
                _showAllCategoriesSheet();
              }
            },
            child:
                Container(
                      margin: EdgeInsets.only(
                        right: index == categories.length - 1 ? 0 : 16,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E172B),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF3D2F57),
                              ),
                            ),
                            child: Icon(
                              item.$2,
                              color: const Color(0xFFFFD700),
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.$1,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 400.ms, delay: (60 * index).ms)
                    .scale(
                      begin: const Offset(0.9, 0.9),
                      end: const Offset(1, 1),
                    ),
          );
        }),
      ),
    );
  }

  void _showAllCategoriesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF171124),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All Features & Fixtures',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Access available tools and navigation',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Betting Tools & Navigation',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.1,
                children: [
                  _buildAllSheetTile(
                    ctx,
                    title: 'BetMachine',
                    subtitle: 'AI Slips',
                    icon: Icons.auto_awesome_rounded,
                    color: const Color(0xFFFFD700),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      BetMachineSheet.show(
                        context,
                        onAddToBetslip: (selections) {
                          setState(() {
                            for (final sel in selections) {
                              final key = sel.uniqueKey;
                              _selectedOddsKeys.add(key);
                              _selectedTicketItems[key] = sel;
                            }
                          });
                        },
                      );
                    },
                  ),
                  _buildAllSheetTile(
                    ctx,
                    title: 'Value Odds',
                    subtitle: '+EV Radar',
                    icon: Icons.query_stats_rounded,
                    color: const Color(0xFFFF3366),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      AdvancedStatsSheet.show(context);
                    },
                  ),
                  _buildAllSheetTile(
                    ctx,
                    title: 'Advance Stat',
                    subtitle: 'Analytics',
                    icon: Icons.analytics_rounded,
                    color: const Color(0xFF00FF87),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ValueOddsSheet.show(
                        context,
                        onAddToBetslip: (selection) {
                          setState(() {
                            final key = selection.uniqueKey;
                            _selectedOddsKeys.add(key);
                            _selectedTicketItems[key] = selection;
                          });
                        },
                      );
                    },
                  ),
                  _buildAllSheetTile(
                    ctx,
                    title: 'Bookings',
                    subtitle: 'My codes',
                    icon: Icons.confirmation_number_rounded,
                    color: const Color(0xFF00C6FF),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              BookingsScreen(sportsService: _sportsService),
                        ),
                      );
                    },
                  ),
                  _buildAllSheetTile(
                    ctx,
                    title: 'Game Center',
                    subtitle: 'FPL Duels',
                    icon: Icons.sports_esports_rounded,
                    color: const Color(0xFFA855F7),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      setState(() => _topTabNavIndex = 3);
                    },
                  ),
                  _buildAllSheetTile(
                    ctx,
                    title: 'Calendar',
                    subtitle: 'Date Picker',
                    icon: Icons.calendar_month_rounded,
                    color: const Color(0xFFFF8800),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(_showHomeCalendar());
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAllSheetTile(
    BuildContext ctx, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF221735),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF382954)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // --- SPORTS & LIVE FILTER BAR ---
  Widget _buildSportsFilterBar() {
    return Container(
      color: const Color(0xFF140F1D),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Sports',
                        style: TextStyle(
                          color: Color(0xFF0D0B12),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 14,
                        color: Color(0xFF0D0B12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                ...List.generate(_currentSports.length, (index) {
                  final item = _currentSports[index];
                  final isSelected = index == _sportsTabNavIndex;
                  return GestureDetector(
                    key: ValueKey('home-sport-${item.key}'),
                    onTap: () {
                      _selectHomeSport(index);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      child: Text(
                        item.name,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFFFFD700)
                              : Colors.white60,
                          fontWeight: isSelected
                              ? FontWeight.w900
                              : FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: List.generate(_filterPills.length, (index) {
                final isSelected = index == _filterPillIndex;
                return GestureDetector(
                  key: ValueKey('home-filter-${_filterPills[index]}'),
                  onTap: () => _selectHomeFilter(index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    child: Text(
                      _filterPills[index],
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFFFFD700)
                            : Colors.white54,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: List.generate(_marketOptions.length, (index) {
                final market = _marketOptions[index];
                final isSelected = market == _selectedMarket;
                return GestureDetector(
                  key: ValueKey('home-market-$market'),
                  onTap: () => _selectHomeMarket(market),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF231B32),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF3E2F59),
                      ),
                    ),
                    child: Text(
                      market,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF0D0B12)
                            : Colors.white70,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // --- LEAGUE GROUPING HELPER & MATCH LIST ---
  Map<String, List<FixtureModel>> _groupFixturesByLeague(
    List<FixtureModel> fixtures,
  ) => groupHomeFixturesByLeague(fixtures);

  double? _leagueLine(
    String title,
    List<FixtureModel> fixtures,
    String market,
  ) {
    final lines = homeMarketLineChoices(fixtures, market);
    if (lines.isEmpty) return null;
    final saved = _leagueLines[title];
    if (saved != null && lines.contains(saved)) return saved;
    final explicit = RegExp(r' ([+-]?\d+(?:\.\d+)?)$').firstMatch(market);
    final requested = double.tryParse(explicit?.group(1) ?? '');
    if (requested != null && lines.contains(requested)) return requested;
    if (baseHomeMarket(market) == 'Over/Under' && lines.contains(1.5))
      return 1.5;
    if (lines.contains(2.5)) return 2.5;
    return lines.first;
  }

  String _leagueMarketForOdds(String title, List<FixtureModel> fixtures) {
    final selected =
        _leagueMarkets[title] ??
        (_selectedMarket == 'All Markets'
            ? defaultHomeMarket(_activeSportKey)
            : _selectedMarket);
    final base = baseHomeMarket(selected);
    final line = _leagueLine(title, fixtures, selected);
    return line == null ? base : homeMarketWithLine(base, line);
  }

  Widget _buildLeagueGroupHeader(
    String title,
    int matchCount,
    List<FixtureModel> fixtures,
  ) {
    final choices = homeMarketChoices(
      _activeSportKey,
      fixtures,
    ).map(baseHomeMarket).toSet().toList();
    final selected =
        _leagueMarkets[title] ??
        (_selectedMarket == 'All Markets'
            ? defaultHomeMarket(_activeSportKey)
            : _selectedMarket);
    final market = baseHomeMarket(selected);
    final lines = homeMarketLineChoices(fixtures, market);
    final selectedLine = _leagueLine(title, fixtures, selected);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1428),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF33254C)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public_rounded, color: Color(0xFFFFD700), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$matchCount ${matchCount == 1 ? 'match' : 'matches'}',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF271A3B),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF4B3472)),
            ),
            child: PopupMenuButton<String>(
              key: ValueKey('league-market-$title'),
              tooltip: 'Switch odds market',
              initialValue: market,
              color: const Color(0xFF231B32),
              onSelected: (value) {
                final availableLines = homeMarketLineChoices(fixtures, value);
                final nextLine =
                    baseHomeMarket(value) == 'Over/Under' &&
                        availableLines.contains(1.5)
                    ? 1.5
                    : availableLines.contains(2.5)
                    ? 2.5
                    : availableLines.isEmpty
                    ? null
                    : availableLines.first;
                setState(() {
                  _leagueMarkets[title] = value;
                  if (nextLine == null) {
                    _leagueLines.remove(title);
                  } else {
                    _leagueLines[title] = nextLine;
                  }
                });
                final effectiveMarket = nextLine == null
                    ? value
                    : homeMarketWithLine(value, nextLine);
                unawaited(
                  _refreshHomeMarketOdds(fixtures, market: effectiveMarket),
                );
              },
              itemBuilder: (context) => choices
                  .map(
                    (choice) => PopupMenuItem(
                      value: choice,
                      child: Text(
                        choice,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        market,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: Color(0xFFFFD700),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (lines.isNotEmpty && selectedLine != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF271A3B),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF4B3472)),
              ),
              child: PopupMenuButton<double>(
                key: ValueKey('league-line-$title'),
                tooltip: 'Switch market line',
                initialValue: selectedLine,
                color: const Color(0xFF231B32),
                onSelected: (line) {
                  setState(() => _leagueLines[title] = line);
                  unawaited(
                    _refreshHomeMarketOdds(
                      fixtures,
                      market: homeMarketWithLine(market, line),
                    ),
                  );
                },
                itemBuilder: (context) => lines
                    .map(
                      (line) => PopupMenuItem<double>(
                        value: line,
                        child: Text(
                          line == line.roundToDouble()
                              ? line.toInt().toString()
                              : line.toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                    .toList(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selectedLine == selectedLine.roundToDouble()
                          ? selectedLine.toInt().toString()
                          : selectedLine.toString(),
                      style: const TextStyle(
                        color: Color(0xFF69F0AE),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: Color(0xFF69F0AE),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- MATCH ODDS CARDS LIST (GROUPED BY LEAGUE) ---
  Widget _buildMatchList(BoxConstraints constraints) {
    final visibleFixtures = filterHomeFixtures(
      _apiPrematchFixtures,
      _selectedMarket,
      _activeSportKey,
    );
    if (visibleFixtures.isEmpty && _isLoadingSportsData) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        decoration: BoxDecoration(
          color: const Color(0xFF171221),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2F2445)),
        ),
        child: const Column(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: Color(0xFFFFD700),
                strokeWidth: 2.5,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Loading matches from server...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Waiting for backend response. Please hold on...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      );
    }
    if (visibleFixtures.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFF171221),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2F2445)),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.event_busy_rounded,
              size: 40,
              color: Colors.white38,
            ),
            const SizedBox(height: 10),
            Text(
              _sportsDataError != null
                  ? 'Unable to Load Fixtures'
                  : _apiPrematchFixtures.isNotEmpty
                  ? 'No Fixtures for This Market'
                  : 'No Scheduled Fixtures',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _sportsDataError ??
                  (_apiPrematchFixtures.isNotEmpty
                      ? 'Choose another market to see the available matches.'
                      : 'No matches found for this sport and date.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _loadSportsData(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFFD700)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(
                Icons.refresh_rounded,
                size: 15,
                color: Color(0xFFFFD700),
              ),
              label: const Text(
                'Refresh Matches',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final grouped = _groupFixturesByLeague(visibleFixtures);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        final leagueTitle = entry.key;
        final leagueFixtures = entry.value;
        final market = _leagueMarketForOdds(leagueTitle, leagueFixtures);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLeagueGroupHeader(
              leagueTitle,
              leagueFixtures.length,
              leagueFixtures,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: List.generate(leagueFixtures.length, (index) {
                  final fx = leagueFixtures[index];
                  final hour = fx.matchTime.hour.toString().padLeft(2, '0');
                  final minute = fx.matchTime.minute.toString().padLeft(2, '0');
                  final matchTimeStr = '$hour:$minute';

                  // Dynamic Prediction details from Betmines
                  final pred = fx.prediction;
                  final hasPred = pred != null && pred.prediction.isNotEmpty;
                  final predTip = hasPred ? pred.prediction : '';
                  final predOdds = hasPred
                      ? homePredictionOdds(fx, pred, _activeSportKey)
                      : '';
                  final predProb = hasPred
                      ? homePredictionProbability(fx, pred, _activeSportKey) ??
                            0
                      : 0;
                  final predReview = hasPred
                      ? homePredictionProbabilityReview(
                          fx,
                          pred,
                          _activeSportKey,
                        )
                      : null;
                  final isWon = hasPred && pred.isWon;
                  final isLost = hasPred && pred.isLost;
                  final predOption = hasPred
                      ? homePredictionOption(fx, pred, _activeSportKey)
                      : null;
                  final predKey = hasPred
                      ? homeOddsSelectionKey(
                          fx.id,
                          predOption?.marketKey ??
                              _mapPredictionToMarketType(predTip),
                          predOption?.selection ?? predTip,
                        )
                      : '';
                  final isPredSelected =
                      hasPred &&
                      (_selectedOddsKeys.contains('pred_${fx.id}_$predTip') ||
                          _selectedOddsKeys.contains(predKey) ||
                          _selectedTicketItems.containsKey(
                            'pred_${fx.id}_$predTip',
                          ) ||
                          _selectedTicketItems.containsKey(predKey));
                  final showScores =
                      fx.isLive ||
                      fx.isFinished ||
                      fx.homeScore > 0 ||
                      fx.awayScore > 0;

                  final oddsOptions = homeMarketOdds(
                    fx,
                    market,
                    _activeSportKey,
                  );

                  return InkWell(
                    key: ValueKey('home-match-${fx.id}'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MatchDetailScreen(
                            fixtureId: fx.id,
                            initialFixture: fx,
                            onToggleOdd: (id, mkt, sel, val) =>
                                _toggleDetailOddSelection(fx, mkt, sel, val),
                            isOddSelected: (id, mkt, sel) =>
                                _isDetailOddSelected(fx, mkt, sel),
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171221),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: hasPred && isWon
                              ? const Color(0xFF2E7D32).withValues(alpha: 0.6)
                              : const Color(0xFF2F2445),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Match details stay vertical and use the full card
                          // width so long team names remain readable.
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Time & Status Tag
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.schedule_rounded,
                                        size: 12,
                                        color: Colors.white54,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        matchTimeStr,
                                        style: TextStyle(
                                          color: fx.isLive
                                              ? const Color(0xFFFFD700)
                                              : Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (fx.isLive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'LIVE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  if (fx.isFinished)
                                    Container(
                                      key: ValueKey('finished-${fx.id}'),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white12,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.white38,
                                          width: 0.7,
                                        ),
                                      ),
                                      child: const Text(
                                        'FINISHED',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  if (fx.sportyBetSynced)
                                    Container(
                                      key: ValueKey('sporty-synced-${fx.id}'),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF00E676,
                                        ).withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xFF00E676),
                                          width: 0.7,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.sync_rounded,
                                            color: Color(0xFF00E676),
                                            size: 9,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            'SYNCED',
                                            style: TextStyle(
                                              color: Color(0xFF00E676),
                                              fontSize: 8,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Builder(
                                    builder: (context) {
                                      final stream = _findMatchingStream(fx);
                                      if (stream == null ||
                                          !stream.hasStreams) {
                                        return const SizedBox.shrink();
                                      }
                                      return GestureDetector(
                                        onTap: () {
                                          LiveStreamSheet.show(
                                            context,
                                            streamEvent: stream,
                                            matchTitle:
                                                '${fx.homeTeam} vs ${fx.awayTeam}',
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFD700),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.live_tv_rounded,
                                                color: Color(0xFF0D0B12),
                                                size: 9,
                                              ),
                                              SizedBox(width: 2),
                                              Text(
                                                'STREAM',
                                                style: TextStyle(
                                                  color: Color(0xFF0D0B12),
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.public_rounded,
                                    size: 11,
                                    color: Colors.white38,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      [
                                        if (fx.country.trim().isNotEmpty)
                                          fx.country.trim(),
                                        if (fx.leagueName.trim().isNotEmpty)
                                          fx.leagueName.trim(),
                                      ].join(' • '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Home Team
                              Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF281C3D),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFF45306B),
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      fx.homeTeam.isNotEmpty
                                          ? fx.homeTeam[0]
                                          : 'H',
                                      style: const TextStyle(
                                        color: Color(0xFFFFD700),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        fx.homeTeam,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (showScores)
                                    Text(
                                      '${fx.homeScore}',
                                      style: const TextStyle(
                                        color: Color(0xFFFFD700),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              // Away Team
                              Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF281C3D),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFF45306B),
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      fx.awayTeam.isNotEmpty
                                          ? fx.awayTeam[0]
                                          : 'A',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        fx.awayTeam,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (showScores)
                                    Text(
                                      '${fx.awayScore}',
                                      style: const TextStyle(
                                        color: Color(0xFFFFD700),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                ],
                              ),
                              if (hasPred) ...[
                                const SizedBox(height: 12),
                                // PREDICTION CARD PILL (BETMINES SYNCED)
                                GestureDetector(
                                  key: ValueKey('home-prediction-${fx.id}'),
                                  onTap: predOdds.isEmpty
                                      ? null
                                      : () => _toggleFixturePredictionSelection(
                                          fx,
                                          pred,
                                        ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPredSelected
                                          ? const Color(0xFF2C2414)
                                          : const Color(0xFF1F162E),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isPredSelected
                                            ? const Color(0xFFFFD700)
                                            : isWon
                                            ? const Color(
                                                0xFF00E676,
                                              ).withValues(alpha: 0.6)
                                            : isLost
                                            ? const Color(
                                                0xFFFF5252,
                                              ).withValues(alpha: 0.4)
                                            : const Color(
                                                0xFFFFD700,
                                              ).withValues(alpha: 0.3),
                                        width: isPredSelected ? 1.5 : 1,
                                      ),
                                      boxShadow: isPredSelected
                                          ? [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFFFFD700,
                                                ).withValues(alpha: 0.25),
                                                blurRadius: 6,
                                                spreadRadius: 1,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      runSpacing: 4,
                                      children: [
                                        Icon(
                                          isPredSelected
                                              ? Icons.check_circle_rounded
                                              : isWon
                                              ? Icons.check_circle_rounded
                                              : isLost
                                              ? Icons.cancel_rounded
                                              : Icons.auto_awesome_rounded,
                                          size: 13,
                                          color: isPredSelected
                                              ? const Color(0xFFFFD700)
                                              : isWon
                                              ? const Color(0xFF00E676)
                                              : isLost
                                              ? const Color(0xFFFF5252)
                                              : const Color(0xFFFFD700),
                                        ),
                                        const SizedBox(width: 5),
                                        const Text(
                                          'PREDICTION: ',
                                          style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2E2245),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            predTip,
                                            style: const TextStyle(
                                              color: Color(0xFFFFD700),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        if (predOdds.isEmpty)
                                          const Text(
                                            ' Odds unavailable',
                                            style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 10,
                                            ),
                                          ),
                                        if (predOdds.isNotEmpty) ...[
                                          const SizedBox(width: 5),
                                          Text(
                                            '@$predOdds',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1A3828),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFF2E7D32),
                                            ),
                                          ),
                                          child: Text(
                                            predReview != null
                                                ? 'Estimate under review'
                                                : '$predProb%',
                                            key: predReview != null
                                                ? ValueKey(
                                                    'home-probability-review-${fx.id}',
                                                  )
                                                : null,
                                            style: TextStyle(
                                              color: predReview != null
                                                  ? const Color(0xFFFFD700)
                                                  : const Color(0xFF69F0AE),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        if (isPredSelected) ...[
                                          const SizedBox(width: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFD700),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            child: const Text(
                                              'ADDED',
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ] else if (isWon) ...[
                                          const SizedBox(width: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF00E676),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            child: const Text(
                                              'WON',
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ] else if (isLost) ...[
                                          const SizedBox(width: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFF5252),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            child: const Text(
                                              'LOST',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _buildMarketProbabilityCarousel(fx),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Market outcomes share the available device width.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: List.generate(oddsOptions.length, (i) {
                              final opt = oddsOptions[i];
                              final key = homeOddsSelectionKey(
                                fx.id,
                                opt.marketKey,
                                opt.selection,
                              );
                              final isSelected =
                                  _selectedOddsKeys.contains(key) ||
                                  _selectedTicketItems.containsKey(key);
                              final hasOdd = opt.odd.isNotEmpty;
                              final outcomeProbability = homeOutcomeProbability(
                                fx,
                                market,
                                opt.selection,
                              );
                              final outcomeReview =
                                  homeOutcomeProbabilityReview(
                                    fx,
                                    market,
                                    opt.selection,
                                    opt.odd,
                                  );

                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: i < oddsOptions.length - 1 ? 6 : 0,
                                  ),
                                  child: GestureDetector(
                                    key: ValueKey(
                                      'home-odds-${fx.id}-${opt.selection}',
                                    ),
                                    onTap: hasOdd
                                        ? () => _toggleFixtureOddsSelection(
                                            fx,
                                            opt.selection,
                                            opt.odd,
                                            marketKey: opt.marketKey,
                                            sportyMarketId: opt.sportyMarketId,
                                            sportyOutcomeId:
                                                opt.sportyOutcomeId,
                                            sportySpecifier:
                                                opt.sportySpecifier,
                                          )
                                        : null,
                                    child: Container(
                                      height: 47,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFFFFD700)
                                            : const Color(0xFF231B32),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFFFFD700)
                                              : const Color(0xFF392A54),
                                          width: isSelected ? 1.5 : 1.0,
                                        ),
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFFFFD700,
                                                  ).withValues(alpha: 0.35),
                                                  blurRadius: 8,
                                                  spreadRadius: 1,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Flexible(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    opt.label,
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                      color: isSelected
                                                          ? const Color(
                                                              0xFF0D0B12,
                                                            )
                                                          : Colors.white54,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                hasOdd ? opt.odd : '-',
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? const Color(0xFF0D0B12)
                                                      : const Color(0xFFFFD700),
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                          ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              outcomeReview != null
                                                  ? 'Review estimate'
                                                  : outcomeProbability == null
                                                  ? '-'
                                                  : '$outcomeProbability% probability',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? const Color(0xFF234D35)
                                                    : outcomeReview != null
                                                    ? const Color(0xFFFFD700)
                                                    : const Color(0xFF69F0AE),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 8,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }

  // --- FLOATING BETSLIP BUTTON ---
  Widget _buildFloatingBetslip() {
    final count = _selectedTicketItems.length;
    return GestureDetector(
      onTap: () {
        _showBetslipBottomSheet(context);
      },
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(alpha: 0.4),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count',
              style: const TextStyle(
                color: Color(0xFF0D0B12),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const Text(
              'Betslip',
              style: TextStyle(
                color: Color(0xFF0D0B12),
                fontWeight: FontWeight.w700,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    ).animate().scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1));
  }

  // --- BETSLIP BOTTOM SHEET WITH SPORTYBET CODE GENERATOR ---
  void _showBetslipBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final items = _selectedTicketItems.values.toList();
            final count = items.length;
            final double totalOdds = ticketSelectionsTotalOdds(items);

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Color(0xFF150A29),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: Color(0xFFFFD700), width: 2),
                ),
              ),
              child: Column(
                children: [
                  // Handle & Header
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.confirmation_number_rounded,
                              color: Color(0xFFFFD700),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Ticket Bucket ($count)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        if (count > 0)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedOddsKeys.clear();
                                _selectedTicketItems.clear();
                              });
                              setModalState(() {});
                            },
                            child: const Text(
                              'Clear All',
                              style: TextStyle(
                                color: Color(0xFFFF5252),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFF2C1E4A), height: 1),

                  // Selections List or Empty State
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt_long_rounded,
                                  size: 56,
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Your Betslip is Empty',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Add AI tips from Popular Predictions or Matches',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (c, idx) {
                              final sel = items[idx];
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1D1236),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF382563),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${sel.homeTeam} vs ${sel.awayTeam}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFFFD700,
                                                  ).withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '${sel.marketType}: ${sel.selection}',
                                                  style: const TextStyle(
                                                    color: Color(0xFFFFD700),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  sel.leagueName,
                                                  style: const TextStyle(
                                                    color: Colors.white38,
                                                    fontSize: 11,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      ticketOddsLabel(sel.odds),
                                      style: const TextStyle(
                                        color: Color(0xFFFFD700),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          if (sel.predictionId != null) {
                                            _selectedOddsKeys.remove(
                                              sel.predictionId,
                                            );
                                          }
                                          _selectedOddsKeys.remove(
                                            sel.uniqueKey,
                                          );
                                          if (sel.fixtureId != null) {
                                            _selectedOddsKeys.remove(
                                              '${sel.fixtureId}-${sel.selection}',
                                            );
                                            _selectedOddsKeys.remove(
                                              'pred_${sel.fixtureId}_${sel.selection}',
                                            );
                                            _selectedOddsKeys.remove(
                                              homeOddsSelectionKey(
                                                sel.fixtureId!,
                                                sel.marketType,
                                                sel.selection,
                                              ),
                                            );
                                          }
                                          _selectedTicketItems.removeWhere(
                                            (k, v) =>
                                                v.uniqueKey == sel.uniqueKey ||
                                                k == sel.uniqueKey ||
                                                k == sel.predictionId ||
                                                (sel.fixtureId != null &&
                                                    (k ==
                                                            '${sel.fixtureId}-${sel.selection}' ||
                                                        k ==
                                                            'pred_${sel.fixtureId}_${sel.selection}' ||
                                                        k ==
                                                            homeOddsSelectionKey(
                                                              sel.fixtureId!,
                                                              sel.marketType,
                                                              sel.selection,
                                                            ))),
                                          );
                                        });
                                        setModalState(() {});
                                      },
                                      child: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.white38,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  // Bottom Action Bar
                  if (items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFF100720),
                        border: Border(
                          top: BorderSide(color: Color(0xFF2C1E4A)),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Accumulator Total Odds:',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  ticketOddsLabel(totalOdds),
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  _handleGenerateBookingCode(items);
                                },
                                icon: const Icon(Icons.bolt_rounded, size: 20),
                                label: const Text(
                                  'Generate SportyBet Booking Code',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFD700),
                                  foregroundColor: const Color(0xFF0D0B12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Handle Booking Code Generation
  Future<void> _handleGenerateBookingCode(
    List<TicketSelectionModel> items,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      ),
    );

    try {
      final res = await _sportsService.generateBookingCode(
        selections: items,
        platform: 'sportybetng',
        title: 'Prediction Slip',
      );
      if (mounted) {
        final currentUser = SessionManager.instance.currentUser;
        if (currentUser != null) {
          await SessionManager.instance.updateUser(
            currentUser.copyWith(
              coins: res.coinsBalance,
              tickets: currentUser.tickets + 1,
            ),
          );
        }
        if (!mounted) return;
        Navigator.pop(context); // Close loading dialog
        _showBookingCodeSuccessDialog(res);
        _loadCommunityTickets();
        _loadUserPicksStream();
      }
    } catch (error) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to generate a SportyBet booking code: $error',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showBookingCodeSuccessDialog(BookingCodeResult result) {
    showDialog(
      context: context,
      builder: (c) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B112D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFFFD700), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFFFFD700),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Booking code ready',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF120D19),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          'SPORTYBET NIGERIA',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                        Spacer(),
                        Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: Color(0xFF00E676),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'READY',
                          style: TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Booking code',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      result.bookingCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Selections: ${result.itemCount}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'Total Odds: @ ${ticketOddsLabel(result.totalOdds)}',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: result.bookingCode),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Booking code ${result.bookingCode} copied.'),
                    backgroundColor: const Color(0xFF1F6B45),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text(
                'Copy Code',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: const Color(0xFF0D0B12),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- POPULAR PREDICTIONS SCREEN (Consensus Picks) ---
  Widget _buildPopularPredictionsScreen(BoxConstraints constraints) {
    if (!_hasPredictionAccess) return _buildVipPredictionPaywall();
    final isMobile = constraints.maxWidth < 600;

    return SingleChildScrollView(
      controller: _predictionScrollController,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHomeDateBar(),
          const SizedBox(height: 10),
          // Horizontal prediction tabs.
          Container(
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF151020),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF302343)),
            ),
            child: ListView.separated(
              key: const ValueKey('prediction-category-list'),
              scrollDirection: Axis.horizontal,
              itemCount: _popularFilterLabels.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final isSelected = index == _popularFilterIndex;
                final isZaiPick = index == _ratingBetFilterIndex;
                final activeColor = isZaiPick
                    ? const Color(0xFF00E5FF)
                    : const Color(0xFFFFD700);
                return Semantics(
                  key: ValueKey(
                    'prediction-filter-${_popularFilterLabels[index]}',
                  ),
                  button: true,
                  selected: isSelected,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _loadPopularPredictions(index),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? activeColor
                              : const Color(0xFF1E162B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? activeColor
                                : const Color(0xFF352752),
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: activeColor.withValues(alpha: 0.22),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          _popularFilterLabels[index],
                          maxLines: 1,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF0D0B12)
                                : Colors.white70,
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w900
                                : FontWeight.w600,
                            letterSpacing: isSelected ? 0.15 : 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          if (_popularFilterIndex == 3) ...[
            _buildPredictionMarketTabs(
              labels: _footballMarketLabels,
              selectedIndex: _footballMarketIndex,
              onSelected: (index) {
                _footballMarketIndex = index;
                _loadPopularPredictions(3);
              },
            ),
            const SizedBox(height: 16),
          ],

          if (_popularFilterIndex == _ratingBetFilterIndex) ...[
            _buildPredictionMarketTabs(
              labels: _ratingBetMarkets
                  .map((market) => market['label']!)
                  .toList(),
              selectedIndex: _ratingBetMarketIndex,
              onSelected: (index) {
                _ratingBetMarketIndex = index;
                _loadPopularPredictions(_ratingBetFilterIndex);
              },
            ),
            const SizedBox(height: 16),
          ],

          if (_popularFilterIndex >= 5 &&
              _popularFilterIndex != _accumulatorFilterIndex) ...[
            _buildPredictionMarketTabs(
              labels: _otherSportSubTabLabels,
              selectedIndex: _otherSportSubTabIndex,
              onSelected: (index) {
                _otherSportSubTabIndex = index;
                _loadPopularPredictions(_popularFilterIndex);
              },
            ),
            const SizedBox(height: 16),
          ],

          // Prediction Feed List via FutureBuilder
          FutureBuilder<Map<String, dynamic>>(
            future: _popularPredictionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !predictionFeedHasContent(
                    snapshot.data ?? const <String, dynamic>{},
                  ) &&
                  _popularPredictionPage == 1 &&
                  !_predictionLoadingMore) {
                return Container(
                  height: 250,
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFFD700)),
                      SizedBox(height: 12),
                      Text(
                        'Loading predictions...',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }

              if (snapshot.hasError || snapshot.data?['load_error'] != null) {
                return _buildPredictionFeedState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load predictions',
                  message:
                      snapshot.data?['load_error']?.toString() ??
                      snapshot.error?.toString() ??
                      'Check your connection and try again.',
                  showRetry: true,
                );
              }

              final rawItems = snapshot.data?['items'] as List?;
              final rawGroups = snapshot.data?['groups'] as List?;
              final topItems = _predictionRows(snapshot.data?['top_items']);
              List<Map<String, dynamic>> items = [];

              if (rawItems != null && rawItems.isNotEmpty) {
                items = rawItems
                    .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
                    .whereType<Map<String, dynamic>>()
                    .toList();
              }

              final groups = (rawGroups ?? const <dynamic>[])
                  .whereType<Map>()
                  .map((group) => Map<String, dynamic>.from(group))
                  .where((group) => group['items'] is List)
                  .toList();

              if (items.isEmpty && groups.isEmpty && topItems.isEmpty) {
                return _buildPredictionFeedState(
                  icon: Icons.insights_rounded,
                  title: snapshot.data?['loading'] == true
                      ? 'Preparing daily predictions'
                      : 'No predictions available',
                  message:
                      snapshot.data?['message']?.toString() ??
                      (snapshot.data?['loading'] == true
                          ? 'Daily picks are being cached. This page refreshes automatically.'
                          : 'No predictions are available for this date.'),
                  showRetry: true,
                );
              }

              final selectedZaiMarket =
                  _popularFilterIndex == _ratingBetFilterIndex &&
                      _ratingBetMarkets.isNotEmpty
                  ? _ratingBetMarkets[_ratingBetMarketIndex]['key'] ?? ''
                  : '';
              return Column(
                children: [
                  if (_popularFilterIndex == 3 &&
                      snapshot.data?['has_top_section'] == true) ...[
                    _predictionSectionHeading('Top'),
                    if (topItems.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          snapshot.data?['top_load_error'] != null
                              ? 'Top predictions are temporarily unavailable.'
                              : snapshot.data?['top_loading'] == true
                              ? 'Preparing top predictions...'
                              : 'No predictions above 75% for this market and date.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    ...topItems.asMap().entries.map(
                      (entry) =>
                          _buildScores24PopularCard(entry.value, entry.key),
                    ),
                    _predictionSectionHeading(
                      snapshot.data?['general_title']?.toString() ??
                          'Predictions',
                    ),
                  ],
                  if (selectedZaiMarket == 'zai-2-odds')
                    _buildZaiFeaturedSummary(
                      selectedZaiMarket,
                      snapshot.data!,
                      items.length,
                    ),
                  if ((selectedZaiMarket == 'zai-accumulators' ||
                          selectedZaiMarket == 'zai-2-odds' ||
                          _popularFilterIndex == _accumulatorFilterIndex) &&
                      groups.isNotEmpty)
                    ...groups.asMap().entries.map(
                      (entry) =>
                          _buildAccumulatorMarketGroup(entry.value, entry.key),
                    )
                  else
                    ...items.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      return _buildScores24PopularCard(item, idx);
                    }),
                  if (_predictionLoadingMore)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        color: Color(0xFFFFD700),
                      ),
                    ),
                  if (_predictionMoreError != null)
                    TextButton(
                      onPressed: () {
                        setState(() => _predictionMoreError = null);
                        unawaited(_loadMorePredictions());
                      },
                      child: const Text('Retry loading more'),
                    ),
                  Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _onPredictionScroll();
                      });
                      return const SizedBox(height: 20);
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAccumulatorMarketGroup(
    Map<String, dynamic> group,
    int groupIndex,
  ) {
    final market = group['market']?.toString() ?? 'Market';
    final target = double.tryParse(group['target_odds']?.toString() ?? '');
    final total = double.tryParse(group['total_odds']?.toString() ?? '');
    final items = (group['items'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF151020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF352752)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    market,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  target == null || target <= 0
                      ? '${items.length} predictions'
                      : 'Target ${target.toStringAsFixed(2)} / ${total?.toStringAsFixed(2) ?? '-'}',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (group['booking_code']?.toString().isNotEmpty == true)
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: Text('Booking code: ${group['booking_code']}'),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: group['booking_code'].toString()),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Booking code copied')),
                );
              },
            ),
          if (group['message']?.toString().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                group['message'].toString(),
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          const SizedBox(height: 4),
          ...items.asMap().entries.map(
            (entry) => _buildScores24PopularCard(entry.value, entry.key),
          ),
        ],
      ),
    );
  }

  Widget _buildZaiFeaturedSummary(
    String marketKey,
    Map<String, dynamic> response,
    int itemCount,
  ) {
    final isTwoOdds = marketKey == 'zai-2-odds';
    final filters = response['filters_applied'];
    final applied = filters is Map ? Map<String, dynamic>.from(filters) : null;
    final totalOdds = double.tryParse(applied?['total_odds']?.toString() ?? '');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF10212A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology_alt_rounded, color: Color(0xFF00E5FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTwoOdds ? 'ZAI 2 Odds VIP Bundle' : 'ZAI Accumulator Pool',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isTwoOdds
                      ? '2.00 target bundles grouped by prediction source.'
                      : 'Market accumulators with 2.00 and 3.00 targets.',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          if (isTwoOdds && totalOdds != null && totalOdds > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                ticketOddsLabel(totalOdds),
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPredictionMarketTabs({
    required List<String> labels,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF151020),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF302343)),
      ),
      child: ListView.separated(
        key: const ValueKey('prediction-market-tabs'),
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return Semantics(
            button: true,
            selected: selected,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(index),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFF1E162B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF00E5FF)
                          : const Color(0xFF352752),
                    ),
                  ),
                  child: Text(
                    labels[index],
                    maxLines: 1,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF0D0B12)
                          : Colors.white60,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPredictionFeedState({
    required IconData icon,
    required String title,
    required String message,
    bool showRetry = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: const Color(0xFF181124),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF352752)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white38, size: 38),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (showRetry) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                _sportsService.clearPredictionCache();
                _loadPopularPredictions(_popularFilterIndex);
              },
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFD700),
                side: const BorderSide(color: Color(0xFFFFD700)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build Scores24 Popular Consensus Card
  Widget _predictionSectionHeading(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );

  Widget _buildPredictionResult(Map<String, dynamic> item) {
    final status = (item['status'] ?? 'pending').toString().toLowerCase();
    final home = item['home_score'];
    final away = item['away_score'];
    final match = (item['match_status'] ?? '').toString().toLowerCase();
    final decided = const {'won', 'lost', 'void'}.contains(status);
    final score =
        home != null &&
            away != null &&
            (decided || const {'finished', 'ft', 'live'}.contains(match))
        ? '$home - $away  '
        : '';
    final label = decided
        ? status.toUpperCase()
        : match == 'live'
        ? 'LIVE'
        : 'PENDING';
    return Text(
      '$score$label',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: status == 'won'
            ? const Color(0xFF69F0AE)
            : status == 'lost'
            ? Colors.redAccent
            : Colors.white54,
      ),
    );
  }

  Widget _buildPredictionKickoff(String rawMatchTime) {
    final parsed = DateTime.tryParse(rawMatchTime)?.toLocal();
    if (parsed == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_rounded, size: 14, color: Colors.white54),
            const SizedBox(width: 5),
            Text(
              rawMatchTime.trim().isEmpty
                  ? 'Kickoff time pending'
                  : rawMatchTime,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final today = DateUtils.dateOnly(DateTime.now());
    final matchDate = DateUtils.dateOnly(parsed);
    final dayDifference = matchDate.difference(today).inDays;
    final calendarDate = '${parsed.day} ${months[parsed.month - 1]}';
    final dateLabel = switch (dayDifference) {
      0 => 'Today, $calendarDate',
      1 => 'Tomorrow, $calendarDate',
      _ =>
        '${weekdays[parsed.weekday - 1]}, $calendarDate'
            '${parsed.year == today.year ? '' : ' ${parsed.year}'}',
    };
    final timeLabel = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(parsed),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    Widget labelChip(IconData icon, String label, {bool highlight = false}) {
      final color = highlight ? const Color(0xFFFFD700) : Colors.white70;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFFFFD700).withValues(alpha: 0.11)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: highlight
                ? const Color(0xFFFFD700).withValues(alpha: 0.3)
                : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 7,
      runSpacing: 6,
      children: [
        labelChip(Icons.calendar_today_rounded, dateLabel),
        labelChip(Icons.schedule_rounded, timeLabel, highlight: true),
      ],
    );
  }

  Widget _buildScores24PopularCard(Map<String, dynamic> item, int idx) {
    final ticketSelection = TicketSelectionModel.fromPrediction(item);
    final id = ticketSelection.uniqueKey;
    final fixtureId = item['fixture_id']?.toString().trim() ?? '';
    final sport = item['sport']?.toString() ?? '';
    final homeTeam = item['home_team']?.toString() ?? '';
    final awayTeam = item['away_team']?.toString() ?? '';
    final league = item['league']?.toString() ?? '';
    final matchTime = item['match_time']?.toString() ?? '';
    final market = item['market']?.toString() ?? '';
    final selection = item['selection']?.toString() ?? '';
    final odds = (item['odds'] is num)
        ? (item['odds'] as num).toDouble()
        : (double.tryParse(item['odds']?.toString() ?? '') ?? 0);

    final isSelected = _selectedOddsKeys.contains(id);
    final isHockey = sport.toLowerCase().contains('hockey');
    final canAddToBetslip = ticketSelection.canAddToBucket;

    return InkWell(
      onTap: () {
        if (fixtureId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Match details are still syncing. Try again shortly.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MatchDetailScreen(
              fixtureId: fixtureId,
              sportsService: _sportsService,
              onToggleOdd: _toggleDetailOddSelection,
              isOddSelected: _isDetailOddSelected,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF181124),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHockey
                ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                : const Color(0xFFFFD700).withValues(alpha: 0.4),
            width: 1.4,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Sport / League Badge + Scores24 Popular Consensus Pill
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isHockey
                              ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                              : const Color(0xFF2C1C45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isHockey
                                  ? Icons.sports_hockey
                                  : (sport.toLowerCase().contains('basketball')
                                        ? Icons.sports_basketball
                                        : (sport.toLowerCase().contains(
                                                'tennis',
                                              )
                                              ? Icons.sports_tennis
                                              : Icons.sports_soccer)),
                              size: 13,
                              color: isHockey
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFFFFD700),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              sport,
                              style: TextStyle(
                                color: isHockey
                                    ? const Color(0xFF00E5FF)
                                    : Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          league,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    predictionConfidenceLabel(item),
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Teams
            Text(
              '$homeTeam  vs  $awayTeam',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 8),

            _buildPredictionKickoff(matchTime),
            const SizedBox(height: 6),
            _buildPredictionResult(item),

            const SizedBox(height: 10),

            // AI / Consensus Recommended Pick Box
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF221834),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3F2B66)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.stars_rounded,
                          color: Color(0xFFFFD700),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$market: $selection',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (odds > 1) ...[
                    const SizedBox(width: 8),
                    Text(
                      '@ ${odds.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (ticketSelection.isUpcoming) ...[
              // Mapped bookmaker selections can be saved before odds arrive.
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: canAddToBetslip
                      ? () {
                          setState(() {
                            if (!ticketSelection.canAddToBucket) return;
                            if (isSelected) {
                              _selectedOddsKeys.remove(id);
                              _selectedTicketItems.remove(id);
                            } else {
                              _selectedOddsKeys.add(id);
                              _selectedTicketItems[id] = ticketSelection;
                            }
                          });
                        }
                      : null,
                  icon: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 16,
                  ),
                  label: Text(
                    canAddToBetslip
                        ? (isSelected ? 'Added to Betslip' : 'Add to Betslip')
                        : predictionBookmakerAvailability(item),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected
                        ? const Color(0xFFFFD700)
                        : const Color(0xFF2B1F43),
                    foregroundColor: isSelected
                        ? const Color(0xFF0D0B12)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF4A3470),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms, delay: (idx * 40).ms);
  }

  // --- PREDICTIONS SCREEN ---
  Widget _buildPredictionsScreen(BoxConstraints constraints) {
    return _buildPopularPredictionsScreen(constraints);
  }

  Widget _buildVipPredictionPaywall() {
    final loggedIn = SessionManager.instance.isLoggedIn;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1E142B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFA855F7)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFFFD700),
                  size: 58,
                ),
                const SizedBox(height: 16),
                const Text(
                  'VIP Predictions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  loggedIn
                      ? 'An active VIP subscription is required to view predictions on the home and prediction pages.'
                      : 'Sign in and activate a VIP subscription to view predictions.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.45),
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: loggedIn
                      ? _openProfile
                      : () => _openAuth(AuthMode.signIn),
                  icon: Icon(loggedIn ? Icons.workspace_premium : Icons.login),
                  label: Text(loggedIn ? 'View VIP Plans' : 'Sign In'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- FEEDS SCREEN ---
  Widget _buildFeedsScreen(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;
    final labels = ['Community Slips', 'User Picks'];
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Community Feed',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Live slips and picks loaded from Zentry',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: labels.length,
              itemBuilder: (context, index) => GestureDetector(
                onTap: () {
                  setState(() => _feedFilterIndex = index);
                  if (index == 0) {
                    _loadCommunityTickets(_communityTicketStatusFilter);
                  } else {
                    _loadUserPicksStream(_userPickStatusFilter);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _feedFilterIndex == index
                        ? const Color(0xFFFFD700)
                        : const Color(0xFF1E162B),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    labels[index],
                    style: TextStyle(
                      color: _feedFilterIndex == index
                          ? const Color(0xFF0D0B12)
                          : Colors.white70,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_feedFilterIndex == 0)
            _buildCommunitySlipsView(isMobile)
          else
            _buildUserPicksStreamView(isMobile),
        ],
      ),
    );
  }

  // --- LIVE TV FOOTBALL STREAMING SCREEN ---
  Widget _buildLiveTvScreen(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;
    final events = _liveStreamEvents;
    final hasStreams = events.isNotEmpty;
    final hasActiveSelection =
        hasStreams &&
        _selectedStreamIndex >= 0 &&
        _selectedStreamIndex < events.length &&
        events[_selectedStreamIndex].live;
    final selectedStream = hasActiveSelection
        ? events[_selectedStreamIndex]
        : null;

    return RefreshIndicator(
      onRefresh: _loadLiveStreams,
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1E142B),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 20,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.live_tv_rounded,
                    color: Color(0xFFFFD700),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Match Broadcasts',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Native HLS and DASH sports streams',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Color(0xFFFFD700),
                  ),
                  tooltip: 'Refresh Feeds',
                  onPressed: _loadLiveStreams,
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (_isLoadingLiveStreams) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFFD700)),
                      SizedBox(height: 16),
                      Text(
                        'Fetching live match feeds...',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_liveStreamsError != null && !hasStreams) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF171221),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _liveStreamsError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadLiveStreams,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry Feeds'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: const Color(0xFF0D0B12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (!hasStreams) ...[
              // Empty State
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF171221),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF2F2445)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.tv_off_rounded,
                        size: 44,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No Live Broadcasts On Air Right Now',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Live streaming channels become available as matches kickoff. Pull down or tap below to check for newly opened streams.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _loadLiveStreams,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Check For Streams'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: const Color(0xFF0D0B12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Featured Live Video Player Card
              if (selectedStream != null) ...[
                SizedBox(
                  height: isMobile ? 260 : 380,
                  width: double.infinity,
                  child: InAppStreamPlayer(
                    key: ValueKey(
                      'live-${selectedStream.id}-$_streamPlayerRevision',
                    ),
                    streamEvent: selectedStream,
                    allEvents: const [],
                    apiBaseUrl: _sportsService.baseUrl,
                    onBack: () {
                      setState(() => _selectedStreamIndex = -1);
                    },
                  ),
                ).animate().fadeIn(duration: 350.ms),
                const SizedBox(height: 18),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E142B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFFD700,
                          ).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Color(0xFFFFD700),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Any Fixture Below To Stream',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Choose an available fixture and watch it in the app.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              Text(
                "Today's Streams (${events.length})",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              // Channels List
              ...events.asMap().entries.map((entry) {
                final idx = entry.key;
                final ev = entry.value;
                final isCurrent = ev.live && _selectedStreamIndex == idx;
                final hasEnded = ev.hasEnded;
                final kickoff = ev.kickoffUtc?.toLocal();
                final statusLine = hasEnded
                    ? '${ev.category.toUpperCase()} • Match ended'
                    : ev.isUpcoming
                    ? '${ev.category.toUpperCase()} • ${kickoff == null ? 'Upcoming today' : 'Starts ${TimeOfDay.fromDateTime(kickoff).format(context)}'}'
                    : !ev.hasStreams
                    ? '${ev.category.toUpperCase()} • Tap to load channels'
                    : '${ev.category.toUpperCase()} • ${ev.playbackSources.length} channel(s) available';
                return GestureDetector(
                  onTap: ev.live
                      ? () => _playLiveStreamEvent(idx, fullscreen: true)
                      : null,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? const Color(0xFF261D3A)
                          : hasEnded
                          ? const Color(0xFF151515)
                          : const Color(0xFF181124),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent
                            ? const Color(0xFFFFD700)
                            : hasEnded
                            ? const Color(0xFF343434)
                            : const Color(0xFF352752),
                        width: isCurrent ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        _resolvingStreamIds.contains(ev.id)
                            ? const SizedBox(
                                width: 32,
                                height: 32,
                                child: Padding(
                                  padding: EdgeInsets.all(6),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFFD700),
                                  ),
                                ),
                              )
                            : Icon(
                                hasEnded
                                    ? Icons.sports_score_rounded
                                    : ev.isUpcoming
                                    ? Icons.schedule_rounded
                                    : isCurrent
                                    ? Icons.play_circle_fill_rounded
                                    : Icons.play_circle_outline_rounded,
                                color: isCurrent
                                    ? const Color(0xFFFFD700)
                                    : hasEnded
                                    ? Colors.white24
                                    : Colors.white38,
                                size: 32,
                              ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ev.displayTitle,
                                style: TextStyle(
                                  color: isCurrent
                                      ? const Color(0xFFFFD700)
                                      : hasEnded
                                      ? Colors.white38
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                statusLine,
                                style: TextStyle(
                                  color: hasEnded
                                      ? Colors.white30
                                      : Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed:
                              ev.live && !_resolvingStreamIds.contains(ev.id)
                              ? () =>
                                    _playLiveStreamEvent(idx, fullscreen: true)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isCurrent
                                ? const Color(0xFFFFD700)
                                : hasEnded
                                ? const Color(0xFF292929)
                                : const Color(0xFF352752),
                            foregroundColor: isCurrent
                                ? const Color(0xFF0D0B12)
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            hasEnded
                                ? 'Ended'
                                : ev.isUpcoming
                                ? 'Upcoming'
                                : _resolvingStreamIds.contains(ev.id)
                                ? 'Loading'
                                : (isCurrent ? 'Playing' : 'Watch'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAceChannelsSection() {
    final future = _aceChannelsFuture ??= _sportsService.getAceChannels();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF352752)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hub_rounded, color: Color(0xFFFFD700), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Local AceStream Channels',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'Playback uses Ace Stream Engine on this device (127.0.0.1:6878). The backend supplies channel IDs only.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _aceChannelQuery = value),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search channels, e.g. Sky Sports or NBA TV',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Colors.white54,
              ),
              filled: true,
              fillColor: const Color(0xFF21182F),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<AceChannelModel>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                  ),
                );
              }
              if (snapshot.hasError) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.cloud_off_rounded,
                    color: Colors.orangeAccent,
                  ),
                  title: const Text(
                    'AceStream catalogue unavailable',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  trailing: IconButton(
                    onPressed: () {
                      setState(() {
                        _aceChannelsFuture = _sportsService.getAceChannels();
                      });
                    },
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                );
              }
              final query = _aceChannelQuery.trim().toLowerCase();
              final channels = (snapshot.data ?? const <AceChannelModel>[])
                  .where(
                    (channel) =>
                        query.isEmpty ||
                        channel.name.toLowerCase().contains(query),
                  )
                  .take(60)
                  .toList();
              if (channels.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text(
                      'No matching AceStream channels.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                );
              }
              return Column(
                children: channels.map((channel) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2B1F3E),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                    title: Text(
                      channel.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '${channel.infoHash.substring(0, 10)}… • Local engine',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () =>
                          AceStreamPlayerScreen.open(context, channel: channel),
                      child: const Text('Play'),
                    ),
                    onTap: () =>
                        AceStreamPlayerScreen.open(context, channel: channel),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // --- CODE CONVERT SCREEN ---
  Widget _buildCodeConvertScreen(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF27134A), Color(0xFF110724)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.published_with_changes_rounded,
                    color: Color(0xFFFFD700),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Code Converter Engine',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Convert booking codes between MSport, SportyBet, 1xBet, Bet9ja & more.',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181124),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF352752)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildPlatformDropdown(
                        label: 'From Bookie',
                        value: _convertSourcePlatform,
                        onChanged: (val) =>
                            setState(() => _convertSourcePlatform = val!),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.swap_horiz_rounded,
                        color: Color(0xFFFFD700),
                        size: 22,
                      ),
                    ),
                    Expanded(
                      child: _buildPlatformDropdown(
                        label: 'To Bookie',
                        value: _convertTargetPlatform,
                        onChanged: (val) =>
                            setState(() => _convertTargetPlatform = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF221735),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3E2C5B)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.qr_code_2_rounded,
                        color: Color(0xFFFFD700),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          onChanged: (val) => _convertCodeText = val,
                          controller:
                              TextEditingController(text: _convertCodeText)
                                ..selection = TextSelection.collapsed(
                                  offset: _convertCodeText.length,
                                ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Enter a real booking code',
                            hintStyle: TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _isConvertingCode ? null : _executeCodeConvert,
                    icon: _isConvertingCode
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0D0B12),
                            ),
                          )
                        : const Icon(
                            Icons.published_with_changes_rounded,
                            size: 18,
                          ),
                    label: Text(
                      _isConvertingCode
                          ? 'Converting...'
                          : 'Convert Booking Code Now',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: const Color(0xFF0D0B12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_codeConvertResult != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF181124),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Converted Code',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _codeConvertResult!['convertedCode'] as String,
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(
                              text:
                                  _codeConvertResult!['convertedCode']
                                      as String,
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Code Copied!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text('Copy'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2F2445),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF352752), height: 24),
                  Text(
                    '${_codeConvertResult!['convertedOk']}/${_codeConvertResult!['totalGames']} selections converted',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms),
          ],
        ],
      ),
    );
  }

  void _executeCodeConvert() async {
    if (_convertCodeText.trim().isEmpty) return;
    setState(() {
      _isConvertingCode = true;
      _codeConvertResult = null;
    });

    try {
      final result = await _fplDuelService.convertBetCode(
        from: _convertSourcePlatform.toLowerCase(),
        to: _convertTargetPlatform.toLowerCase(),
        code: _convertCodeText.trim(),
      );
      final targetCode = result['targetCode']?.toString().trim() ?? '';
      if (targetCode.isEmpty) {
        throw Exception('The converter did not return a booking code.');
      }
      if (!mounted) return;
      setState(() {
        _isConvertingCode = false;
        _codeConvertResult = {
          'convertedCode': targetCode,
          'totalGames': (result['totalGames'] as num?)?.toInt() ?? 0,
          'convertedOk': (result['convertedOk'] as num?)?.toInt() ?? 0,
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isConvertingCode = false;
        _codeConvertResult = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFF32131C),
        ),
      );
    }
  }

  // --- BOTTOM NAVIGATION BAR ---
  Widget _buildBottomNavBar() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Container(
        height: 64,
        decoration: const BoxDecoration(
          color: Color(0xFF140F1D),
          border: Border(top: BorderSide(color: Color(0xFF2C2042), width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // 1. Matches
            Expanded(
              child: _buildBottomNavItem(
                index: 0,
                label: 'Matches',
                icon: Icons.sports_soccer_rounded,
                onTap: () {
                  setState(() {
                    _bottomNavIndex = 0;
                    _topTabNavIndex = 0;
                  });
                },
              ),
            ),

            // 2. Prediction
            Expanded(
              child: _buildBottomNavItem(
                index: 1,
                label: 'Prediction',
                icon: Icons.auto_awesome_rounded,
                onTap: () {
                  setState(() {
                    _bottomNavIndex = 1;
                    _topTabNavIndex = 4;
                  });
                  _loadPopularPredictions(_popularFilterIndex);
                },
              ),
            ),

            // 3. Feeds
            Expanded(
              child: _buildBottomNavItem(
                index: 2,
                label: 'Feeds',
                icon: Icons.dynamic_feed_rounded,
                onTap: () {
                  setState(() {
                    _bottomNavIndex = 2;
                    _topTabNavIndex = 5;
                  });
                },
              ),
            ),

            // 4. LiveTv
            Expanded(
              child: _buildBottomNavItem(
                index: 3,
                label: 'LiveTv',
                icon: Icons.live_tv_rounded,
                onTap: () {
                  setState(() {
                    _bottomNavIndex = 3;
                    _topTabNavIndex = 6;
                    _selectedStreamIndex = -1;
                  });
                  unawaited(_loadLiveStreams());
                },
              ),
            ),

            // 5. SlipIQ (AI Booking Code Analyzer)
            Expanded(
              child: _buildBottomNavItem(
                index: 4,
                label: 'SlipIQ',
                icon: Icons.analytics_rounded,
                onTap: () {
                  setState(() {
                    _bottomNavIndex = 4;
                    _topTabNavIndex = 7;
                  });
                },
              ),
            ),

            // 6. Code Convert (Cross-Bookie Converter)
            Expanded(
              child: _buildBottomNavItem(
                index: 5,
                label: 'Code Convert',
                icon: Icons.published_with_changes_rounded,
                onTap: () {
                  setState(() {
                    _bottomNavIndex = 5;
                    _topTabNavIndex = 8;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required int index,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isSelected = _bottomNavIndex == index;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 21,
              color: isSelected ? const Color(0xFFFFD700) : Colors.white54,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFFD700) : Colors.white54,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformDropdown({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    final platforms = [
      'MSport',
      'SportyBet',
      '1xBet',
      'Bet9ja',
      'BetKing',
      '22Bet',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E162B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF382954)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E162B),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white54,
                size: 18,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              items: platforms.map((p) {
                return DropdownMenuItem(value: p, child: Text(p));
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  String _ticketCreatedLabel(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour == 0
        ? 12
        : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return 'Created ${date.day} ${months[date.month - 1]} ${date.year}, $hour:$minute $period';
  }

  Widget _buildCommunitySlipsView(bool isMobile) {
    final statusList = ['all', 'pending', 'won', 'lost', 'void'];
    final statusLabels = [
      'All Slips',
      '⏳ Pending',
      '🏆 Won',
      '❌ Lost',
      '⚪ Void',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Community Slips Header & Refresh Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF221639),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.confirmation_number_outlined,
                  size: 16,
                  color: Color(0xFFFFD700),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Community Slips',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Auto-settled in real time',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () =>
                    _loadCommunityTickets(_communityTicketStatusFilter),
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFFFFD700),
                  size: 20,
                ),
                tooltip: 'Refresh Slips Feed',
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Status Sub-filter Chips
        SizedBox(
          height: 32,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: statusList.length,
            itemBuilder: (context, idx) {
              final val = statusList[idx];
              final isSel = _communityTicketStatusFilter == val;
              return GestureDetector(
                onTap: () => _loadCommunityTickets(val),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSel
                        ? const Color(0xFFFFD700)
                        : const Color(0xFF1B112B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSel
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF352752),
                    ),
                  ),
                  child: Text(
                    statusLabels[idx],
                    style: TextStyle(
                      color: isSel ? const Color(0xFF0D0B12) : Colors.white70,
                      fontSize: 11,
                      fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 14),

        if (_loadingCommunityTickets)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(color: Color(0xFFFFD700)),
            ),
          )
        else if (_communityTickets.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF181124),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF352752)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white24,
                  size: 40,
                ),
                const SizedBox(height: 10),
                const Text(
                  'No community slips found',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'When users select picks and generate booking codes, their slips appear here!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        else
          ..._communityTickets.map((ticket) {
            Color statusColor;
            IconData statusIcon;
            String statusText = ticket.status.toUpperCase();
            if (statusText.isEmpty) statusText = 'PENDING';
            final normalizedTitle = ticket.title.trim().toLowerCase();
            final showTitle =
                normalizedTitle != 'ai consensus slip' &&
                normalizedTitle != 'ai concensus slip';

            switch (statusText) {
              case 'WON':
                statusColor = const Color(0xFF00E676);
                statusIcon = Icons.check_circle_rounded;
                break;
              case 'LOST':
                statusColor = const Color(0xFFFF5252);
                statusIcon = Icons.cancel_rounded;
                break;
              case 'VOID':
                statusColor = Colors.grey;
                statusIcon = Icons.block_rounded;
                break;
              default:
                statusColor = const Color(0xFFFFD700);
                statusIcon = Icons.hourglass_top_rounded;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF181124),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ticket Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF201633),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFFD700,
                                  ).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  ticket.platform.toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (showTitle) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ticket.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: statusColor, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 12, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_ticketCreatedLabel(ticket.createdAt).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 7, 14, 0),
                      child: Text(
                        _ticketCreatedLabel(ticket.createdAt),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ),

                  // Booking Code & Odds Banner
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (ticket.bookingCode.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: ticket.bookingCode),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Booking code "${ticket.bookingCode}" copied to clipboard!',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF281C3D),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFFD700,
                                  ).withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.copy_rounded,
                                    color: Color(0xFFFFD700),
                                    size: 13,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    ticket.bookingCode,
                                    style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          const SizedBox(),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF281C3D),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${ticket.itemCount} Picks',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B1E54),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Odds: ${ticketOddsLabel(ticket.totalOdds)}',
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Selections List
                  if (ticket.selections.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        children: ticket.selections.map((sel) {
                          Color pickColor;
                          String pStatus = sel.status.toUpperCase();
                          if (pStatus == 'WON') {
                            pickColor = const Color(0xFF00E676);
                          } else if (pStatus == 'LOST') {
                            pickColor = const Color(0xFFFF5252);
                          } else if (pStatus == 'VOID') {
                            pickColor = Colors.grey;
                          } else {
                            pickColor = const Color(0xFFFFD700);
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF130D1D),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${sel.homeTeam} vs ${sel.awayTeam}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (sel.leagueName.isNotEmpty)
                                        Text(
                                          sel.leagueName,
                                          style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 10,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF281C3D),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${sel.marketType}: ${sel.selection}',
                                    style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  ticketOddsLabel(sel.odds),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: pickColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // Card Footer / Load to Bucket Button
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          int added = 0;
                          setState(() {
                            for (final s in ticket.selections) {
                              final key = s.uniqueKey;
                              if (!_selectedTicketItems.containsKey(key)) {
                                _selectedOddsKeys.add(key);
                                _selectedTicketItems[key] = s;
                                added++;
                              }
                            }
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF281C3D),
                              content: Text(
                                'Added $added picks from slip to your BetSlip!',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.playlist_add_rounded,
                          size: 16,
                          color: Color(0xFFFFD700),
                        ),
                        label: const Text(
                          'Load Slip to My BetSlip',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: const Color(
                              0xFFFFD700,
                            ).withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildUserPicksStreamView(bool isMobile) {
    final statusList = ['all', 'pending', 'won', 'lost', 'void'];
    final statusLabels = [
      'All Picks',
      '⏳ Pending',
      '🏆 Won',
      '❌ Lost',
      '⚪ Void',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status Sub-filter Chips & Refresh
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 32,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: statusList.length,
                  itemBuilder: (context, idx) {
                    final val = statusList[idx];
                    final isSel = _userPickStatusFilter == val;
                    return GestureDetector(
                      onTap: () => _loadUserPicksStream(val),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? const Color(0xFFFFD700)
                              : const Color(0xFF1B112B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSel
                                ? const Color(0xFFFFD700)
                                : const Color(0xFF352752),
                          ),
                        ),
                        child: Text(
                          statusLabels[idx],
                          style: TextStyle(
                            color: isSel
                                ? const Color(0xFF0D0B12)
                                : Colors.white70,
                            fontSize: 11,
                            fontWeight: isSel
                                ? FontWeight.w900
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            IconButton(
              onPressed: () => _loadUserPicksStream(_userPickStatusFilter),
              icon: const Icon(
                Icons.refresh_rounded,
                color: Color(0xFFFFD700),
                size: 20,
              ),
              tooltip: 'Refresh Picks Stream',
            ),
          ],
        ),

        const SizedBox(height: 14),

        if (_loadingUserPicksStream)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(color: Color(0xFFFFD700)),
            ),
          )
        else if (_userPicksStream.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF181124),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF352752)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.sports_soccer_rounded,
                  color: Colors.white24,
                  size: 40,
                ),
                const SizedBox(height: 10),
                const Text(
                  'No picks found in stream',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'User generated picks and selections will show up in this live feed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        else
          ..._userPicksStream.map((pick) {
            Color statusColor;
            String pStatus = pick.status.toUpperCase();
            if (pStatus.isEmpty) pStatus = 'PENDING';
            if (pStatus == 'WON') {
              statusColor = const Color(0xFF00E676);
            } else if (pStatus == 'LOST') {
              statusColor = const Color(0xFFFF5252);
            } else if (pStatus == 'VOID') {
              statusColor = Colors.grey;
            } else {
              statusColor = const Color(0xFFFFD700);
            }

            final isAdded = _selectedTicketItems.containsKey(
              pick.toSelectionModel().uniqueKey,
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF181124),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF352752)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${pick.homeTeam} vs ${pick.awayTeam}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (pick.leagueName.isNotEmpty) ...[
                              Flexible(
                                child: Text(
                                  pick.leagueName,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (pick.bookingCode.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFFD700,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  pick.bookingCode,
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_ticketCreatedLabel(pick.createdAt).isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            _ticketCreatedLabel(pick.createdAt),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF281C3D),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${pick.marketType}: ${pick.selection}',
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B1E54),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Odds ${ticketOddsLabel(pick.odds)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            // Status Pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: statusColor,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                pStatus,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Add to BetSlip Button
                  IconButton(
                    onPressed: () {
                      final sel = pick.toSelectionModel();
                      final key = sel.uniqueKey;
                      setState(() {
                        if (_selectedTicketItems.containsKey(key)) {
                          _selectedTicketItems.remove(key);
                          _selectedOddsKeys.remove(key);
                        } else {
                          _selectedTicketItems[key] = sel;
                          _selectedOddsKeys.add(key);
                        }
                      });
                    },
                    icon: Icon(
                      isAdded
                          ? Icons.check_circle_rounded
                          : Icons.add_circle_outline_rounded,
                      color: isAdded
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFFD700),
                      size: 24,
                    ),
                    tooltip: isAdded ? 'Remove from BetSlip' : 'Add to BetSlip',
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
