import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/slip_agent_service.dart';
import 'services/session_manager.dart';

class SlipAgentScreen extends StatefulWidget {
  final String? baseUrl;
  final SlipAgentService? service;
  final Future<Uint8List?> Function()? selectImage;
  const SlipAgentScreen({
    super.key,
    this.baseUrl,
    this.service,
    this.selectImage,
  });
  @override
  State<SlipAgentScreen> createState() => _SlipAgentScreenState();
}

class _SlipAgentScreenState extends State<SlipAgentScreen> {
  late final SlipAgentService _api =
      widget.service ?? SlipAgentService(baseUrl: widget.baseUrl);
  final _message = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _session;
  Map<String, dynamic>? _pending;
  Uint8List? _image;
  bool _loading = true, _busy = false, _confirmBooking = false;
  String? _error, _warning;

  Map<String, dynamic> get _state =>
      Map<String, dynamic>.from((_session?['state'] as Map?) ?? {});
  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    _scroll.dispose();
    if (widget.service == null) _api.dispose();
    super.dispose();
  }

  Future<void> _load({bool fresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (fresh) {
        final session = await _api.createSession();
        if (!mounted) return;
        setState(() {
          _session = session;
          _sessions.insert(0, session);
          _pending = null;
          _image = null;
          _confirmBooking = false;
          _warning = null;
        });
      } else if (_session != null) {
        final session = await _api.getSession(_session!['id'].toString());
        if (!mounted) return;
        setState(() {
          _session = session;
          _pending = null;
          _confirmBooking = false;
          _warning = null;
        });
      } else {
        final sessions = await _api.listSessions();
        final latest = sessions.isEmpty
            ? null
            : await _api.getSession(sessions.first['id'].toString());
        if (!mounted) return;
        setState(() {
          _sessions = sessions;
          _session = latest;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _attach() async {
    try {
      Uint8List? bytes;
      if (widget.selectImage != null) {
        bytes = await widget.selectImage!();
      } else {
        const type = XTypeGroup(
          label: 'Slip screenshots',
          extensions: ['png', 'jpg', 'jpeg'],
          mimeTypes: ['image/png', 'image/jpeg'],
          uniformTypeIdentifiers: ['public.png', 'public.jpeg'],
        );
        final file = await openFile(acceptedTypeGroups: [type]);
        if (file != null) {
          if (await file.length() > 2 * 1024 * 1024) {
            throw const SlipAgentException(
              'Choose a PNG or JPEG screenshot below 2 MB.',
            );
          }
          bytes = await file.readAsBytes();
        }
      }
      if (bytes != null && bytes.length > 2 * 1024 * 1024) {
        throw const SlipAgentException('Choose a screenshot below 2 MB.');
      }
      if (mounted && bytes != null) {
        setState(() {
          _image = bytes;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _send([
    String? text,
    bool confirmed = false,
    List<String>? bookingTickets,
  ]) async {
    if (_busy || _loading) return;
    final question = text ?? _message.text.trim();
    if (_pending == null && question.isEmpty && _image == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _warning = null;
    });
    try {
      if (_session == null) {
        final created = await _api.createSession();
        if (!mounted) return;
        setState(() {
          _session = created;
          _sessions.insert(0, created);
        });
      }
      _pending ??= {
        'request_id': newSlipAgentRequestId(),
        'version': _session!['version'],
        'message': question.isNotEmpty
            ? question
            : 'Read every visible pick in this screenshot, create a ticket and analyze it. Flag anything unclear.',
        'confirm_booking': confirmed,
        if (confirmed)
          'booking_ticket_ids':
              bookingTickets ?? (_state['active_ticket_ids'] as List? ?? []),
        if (_image != null) 'image_base64': base64Encode(_image!),
      };
      final result = await _api.sendTurn(_session!['id'].toString(), _pending!);
      if (!mounted) return;
      if (result['session'] is! Map) {
        throw const SlipAgentException(
          'Incomplete conversation response. Reload before retrying.',
        );
      }
      setState(() {
        _session = Map<String, dynamic>.from(result['session'] as Map);
        _confirmBooking = result['needs_booking_confirmation'] == true;
        final charge = result['coins_charged'];
        final balance = result['coins_balance'];
        _warning = [
          if (charge is num && balance is num)
            '$charge coins charged for this AI request. Balance: $balance coins.',
          if (result['warning'] != null) result['warning'].toString(),
        ].join(' ');
        _pending = null;
        _image = null;
        _message.clear();
        _sessions.removeWhere((s) => s['id'] == _session!['id']);
        _sessions.insert(0, _session!);
      });
      final user = SessionManager.instance.currentUser;
      if (user != null && result['coins_balance'] is num) {
        await SessionManager.instance.updateUser(
          user.copyWith(coins: (result['coins_balance'] as num).toInt()),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          if (e is SlipAgentException && e.status == 402) {
            _pending = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _ticket(Map<String, dynamic> ticket) {
    final picks = _rows(ticket['picks']);
    final active = (_state['active_ticket_ids'] as List? ?? []).contains(
      ticket['id'],
    );
    final booking = ticket['booking'] is Map
        ? Map<String, dynamic>.from(ticket['booking'] as Map)
        : <String, dynamic>{};
    final code = booking['booking_code']?.toString() ?? '';
    final total = double.tryParse(ticket['total_odds'].toString()) ?? 0;
    final id = ticket['id'].toString();
    return Card(
      child: ExpansionTile(
        key: PageStorageKey('slip-ticket-$id'),
        initiallyExpanded: active,
        title: Text(ticket['title']?.toString() ?? 'Ticket'),
        subtitle: Text(
          '${picks.length} picks ? ${active ? 'Active ticket' : 'Saved original / earlier ticket'}\nPrematch odds: ${total > 1 ? total.toStringAsFixed(2) : 'Unavailable'}',
        ),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          for (var i = 0; i < picks.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${i + 1}. ${picks[i]['home_team']} vs ${picks[i]['away_team']}\n'
                  '${picks[i]['selection']} (${picks[i]['market']}) ? ${_sport(picks[i]['sport_id'])}\n'
                  'Odds: ${_odds(picks[i]['odds'])} ? Probability: ${_probability(picks[i]['probability'])}'
                  '${picks[i]['probability_source'] == null || picks[i]['probability_source'] == '' ? '' : ' (Betmines estimate)'}'
                  '${picks[i]['warning'] == null || picks[i]['warning'] == '' ? '' : '\n${picks[i]['warning']}'}',
                ),
              ),
            ),
          if (code.isNotEmpty) ...[
            const Divider(),
            SelectableText(
              'SportyBet code: $code',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (booking['partial'] == true)
              Text(
                'Partial booking: ${booking['item_count']} of ${booking['requested_count']} picks accepted. Check the exclusions.',
              ),
            for (final excluded in _rows(booking['excluded_selections']))
              Text(
                '${excluded['home_team']} vs ${excluded['away_team']}: ${excluded['reason']}',
              ),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              icon: const Icon(Icons.copy),
              label: const Text('Copy code'),
            ),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: _busy || _pending != null
                    ? null
                    : () => _send('Analyze ticket $id only.'),
                child: const Text('Analyze'),
              ),
              if (picks.length >= 2)
                TextButton(
                  onPressed: _busy || _pending != null
                      ? null
                      : () => _send(
                          'Split ticket $id into two tickets and preserve its original.',
                        ),
                  child: const Text('Split in 2'),
                ),
              if (code.isEmpty)
                FilledButton.tonal(
                  onPressed: _busy || _pending != null
                      ? null
                      : () => _send(
                          'Generate a SportyBet booking code for ticket $id only. Do not edit any picks.',
                          true,
                          [id],
                        ),
                  child: const Text('Generate code (200 coins)'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _odds(dynamic value) {
    final n = double.tryParse(value.toString());
    return n != null && n.isFinite && n > 1 ? n.toStringAsFixed(2) : '\u2014';
  }

  String _probability(dynamic value) {
    final n = double.tryParse(value.toString());
    return n != null && n.isFinite && n >= 0 && n <= 100
        ? '${n.round()}%'
        : '\u2014';
  }

  String _sport(dynamic id) =>
      const {
        1: 'Football',
        2: 'Basketball',
        3: 'Tennis',
        4: 'Baseball',
        5: 'Hockey',
        6: 'Handball',
        7: 'Cricket',
        9: 'American football',
        10: 'Rugby union',
        8: 'Volleyball',
      }[id] ??
      'Sport unverified';

  @override
  Widget build(BuildContext context) {
    final messages = _rows(_state['messages']);
    final tickets = _rows(_state['tickets']);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'SlipIQ assistant',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Recent conversations',
                enabled: !_busy && !_loading,
                onSelected: (id) {
                  final selected = _sessions.firstWhere((s) => s['id'] == id);
                  setState(() {
                    _session = selected;
                    _pending = null;
                  });
                  _load();
                },
                itemBuilder: (_) => _sessions
                    .take(20)
                    .map(
                      (s) => PopupMenuItem(
                        value: s['id'].toString(),
                        child: Text(
                          'Conversation ${s['id'].toString().substring(0, 8)}',
                        ),
                      ),
                    )
                    .toList(),
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: 'New conversation',
                onPressed: _busy || _loading ? null : () => _load(fresh: true),
                icon: const Icon(Icons.add_comment_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (messages.isEmpty) ...[
                      const Text(
                        'Paste a booking code, attach a slip screenshot, or describe your picks. Then ask me to analyze, change or split the ticket.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Import a booking code'),
                            onPressed: () {
                              _message.text = 'Import my SportyBet code ';
                            },
                          ),
                          ActionChip(
                            label: const Text('Read a screenshot'),
                            onPressed: _busy ? null : _attach,
                          ),
                        ],
                      ),
                    ],
                    for (final message in messages)
                      Align(
                        alignment: message['role'] == 'user'
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: message['role'] == 'user'
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            message['text']?.toString() ?? '',
                          ),
                        ),
                      ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Checking your request and ticket data?'),
                      ),
                    for (final ticket in tickets) _ticket(ticket),
                    if (_warning != null && _warning!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(_warning!),
                      ),
                    if (_confirmBooking)
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _send(
                                'Generate SportyBet booking codes for the active tickets, without changing their picks.',
                                true,
                              ),
                        child: const Text('Generate booking codes'),
                      ),
                  ],
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (_pending != null)
                      TextButton(
                        onPressed: _busy ? null : () => _send(),
                        child: const Text('Retry same request'),
                      ),
                    TextButton(
                      onPressed: _busy ? null : () => _load(),
                      child: const Text('Reload conversation'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_image != null)
          Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.image_outlined),
              const SizedBox(width: 8),
              const Expanded(child: Text('Screenshot attached')),
              IconButton(
                tooltip: 'Remove screenshot',
                onPressed: _busy || _pending != null
                    ? null
                    : () => setState(() => _image = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                key: const Key('slipiq-attach'),
                tooltip: 'Attach slip screenshot',
                onPressed: _busy || _pending != null ? null : _attach,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              Expanded(
                child: TextField(
                  key: const Key('slipiq-message'),
                  controller: _message,
                  enabled: !_busy && _pending == null,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    hintText: 'Ask SlipIQ or edit your ticket?',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                key: const Key('slipiq-send'),
                tooltip: 'Send (100 coins)',
                onPressed: _busy || _loading || _pending != null
                    ? null
                    : () => _send(),
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '100 coins per AI request, including edits and screenshots.\nBooking: 100 coins extra per new code. Admins are exempt.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}
