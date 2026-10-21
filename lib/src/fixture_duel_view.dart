import 'package:flutter/material.dart';

import 'models/fixture_duel_model.dart';
import 'models/fixture_model.dart';
import 'models/fpl_duel_model.dart';
import 'services/fixture_duel_service.dart';
import 'services/fpl_duel_service.dart';
import 'services/session_manager.dart';

class FixtureDuelView extends StatefulWidget {
  final VoidCallback onOpenWallet;
  final int initialTab;
  const FixtureDuelView({
    super.key,
    required this.onOpenWallet,
    this.initialTab = 0,
  });

  @override
  State<FixtureDuelView> createState() => _FixtureDuelViewState();
}

class _FixtureDuelViewState extends State<FixtureDuelView> {
  final _service = FixtureDuelService();
  final _walletService = FplDuelService();
  final _stakes = const [20000, 50000, 100000, 200000, 500000, 1000000];
  List<FixtureModel> _fixtures = [];
  List<FixtureDuelModel> _lobby = [];
  List<FixtureDuelModel> _mine = [];
  FplWalletModel? _wallet;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab < 0
        ? 0
        : widget.initialTab > 2
        ? 2
        : widget.initialTab;
    _load();
  }

  Future<void> _load() async {
    if (!SessionManager.instance.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = 'Sign in to create or join a fixture challenge.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _service.eligibleFixtures(),
        _service.lobby(),
        _service.mine(),
        _walletService.getWallet(),
      ]);
      if (!mounted) return;
      setState(() {
        _fixtures = results[0] as List<FixtureModel>;
        _lobby = results[1] as List<FixtureDuelModel>;
        _mine = results[2] as List<FixtureDuelModel>;
        _wallet = results[3] as FplWalletModel;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _money(int kobo) => '₦${(kobo / 100).toStringAsFixed(0)}';

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _create(FixtureModel fixture) async {
    var pick = 'HOME';
    var stake = 100000;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF21182F),
          title: const Text(
            'Create Fixture Duel',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${fixture.homeTeam} vs ${fixture.awayTeam}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Kickoff ${_date(fixture.matchTime)} • closes 5 minutes earlier',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const Text('Your team', style: TextStyle(color: Colors.white70)),
              DropdownButton<String>(
                value: pick,
                dropdownColor: const Color(0xFF21182F),
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: 'HOME',
                    child: Text(
                      fixture.homeTeam,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'AWAY',
                    child: Text(
                      fixture.awayTeam,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => pick = value ?? 'HOME'),
              ),
              const Text(
                'Each player stakes',
                style: TextStyle(color: Colors.white70),
              ),
              DropdownButton<int>(
                value: stake,
                dropdownColor: const Color(0xFF21182F),
                isExpanded: true,
                items: _stakes
                    .map(
                      (amount) => DropdownMenuItem(
                        value: amount,
                        child: Text(
                          _money(amount),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => stake = value ?? 100000),
              ),
              const SizedBox(height: 8),
              const Text(
                'Opponent backs the other team. A draw refunds both stakes. Winner receives the pot after the 10% game fee.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Stake & create'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || _submitting) return;
    setState(() => _submitting = true);
    try {
      await _service.create(
        fixtureId: fixture.id,
        creatorPick: pick,
        stake: stake,
      );
      await _load();
      if (mounted) setState(() => _tab = 2);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _accept(FixtureDuelModel duel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Fixture Duel'),
        content: Text(
          'Back ${duel.opponentTeam} against ${duel.creatorTeam} for ${_money(duel.stake)}? A draw refunds both stakes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Join & stake'),
          ),
        ],
      ),
    );
    if (confirmed != true || _submitting) return;
    setState(() => _submitting = true);
    try {
      await _service.accept(duel);
      await _load();
      if (mounted) setState(() => _tab = 2);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancel(FixtureDuelModel duel) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await _service.cancel(duel);
      await _load();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _fixtureCard(FixtureModel f) => Card(
    color: const Color(0xFF21182F),
    child: ListTile(
      title: Text(
        '${f.homeTeam} vs ${f.awayTeam}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        '${f.leagueName} • ${_date(f.matchTime)}',
        style: const TextStyle(color: Colors.white70),
      ),
      trailing: const Icon(Icons.add_circle_outline, color: Color(0xFFFFD700)),
      onTap: _submitting ? null : () => _create(f),
    ),
  );

  Widget _duelCard(FixtureDuelModel d, {required bool mine}) {
    final myID = SessionManager.instance.currentUser?.id;
    final isCreator = d.creatorId == myID;
    return Card(
      color: const Color(0xFF21182F),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${d.fixture.homeTeam} vs ${d.fixture.awayTeam}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${d.fixture.leagueName} • ${_date(d.kickoff)}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 7),
            Text(
              '${d.creatorTeam} vs ${d.opponentTeam}  •  ${_money(d.stake)} each',
              style: const TextStyle(color: Color(0xFFFFD700)),
            ),
            Text(
              'Status: ${d.status}${d.status == 'SETTLED' || d.status == 'PUSHED' ? ' • ${d.homeScore}-${d.awayScore}' : ''}',
              style: const TextStyle(color: Colors.white70),
            ),
            if (mine && d.status == 'OPEN' && isCreator)
              TextButton(
                onPressed: _submitting ? null : () => _cancel(d),
                child: const Text('Cancel & refund'),
              ),
            if (!mine && d.status == 'OPEN' && !isCreator)
              FilledButton(
                onPressed: _submitting ? null : () => _accept(d),
                child: const Text('Join challenge'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D0B12),
    appBar: AppBar(
      title: const Text('Fixture Duel'),
      backgroundColor: const Color(0xFF171221),
      foregroundColor: Colors.white,
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              const Text(
                'Real matches • Premier League, La Liga, Bundesliga, Serie A, Ligue 1 & Champions League',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Wallet: ${_wallet == null ? '—' : _money(_wallet!.totalBalance)}',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onOpenWallet,
                    child: const Text('Fund wallet'),
                  ),
                ],
              ),
              const Text(
                'Create or join until 5 minutes before kickoff. Unmatched challenges refund at kickoff; matched challenges settle after the final score.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Fixtures')),
            ButtonSegment(value: 1, label: Text('Lobby')),
            ButtonSegment(value: 2, label: Text('Mine')),
          ],
          selected: {_tab},
          onSelectionChanged: (value) => setState(() => _tab = value.first),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                )
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: switch (_tab) {
                      0 =>
                        _fixtures.isEmpty
                            ? [
                                const _EmptyDuelList(
                                  'No eligible fixtures are available yet.',
                                ),
                              ]
                            : _fixtures.map(_fixtureCard).toList(),
                      1 =>
                        _lobby.isEmpty
                            ? [const _EmptyDuelList('No open challenges yet.')]
                            : _lobby
                                  .map((d) => _duelCard(d, mine: false))
                                  .toList(),
                      _ =>
                        _mine.isEmpty
                            ? [
                                const _EmptyDuelList(
                                  'You have no fixture challenges yet.',
                                ),
                              ]
                            : _mine
                                  .map((d) => _duelCard(d, mine: true))
                                  .toList(),
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}

class _EmptyDuelList extends StatelessWidget {
  final String message;
  const _EmptyDuelList(this.message);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(36),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white60),
    ),
  );
}
