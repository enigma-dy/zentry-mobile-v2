import 'package:flutter/material.dart';

import 'ads/ad_slot.dart';
import 'models/fixture_model.dart';
import 'models/home_markets.dart';
import 'services/sports_service.dart';
import 'live_stream_sheet.dart';

class MatchDetailScreen extends StatefulWidget {
  final String fixtureId;
  final FixtureModel? initialFixture;
  final Function(
    String fixtureId,
    String marketKey,
    String selection,
    double odds,
  )?
  onToggleOdd;
  final bool Function(String fixtureId, String marketKey, String selection)?
  isOddSelected;

  const MatchDetailScreen({
    super.key,
    required this.fixtureId,
    this.initialFixture,
    this.onToggleOdd,
    this.isOddSelected,
  });

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SportsService _sportsService = SportsService();

  bool _isLoading = true;
  String? _errorMessage;
  EnrichedFixtureDetailModel? _enrichedDetail;
  FixtureStreamsModel? _fixtureStreams;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadFixtureDetail();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDateShort(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = (date.year % 100).toString().padLeft(2, '0');
    return '$d/$m/$y';
  }

  String _formatMatchTime(DateTime time) {
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const monthNames = [
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
    final local = time.toLocal();
    final w = weekdayNames[(local.weekday - 1) % 7];
    final m = monthNames[(local.month - 1) % 12];
    final d = local.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$w, $d $m • $hh:$mm';
  }

  String _formatFullDate(DateTime time) {
    const weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final local = time.toLocal();
    final w = weekdayNames[(local.weekday - 1) % 7];
    final m = monthNames[(local.month - 1) % 12];
    final d = local.day;
    final y = local.year;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$w, $d $m $y $hh:$mm';
  }

  Future<void> _loadFixtureDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detail = await _sportsService.getFixtureDetail(
        widget.fixtureId,
        includeStreams: true,
        refresh: true,
        timeout: const Duration(seconds: 20),
      );
      FixtureStreamsModel? streams = detail.streams;
      if (streams == null || !streams.hasStreams) {
        try {
          streams = await _sportsService.getFixtureStreams(
            widget.fixtureId,
            timeout: const Duration(seconds: 3),
          );
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _enrichedDetail = streams != null && streams.hasStreams
              ? detail.copyWithStreams(streams)
              : detail;
          _fixtureStreams = streams;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0F1D) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF131B2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final mutedTextColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final fx = _enrichedDetail?.fixture ?? widget.initialFixture;

    return Scaffold(
      bottomNavigationBar: const AdSlot(placement: AdPlacement.match),
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fx?.leagueName ?? 'Match Details',
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (fx != null && fx.country.isNotEmpty)
              Text(
                fx.country.toUpperCase(),
                style: TextStyle(
                  color: mutedTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: textColor),
            onPressed: _loadFixtureDetail,
            tooltip: 'Refresh Match Data',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF00E676)),
                  SizedBox(height: 16),
                  Text(
                    'Loading live match data...',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Checking available fixture providers',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ],
              ),
            )
          : fx == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load match details',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage ??
                          'Match information could not be retrieved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedTextColor, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _loadFixtureDetail,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    color: Colors.amber.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Using cached match data: $_errorMessage',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Header Scoreboard Card
                _buildHeaderScoreboard(
                  fx,
                  cardColor,
                  textColor,
                  mutedTextColor,
                ),
                // Tab Bar
                Container(
                  color: cardColor,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFF00E676),
                    indicatorWeight: 3,
                    labelColor: const Color(0xFF00E676),
                    unselectedLabelColor: mutedTextColor,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    tabs: const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Stats'),
                      Tab(text: 'H2H'),
                      Tab(text: 'Timeline'),
                    ],
                  ),
                ),
                // Tab Bar Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(
                        fx,
                        cardColor,
                        textColor,
                        mutedTextColor,
                      ),
                      _buildStatsTab(cardColor, textColor, mutedTextColor),
                      _buildH2HTab(fx, cardColor, textColor, mutedTextColor),
                      _buildTimelineTab(cardColor, textColor, mutedTextColor),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderScoreboard(
    FixtureModel fx,
    Color cardColor,
    Color textColor,
    Color mutedTextColor,
  ) {
    final isLive = fx.isLive;
    final timeStr = _formatMatchTime(fx.matchTime);
    final periodScores = _enrichedDetail?.periodScores ?? {};
    final streamInfo = _fixtureStreams ?? _enrichedDetail?.streams;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        children: [
          // Live/Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isLive
                  ? Colors.redAccent.withValues(alpha: 0.15)
                  : const Color(0xFF00E676).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLive ? Colors.redAccent : const Color(0xFF00E676),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLive) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  isLive ? 'LIVE' : fx.status.toUpperCase(),
                  style: TextStyle(
                    color: isLive ? Colors.redAccent : const Color(0xFF00E676),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Scoreboard layout (Home vs Away)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Home Team
              Expanded(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFF00E676)
                          .withValues(alpha: 0.2),
                      child: Text(
                        fx.homeTeam.isNotEmpty ? fx.homeTeam[0] : 'H',
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fx.homeTeam,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Score Box
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A243B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '${fx.homeScore} - ${fx.awayScore}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeStr,
                      style: TextStyle(color: mutedTextColor, fontSize: 11),
                    ),
                  ],
                ),
              ),

              // Away Team
              Expanded(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFF00B0FF)
                          .withValues(alpha: 0.2),
                      child: Text(
                        fx.awayTeam.isNotEmpty ? fx.awayTeam[0] : 'A',
                        style: const TextStyle(
                          color: Color(0xFF00B0FF),
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fx.awayTeam,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Period Scores Row
          if (periodScores.isNotEmpty) ...[
            const SizedBox(height: 14),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: periodScores.entries.map((entry) {
                  final label = entry.key.replaceAll('_', ' ').toUpperCase();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$label: ${entry.value}',
                      style: TextStyle(
                        color: mutedTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          // Live Streaming Action Button
          if (streamInfo?.hasStreams == true) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () {
                final event = streamInfo?.primaryEvent;
                if (event != null) {
                  LiveStreamSheet.show(
                    context,
                    streamEvent: event,
                    matchTitle: '${fx.homeTeam} vs ${fx.awayTeam}',
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFFB81D24)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE50914).withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.live_tv_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'WATCH LIVE STREAM',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white70,
                      size: 12,
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

  // --- OVERVIEW TAB ---
  Widget _buildOverviewTab(
    FixtureModel fx,
    Color cardColor,
    Color textColor,
    Color mutedTextColor,
  ) {
    final markets = fx.effectiveMarkets;
    final oneXTwo = markets.oneXTwo;
    final overUnder = markets.overUnder;
    final bothTeamsToScore = markets.bothTeamsToScore;
    final homeOdds =
        double.tryParse(oneXTwo?.home ?? '') ?? double.tryParse(fx.odd1);
    final drawOdds =
        double.tryParse(oneXTwo?.draw ?? '') ?? double.tryParse(fx.oddX);
    final awayOdds =
        double.tryParse(oneXTwo?.away ?? '') ?? double.tryParse(fx.odd2);
    final overOdds = double.tryParse(overUnder['over'] ?? '');
    final underOdds = double.tryParse(overUnder['under'] ?? '');
    final goalLine = overUnder['line'] ?? '2.5';
    final yesOdds = double.tryParse(bothTeamsToScore['yes'] ?? '');
    final noOdds = double.tryParse(bothTeamsToScore['no'] ?? '');
    final hasAnyMarket =
        (homeOdds != null && drawOdds != null && awayOdds != null) ||
        (overOdds != null && underOdds != null) ||
        (yesOdds != null && noOdds != null);
    final streamInfo = _fixtureStreams ?? _enrichedDetail?.streams;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live Video Stream Broadcast Card
          if (streamInfo?.hasStreams == true) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1F0D42), Color(0xFF38105E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Colors.white, size: 7),
                            SizedBox(width: 4),
                            Text(
                              'LIVE FEED AVAILABLE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.hd_rounded,
                        color: Color(0xFFFFD700),
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Real-Time Match Broadcast',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Native HLS or DASH streaming is available for this match.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final event = streamInfo?.primaryEvent;
                        if (event != null) {
                          LiveStreamSheet.show(
                            context,
                            streamEvent: event,
                            matchTitle: '${fx.homeTeam} vs ${fx.awayTeam}',
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 20,
                      ),
                      label: const Text('Open Stream Player'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: const Color(0xFF0D0B12),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (fx.prediction != null &&
              fx.prediction!.prediction.isNotEmpty) ...[
            Builder(
              builder: (context) {
                final pred = fx.prediction!;
                final isPredSelected =
                    widget.isOddSelected?.call(
                      widget.fixtureId,
                      'PREDICTION',
                      pred.prediction,
                    ) ??
                    false;
                final predOdds = double.tryParse(
                  fx.sportId == 1
                      ? homePredictionOdds(fx, pred, 'football')
                      : fx.oddsForPrediction(pred),
                );
                final predProbability = homePredictionProbability(
                  fx,
                  pred,
                  'football',
                );
                final predReview = homePredictionProbabilityReview(
                  fx,
                  pred,
                  'football',
                );

                return InkWell(
                  onTap: predOdds == null
                      ? null
                      : () {
                          if (widget.onToggleOdd != null) {
                            widget.onToggleOdd!(
                              widget.fixtureId,
                              'PREDICTION',
                              pred.prediction,
                              predOdds,
                            );
                            setState(() {});
                          }
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isPredSelected
                          ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                          : const Color(0xFF00E676).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isPredSelected
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF00E676).withValues(alpha: 0.35),
                        width: isPredSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isPredSelected
                              ? Icons.check_circle_rounded
                              : Icons.auto_awesome,
                          color: isPredSelected
                              ? const Color(0xFFFFD700)
                              : const Color(0xFF00E676),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Prediction: ${pred.prediction}',
                                    style: TextStyle(
                                      color: isPredSelected
                                          ? const Color(0xFFFFD700)
                                          : textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (isPredSelected) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD700),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'ADDED',
                                        style: TextStyle(
                                          color: Color(0xFF0D0B12),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (predProbability != null)
                                Text(
                                  predReview != null
                                      ? 'Estimate under review: model $predProbability%; odds imply ${predReview.rawImpliedProbability.toStringAsFixed(1)}% (before margin adjustment).'
                                      : '$predProbability% probability • Tap to ${isPredSelected ? "remove from" : "add to"} ticket bucket',
                                  style: TextStyle(
                                    color: mutedTextColor,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isPredSelected
                                ? const Color(0xFFFFD700)
                                : const Color(0xFF2E2245),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            predOdds == null
                                ? 'Odds unavailable'
                                : '@${fx.oddsForPrediction(pred)}',
                            style: TextStyle(
                              color: isPredSelected
                                  ? const Color(0xFF0D0B12)
                                  : const Color(0xFFFFD700),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
          ],
          if (homeOdds != null && drawOdds != null && awayOdds != null) ...[
            _buildMarketHeader('1X2 Match Result', textColor),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildOddsButton(
                    label: 'Home (${fx.homeTeam})',
                    oddsVal: homeOdds,
                    marketKey: '1X2',
                    selection: '1',
                    cardColor: cardColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildOddsButton(
                    label: 'Draw',
                    oddsVal: drawOdds,
                    marketKey: '1X2',
                    selection: 'X',
                    cardColor: cardColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildOddsButton(
                    label: 'Away (${fx.awayTeam})',
                    oddsVal: awayOdds,
                    marketKey: '1X2',
                    selection: '2',
                    cardColor: cardColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          if (overOdds != null && underOdds != null) ...[
            _buildMarketHeader('Over / Under $goalLine Goals', textColor),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildOddsButton(
                    label: 'Over $goalLine',
                    oddsVal: overOdds,
                    marketKey: 'OU$goalLine',
                    selection: 'Over',
                    cardColor: cardColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOddsButton(
                    label: 'Under $goalLine',
                    oddsVal: underOdds,
                    marketKey: 'OU$goalLine',
                    selection: 'Under',
                    cardColor: cardColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          if (yesOdds != null && noOdds != null) ...[
            _buildMarketHeader('Both Teams to Score (GG/NG)', textColor),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildOddsButton(
                    label: 'Yes (GG)',
                    oddsVal: yesOdds,
                    marketKey: 'BTTS',
                    selection: 'Yes',
                    cardColor: cardColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOddsButton(
                    label: 'No (NG)',
                    oddsVal: noOdds,
                    marketKey: 'BTTS',
                    selection: 'No',
                    cardColor: cardColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                  ),
                ),
              ],
            ),
          ],
          if (!hasAnyMarket)
            _buildEmptyDataMessage(
              'Betting markets are not available for this fixture.',
              mutedTextColor,
            ),
          const SizedBox(height: 24),

          // Match Information Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MATCH INFORMATION',
                  style: TextStyle(
                    color: mutedTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'League',
                  fx.leagueName,
                  textColor,
                  mutedTextColor,
                ),
                const Divider(height: 16, color: Colors.white10),
                _buildInfoRow(
                  'Country',
                  fx.country.isEmpty ? 'Global' : fx.country,
                  textColor,
                  mutedTextColor,
                ),
                const Divider(height: 16, color: Colors.white10),
                _buildInfoRow(
                  'Kickoff Time',
                  _formatFullDate(fx.matchTime),
                  textColor,
                  mutedTextColor,
                ),
                const Divider(height: 16, color: Colors.white10),
                _buildInfoRow(
                  'Status',
                  fx.status.toUpperCase(),
                  textColor,
                  mutedTextColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketHeader(String title, Color textColor) {
    return Text(
      title,
      style: TextStyle(
        color: textColor,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildOddsButton({
    required String label,
    required double oddsVal,
    required String marketKey,
    required String selection,
    required Color cardColor,
    required Color textColor,
    required Color mutedTextColor,
  }) {
    final isSelected =
        widget.isOddSelected?.call(widget.fixtureId, marketKey, selection) ??
        false;

    return InkWell(
      onTap: () {
        if (widget.onToggleOdd != null) {
          widget.onToggleOdd!(widget.fixtureId, marketKey, selection, oddsVal);
          setState(() {});
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E676) : cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00E676)
                : Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.black : mutedTextColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              oddsVal.toStringAsFixed(2),
              style: TextStyle(
                color: isSelected ? Colors.black : const Color(0xFF00E676),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    Color textColor,
    Color mutedTextColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: mutedTextColor, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // --- STATS TAB ---
  Widget _buildStatsTab(
    Color cardColor,
    Color textColor,
    Color mutedTextColor,
  ) {
    final stats = _enrichedDetail?.stats ?? const MatchStatsModel();
    final hasStats = [
      stats.possessionHome,
      stats.possessionAway,
      stats.shotsOnTargetHome,
      stats.shotsOnTargetAway,
      stats.totalShotsHome,
      stats.totalShotsAway,
      stats.cornersHome,
      stats.cornersAway,
      stats.yellowCardsHome,
      stats.yellowCardsAway,
      stats.redCardsHome,
      stats.redCardsAway,
      stats.foulsHome,
      stats.foulsAway,
      stats.offsidesHome,
      stats.offsidesAway,
    ].any((value) => value != 0);

    if (!hasStats) {
      return _buildEmptyDataMessage(
        'Match statistics are not available yet.',
        mutedTextColor,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            _buildStatBarRow(
              'Possession %',
              stats.possessionHome,
              stats.possessionAway,
              textColor,
              isPercent: true,
            ),
            const SizedBox(height: 18),
            _buildStatBarRow(
              'Shots on Target',
              stats.shotsOnTargetHome,
              stats.shotsOnTargetAway,
              textColor,
            ),
            const SizedBox(height: 18),
            _buildStatBarRow(
              'Total Shots',
              stats.totalShotsHome,
              stats.totalShotsAway,
              textColor,
            ),
            const SizedBox(height: 18),
            _buildStatBarRow(
              'Corner Kicks',
              stats.cornersHome,
              stats.cornersAway,
              textColor,
            ),
            const SizedBox(height: 18),
            _buildStatBarRow(
              'Yellow Cards',
              stats.yellowCardsHome,
              stats.yellowCardsAway,
              textColor,
            ),
            const SizedBox(height: 18),
            _buildStatBarRow(
              'Red Cards',
              stats.redCardsHome,
              stats.redCardsAway,
              textColor,
            ),
            const SizedBox(height: 18),
            _buildStatBarRow(
              'Fouls',
              stats.foulsHome,
              stats.foulsAway,
              textColor,
            ),
            const SizedBox(height: 18),
            _buildStatBarRow(
              'Offsides',
              stats.offsidesHome,
              stats.offsidesAway,
              textColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBarRow(
    String title,
    int homeVal,
    int awayVal,
    Color textColor, {
    bool isPercent = false,
  }) {
    final total = homeVal + awayVal;
    final homePct = total > 0 ? (homeVal / total) : 0.5;
    final awayPct = total > 0 ? (awayVal / total) : 0.5;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isPercent ? '$homeVal%' : '$homeVal',
              style: const TextStyle(
                color: Color(0xFF00E676),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              isPercent ? '$awayVal%' : '$awayVal',
              style: const TextStyle(
                color: Color(0xFF00B0FF),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              Expanded(
                flex: (homePct * 100).round().clamp(1, 99),
                child: Container(height: 8, color: const Color(0xFF00E676)),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: (awayPct * 100).round().clamp(1, 99),
                child: Container(height: 8, color: const Color(0xFF00B0FF)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyDataMessage(String message, Color mutedTextColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: mutedTextColor, fontSize: 14),
        ),
      ),
    );
  }

  // --- H2H TAB ---
  Widget _buildH2HTab(
    FixtureModel fx,
    Color cardColor,
    Color textColor,
    Color mutedTextColor,
  ) {
    final h2h = _enrichedDetail?.h2h ?? const H2HSummaryModel();

    final total = h2h.totalMatches > 0 ? h2h.totalMatches : 1;
    final homeWinRatio = h2h.homeWins / total;
    final drawRatio = h2h.draws / total;
    final awayWinRatio = h2h.awayWins / total;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HEAD TO HEAD SUMMARY',
                  style: TextStyle(
                    color: mutedTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildH2HCounter(
                      'Home Wins',
                      h2h.homeWins,
                      const Color(0xFF00E676),
                    ),
                    _buildH2HCounter('Draws', h2h.draws, Colors.amberAccent),
                    _buildH2HCounter(
                      'Away Wins',
                      h2h.awayWins,
                      const Color(0xFF00B0FF),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: (homeWinRatio * 100).round().clamp(1, 98),
                        child: Container(
                          height: 8,
                          color: const Color(0xFF00E676),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        flex: (drawRatio * 100).round().clamp(1, 98),
                        child: Container(height: 8, color: Colors.amberAccent),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        flex: (awayWinRatio * 100).round().clamp(1, 98),
                        child: Container(
                          height: 8,
                          color: const Color(0xFF00B0FF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Matches List Header
          Text(
            'PAST MEETINGS (${h2h.matches.length})',
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          if (h2h.matches.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'No historical meeting records found.',
                  style: TextStyle(color: mutedTextColor, fontSize: 13),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: h2h.matches.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final match = h2h.matches[index];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Date
                      SizedBox(
                        width: 70,
                        child: Text(
                          _formatDateShort(match.date),
                          style: TextStyle(color: mutedTextColor, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Teams & Score
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${match.homeTeam} vs ${match.awayTeam}',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              match.leagueName,
                              style: TextStyle(
                                color: mutedTextColor,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Score Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A243B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${match.homeScore} - ${match.awayScore}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildH2HCounter(String title, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // --- TIMELINE / COMMENTARY TAB ---
  Widget _buildTimelineTab(
    Color cardColor,
    Color textColor,
    Color mutedTextColor,
  ) {
    final events = _enrichedDetail?.timeline ?? [];

    if (events.isEmpty) {
      return Center(
        child: Text(
          'No match events recorded yet.',
          style: TextStyle(color: mutedTextColor, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isSystem = event.team == 'system';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Minute indicator
              SizedBox(
                width: 44,
                child: Text(
                  isSystem ? '---' : "${event.minute}'",
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              // Icon Badge
              _buildEventIcon(event.type),
              const SizedBox(width: 12),
              // Event details card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: event.type == 'goal'
                          ? const Color(0xFF00E676).withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              event.playerName.isNotEmpty
                                  ? event.playerName
                                  : event.detail,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (event.currentScore.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676)
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                event.currentScore,
                                style: const TextStyle(
                                  color: Color(0xFF00E676),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (event.playerName.isNotEmpty &&
                          event.detail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          event.detail,
                          style: TextStyle(color: mutedTextColor, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEventIcon(String type) {
    switch (type.toLowerCase()) {
      case 'goal':
        return const CircleAvatar(
          radius: 14,
          backgroundColor: Color(0xFF00E676),
          child: Icon(Icons.sports_soccer, size: 16, color: Colors.black),
        );
      case 'card_yellow':
        return Container(
          width: 16,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.amberAccent,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case 'card_red':
        return Container(
          width: 16,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case 'sub':
        return const CircleAvatar(
          radius: 14,
          backgroundColor: Color(0xFF00B0FF),
          child: Icon(Icons.swap_horiz, size: 16, color: Colors.black),
        );
      default:
        return const CircleAvatar(
          radius: 14,
          backgroundColor: Colors.white12,
          child: Icon(Icons.flag, size: 14, color: Colors.white70),
        );
    }
  }
}
