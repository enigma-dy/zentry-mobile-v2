import 'package:flutter/material.dart';

import 'services/sports_service.dart';

class AdvancedStatsSheet extends StatefulWidget {
  const AdvancedStatsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AdvancedStatsSheet(),
  );

  @override
  State<AdvancedStatsSheet> createState() => _AdvancedStatsSheetState();
}

class _AdvancedStatsSheetState extends State<AdvancedStatsSheet> {
  final _service = SportsService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.getAdvancedTeamStats();
  }

  void _reload() => setState(() {
    _future = _service.getAdvancedTeamStats();
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * .88,
      decoration: const BoxDecoration(
        color: Color(0xFF120A20),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.analytics_rounded,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Advanced Team Stats',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Form calculated from completed matches',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
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
          ),
          const SizedBox(height: 14),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00E676)),
                  );
                }
                if (snapshot.hasError) {
                  return _EmptyState(
                    message: 'Could not load advanced stats.',
                    onRetry: _reload,
                  );
                }
                final teams = snapshot.data ?? const [];
                if (teams.isEmpty) {
                  return _EmptyState(
                    message: 'Not enough completed-match data yet.',
                    onRetry: _reload,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                  itemCount: teams.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _TeamStatCard(rank: index + 1, data: teams[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamStatCard extends StatelessWidget {
  const _TeamStatCard({required this.rank, required this.data});
  final int rank;
  final Map<String, dynamic> data;

  double number(String key) => (data[key] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final winRate = number('win_rate');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF201333), Color(0xFF171023)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF3A2854)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF00E676).withValues(alpha: .15),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  data['team']?.toString() ?? 'Team',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${winRate.toStringAsFixed(1)}% wins',
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (winRate / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 6,
              backgroundColor: Colors.white10,
              color: const Color(0xFF00E676),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Metric('Matches', '${data['matches'] ?? 0}'),
              _Metric(
                'W-D-L',
                '${data['wins'] ?? 0}-${data['draws'] ?? 0}-${data['losses'] ?? 0}',
              ),
              _Metric('Avg goals', number('average_goals').toStringAsFixed(2)),
              _Metric('BTTS', '${number('btts_rate').toStringAsFixed(0)}%'),
              _Metric('O2.5', '${number('over_25_rate').toStringAsFixed(0)}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.analytics_outlined, color: Colors.white38, size: 42),
        const SizedBox(height: 10),
        Text(message, style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}
