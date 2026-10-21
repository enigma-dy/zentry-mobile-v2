import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/fixture_model.dart';
import 'models/ticket_bucket_model.dart';
import 'services/sports_service.dart';

class BetMachineSheet extends StatefulWidget {
  final Function(List<TicketSelectionModel>)? onAddToBetslip;

  const BetMachineSheet({super.key, this.onAddToBetslip});

  static Future<void> show(
    BuildContext context, {
    Function(List<TicketSelectionModel>)? onAddToBetslip,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BetMachineSheet(onAddToBetslip: onAddToBetslip),
    );
  }

  @override
  State<BetMachineSheet> createState() => _BetMachineSheetState();
}

class _BetMachineSheetState extends State<BetMachineSheet> {
  final SportsService _sportsService = SportsService();

  // Generator Options
  double _targetOdds = 10.0;
  int _matchCount = 5;
  String _riskLevel = 'BALANCED'; // SAFE, BALANCED, HIGH_RETURN
  String _preferredMarket = 'ALL'; // ALL, GOALS, BTTS, 1X2

  bool _isGenerating = false;
  String? _errorMessage;

  // Generated Ticket Result
  List<PredictionModel> _generatedPicks = [];
  double _actualOdds = 1.0;
  int _avgConfidence = 0;

  @override
  void initState() {
    super.initState();
    _generateTicket();
  }

  DateTime _parseMatchDateTime(String dateRaw, String timeRaw) {
    final now = DateTime.now();
    try {
      final dateParts = dateRaw.trim().split('-');
      final timeParts = timeRaw.trim().split(':');
      final year = dateParts.length == 3 ? int.parse(dateParts[0]) : now.year;
      final month = dateParts.length == 3 ? int.parse(dateParts[1]) : now.month;
      final day = dateParts.length == 3 ? int.parse(dateParts[2]) : now.day;
      final hour = timeParts.isNotEmpty ? int.parse(timeParts[0]) : 18;
      final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return now;
    }
  }

  String _inferMarketLabel(String insight) {
    final lower = insight.toLowerCase();
    if (lower.contains('over ') || lower.contains('under ') || lower.contains('goal')) {
      return 'GOALS STREAK';
    }
    if (lower.contains('both teams') || lower.contains('btts')) {
      return 'BTTS STREAK';
    }
    if (lower.contains('won') || lower.contains('unbeaten') || lower.contains('draw')) {
      return 'FORM STREAK';
    }
    return 'STATISTICAL EDGE';
  }

  bool _matchesPreferredMarket(PredictionModel p) {
    if (_preferredMarket == 'ALL') return true;
    final text = '${p.market} ${p.prediction} ${p.tag}'.toLowerCase();
    if (_preferredMarket == 'GOALS') {
      return text.contains('over') ||
          text.contains('under') ||
          text.contains('goal') ||
          text.contains('half');
    }
    if (_preferredMarket == 'BTTS') {
      return text.contains('btts') ||
          text.contains('both') ||
          text.contains('gg') ||
          text.contains('scored');
    }
    if (_preferredMarket == '1X2') {
      return text.contains('won') ||
          text.contains('win') ||
          text.contains('unbeaten') ||
          text.contains('draw');
    }
    return true;
  }

  Future<void> _generateTicket() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final minOdd = _riskLevel == 'SAFE'
          ? 1.18
          : (_riskLevel == 'BALANCED' ? 1.25 : 1.40);
      final maxOdd = _riskLevel == 'SAFE'
          ? 1.85
          : (_riskLevel == 'BALANCED' ? 3.20 : 5.00);

      var machine = await _sportsService.getBetMachine(
        totalOdds: _targetOdds.round().clamp(2, 1000),
        minOdd: minOdd,
        maxOdd: maxOdd,
        onlyToday: false,
      );

