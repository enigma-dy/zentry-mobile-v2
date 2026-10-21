import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/support_model.dart';
import 'logging_client.dart';
import 'app_config.dart';

class SupportServiceException implements Exception {
  final String message;
  final int statusCode;

  SupportServiceException(this.message, {this.statusCode = 400});

  @override
  String toString() => message;
}

class SupportService {
  final String baseUrl;
  final http.Client _client;

  SupportService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? _getDefaultBaseUrl(),
      _client = client ?? LoggingClient();

  static String _getDefaultBaseUrl() {
    return AppConfig.apiBaseUrl;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Submit contact us form payload to `POST /api/v1/support/contact`
  Future<ContactResponse> submitContactForm(ContactRequest request) async {
    final url = Uri.parse('$baseUrl/api/v1/support/contact');
    final response = await _client.post(
      url,
      headers: _headers,
      body: jsonEncode(request.toJson()),
    );

    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'] as Map<String, dynamic>? ?? jsonMap;
    return ContactResponse.fromJson(data);
  }

  /// Retrieve contact info and FAQs from `GET /api/v1/support/help`
  Future<HelpInfo> getHelpInfo() async {
    final url = Uri.parse('$baseUrl/api/v1/support/help');
    final response = await _client.get(url, headers: _headers);

    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'] as Map<String, dynamic>? ?? jsonMap;
    return HelpInfo.fromJson(data);
  }

  Map<String, dynamic> _parseResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw SupportServiceException(
        'Server returned invalid response format (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'data': decoded};
    }

    String message = 'Request failed';
    if (decoded is Map<String, dynamic>) {
      message = decoded['message'] as String? ?? message;
    }

    throw SupportServiceException(message, statusCode: response.statusCode);
  }
}
