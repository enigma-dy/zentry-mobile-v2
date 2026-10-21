import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'session_manager.dart';

/// An [http.Client] wrapper that logs HTTP requests and responses sent to the backend.
class LoggingClient extends http.BaseClient {
  final http.Client _inner;

  LoggingClient([http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _attachCurrentToken(request);
    final String requestBody;

    if (request is http.Request && request.body.isNotEmpty) {
      requestBody = request.body;
    } else {
      requestBody = '';
    }

    _logRequest(
      method: request.method,
      url: request.url,
      headers: request.headers,
      body: requestBody,
    );

    try {
      var response = await _inner.send(request);
      if (response.statusCode == 401 &&
          request is http.Request &&
          !_isAuthEndpoint(request.url)) {
        final unauthorizedBytes = await response.stream.toBytes();
        final refreshed = await SessionManager.instance.getValidAccessToken(
          forceRefresh: true,
        );
        if (refreshed != null && refreshed.isNotEmpty) {
          final retry = _copyRequest(request);
          retry.headers['Authorization'] = 'Bearer $refreshed';
          response = await _inner.send(retry);
        } else {
          response = http.StreamedResponse(
            Stream.value(unauthorizedBytes),
            response.statusCode,
            contentLength: unauthorizedBytes.length,
            request: response.request,
            headers: response.headers,
            isRedirect: response.isRedirect,
            persistentConnection: response.persistentConnection,
            reasonPhrase: response.reasonPhrase,
          );
        }
      }
      final bytes = await response.stream.toBytes();

      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      rethrow;
    }
  }

  Future<void> _attachCurrentToken(http.BaseRequest request) async {
    if (_isAuthEndpoint(request.url)) return;
    if (!request.headers.containsKey('Authorization')) return;
    final token = await SessionManager.instance.getValidAccessToken();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
  }

  bool _isAuthEndpoint(Uri url) => url.path.contains('/api/v1/auth/');

  http.Request _copyRequest(http.Request original) {
    final copy = http.Request(original.method, original.url)
      ..headers.addAll(original.headers)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection
      ..bodyBytes = original.bodyBytes;
    return copy;
  }

  void _logRequest({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required String body,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('==================================================');
    buffer.writeln('🌐 [HTTP REQUEST] $method $url');
    if (headers.isNotEmpty) {
      buffer.writeln('📋 Headers: ${jsonEncode(headers)}');
    }
    if (body.isNotEmpty) {
      buffer.writeln('📦 Body: ${_formatJsonIfPossible(body)}');
    }
    buffer.write('==================================================');
    debugPrint(buffer.toString());
  }

  void _logResponse({
    required int statusCode,
    required String method,
    required Uri url,
    required String body,
    required int durationMs,
  }) {
    final isSuccess = statusCode >= 200 && statusCode < 300;
    final icon = isSuccess ? '✅' : '❌';
    final buffer = StringBuffer();
    buffer.writeln('--------------------------------------------------');
    buffer.writeln(
      '$icon [HTTP RESPONSE] $statusCode $method $url (${durationMs}ms)',
    );
    if (body.isNotEmpty) {
      buffer.writeln('📄 Body: ${_formatJsonIfPossible(body)}');
    }
    buffer.write('--------------------------------------------------');
    debugPrint(buffer.toString());
  }

  void _logError({
    required String method,
    required Uri url,
    required Object error,
    required int durationMs,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('--------------------------------------------------');
    buffer.writeln('⚠️ [HTTP ERROR] $method $url failed after ${durationMs}ms');
    buffer.writeln('🚨 Error: $error');
    buffer.write('--------------------------------------------------');
    debugPrint(buffer.toString());
  }

  String _formatJsonIfPossible(String input) {
    try {
      final decoded = jsonDecode(input);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return input;
    }
  }

  @override
  void close() {
    _inner.close();
  }
}
