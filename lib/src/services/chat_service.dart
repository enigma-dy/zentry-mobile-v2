import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'session_manager.dart';
import 'app_config.dart';

class ChatService {
  final String baseUrl;
  final http.Client _client;
  WebSocketChannel? _channel;
  bool _closed = false;

  ChatService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? _defaultBaseUrl(),
      _client = client ?? http.Client();

  static String _defaultBaseUrl() {
    return AppConfig.apiBaseUrl;
  }

  Future<Map<String, String>> _headers() async {
    final token = await SessionManager.getAccessToken();
    if (token == null || token.isEmpty) throw StateError('Login is required');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['message']?.toString() ?? 'Request failed');
    }
    return body;
  }

  Future<List<Map<String, dynamic>>> loadMessages() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/chat/messages?limit=100'),
      headers: await _headers(),
    );
    final data = _decode(response)['data'];
    return data is List
        ? data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : [];
  }

  Future<Stream<Map<String, dynamic>>> connect({
    Iterable<String> knownMessageIds = const [],
  }) async {
    _closed = false;
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/v1/chat/socket-ticket'),
        headers: await _headers(),
      );
      final data = Map<String, dynamic>.from(_decode(response)['data'] as Map);
      final ticket = data['ticket']?.toString() ?? '';
      if (ticket.isEmpty) throw Exception('Socket ticket was not returned');
      final base = Uri.parse(baseUrl);
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/api/v1/chat/ws',
        queryParameters: {'ticket': ticket},
        fragment: '',
      );
      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 8));
      _channel = channel;
      return channel.stream.map((event) {
        final decoded = jsonDecode(event.toString());
        return Map<String, dynamic>.from(decoded as Map);
      });
    } catch (_) {
      await _channel?.sink.close();
      _channel = null;
      return _pollMessages(knownMessageIds.toSet());
    }
  }

  Stream<Map<String, dynamic>> _pollMessages(Set<String> seen) async* {
    while (!_closed) {
      try {
        final messages = await loadMessages();
        for (final message in messages) {
          final id = message['id']?.toString() ?? '';
          if (id.isNotEmpty && seen.add(id)) {
            yield {'type': 'chat_message', 'data': message};
          }
        }
      } catch (_) {
        // A later poll retries transient proxy or network failures.
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> sendMessage({
    required String body,
    List<String> mentionedUserIds = const [],
    String? entityType,
    String? entityId,
  }) async {
    final payload = {
      'body': body,
      'mentioned_user_ids': mentionedUserIds,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
    };
    final channel = _channel;
    if (channel != null) {
      channel.sink.add(jsonEncode(payload));
      return;
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/chat/messages'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    _decode(response);
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/users/search',
    ).replace(queryParameters: {'q': query});
    final response = await _client.get(uri, headers: await _headers());
    final data = _decode(response)['data'];
    if (data is Map && data['users'] is List) {
      return (data['users'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> loadNotifications() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/chat/notifications'),
      headers: await _headers(),
    );
    final data = _decode(response)['data'];
    return data is List
        ? data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : [];
  }

  Future<void> markNotificationRead(String id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/chat/notifications/$id/read'),
      headers: await _headers(),
    );
    if (response.statusCode != 204) _decode(response);
  }

  Future<void> clearNotifications() async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/v1/chat/notifications'),
      headers: await _headers(),
    );
    if (response.statusCode != 204) _decode(response);
  }

  Future<bool> notificationMuted() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/chat/notifications/preferences'),
      headers: await _headers(),
    );
    final data = _decode(response)['data'];
    return data is Map && data['muted'] == true;
  }

  Future<void> setNotificationMuted(bool muted) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/api/v1/chat/notifications/preferences'),
      headers: await _headers(),
      body: jsonEncode({'muted': muted}),
    );
    _decode(response);
  }

  Future<void> close() async {
    _closed = true;
    await _channel?.sink.close();
    _channel = null;
    _client.close();
  }
}
