import 'package:flutter/material.dart';

class GameCenter extends StatefulWidget {
  final VoidCallback onFanDuel;
  final VoidCallback? onFixtureDuel;

  const GameCenter({super.key, required this.onFanDuel, this.onFixtureDuel});

  @override
  State<GameCenter> createState() => _GameCenterState();
}

class _GameCenterState extends State<GameCenter> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: [
        // Title & Header Banner
        _buildHeroBanner(),

        const SizedBox(height: 18),

        // Section Title
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _getCategoryTitle(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00FF87).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_getFilteredCount()} Active',
                style: const TextStyle(
                  color: Color(0xFF00FF87),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Fan Duel (FPL Duel)
        _buildToolCard(
          key: const Key('game-fan-duel'),
          tag: '1V1 FANTASY ARENA',
          tagColor: const Color(0xFF00FF87),
          icon: Icons.sports_soccer_rounded,
          iconGradient: const [Color(0xFF00FF87), Color(0xFF00B4D8)],
          title: 'Fan Duel',
          description:
              'Challenge another manager with your official Fantasy Premier League squad. Official gameweek scoring and escrow stake matching.',
          badges: ['Official FPL', '₦200 - ₦10k Stakes', 'Ledger Escrow'],
          actionText: 'Enter Duel Arena',
          actionColor: const Color(0xFF00FF87),
          onTap: widget.onFanDuel,
        ),
        _buildToolCard(
          key: const Key('game-fixture-duel'),
          tag: 'REAL MATCH 1V1',
          tagColor: const Color(0xFFFFD700),
          icon: Icons.emoji_events_rounded,
          iconGradient: const [Color(0xFFFFD700), Color(0xFFFF8800)],
          title: 'Fixture Duel',
          description:
              'Back a team in a real match from the top five European leagues or Champions League. Challenge another fan and settle on the final score.',
          badges: ['Real fixtures', '5-minute lock', 'Automatic payout'],
          actionText: 'Enter Fixture Duel',
          actionColor: const Color(0xFFFFD700),
          onTap: widget.onFixtureDuel,
        ),
      ],
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF2C104B), Color(0xFF150727)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2C104B).withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFF8800)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.sports_esports_rounded,
              color: Color(0xFF0D0B12),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zentry Game Center',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Fantasy duels and community rival challenges',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolCard({
    required Key key,
    required String tag,
    required Color tagColor,
    required IconData icon,
    required List<Color> iconGradient,
    required String title,
    required String description,
    required List<String> badges,
    required String actionText,
    required Color actionColor,
    required VoidCallback? onTap,
  }) {
    return Card(
      key: key,
      color: const Color(0xFF190D2A),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Tag & Icon Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tagColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: tagColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: tagColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: iconGradient),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.black, size: 20),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Title
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 6),

              // Description
              Text(
                description,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 12),

              // Feature Badges
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: badges.map((b) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF261440),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      b,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Action Row
              Row(
                children: [
                  Text(
                    actionText,
                    style: TextStyle(
                      color: actionColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: actionColor,
                    size: 16,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCategoryTitle() {
    return 'Games & Duels';
  }

  int _getFilteredCount() {
    return 1;
  }
}
