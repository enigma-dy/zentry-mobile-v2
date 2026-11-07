import 'package:flutter/material.dart';

import 'tv_catalog.dart';
import '../ads/ad_slot.dart';

enum GuideView { live, channels, upcoming, all }

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.loadCatalog,
    required this.onWatch,
  });
  final Future<List<TvListing>> Function() loadCatalog;
  final void Function(TvListing listing, TvSource source) onWatch;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> with WidgetsBindingObserver {
  List<TvListing> _listings = [];
  bool _loading = true;
  String? _error;
  DateTime? _updated;
  String _query = '';
  String? _category;
  GuideView _view = GuideView.live;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_loading &&
        (_updated == null ||
            DateTime.now().difference(_updated!) >
                const Duration(minutes: 2))) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listings = await widget.loadCatalog();
      if (!mounted) return;
      setState(() {
        _listings = listings;
        _updated = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is CatalogUnavailable
            ? error.message
            : 'Couldn’t load the TV guide. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _watch(TvListing listing) async {
    if (!listing.canWatch) return;
    var source = listing.sources.first;
    if (listing.sources.length > 1) {
      final selected = await showModalBottomSheet<TvSource>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  'Choose a server',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final option in listing.sources)
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(option.name),
                  subtitle: Text(listing.name),
                  onTap: () => Navigator.pop(context, option),
                ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      source = selected;
    }
    widget.onWatch(listing, source);
  }

  @override
  Widget build(BuildContext context) {
    final categories = _listings.map((item) => item.category).toSet().toList()
      ..sort();
    final query = _query.trim().toLowerCase();
    final visible = _listings.where((item) {
      final inView = switch (_view) {
        GuideView.live => item.isLive,
        GuideView.channels =>
          item.alwaysLive || item.category == '24/7-streams',
        GuideView.upcoming => item.isUpcoming,
        GuideView.all => true,
      };
      return inView &&
          (_category == null || item.category == _category) &&
          '${item.name} ${item.league} ${categoryLabel(item.category)}'
              .toLowerCase()
              .contains(query);
    }).toList();
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        selectedIndex: _view.index,
        onDestinationSelected: (index) =>
            setState(() => _view = GuideView.values[index]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sensors), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.tv), label: 'Channels'),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            label: 'Schedule',
          ),
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'All'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loading ? () async {} : _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        hintText: 'Search channels, teams, leagues…',
                        prefixIcon: Icon(Icons.search),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_loading) const LinearProgressIndicator(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            if (_listings.isNotEmpty)
                              const Text('Showing previously loaded listings.'),
                            TextButton.icon(
                              onPressed: _loading ? null : _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All sports'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                    ),
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(categoryLabel(category)),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (visible.isEmpty && !_loading && _error == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.live_tv,
                          size: 48,
                          color: Colors.white38,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          query.isNotEmpty || _category != null
                              ? 'No matches. Try another search or sport.'
                              : 'Nothing here right now. Check the other tabs or refresh the guide.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final columns = width >= 1100
                      ? 5
                      : width >= 800
                      ? 4
                      : width >= 600
                      ? 3
                      : 2;
                  final cardWidth = (width - (columns - 1) * 12) / columns;
                  final boundaries = <int>[
                    0,
                    for (
                      var offset = 12;
                      offset < visible.length && offset <= 36;
                      offset += 12
                    )
                      offset,
                    visible.length,
                  ];
                  return SliverMainAxisGroup(
                    slivers: [
                      for (
                        var section = 0;
                        section < boundaries.length - 1;
                        section++
                      ) ...[
                        SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: cardWidth * 9 / 16 + 136,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = visible[boundaries[section] + index];
                              return _ListingCard(
                                listing: item,
                                onTap: item.canWatch
                                    ? () => _watch(item)
                                    : null,
                              );
                            },
                            childCount:
                                boundaries[section + 1] - boundaries[section],
                          ),
                        ),
                        if (visible.isNotEmpty && section < 3)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: AdSlot(
                                key: ValueKey('live-tv-ad-$section'),
                                placement: AdPlacement.liveTvList,
                                useNativeTemplate: section.isOdd,
                              ),
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing, this.onTap});
  final TvListing listing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final time = listing.startsAt?.toLocal();
    final date = time == null
        ? 'Time to be announced'
        : '${MaterialLocalizations.of(context).formatShortDate(time)} · ${TimeOfDay.fromDateTime(time).format(context)}';
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(
                    color: Color(0xFF172B40),
                    child: Icon(Icons.sports, size: 40, color: Colors.white24),
                  ),
                  if (listing.poster != null)
                    Image.network(
                      listing.poster.toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB3000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: listing.isLive
                            ? const Color(0xFFE94E65)
                            : const Color(0xDD142236),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        listing.isLive
                            ? '● LIVE'
                            : listing.isUpcoming
                            ? 'UPCOMING'
                            : 'OFF AIR',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                  ),
                  if (listing.canWatch)
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.league.isEmpty
                        ? categoryLabel(listing.category)
                        : listing.league,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    listing.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    listing.isUpcoming
                        ? date
                        : !listing.canWatch
                        ? 'Stream unavailable'
                        : listing.alwaysLive
                        ? '24/7 channel'
                        : '${listing.sources.length} ${listing.sources.length == 1 ? 'server' : 'servers'} available',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
