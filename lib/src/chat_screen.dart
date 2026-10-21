import 'dart:async';
import 'package:flutter/material.dart';

import 'models/fixture_model.dart';
import 'models/fpl_duel_model.dart';
import 'services/chat_service.dart';
import 'services/fpl_duel_service.dart';

class ChatScreen extends StatefulWidget {
  final List<FixtureModel> fixtures;
  final List<PredictionModel> predictions;
  final VoidCallback onCreateChallenge;

  const ChatScreen({
    super.key,
    required this.fixtures,
    required this.predictions,
    required this.onCreateChallenge,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _service = ChatService();
  final FplDuelService _duelService = FplDuelService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  List<Map<String, dynamic>> _messages = [];
  final Map<String, String> _mentions = {};
  Map<String, String>? _entity;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final messages = await _service.loadMessages();
      final stream = await _service.connect(
        knownMessageIds: messages.map(
          (message) => message['id']?.toString() ?? '',
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = messages;
        _loading = false;
      });
      _subscription = stream.listen(
        (event) {
          if (!mounted) return;
          if (event['type'] == 'chat_message' && event['data'] is Map) {
            final message = Map<String, dynamic>.from(event['data'] as Map);
            final messageID = message['id']?.toString() ?? '';
            if (messageID.isEmpty ||
                !_messages.any((item) => item['id']?.toString() == messageID)) {
              setState(() => _messages.add(message));
            }
            _scrollToEnd();
          } else if (event['type'] == 'notification' && event['data'] is Map) {
            final data = Map<String, dynamic>.from(event['data'] as Map);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message']?.toString() ?? 'New mention'),
              ),
            );
          } else if (event['type'] == 'error') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(event['message']?.toString() ?? 'Chat error'),
              ),
            );
          }
        },
        onError: (Object error) {
          if (mounted) setState(() => _error = 'Chat connection lost: $error');
        },
      );
      _scrollToEnd();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    try {
      await _service.sendMessage(
        body: body,
        mentionedUserIds: _mentions.keys.toList(),
        entityType: _entity?['type'],
        entityId: _entity?['id'],
      );
      _controller.clear();
      setState(() {
        _mentions.clear();
        _entity = null;
      });
    } catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _pickMention() async {
    final users = await _service.searchUsers('');
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF191126),
      builder: (context) => ListView(
        children: users.map((user) {
          final id = user['id']?.toString() ?? '';
          final username = user['username']?.toString() ?? '';
          return ListTile(
            leading: const Icon(
              Icons.alternate_email,
              color: Color(0xFFFFD700),
            ),
            title: Text(
              '@$username',
              style: const TextStyle(color: Colors.white),
            ),
            trailing: TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onCreateChallenge();
              },
              child: const Text('Challenge'),
            ),
            onTap: id.isEmpty || username.isEmpty
                ? null
                : () {
                    setState(() {
                      _mentions[id] = username;
                      final prefix = _controller.text.isEmpty
                          ? ''
                          : '${_controller.text} ';
                      _controller.text = '$prefix@$username ';
                      _controller.selection = TextSelection.collapsed(
                        offset: _controller.text.length,
                      );
                    });
                    Navigator.pop(context);
                  },
          );
        }).toList(),
      ),
    );
  }

  Future<void> _pickEntity() async {
    var challenges = <FplDuelChallengeModel>[];
    try {
      challenges = await _duelService.getMyChallenges();
    } catch (_) {
      // Fixtures and predictions remain available if challenges cannot load.
    }
    if (!mounted) return;
    final entries = <Map<String, String>>[
      ...widget.fixtures
          .take(20)
          .map(
            (f) => {
              'type': 'fixture',
              'id': f.id,
              'label': '${f.homeTeam} vs ${f.awayTeam}',
            },
          ),
      ...widget.predictions
          .where((p) => RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(p.id))
          .take(20)
          .map(
            (p) => {
              'type': 'prediction',
              'id': p.id,
              'label': '${p.homeTeam} vs ${p.awayTeam} · ${p.prediction}',
            },
          ),
      ...challenges
          .take(20)
          .map(
            (c) => {
              'type': 'challenge',
              'id': c.id,
              'label': '${c.creatorTeamName} · GW${c.gameweek}',
            },
          ),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF191126),
      builder: (context) => entries.isEmpty
          ? const Center(
              child: Text(
                'No real fixtures, predictions, or challenges available.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : ListView(
              children: entries
                  .map(
                    (entry) => ListTile(
                      leading: const Icon(Icons.tag, color: Color(0xFF00E676)),
                      title: Text(
                        entry['label']!,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        entry['type']!,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      onTap: () {
                        setState(() => _entity = entry);
                        Navigator.pop(context);
                      },
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Future<void> _showNotifications() async {
    try {
      final notifications = await _service.loadNotifications();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF191126),
        builder: (context) => notifications.isEmpty
            ? const Center(
                child: Text(
                  'No notifications yet.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : ListView(
                children: notifications.map((notification) {
                  final id = notification['id']?.toString() ?? '';
                  final unread = notification['read_at'] == null;
                  return ListTile(
                    leading: Icon(
                      unread ? Icons.notifications_active : Icons.notifications,
                      color: unread ? const Color(0xFFFFD700) : Colors.white38,
                    ),
                    title: Text(
                      notification['message']?.toString() ?? '',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: id.isEmpty
                        ? null
                        : () async {
                            if (unread) await _service.markNotificationRead(id);
                            if (context.mounted) Navigator.pop(context);
                          },
                  );
                }).toList(),
              ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.close();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B12),
      appBar: AppBar(
        title: const Text('Chat'),
        backgroundColor: const Color(0xFF171221),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _showNotifications,
            tooltip: 'Mentions',
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(onPressed: _start, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final label = message['entity_label']?.toString() ?? '';
                      return Card(
                        color: const Color(0xFF1B1426),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@${message['username']}',
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message['body']?.toString() ?? '',
                                style: const TextStyle(color: Colors.white),
                              ),
                              if (label.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Chip(
                                  label: Text(label),
                                  avatar: const Icon(Icons.tag, size: 16),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_entity != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.tag, color: Color(0xFF00E676)),
              title: Text(
                _entity!['label']!,
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: IconButton(
                onPressed: () => setState(() => _entity = null),
                icon: const Icon(Icons.close, color: Colors.white54),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _pickMention,
                    tooltip: 'Mention user',
                    icon: const Icon(
                      Icons.alternate_email,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                  IconButton(
                    onPressed: _pickEntity,
                    tooltip: 'Tag fixture, prediction, or challenge',
                    icon: const Icon(Icons.tag, color: Color(0xFF00E676)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Message the community…',
                        hintStyle: TextStyle(color: Colors.white38),
                        counterText: '',
                        filled: true,
                        fillColor: Color(0xFF1B1426),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
