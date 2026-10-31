import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'session_manager.dart';

class SlipAgentException implements Exception {
  final String message;
  final int status;
  const SlipAgentException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

String newSlipAgentRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// No automatic POST retries: the UI retains the same request ID and payload.
/// Image bodies and auth headers never go through the app's logging client.
class SlipAgentService {
  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  SlipAgentService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  Future<dynamic> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final existing = SessionManager.instance.accessToken;
    final token = existing == null
        ? null
        : await SessionManager.instance.getValidAccessToken();
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final uri = Uri.parse(
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/slip-analysis/agent/$path',
    );
    try {
      final response =
          await (method == 'POST'
                  ? _client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(body ?? {}),
                    )
                  : _client.get(uri, headers: headers))
              .timeout(const Duration(seconds: 95));
      dynamic parsed;
      try {
        parsed = jsonDecode(response.body);
      } catch (_) {
        throw const SlipAgentException(
          'SlipIQ returned an unreadable response. Reload before retrying.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = parsed is Map ? parsed['message']?.toString() : null;
        throw SlipAgentException(
          response.statusCode == 401
              ? 'Sign in to use SlipIQ.'
              : (message ?? 'SlipIQ could not complete this request.'),
          response.statusCode,
        );
      }
      if (parsed is! Map || !parsed.containsKey('data')) {
        throw const SlipAgentException(
          'SlipIQ returned an incomplete response. Reload before retrying.',
        );
      }
      return parsed['data'];
    } on TimeoutException {
      throw const SlipAgentException(
        'SlipIQ is taking longer than expected. Retry the same request or reload to check saved changes.',
      );
    } on http.ClientException {
      throw const SlipAgentException(
        'Connection interrupted. Retry the same request or reload before generating another code.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    final data = await _request('GET', 'sessions');
    if (data is! List) {
      throw const SlipAgentException('Conversations could not be loaded.');
    }
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createSession() async =>
      Map<String, dynamic>.from(await _request('POST', 'sessions') as Map);
  Future<Map<String, dynamic>> getSession(String id) async =>
      Map<String, dynamic>.from(
        await _request('GET', 'sessions/${Uri.encodeComponent(id)}') as Map,
      );
  Future<Map<String, dynamic>> sendTurn(
    String id,
    Map<String, dynamic> request,
  ) async => Map<String, dynamic>.from(
    await _request('POST', 'sessions/${Uri.encodeComponent(id)}/turns', request)
        as Map,
  );
  void dispose() {
    if (_ownsClient) _client.close();
  }
}
