import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'models/fpl_duel_model.dart';
import 'payment_checkout_screen.dart';
import 'services/fpl_duel_service.dart';
import 'find_users_dialog.dart';

class FplDuelView extends StatefulWidget {
  const FplDuelView({super.key});

  @override
  State<FplDuelView> createState() => _FplDuelViewState();
}

class _FplDuelViewState extends State<FplDuelView> {
  final FplDuelService _service = FplDuelService();

  int _selectedTabIndex = 0; // 0: Lobby, 1: My Duels, 2: Create Duel
  String _selectedModeFilter = 'ALL';
  int? _selectedStakeFilter;

  FplGameweekModel? _gameweek;
  FplTeamModel? _myTeam;
  FplWalletModel? _wallet;
  List<FplDuelChallengeModel> _lobbyChallenges = [];
  List<FplDuelChallengeModel> _myChallenges = [];

  bool _isLoading = true;

  // Create Challenge Form State
  String _createMode = 'CLASSIC';
  int _createStakeKobo = 100000; // default ₦1,000
  bool _createAllowChips = false;
  bool _isCreating = false;

  final List<int> _presetTiers = [
    20000, // ₦200
    50000, // ₦500
    100000, // ₦1,000
    200000, // ₦2,000
    500000, // ₦5,000
    1000000, // ₦10,000
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final gwFuture = _service.getGameweekStatus();
      final teamFuture = _service.getMyTeam();
      // Wallet refresh must not depend on FPL or lobby availability.
      final walletFuture = _service.getWallet().then((wallet) {
        if (mounted) setState(() => _wallet = wallet);
        return wallet;
      });
      final lobbyFuture = _service.getLobbyChallenges(
        mode: _selectedModeFilter == 'ALL' ? null : _selectedModeFilter,
        minStake: _selectedStakeFilter,
        maxStake: _selectedStakeFilter,
      );
      final myChallengesFuture = _service.getMyChallenges();

      final results = await Future.wait([
        gwFuture,
        teamFuture,
        walletFuture,
        lobbyFuture,
        myChallengesFuture,
      ]);

      if (!mounted) return;
      setState(() {
        _gameweek = results[0] as FplGameweekModel;
        _myTeam = results[1] as FplTeamModel?;
        _wallet = results[2] as FplWalletModel;
        _lobbyChallenges = results[3] as List<FplDuelChallengeModel>;
        _myChallenges = results[4] as List<FplDuelChallengeModel>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _gameweek == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(color: Color(0xFF00FF87)),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF00FF87),
      backgroundColor: const Color(0xFF1E0D36),
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          const SizedBox(height: 12),

          // 1. TOP HERO BANNER: FPL DUEL HEADER
          _buildHeroHeader(),

          const SizedBox(height: 12),

          // 2. FPL TEAM CLAIM / VERIFICATION STATUS CARD
          _buildTeamStatusCard(),

          const SizedBox(height: 12),

          _buildRivalManagerCard(),

          const SizedBox(height: 12),

          // 3. WALLET BALANCES CARD
          _buildWalletBar(),

          const SizedBox(height: 16),

          // 4. SUB-NAVIGATION TABS (Lobby, My Duels, Create Duel)
          _buildSubNavTabs(),

          const SizedBox(height: 16),

          // 5. ACTIVE TAB VIEW CONTENT
          if (_selectedTabIndex == 0) ...[
            _buildLobbyView(),
          ] else if (_selectedTabIndex == 1) ...[
            _buildMyDuelsView(),
          ] else ...[
            _buildCreateDuelView(),
          ],
        ],
      ),
    );
  }

  // --- 1. HERO HEADER ---
  Widget _buildHeroHeader() {
    final gwName = _gameweek?.name ?? 'Gameweek unavailable';
    final isLive = _gameweek?.isCurrent == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF38003C), Color(0xFF180022)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFF00FF87).withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00FF87).withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF87),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isLive ? '$gwName • LIVE' : '$gwName • UPCOMING',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF38003C),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text(
                      '1v1 ESCROW',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'FPL DUEL ARENA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Challenge FPL managers in single-gameweek 1v1 duels. Winner takes the pot.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Opacity(
              opacity: 0.25,
              child: const Icon(
                Icons.sports_soccer_rounded,
                size: 72,
                color: Color(0xFF00FF87),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms);
  }

  // --- 2. FPL TEAM STATUS CARD ---
  Widget _buildTeamStatusCard() {
    final hasTeam = _myTeam != null;
    final isVerified = _myTeam?.isVerified == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B112B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isVerified
              ? const Color(0xFF00FF87).withValues(alpha: 0.4)
              : const Color(0xFFFFD700).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isVerified
                  ? const Color(0xFF00FF87).withValues(alpha: 0.15)
                  : const Color(0xFFFFD700).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isVerified ? Icons.verified_user_rounded : Icons.shield_outlined,
              color: isVerified
                  ? const Color(0xFF00FF87)
                  : const Color(0xFFFFD700),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasTeam
                      ? _myTeam!.teamName
                      : 'Connect your Official FPL Team',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isVerified
                      ? 'Verified Manager: ${_myTeam!.playerName.isNotEmpty ? _myTeam!.playerName : 'Ready for Duels'}'
                      : hasTeam
                      ? 'Verification Code: ${_myTeam!.verificationCode}'
                      : 'Required to create and accept duels',
                  style: TextStyle(
                    color: isVerified
                        ? const Color(0xFF00FF87)
                        : Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _showFplClaimDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: isVerified
                  ? const Color(0xFF2E2245)
                  : const Color(0xFF00FF87),
              foregroundColor: isVerified
                  ? Colors.white70
                  : const Color(0xFF0D0B12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: Text(
              isVerified
                  ? 'Manage'
                  : hasTeam
                  ? 'Verify Now'
                  : 'Connect Team',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. WALLET BALANCES BAR ---
  Widget _buildRivalManagerCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        onPressed: () => FindUsersDialog.show(
          context,
          onChallengeUser: (_) {
            if (mounted) setState(() => _selectedTabIndex = 2);
          },
        ),
        icon: const Icon(Icons.person_search_rounded),
        label: const Text('Rival Manager'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFA855F7),
          side: const BorderSide(color: Color(0xFFA855F7)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildWalletBar() {
    final deposit = _wallet?.depositNaira ?? 0.0;
    final winnings = _wallet?.winningsNaira ?? 0.0;
    final total = _wallet?.totalNaira ?? 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF180F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF32224A)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FPL DUEL WALLET',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '₦${total.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Deposit: ₦${deposit.toStringAsFixed(0)} • Winnings: ₦${winnings.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: _showDepositDialog,
            icon: const Icon(Icons.add_rounded, size: 14),
            label: const Text('Add Funds', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFD700),
              side: const BorderSide(color: Color(0xFFFFD700)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 4. SUB-NAVIGATION TABS ---
  Widget _buildSubNavTabs() {
    final tabs = [
      ('LOBBY (${_lobbyChallenges.length})', Icons.sports_mma_rounded),
      ('MY DUELS (${_myChallenges.length})', Icons.history_rounded),
      ('CREATE DUEL', Icons.add_circle_outline_rounded),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A112A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF342352)),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _selectedTabIndex == index;
          final tab = tabs[index];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedTabIndex = index);
              },
              child: AnimatedContainer(
                duration: 200.ms,
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF00FF87)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.$2,
                      size: 13,
                      color: isSelected
                          ? const Color(0xFF0D0B12)
                          : Colors.white54,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        tab.$1,
                        maxLines: 1,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF0D0B12)
                              : Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // --- 5A. LOBBY VIEW ---
  Widget _buildLobbyView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildFilterChip('ALL', 'All Modes'),
              _buildFilterChip('CLASSIC', 'Classic 1v1'),
              _buildFilterChip('CAPTAIN_DUEL', 'Captain Duel'),
              _buildFilterChip('UNDERDOG', 'Underdog 2X'),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Stake Tier Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildStakeChip(null, 'All Stakes'),
              ..._presetTiers.map(
                (t) => _buildStakeChip(t, '₦${(t / 100).toStringAsFixed(0)}'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (_lobbyChallenges.isEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF1B112B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF332350)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.sports_soccer_rounded,
                  size: 48,
                  color: Colors.white38,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No Open Duels in Lobby',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Be the first to launch a challenge and wait for an opponent to accept.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _selectedTabIndex = 2),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Create New Duel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF87),
                    foregroundColor: const Color(0xFF0D0B12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: _lobbyChallenges
                  .map((ch) => _buildChallengeCard(ch))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterChip(String modeKey, String label) {
    final isSelected = _selectedModeFilter == modeKey;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedModeFilter = modeKey);
        _loadData();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00FF87).withValues(alpha: 0.2)
              : const Color(0xFF1F1433),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00FF87)
                : const Color(0xFF3A285A),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00FF87) : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildStakeChip(int? stakeKobo, String label) {
    final isSelected = _selectedStakeFilter == stakeKobo;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedStakeFilter = stakeKobo);
        _loadData();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFD700).withValues(alpha: 0.2)
              : const Color(0xFF1A112A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFD700)
                : const Color(0xFF342352),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFD700) : Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // --- CHALLENGE CARD (Lobby) ---
  Widget _buildChallengeCard(FplDuelChallengeModel ch) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1128),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF33224E)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row: Gameweek & Mode Badge
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C1945),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF4C3075)),
                    ),
                    child: Text(
                      'GW ${ch.gameweek}',
                      style: const TextStyle(
                        color: Color(0xFF00FF87),
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      ch.modeLabel,
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (ch.allowChips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'CHIPS ON',
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                'POT: ₦${ch.potNaira.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Color(0xFF00FF87),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Challenger Info
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF2E1B4A),
                child: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFFFFD700),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ch.creatorTeamName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      ch.modeDescription,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Action row: Stake Info & Accept Button
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 10,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SYMMETRIC STAKE (§4A)',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '₦${ch.stakeNaira.toStringAsFixed(0)} each',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _confirmAcceptDuel(ch),
                icon: const Icon(Icons.flash_on_rounded, size: 16),
                label: Text('Accept ₦${ch.stakeNaira.toStringAsFixed(0)}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF87),
                  foregroundColor: const Color(0xFF0D0B12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 5B. MY DUELS VIEW ---
  Widget _buildMyDuelsView() {
    if (_myChallenges.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF1B112B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF332350)),
        ),
        child: Column(
          children: [
            const Icon(Icons.history_rounded, size: 48, color: Colors.white38),
            const SizedBox(height: 12),
            const Text(
              'No Duels Yet',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Accept an open challenge from the lobby or create your own.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: _myChallenges.map((ch) => _buildMyDuelCard(ch)).toList(),
      ),
    );
  }

  Widget _buildMyDuelCard(FplDuelChallengeModel ch) {
    final isSettled = ch.isSettled;
    final isLive = ch.isLive;
    final isLocked = ch.isLocked;
    final isOpen = ch.isOpen;

    Color statusColor = const Color(0xFFFFD700);
    String statusText = ch.status;

    if (isSettled) {
      statusColor = const Color(0xFF00E676);
      statusText = 'SETTLED';
    } else if (isLive) {
      statusColor = Colors.redAccent;
      statusText = 'LIVE';
    } else if (isLocked) {
      statusColor = Colors.cyanAccent;
      statusText = 'LOCKED';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1128),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'GW ${ch.gameweek} • ${ch.modeLabel}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Head-to-Head Scoreboard
          Row(
            children: [
              // You
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ch.creatorTeamName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ch.creatorScore} pts',
                      style: const TextStyle(
                        color: Color(0xFF00FF87),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),

              // VS
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E1C4A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'VS',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),

              // Opponent
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ch.opponentTeamName.isNotEmpty
                          ? ch.opponentTeamName
                          : 'Awaiting Opponent',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ch.opponentScore} pts',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Pot info & actions
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'Pot: ₦${ch.potNaira.toStringAsFixed(0)} (₦${ch.stakeNaira.toStringAsFixed(0)} each)',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              if (isOpen)
                TextButton(
                  onPressed: () => _cancelDuel(ch),
                  child: const Text(
                    'Cancel Challenge',
                    style: TextStyle(color: Colors.redAccent, fontSize: 11),
                  ),
                )
              else if (!isSettled)
                const Text(
                  'Awaiting official FPL settlement',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 5C. CREATE DUEL VIEW ---
  Widget _buildCreateDuelView() {
    final potNaira = (_createStakeKobo * 2) / 100.0;
    final rakeNaira = (potNaira * 0.10);
    final winTakeHome = potNaira - rakeNaira;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF191026),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF352352)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LAUNCH NEW 1v1 DUEL',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Escrow your stake. An open duel is matched symmetrically (§4A).',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),

            const SizedBox(height: 18),

            // Mode Selector
            const Text(
              'CHALLENGE MODE',
              style: TextStyle(
                color: Color(0xFF00FF87),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            _buildModeOption(
              'CLASSIC',
              'Classic 1v1',
              'Starting XI points minus transfer cost.',
              Icons.sports_soccer_rounded,
            ),
            const SizedBox(height: 8),
            _buildModeOption(
              'CAPTAIN_DUEL',
              'Captain Duel',
              'High stakes battle on Captain points only.',
              Icons.flash_on_rounded,
            ),
            const SizedBox(height: 8),
            _buildModeOption(
              'UNDERDOG',
              'Underdog 2X',
              '2x points on differential players with <15% ownership.',
              Icons.auto_awesome_rounded,
            ),

            const SizedBox(height: 20),

            // Stake Tier Selector
            const Text(
              'STAKE AMOUNT (§4A PRESET TIERS)',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetTiers.map((tier) {
                final isSelected = _createStakeKobo == tier;
                final naira = (tier / 100).toStringAsFixed(0);
                return GestureDetector(
                  onTap: () => setState(() => _createStakeKobo = tier),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF25183A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF3F2B60),
                      ),
                    ),
                    child: Text(
                      '₦$naira',
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF0D0B12)
                            : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 18),

            // Chips Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Allow Chips (3x Captain / Bench Boost)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              subtitle: const Text(
                'If off, chip bonuses are ignored in scoring',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: _createAllowChips,
              activeColor: const Color(0xFF00FF87),
              onChanged: (val) => setState(() => _createAllowChips = val),
            ),

            const SizedBox(height: 16),

            // Payout calculation summary box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF221535),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3D275E)),
              ),
              child: Column(
                children: [
                  _buildSummaryRow(
                    'Your Escrow Stake',
                    '₦${(_createStakeKobo / 100).toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 6),
                  _buildSummaryRow(
                    'Opponent Match Stake',
                    '₦${(_createStakeKobo / 100).toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 6),
                  _buildSummaryRow(
                    'Total Pot',
                    '₦${potNaira.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 6),
                  _buildSummaryRow(
                    'Rake (10%)',
                    '₦${rakeNaira.toStringAsFixed(0)}',
                  ),
                  const Divider(color: Color(0xFF452D6A), height: 16),
                  _buildSummaryRow(
                    'Winner Take-Home',
                    '₦${winTakeHome.toStringAsFixed(0)}',
                    isHighlight: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isCreating ? null : _submitCreateDuel,
                icon: _isCreating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.flash_on_rounded, size: 20),
                label: Text(
                  _isCreating
                      ? 'Escrowing Funds...'
                      : 'Fund & Create Challenge',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF87),
                  foregroundColor: const Color(0xFF0D0B12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeOption(
    String modeKey,
    String title,
    String desc,
    IconData icon,
  ) {
    final isSelected = _createMode == modeKey;
    return GestureDetector(
      onTap: () => setState(() => _createMode = modeKey),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00FF87).withValues(alpha: 0.12)
              : const Color(0xFF221535),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00FF87)
                : const Color(0xFF382554),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF00FF87)
                  : const Color(0xFFFFD700),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF00FF87)
                          : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    desc,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isHighlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isHighlight ? const Color(0xFF00FF87) : Colors.white54,
              fontSize: isHighlight ? 13 : 11,
              fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: isHighlight ? const Color(0xFF00FF87) : Colors.white,
            fontSize: isHighlight ? 15 : 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  // --- ACTIONS & DIALOGS ---

  Future<void> _submitCreateDuel() async {
    setState(() => _isCreating = true);
    try {
      final gw = _gameweek?.gameweek ?? 28;
      final ch = await _service.createChallenge(
        gameweek: gw,
        mode: _createMode,
        stakeKobo: _createStakeKobo,
        allowChips: _createAllowChips,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Duel created for ₦${ch.stakeNaira.toStringAsFixed(0)}!',
          ),
          backgroundColor: const Color(0xFF00FF87),
        ),
      );
      setState(() {
        _isCreating = false;
        _selectedTabIndex = 0; // Go back to lobby
      });
      _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create duel: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _confirmAcceptDuel(FplDuelChallengeModel ch) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1035),
        title: const Text(
          'Accept 1v1 Challenge',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are accepting ${ch.creatorTeamName}\'s ${ch.modeLabel} challenge.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF281845),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _buildSummaryRow(
                    'Your Stake',
                    '₦${ch.stakeNaira.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 4),
                  _buildSummaryRow(
                    'Total Pot',
                    '₦${ch.potNaira.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 4),
                  _buildSummaryRow(
                    'Winner Net',
                    '₦${ch.winPayoutNaira.toStringAsFixed(0)}',
                    isHighlight: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _service.acceptChallenge(
                  ch.id,
                  expectedStakeKobo: ch.stake,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Duel accepted! Match is now locked and funded.',
                    ),
                    backgroundColor: Color(0xFF00FF87),
                  ),
                );
                _loadData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to accept: $e'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF87),
              foregroundColor: const Color(0xFF0D0B12),
            ),
            child: const Text('Confirm & Stake'),
          ),
        ],
      ),
    );
  }

  void _showFplClaimDialog() {
    final entryController = TextEditingController(
      text: _myTeam != null ? _myTeam!.fplEntryId.toString() : '',
    );
    bool isClaiming = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1035),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 24,
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Claim & Verify FPL Team',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Enter your official Fantasy Premier League Entry/Team ID (found in your URL on fantasy.premierleague.com).',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: entryController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'FPL Entry ID (e.g. 1234567)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF281845),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_myTeam != null && !_myTeam!.isVerified) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E1C4A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFD700)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Verification Instruction:',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Temporarily change your FPL team name to: "${_myTeam!.verificationCode}". Then click Verify below.',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isClaiming
                            ? null
                            : () async {
                                final id = int.tryParse(
                                  entryController.text.trim(),
                                );
                                if (id == null || id <= 0) return;
                                setModalState(() => isClaiming = true);
                                try {
                                  final team = await _service.claimTeam(id);
                                  setState(() => _myTeam = team);
                                  setModalState(() => isClaiming = false);
                                  _loadData();
                                } catch (e) {
                                  setModalState(() => isClaiming = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E1C4A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Claim Team ID'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isClaiming
                            ? null
                            : () async {
                                setModalState(() => isClaiming = true);
                                try {
                                  final team = await _service.verifyTeam();
                                  setState(() => _myTeam = team);
                                  Navigator.pop(ctx);
                                  _loadData();
                                } catch (e) {
                                  setModalState(() => isClaiming = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FF87),
                          foregroundColor: const Color(0xFF0D0B12),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Verify Team',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDepositDialog() async {
    final pendingReference = await _service.pendingWalletReference();
    if (!mounted) return;
    final referenceController = TextEditingController(
      text: pendingReference ?? "",
    );
    int selectedAmount = 5000;
    String selectedProvider = 'paystack';
    final customAmountController = TextEditingController(text: '5000');
    bool isProcessing = false;
    String? statusMessage;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final depositBal = _wallet?.depositNaira ?? 0.0;
          final winBal = _wallet?.winningsNaira ?? 0.0;
          final totalBal = _wallet?.totalNaira ?? 0.0;

          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF160B24),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 24,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
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
                          color: const Color(
                            0xFF00FF87,
                          ).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Color(0xFF00FF87),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fund FPL Duel Wallet',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Instant, secure wallet top-up via Paystack or Crypto',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Current Balance Banner
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF231438),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CURRENT BALANCE',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₦${totalBal.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Deposits: ₦${depositBal.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  'Winnings: ₦${winBal.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Color(0xFF00FF87),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Amount Selection Header
                  const Text(
                    'SELECT AMOUNT (NGN)',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Preset Amount Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [1000, 2500, 5000, 10000, 25000, 50000].map((
                      amt,
                    ) {
                      final isSelected = selectedAmount == amt;
                      return ChoiceChip(
                        label: Text('₦$amt'),
                        selected: isSelected,
                        selectedColor: const Color(0xFF00FF87),
                        backgroundColor: const Color(0xFF221136),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? const Color(0xFF0D0B12)
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFF00FF87)
                              : Colors.white12,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setModalState(() {
                              selectedAmount = amt;
                              customAmountController.text = amt.toString();
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),

                  // Custom Amount Field
                  TextField(
                    controller: customAmountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.currency_pound,
                        color: Color(0xFFFFD700),
                        size: 18,
                      ),
                      prefixText: '₦ ',
                      prefixStyle: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.bold,
                      ),
                      labelText: 'Custom Amount',
                      labelStyle: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1E0E32),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF00FF87)),
                      ),
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val) ?? 0;
                      setModalState(() {
                        selectedAmount = parsed;
                      });
                    },
                  ),

                  const SizedBox(height: 20),

                  // Payment Gateway Selector
                  const Text(
                    'CHOOSE PAYMENT METHOD',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Option 1: Paystack
                  InkWell(
                    onTap: () =>
                        setModalState(() => selectedProvider = 'paystack'),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: selectedProvider == 'paystack'
                            ? const Color(0xFF281140)
                            : const Color(0xFF1B0B2E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selectedProvider == 'paystack'
                              ? const Color(0xFF00FF87)
                              : Colors.white12,
                          width: selectedProvider == 'paystack' ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF09A5DB,
                              ).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.credit_card_rounded,
                              color: Color(0xFF09A5DB),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Paystack (Card, Transfer, USSD)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Instant Nigerian Debit Card, Bank & USSD Checkout',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF09A5DB,
                              ).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'INSTANT',
                              style: TextStyle(
                                color: Color(0xFF09A5DB),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Option 2: NOWPayments
                  InkWell(
                    onTap: () =>
                        setModalState(() => selectedProvider = 'nowpayments'),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: selectedProvider == 'nowpayments'
                            ? const Color(0xFF281140)
                            : const Color(0xFF1B0B2E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selectedProvider == 'nowpayments'
                              ? const Color(0xFF00FF87)
                              : Colors.white12,
                          width: selectedProvider == 'nowpayments' ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFF9900,
                              ).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.currency_bitcoin_rounded,
                              color: Color(0xFFFF9900),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'NOWPayments (USDT, BTC, ETH)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Pay via USDT (TRC20/ERC20), BTC, ETH & 100+ coins',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFF9900,
                              ).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'CRYPTO',
                              style: TextStyle(
                                color: Color(0xFFFF9900),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FF87).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Color(0xFF00FF87),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              statusMessage!,
                              style: const TextStyle(
                                color: Color(0xFF00FF87),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isProcessing || selectedAmount <= 0
                          ? null
                          : () async {
                              setModalState(() {
                                isProcessing = true;
                                statusMessage =
                                    'Initializing funding session...';
                              });

                              try {
                                final checkout = await _service
                                    .createWalletCheckout(
                                      provider: selectedProvider,
                                      amountNgn: selectedAmount.toDouble(),
                                    );

                                if (!mounted || !sheetCtx.mounted) return;
                                final checkoutUrl =
                                    checkout['checkout_url'] as String?;
                                if (checkoutUrl != null &&
                                    checkoutUrl.isNotEmpty) {
                                  referenceController.text =
                                      checkout['reference']?.toString() ?? '';
                                  await PaymentCheckoutScreen.open(
                                    context,
                                    checkoutUrl: checkoutUrl,
                                    title: 'Fund Duel Wallet',
                                  );

                                  if (!mounted || !sheetCtx.mounted) return;
                                  final payment = await _service
                                      .verifyWalletPayment(
                                        referenceController.text,
                                      );
                                  await _loadData();
                                  if (!mounted || !sheetCtx.mounted) return;
                                  setModalState(() {
                                    isProcessing = false;
                                    statusMessage =
                                        payment['message']?.toString() ??
                                        'Payment is awaiting confirmation.';
                                  });
                                  return;
                                }

                                throw Exception(
                                  'Could not open the secure checkout URL.',
                                );
                              } catch (e) {
                                if (!mounted || !sheetCtx.mounted) return;
                                setModalState(() {
                                  isProcessing = false;
                                  statusMessage = 'Error: $e';
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF87),
                        foregroundColor: const Color(0xFF0D0B12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: isProcessing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFF0D0B12),
                              ),
                            )
                          : Text(
                              'Fund ₦${selectedAmount > 0 ? selectedAmount : 0} via ${selectedProvider == "paystack" ? "Paystack" : "NOWPayments"}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),

                  // If checkout was opened, show Verify / Complete button
                  ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: referenceController,
                      enabled: !isProcessing,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText:
                            'Payment reference (check an earlier payment)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: isProcessing
                            ? null
                            : () async {
                                if (referenceController.text.trim().isEmpty) {
                                  setModalState(
                                    () => statusMessage =
                                        'Enter your payment reference first.',
                                  );
                                  return;
                                }
                                setModalState(() => isProcessing = true);
                                try {
                                  final payment = await _service
                                      .verifyWalletPayment(
                                        referenceController.text,
                                      );
                                  await _loadData();
                                  if (!mounted || !sheetCtx.mounted) return;
                                  setModalState(() {
                                    isProcessing = false;
                                    statusMessage =
                                        payment['message']?.toString() ??
                                        'Payment is awaiting confirmation.';
                                  });
                                } catch (error) {
                                  if (!mounted || !sheetCtx.mounted) return;
                                  setModalState(() {
                                    isProcessing = false;
                                    statusMessage =
                                        'Could not confirm payment: $error';
                                  });
                                }
                              },
                        icon: const Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFF00FF87),
                          size: 18,
                        ),
                        label: const Text(
                          'Check Payment Status',
                          style: TextStyle(color: Color(0xFF00FF87)),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF00FF87)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _cancelDuel(FplDuelChallengeModel ch) async {
    try {
      await _service.cancelChallenge(ch.id);
      _loadData();
    } catch (_) {}
  }
}
