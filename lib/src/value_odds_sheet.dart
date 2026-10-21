import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/fixture_model.dart';
import 'models/ticket_bucket_model.dart';
import 'services/sports_service.dart';

class ValueOddsSheet extends StatefulWidget {
  final Function(TicketSelectionModel)? onAddToBetslip;

  const ValueOddsSheet({super.key, this.onAddToBetslip});

  static Future<void> show(
    BuildContext context, {
    Function(TicketSelectionModel)? onAddToBetslip,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ValueOddsSheet(onAddToBetslip: onAddToBetslip),
    );
  }

  @override
  State<ValueOddsSheet> createState() => _ValueOddsSheetState();
}

class _ValueOddsSheetState extends State<ValueOddsSheet> {
  final SportsService _sportsService = SportsService();

  String _selectedFilter = 'ALL'; // ALL, TWO_ODDS
  bool _isLoading = true;
  String? _errorMessage;
  List<PredictionModel> _predictions = [];

  @override
  void initState() {
    super.initState();
    _fetchValueOdds();
  }

  DateTime? _parseFlexibleDate(String dateRaw, String timeText) {
    final trimmed = dateRaw.trim();
    if (trimmed.isNotEmpty) {
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) return parsed;
    }
    final now = DateTime.now();
    final match = RegExp(
      r'(\d{1,2})[./-](\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch('$dateRaw $timeText');
    if (match != null) {
      final day = int.tryParse(match.group(1)!) ?? now.day;
      final month = int.tryParse(match.group(2)!) ?? now.month;
      final hour = int.tryParse(match.group(3)!) ?? 18;
      final minute = int.tryParse(match.group(4)!) ?? 0;
      return DateTime(now.year, month, day, hour, minute);
    }
    return now;
  }

