import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/fixture_duel_model.dart';
import '../models/fixture_model.dart';
import 'app_config.dart';
import 'logging_client.dart';
import 'session_manager.dart';

class FixtureDuelService {
  final String baseUrl;
  final http.Client _client;

  FixtureDuelService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
      _client = client ?? LoggingClient();

  Map<String, String> get _headers {
    final token = SessionManager.instance.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to play Fixture Duel.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> _request(String path, {Object? body}) async {
    final url = Uri.parse('$baseUrl/api/v1/fixture-duel$path');
    final response =
        await (body == null
                ? _client.get(url, headers: _headers)
                : _client.post(url, headers: _headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 20));
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message'] : null;
      throw StateError(message?.toString() ?? 'Fixture Duel request failed.');
    }
    if (decoded is! Map) throw StateError('Invalid Fixture Duel response.');
    return decoded['data'];
  }

  Future<List<FixtureModel>> eligibleFixtures() async {
    final data = await _request('/fixtures');
    return data is List
        ? data
              .whereType<Map>()
              .map((e) => FixtureModel.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : [];
  }

  Future<List<FixtureDuelModel>> lobby() async {
    final data = await _request('/challenges');
    return _parseDuels(data);
  }

  Future<List<FixtureDuelModel>> mine() async {
    final data = await _request('/my-challenges');
    return _parseDuels(data);
  }

  List<FixtureDuelModel> _parseDuels(dynamic data) => data is List
      ? data
            .whereType<Map>()
            .map((e) => FixtureDuelModel.fromJson(Map<String, dynamic>.from(e)))
            .toList()
      : [];

  Future<FixtureDuelModel> create({
    required String fixtureId,
    required String creatorPick,
    required int stake,
  }) async {
    final data = await _request(
      '/challenges',
      body: {
        'fixture_id': fixtureId,
        'creator_pick': creatorPick,
        'stake': stake,
      },
    );
    return FixtureDuelModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<FixtureDuelModel> accept(FixtureDuelModel duel) async {
    final data = await _request(
      '/challenges/${duel.id}/accept',
      body: {'expected_stake': duel.stake},
    );
    return FixtureDuelModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> cancel(FixtureDuelModel duel) async {
    await _request('/challenges/${duel.id}/cancel', body: <String, dynamic>{});
  }
}
