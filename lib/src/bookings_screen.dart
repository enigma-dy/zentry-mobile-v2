import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/ticket_bucket_model.dart';
import 'services/sports_service.dart';

class BookingsScreen extends StatefulWidget {
  final SportsService? sportsService;

  const BookingsScreen({super.key, this.sportsService});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  late final SportsService _sportsService =
      widget.sportsService ?? SportsService();
  TicketBucketFeedResponseModel? _bookings;
  bool _loading = true;
  String? _error;
  int _page = 1;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadPage(1);
  }

  Future<void> _loadPage(int page) async {
    if (page < 1) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _sportsService.getMyBookings(
        page: page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _bookings = result;
        _page = result.page;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  int get _totalPages {
    final data = _bookings;
    if (data == null || data.total == 0) return 0;
    if (data.totalPages > 0) return data.totalPages;
    return (data.total / data.pageSize).ceil();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0914),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151020),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Bookings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            Text(
              'Your generated booking codes',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFFD700),
        backgroundColor: const Color(0xFF21182F),
        onRefresh: () => _loadPage(_page),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _bookings == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      );
    }
    if (_error != null && _bookings == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 54),
          const SizedBox(height: 16),
          const Text(
            'Could not load your bookings',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: () => _loadPage(_page),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    final bookings = _bookings?.tickets ?? const <TicketBucketModel>[];
    if (bookings.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: const [
          SizedBox(height: 100),
          Icon(
            Icons.confirmation_number_outlined,
            color: Color(0xFFFFD700),
            size: 58,
          ),
          SizedBox(height: 18),
          Text(
            'No booking codes yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Codes you generate from your betslip will appear here. Public feed posts and Fan Duel campaigns are not included.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, height: 1.5),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_bookings?.total ?? bookings.length} generated code${(_bookings?.total ?? bookings.length) == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFFD700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ...bookings.map(_buildBookingCard),
        if (_totalPages > 1) _buildPagination(),
      ],
    );
  }

  Widget _buildBookingCard(TicketBucketModel booking) {
    final statusColor = _statusColor(booking.status);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BookingDetailsScreen(
            bookingId: booking.id,
            initialBooking: booking,
            sportsService: _sportsService,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF191224),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF352747)),
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
                    color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _platformName(booking.platform),
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    booking.status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              booking.bookingCode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                letterSpacing: 2,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metric('${booking.itemCount}', 'Picks'),
                const SizedBox(width: 22),
                _metric(ticketOddsLabel(booking.totalOdds), 'Total odds'),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy booking code',
                  onPressed: () => _copyCode(booking.bookingCode),
                  icon: const Icon(
                    Icons.copy_rounded,
                    color: Color(0xFFFFD700),
                    size: 20,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              ],
            ),
            const Divider(color: Colors.white10, height: 18),
            Text(
              _formatDate(booking.createdAt),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            onPressed: !_loading && _page > 1
                ? () => _loadPage(_page - 1)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'Page $_page of $_totalPages',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: !_loading && _page < _totalPages
                ? () => _loadPage(_page + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Booking code $code copied.')));
  }
}

class BookingDetailsScreen extends StatefulWidget {
  final String bookingId;
  final TicketBucketModel initialBooking;
  final SportsService sportsService;

  const BookingDetailsScreen({
    super.key,
    required this.bookingId,
    required this.initialBooking,
    required this.sportsService,
  });

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  late Future<TicketBucketModel> _bookingFuture;

  @override
  void initState() {
    super.initState();
    _bookingFuture = widget.sportsService.getTicketBucket(widget.bookingId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0914),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151020),
        foregroundColor: Colors.white,
        title: const Text('Booking Details'),
      ),
      body: FutureBuilder<TicketBucketModel>(
        future: _bookingFuture,
        initialData: widget.initialBooking,
        builder: (context, snapshot) {
          final booking = snapshot.data ?? widget.initialBooking;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A1742), Color(0xFF171020)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF5A3A7A)),
                ),
                child: Column(
                  children: [
                    Text(
                      _platformName(booking.platform),
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      booking.bookingCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: booking.bookingCode),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Booking code copied.')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy code'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: const Color(0xFF171020),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _summaryCard(
                      '${booking.itemCount}',
                      'Selections',
                      Icons.list_alt_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _summaryCard(
                      ticketOddsLabel(booking.totalOdds),
                      'Total odds',
                      Icons.trending_up_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Selections',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              if (booking.selections.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    'No selection details are available.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                ...booking.selections.asMap().entries.map(
                  (entry) => _selectionCard(entry.key + 1, entry.value),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCard(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF191224),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF352747)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFFD700), size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selectionCard(int index, TicketSelectionModel selection) {
    final color = _statusColor(selection.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF191224),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF352747)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: const Color(0xFFFFD700).withValues(alpha: 0.14),
            child: Text(
              '$index',
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${selection.homeTeam} vs ${selection.awayTeam}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${selection.marketType} • ${selection.selection}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                if (selection.leagueName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    selection.leagueName,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                ticketOddsLabel(selection.odds),
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                selection.status.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'won':
      return const Color(0xFF00E676);
    case 'lost':
      return const Color(0xFFFF5252);
    case 'void':
      return Colors.blueGrey;
    default:
      return const Color(0xFFFFD700);
  }
}

String _platformName(String platform) {
  final normalized = platform.toLowerCase();
  if (normalized.contains('sporty')) return 'SPORTYBET';
  if (normalized.contains('1xbet')) return '1XBET';
  if (normalized.contains('msport')) return 'MSPORT';
  return platform.toUpperCase();
}

String _formatDate(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return 'Date unavailable';
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
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${date.day} ${months[date.month - 1]} ${date.year} • $hour:$minute $period';
}