      var machineMatches = (machine['matches'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (machineMatches.isEmpty) {
        machine = await _sportsService.getBetMachine(
          totalOdds: 50,
          minOdd: 1.20,
          maxOdd: 5.00,
          onlyToday: false,
        );
        machineMatches = (machine['matches'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }

      if (machineMatches.isEmpty) {
        throw Exception('No BetMachine fixtures available right now. Try refreshing.');
      }

      final allPicks = <PredictionModel>[];
      for (var i = 0; i < machineMatches.length; i++) {
        final item = machineMatches[i];
        final home = (item['home_team']?.toString() ?? '').trim();
        final away = (item['away_team']?.toString() ?? '').trim();
        if (home.isEmpty || away.isEmpty) continue;

        final oddStr = (item['odd']?.toString() ?? '1.30').replaceAll(',', '.').trim();
        final oddVal = double.tryParse(oddStr) ?? 1.30;
        final insight = (item['insight']?.toString() ?? '').trim();
        final league = (item['league']?.toString() ?? '').trim();
        final matchDate = (item['match_date']?.toString() ?? '').trim();
        final matchTime = (item['match_time']?.toString() ?? '').trim();
        final fixtureId = (item['fixture_id']?.toString() ?? 'bm_${i + 1}').trim();

        final impliedConfidence = (100.0 / (oddVal > 1.0 ? oddVal : 1.30))
            .clamp(52.0, 92.0)
            .round();

        allPicks.add(
          PredictionModel(
            id: fixtureId.isNotEmpty ? fixtureId : 'bm_${i + 1}',
            fixtureId: fixtureId.isNotEmpty ? fixtureId : 'bm_${i + 1}',
            sportId: 1,
            sportyEventId: (item['sportybet_event_id']?.toString() ?? '').trim(),
            provider: 'BetMachine AI',
            market: _inferMarketLabel(insight),
            tag: matchDate.isNotEmpty ? '$matchDate • $matchTime' : matchTime,
            prediction: insight.isNotEmpty ? insight : 'Statistical Pick',
            predictionOdds: oddVal.toStringAsFixed(2),
            probability: impliedConfidence,
            homeTeam: home,
            awayTeam: away,
            leagueName: league.isNotEmpty ? league : 'H2H Statistical Edge',
            matchTime: _parseMatchDateTime(matchDate, matchTime),
          ),
        );
      }

      var filtered = allPicks.where(_matchesPreferredMarket).toList();
      if (filtered.isEmpty) {
        filtered = allPicks;
      }

      final selected = <PredictionModel>[];
      double currentCombinedOdds = 1.0;
      int totalConf = 0;

      for (final p in filtered) {
        if (selected.length >= _matchCount) break;
        final oddVal = double.tryParse(p.predictionOdds) ?? 1.30;
        selected.add(p);
        currentCombinedOdds *= oddVal;
        totalConf += p.probability;
      }

      if (selected.isEmpty) {
        throw Exception('No fixtures matched the current filter selection.');
      }

      final avgConf = (totalConf / selected.length).round();

      if (mounted) {
        setState(() {
          _generatedPicks = selected;
          _actualOdds = currentCombinedOdds;
          _avgConfidence = avgConf;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  void _copySlipSummary() {
    if (_generatedPicks.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln(
      '⚡ Zentry BetMachine Slip (${_actualOdds.toStringAsFixed(2)}x Total Odds)',
    );
    buffer.writeln('----------------------------------------');
    for (var i = 0; i < _generatedPicks.length; i++) {
      final p = _generatedPicks[i];
      buffer.writeln(
        '${i + 1}. ${p.homeTeam} vs ${p.awayTeam} (${p.tag})\n'
        '   Pick: ${p.prediction} @ ${p.predictionOdds}',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('BetMachine slip copied to clipboard!'),
        backgroundColor: Color(0xFF00FF87),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _loadAllToSlip() {
    if (_generatedPicks.isEmpty) return;

    final selections = _generatedPicks.map((p) {
      return TicketSelectionModel(
        fixtureId: p.fixtureId,
        sportId: p.sportId,
        sportyEventId: p.sportyEventId,
        sportyMarketId: p.sportyMarketId,
        sportyOutcomeId: p.sportyOutcomeId,
        sportySpecifier: p.sportySpecifier,
        homeTeam: p.homeTeam,
        awayTeam: p.awayTeam,
        matchTime: (p.matchTime ?? DateTime.now()).toIso8601String(),
        marketType: p.market,
        selection: p.prediction,
        odds: double.tryParse(p.predictionOdds) ?? 1.30,
        confidence: p.probability,
      );
    }).toList();

    if (widget.onAddToBetslip != null) {
      widget.onAddToBetslip!.call(selections);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${selections.length} BetMachine picks added to Betslip!',
          ),
          backgroundColor: const Color(0xFF00FF87),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      _copySlipSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF170B2C), Color(0xFF0D0718)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.18),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 36,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 46,
              height: 4,
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
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF0D0B12),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'BetMachine AI',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FF87).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF00FF87).withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Text(
                            'INSTANT',
                            style: TextStyle(
                              color: Color(0xFF00FF87),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'High-streak statistical accumulator generator',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                ),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Controls / Filters Bar
          _buildFilterOptions(),

          const SizedBox(height: 14),

          // Main Content: Ticket View or Loading
          Expanded(
            child: _isGenerating
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A0E2E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Color(0xFFFFD700),
                            strokeWidth: 3,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Scanning statistical streaks...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Building your custom odds slip without delay',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  )
                : _errorMessage != null
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A0E2E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.bolt_rounded,
                              color: Colors.redAccent,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _generateTicket,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Try Again'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD700),
                              foregroundColor: Colors.black,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _buildTicketContent(),
          ),

          const SizedBox(height: 12),

          // Action Buttons
          if (!_isGenerating && _generatedPicks.isNotEmpty)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _generateTicket,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Shuffle'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF1E1136),
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: _loadAllToSlip,
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: Text(
                      widget.onAddToBetslip != null
                          ? 'Add ${_generatedPicks.length} Picks to Slip'
                          : 'Copy Full Slip',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF87),
                      foregroundColor: const Color(0xFF0D0B12),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFilterOptions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1033),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Target Odds',
                  value: '$_targetOdds',
                  items: const [
                    DropdownMenuItem(value: '3.5', child: Text('3.50x Odds')),
                    DropdownMenuItem(value: '5.0', child: Text('5.00x Odds')),
                    DropdownMenuItem(value: '10.0', child: Text('10.00x Odds')),
                    DropdownMenuItem(value: '25.0', child: Text('25.00x Odds')),
                    DropdownMenuItem(value: '50.0', child: Text('50.00x Odds')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _targetOdds = double.parse(val));
                      _generateTicket();
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDropdown(
                  label: 'Max Picks',
                  value: '$_matchCount',
                  items: const [
                    DropdownMenuItem(value: '3', child: Text('3 Matches')),
                    DropdownMenuItem(value: '5', child: Text('5 Matches')),
                    DropdownMenuItem(value: '8', child: Text('8 Matches')),
                    DropdownMenuItem(value: '12', child: Text('12 Matches')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _matchCount = int.parse(val));
                      _generateTicket();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Risk Profile',
                  value: _riskLevel,
                  items: const [
                    DropdownMenuItem(value: 'SAFE', child: Text('Safe (Low Odd)')),
                    DropdownMenuItem(value: 'BALANCED', child: Text('Balanced')),
                    DropdownMenuItem(
                      value: 'HIGH_RETURN',
                      child: Text('High Return'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _riskLevel = val);
                      _generateTicket();
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDropdown(
                  label: 'Focus Market',
                  value: _preferredMarket,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All Streaks')),
                    DropdownMenuItem(value: 'GOALS', child: Text('Goals / O-U')),
                    DropdownMenuItem(value: 'BTTS', child: Text('Scoring / BTTS')),
                    DropdownMenuItem(value: '1X2', child: Text('Form / Unbeaten')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _preferredMarket = val);
                      _generateTicket();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final matchingItems = items.where((item) => item.value == value).length;
    final selectedValue = matchingItems == 1 ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFFB6A4D8),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF120921),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selectedValue,
              hint: const Text(
                'Select',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              items: items,
              onChanged: onChanged,
              dropdownColor: const Color(0xFF231140),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFFFFD700),
                size: 16,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTicketContent() {
    return ListView(
      children: [
        // Hero Ticket Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2D1254), Color(0xFF190830)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFFD700).withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2D1254).withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'COMBINED SLIP ODDS',
                        style: TextStyle(
                          color: Color(0xFFB7A8D9),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${_actualOdds.toStringAsFixed(2)}x',
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_generatedPicks.length} Legs',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'STREAK STRENGTH',
                        style: TextStyle(
                          color: Color(0xFFB7A8D9),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FF87).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: const Color(0xFF00FF87).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.trending_up_rounded,
                              color: Color(0xFF00FF87),
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_avgConfidence% Edge',
                              style: const TextStyle(
                                color: Color(0xFF00FF87),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      color: Color(0xFFFFD700),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Direct statistical fixtures — instant load without slow bookie sync',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _copySlipSummary,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.copy_rounded,
                              color: Color(0xFFFFD700),
                              size: 12,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'COPY',
                              style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
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

        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'GENERATED FIXTURES & INSIGHTS',
              style: TextStyle(
                color: Color(0xFFB7A8D9),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            Text(
              '${_generatedPicks.length} selections',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Picks List
        ..._generatedPicks.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final pick = entry.value;
          final dt = pick.matchTime;
          final timeStr = pick.tag.isNotEmpty
              ? pick.tag
              : (dt != null
                    ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                    : 'Upcoming');

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0F2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        '$idx',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  pick.market,
                                  style: const TextStyle(
                                    color: Color(0xFF00FF87),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  timeStr,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${pick.homeTeam} vs ${pick.awayTeam}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF331B59), Color(0xFF241142)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            pick.predictionOdds,
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text(
                            'ODD',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF120920),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF00FF87).withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.insights_rounded,
                        color: Color(0xFF00FF87),
                        size: 15,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          pick.prediction,
                          style: const TextStyle(
                            color: Color(0xFFE6DDF7),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