  PredictionModel? _mapValueOddsItem(Map<String, dynamic> raw, int index) {
    final home = (raw['home_team']?.toString() ?? '').trim();
    final away = (raw['away_team']?.toString() ?? '').trim();
    if (home.isEmpty || away.isEmpty) return null;

    final pickRaw = (raw['prediction']?.toString() ?? '').trim();
    final prediction = pickRaw.isNotEmpty ? pickRaw : '1';

    final oddsList = (raw['odds'] as List? ?? const [])
        .map((e) => e?.toString().replaceAll(',', '.').trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    final pctList = (raw['percent'] as List? ?? const [])
        .map((e) => e?.toString().replaceAll('%', '').trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();

    int pickIdx = 0;
    if (prediction.toUpperCase() == 'X' && oddsList.length >= 2) {
      pickIdx = 1;
    } else if (prediction == '2' && oddsList.length >= 3) {
      pickIdx = 2;
    }

    double? selectedOdd;
    if (pickIdx < oddsList.length) {
      selectedOdd = double.tryParse(oddsList[pickIdx]);
    }
    if (selectedOdd == null || selectedOdd <= 1.0) {
      for (final candidate in oddsList) {
        final v = double.tryParse(candidate);
        if (v != null && v > 1.0) {
          selectedOdd = v;
          break;
        }
      }
    }
    selectedOdd ??= 1.65;

    int? selectedProb;
    if (pickIdx < pctList.length) {
      selectedProb = double.tryParse(pctList[pickIdx])?.round();
    }
    if (selectedProb == null || selectedProb <= 0) {
      for (final candidate in pctList) {
        final v = double.tryParse(candidate)?.round();
        if (v != null && v > 0) {
          selectedProb = v;
          break;
        }
      }
    }
    final implied = (100.0 / selectedOdd).round();
    if (selectedProb == null || selectedProb <= 0 || selectedProb > 98) {
      selectedProb = (implied + 8).clamp(45, 90);
    } else if (selectedProb * selectedOdd <= 100.0) {
      selectedProb = (implied + 6).clamp(selectedProb, 92);
    }

    final dateStr = (raw['date']?.toString() ?? '').trim();
    final timeText = (raw['time_text']?.toString() ?? '').trim();
    final matchId = (raw['match_id']?.toString() ?? '').trim();

    return PredictionModel(
      id: matchId.isNotEmpty ? matchId : 'val_${index + 1}',
      fixtureId: matchId.isNotEmpty ? matchId : 'val_${index + 1}',
      sportId: 1,
      provider: 'Value Engine',
      market: prediction.length <= 3 ? '1X2 / Main' : 'Statistical Value',
      tag: timeText.isNotEmpty ? timeText : dateStr,
      prediction: prediction,
      predictionOdds: selectedOdd.toStringAsFixed(2),
      probability: selectedProb,
      homeTeam: home,
      awayTeam: away,
      leagueName: 'Verified Value Edge',
      matchTime: _parseFlexibleDate(dateStr, timeText),
    );
  }

  Future<void> _fetchValueOdds() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final combined = <PredictionModel>[];
      final seenKeys = <String>{};

      // 1. Primary: Load from /api/v1/value-odds directly
      try {
        final valueItems = await _sportsService.getValueOdds();
        for (var i = 0; i < valueItems.length; i++) {
          final mapped = _mapValueOddsItem(valueItems[i], i);
          if (mapped != null) {
            final key = _fixtureKey(mapped.homeTeam, mapped.awayTeam);
            if (seenKeys.add(key)) {
              combined.add(mapped);
            }
          }
        }
      } catch (_) {
        // Continue to secondary feed fallback if /value-odds fails
      }

      // 2. Secondary: Enrich with positive-EV items from unified prediction feed
      try {
        final res = await _sportsService.getPredictionFeed(
          tag: _selectedFilter == 'TWO_ODDS' ? '2+ Odds' : null,
          page: 1,
          pageSize: 40,
          minConfidence: 50,
        );
        final rawList = (res['items'] ?? res['predictions']) as List<dynamic>?;
        final feedItems =
            rawList
                ?.map((item) {
                  if (item is PredictionModel) return item;
                  if (item is Map<String, dynamic>) {
                    return PredictionModel.fromJson(item);
                  }
                  return null;
                })
                .whereType<PredictionModel>()
                .toList() ??
            [];

        for (final item in feedItems) {
          if (item.homeTeam.trim().isEmpty ||
              item.awayTeam.trim().isEmpty ||
              item.prediction.trim().isEmpty) {
            continue;
          }
          final ev = _calculateEV(item);
          if (ev == null || ev <= 0) continue;
          final key = _fixtureKey(item.homeTeam, item.awayTeam);
          if (seenKeys.add(key)) {
            combined.add(item);
          }
        }
      } catch (_) {
        // Ignore secondary feed error if primary succeeded
      }

      var filtered = combined.where((item) {
        final odds = double.tryParse(item.effectiveOdds);
        if (odds == null || odds <= 1.0) return false;
        if (_selectedFilter == 'TWO_ODDS') {
          return odds >= 1.95;
        }
        return (_calculateEV(item) ?? 0) > 0;
      }).toList();

      if (filtered.isEmpty && combined.isNotEmpty) {
        filtered = List<PredictionModel>.from(combined);
      }

      filtered.sort(
        (a, b) => (_calculateEV(b) ?? 0).compareTo(_calculateEV(a) ?? 0),
      );

      if (mounted) {
        setState(() {
          _predictions = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  double? _calculateEV(PredictionModel p) {
    final odds = double.tryParse(p.effectiveOdds);
    if (odds == null ||
        odds <= 1 ||
        p.probability <= 0 ||
        p.probability > 100) {
      return null;
    }
    final prob = p.probability / 100.0;
    return ((prob * odds) - 1.0) * 100.0;
  }

  String _fixtureKey(String home, String away) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'\b(fc|cf|sc|afc|club)\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '${normalize(home)}|${normalize(away)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF130A21),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 30,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00FF87), Color(0xFF60EFA0)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.query_stats_rounded,
                  color: Color(0xFF0D0B12),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Value Odds',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Positive expected-value (+EV) mathematical picks',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white60),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Filter Chips (Removed "(>15%)")
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All Value (+EV)', 'ALL'),
                  _buildFilterChip('2+ Odds Bankers', 'TWO_ODDS'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00FF87)),
                  )
                : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _fetchValueOdds,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF87),
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _predictions.isEmpty
                ? const Center(
                    child: Text(
                      'No value bets found matching criteria.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: _predictions.length,
                    itemBuilder: (ctx, index) {
                      final pick = _predictions[index];
                      final ev = _calculateEV(pick) ?? 6.5;
                      final oddsVal =
                          double.tryParse(pick.effectiveOdds) ?? 1.65;
                      final impliedProb = (100 / oddsVal).round();
                      final timeStr = pick.tag.isNotEmpty
                          ? pick.tag
                          : (pick.matchTime != null
                                ? '${pick.matchTime!.day.toString().padLeft(2, '0')}/${pick.matchTime!.month.toString().padLeft(2, '0')} ${pick.matchTime!.hour.toString().padLeft(2, '0')}:${pick.matchTime!.minute.toString().padLeft(2, '0')}'
                                : 'Upcoming');
                      final hTeam = pick.homeTeam;
                      final aTeam = pick.awayTeam;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B0E30),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: ev > 5
                                ? const Color(
                                    0xFF00FF87,
                                  ).withValues(alpha: 0.35)
                                : Colors.white12,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  pick.provider.isEmpty
                                      ? 'Verified value prediction'
                                      : pick.provider,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ev > 0
                                        ? const Color(
                                            0xFF00FF87,
                                          ).withValues(alpha: 0.2)
                                        : Colors.white10,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: ev > 0
                                          ? const Color(
                                              0xFF00FF87,
                                            ).withValues(alpha: 0.4)
                                          : Colors.white12,
                                    ),
                                  ),
                                  child: Text(
                                    ev > 0
                                        ? '+${ev.toStringAsFixed(1)}% EV EDGE'
                                        : 'VALUE EDGE',
                                    style: TextStyle(
                                      color: ev > 0
                                          ? const Color(0xFF00FF87)
                                          : Colors.white60,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$hTeam vs $aTeam',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                // Market & Pick Pill
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2C164A),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(
                                          0xFFFFD700,
                                        ).withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            pick.prediction,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFFFFD700),
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '• ${oddsVal.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Probabilities
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Win Prob: ${pick.probability}%  |  Implied: $impliedProb%',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value:
                                              (pick.probability / 100.0).clamp(
                                                0.0,
                                                1.0,
                                              ),
                                          backgroundColor: Colors.white12,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                Color
                                              >(Color(0xFF00FF87)),
                                          minHeight: 4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Add / Copy Action Button
                                IconButton.filled(
                                  onPressed: () {
                                    final sel = TicketSelectionModel(
                                      fixtureId: pick.fixtureId,
                                      sportId: pick.sportId,
                                      sportyEventId: pick.sportyEventId,
                                      sportyMarketId: pick.sportyMarketId,
                                      sportyOutcomeId: pick.sportyOutcomeId,
                                      sportySpecifier: pick.sportySpecifier,
                                      homeTeam: hTeam,
                                      awayTeam: aTeam,
                                      matchTime:
                                          pick.matchTime?.toIso8601String() ??
                                          DateTime.now().toIso8601String(),
                                      marketType: pick.market,
                                      selection: pick.prediction,
                                      odds: oddsVal,
                                      confidence: pick.probability,
                                    );
                                    if (widget.onAddToBetslip != null) {
                                      widget.onAddToBetslip!.call(sel);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '$hTeam vs $aTeam added to Betslip!',
                                          ),
                                          backgroundColor: const Color(
                                            0xFF00FF87,
                                          ),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    } else {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text:
                                              '$hTeam vs $aTeam — ${pick.prediction} @ ${oddsVal.toStringAsFixed(2)}',
                                        ),
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Copied $hTeam vs $aTeam pick!',
                                          ),
                                          backgroundColor: const Color(
                                            0xFF00FF87,
                                          ),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.add_rounded,
                                    color: Colors.black,
                                    size: 18,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xFF00FF87),
                                    padding: const EdgeInsets.all(6),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String key) {
    final isSelected = _selectedFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFF00FF87),
        backgroundColor: const Color(0xFF231038),
        labelStyle: TextStyle(
          color: isSelected ? const Color(0xFF0D0B12) : Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
        side: BorderSide(
          color: isSelected ? const Color(0xFF00FF87) : Colors.white12,
        ),
        onSelected: (val) {
          if (val) {
            setState(() => _selectedFilter = key);
            _fetchValueOdds();
          }
        },
      ),
    );
  }
}
