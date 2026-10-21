import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/fpl_duel_model.dart';
import 'logging_client.dart';
import 'session_manager.dart';
import 'app_config.dart';

class FplDuelService {
  final String baseUrl;
  final http.Client _client;

  FplDuelService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? _getDefaultBaseUrl(),
      _client = client ?? LoggingClient();

  static String _getDefaultBaseUrl() {
    return AppConfig.apiBaseUrl;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = SessionManager.instance.accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      throw StateError('Sign in is required to use Fan Duel.');
    }
    return headers;
  }

  dynamic _safeJsonDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Future<FplGameweekModel> getGameweekStatus({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/fpl-duel/gameweek');
    try {
      final res = await _client.get(url, headers: _headers).timeout(timeout);
      final body = _safeJsonDecode(res.body);
      if (res.statusCode == 200) {
        if (body is Map && body['data'] != null) {
          return FplGameweekModel.fromJson(body['data']);
        }
      }
      throw Exception(
        (body is Map ? body['message'] : null) ??
            'Failed to load official FPL gameweek (${res.statusCode})',
      );
    } on TimeoutException {
      throw Exception('Official FPL gameweek request timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to load official FPL gameweek: $e');
    }
  }

  Future<FplTeamModel?> getMyTeam({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/fpl-duel/my-team');
    try {
      final res = await _client.get(url, headers: _headers).timeout(timeout);
      if (res.statusCode == 200) {
        final body = _safeJsonDecode(res.body);
        if (body is Map && body['data'] != null) {
          return FplTeamModel.fromJson(body['data']);
        }
        return null;
      }
      final body = _safeJsonDecode(res.body);
      throw Exception(
        (body is Map ? body['message'] : null) ??
            'Failed to load FPL team (${res.statusCode})',
      );
    } on TimeoutException {
      throw Exception('FPL team request timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to load FPL team: $e');
    }
  }

  Future<FplTeamModel> claimTeam(
    int fplEntryId, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/fpl-duel/claim');
    try {
      final res = await _client
          .post(
            url,
            headers: _headers,
            body: jsonEncode({'fpl_entry_id': fplEntryId}),
          )
          .timeout(timeout);
      final body = _safeJsonDecode(res.body);
      if (res.statusCode == 200 && body is Map && body['data'] != null) {
        return FplTeamModel.fromJson(body['data']);
      }
      final msg =
          (body is Map ? body['message'] : null) ??
          'Failed to claim FPL team (${res.statusCode})';
      throw Exception(msg);
    } on TimeoutException {
      throw Exception(
        'Connection timed out while claiming team. Please check your network.',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to claim team: $e');
    }
  }

  Future<FplTeamModel> verifyTeam({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/fpl-duel/verify');
    try {
      final res = await _client.post(url, headers: _headers).timeout(timeout);
      final body = _safeJsonDecode(res.body);
      if (res.statusCode == 200 && body is Map && body['data'] != null) {
        return FplTeamModel.fromJson(body['data']);
      }
      final msg =
          (body is Map ? body['message'] : null) ??
          'Verification failed (${res.statusCode})';
      throw Exception(msg);
    } on TimeoutException {
      throw Exception('Verification request timed out. Please try again.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Verification failed: $e');
    }
  }

  Future<FplWalletModel> getWallet({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/fpl-duel/wallet');
    try {
      final res = await _client.get(url, headers: _headers).timeout(timeout);
      if (res.statusCode == 200) {
        final body = _safeJsonDecode(res.body);
        if (body is Map && body['data'] != null) {
          return FplWalletModel.fromJson(body['data']);
        }
      }
      final body = _safeJsonDecode(res.body);
      throw Exception(
        (body is Map ? body['message'] : null) ??
            'Failed to load wallet (${res.statusCode})',
      );
    } on TimeoutException {
      throw Exception('Wallet request timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to load wallet: $e');
    }
  }

  Future<List<FplDuelChallengeModel>> getLobbyChallenges({
    String? mode,
    int? minStake,
    int? maxStake,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final queryParams = <String, String>{};
    if (mode != null && mode.isNotEmpty && mode != 'ALL') {
      queryParams['mode'] = mode;
    }
    if (minStake != null && minStake > 0) {
      queryParams['min_stake'] = minStake.toString();
    }
    if (maxStake != null && maxStake > 0) {
      queryParams['max_stake'] = maxStake.toString();
    }

    final uri = Uri.parse(
      '$baseUrl/api/v1/fpl-duel/challenges',
    ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);

    try {
      final res = await _client.get(uri, headers: _headers).timeout(timeout);
      final body = _safeJsonDecode(res.body);
      if (res.statusCode == 200) {
        if (body is Map && body['data'] is List) {
          return (body['data'] as List)
              .whereType<Map<String, dynamic>>()
              .map((item) => FplDuelChallengeModel.fromJson(item))
              .toList();
        }
      }
      throw Exception(
        (body is Map ? body['message'] : null) ??
            'Failed to load duel lobby (${res.statusCode})',
      );
    } on TimeoutException {
      throw Exception('Duel lobby request timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to load duel lobby: $e');
    }
  }

  Future<List<FplDuelChallengeModel>> getMyChallenges({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/fpl-duel/my-challenges');
    try {
      final res = await _client.get(url, headers: _headers).timeout(timeout);
      final body = _safeJsonDecode(res.body);
      if (res.statusCode == 200) {
        if (body is Map && body['data'] is List) {
          return (body['data'] as List)
              .whereType<Map<String, dynamic>>()
              .map((item) => FplDuelChallengeModel.fromJson(item))
              .toList();
        }
      }
      throw Exception(
        (body is Map ? body['message'] : null) ??
            'Failed to load your duels (${res.statusCode})',
      );
    } on TimeoutException {
      throw Exception('My duels request timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to load your duels: $e');
    }
  }

  Future<FplDuelChallengeModel> createChallenge({
    required int gameweek,
    required String mode,
    required int stakeKobo,
    bool allowChips = false,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/fpl-duel/challenges');
    try {
      final res = await _client
          .post(
            url,
            headers: _headers,
            body: jsonEncode({
              'gameweek': gameweek,
              'mode': mode,
              'stake': stakeKobo,
              'allow_chips': allowChips,
              'visibility': 'PUBLIC',
            }),
          )
          .timeout(timeout);
      final body = _safeJsonDecode(res.body);
      if ((res.statusCode == 200 || res.statusCode == 201) &&
          body is Map &&
          body['data'] != null) {
        return FplDuelChallengeModel.fromJson(body['data']);
      }
      final msg =
          (body is Map ? body['message'] : null) ??
          'Failed to create challenge (${res.statusCode})';
      throw Exception(msg);
    } on TimeoutException {
      throw Exception(
        'Challenge creation timed out. Please check your network.',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to create challenge: $e');
    }
  }

  Future<FplDuelChallengeModel> acceptChallenge(
    String challengeId, {
    int? expectedStakeKobo,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/v1/fpl-duel/challenges/$challengeId/accept',
    );
    try {
      final res = await _client
          .post(
            url,
            headers: _headers,
            body: jsonEncode({
              if (expectedStakeKobo != null)
                'expected_stake': expectedStakeKobo,
            }),
          )
          .timeout(timeout);
      final body = _safeJsonDecode(res.body);
      if (res.statusCode == 200 && body is Map && body['data'] != null) {
        return FplDuelChallengeModel.fromJson(body['data']);
      }
      final msg =
          (body is Map ? body['message'] : null) ??
          'Failed to accept challenge (${res.statusCode})';
      throw Exception(msg);
    } on TimeoutException {
      throw Exception('Accept challenge request timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to accept challenge: $e');
    }
  }

  Future<void> cancelChallenge(
    String challengeId, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/v1/fpl-duel/challenges/$challengeId/cancel',
    );
    try {
      final res = await _client.post(url, headers: _headers).timeout(timeout);
      if (res.statusCode != 200) {
        final body = _safeJsonDecode(res.body);
        final msg =
            (body is Map ? body['message'] : null) ??
            'Failed to cancel challenge (${res.statusCode})';
        throw Exception(msg);
      }
    } on TimeoutException {
      throw Exception('Cancel request timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to cancel challenge: $e');
    }
  }

  /// Search users/rivals by query for FPL Duels
  Future<List<Map<String, dynamic>>> searchUsers(
    String query, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/users/search',
    ).replace(queryParameters: {'q': query});
    try {
      final res = await _client.get(uri, headers: _headers).timeout(timeout);
      final body = _safeJsonDecode(res.body);
      if (res.statusCode == 200) {
        if (body is Map &&
            body['data'] is Map &&
            body['data']['users'] is List) {
          return List<Map<String, dynamic>>.from(body['data']['users']);
        }
      }
      throw Exception(
        (body is Map ? body['message'] : null) ??
            'Rival search failed (${res.statusCode})',
      );
    } on TimeoutException {
      throw Exception('Rival search request timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Rival search failed: $e');
    }
  }

  /// Initialize real Paystack or NOWPayments checkout for wallet funding
  Future<Map<String, dynamic>> createWalletCheckout({
    required String provider,
    required double amountNgn,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/billing/checkout');
    try {
      final res = await _client
          .post(
            url,
            headers: _headers,
            body: jsonEncode({
              'provider': provider,
              'item_type': 'wallet_deposit',
              'item_id': 'wallet_${amountNgn.toInt()}',
              'amount': amountNgn,
            }),
          )
          .timeout(timeout);
      final body = _safeJsonDecode(res.body);
      if (res.statusCode == 200 && body is Map && body['data'] != null) {
        return Map<String, dynamic>.from(body['data'] as Map);
      }
      final msg =
          (body is Map ? body['message'] : null) ??
          'Failed to initialize payment checkout';
      throw Exception(msg);
    } on TimeoutException {
      throw Exception('Payment gateway connection timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Payment initialization failed: $e');
    }
  }

  /// Convert booking codes between bookmakers
  Future<Map<String, dynamic>> convertBetCode({
    required String from,
    required String to,
    required String code,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/betcode/convert');
    try {
      final res = await _client
          .post(
            url,
            headers: _headers,
            body: jsonEncode({'from': from, 'to': to, 'code': code}),
          )
          .timeout(timeout);
      final body = _safeJsonDecode(res.body);
      if (res.statusCode == 200 && body is Map && body['data'] != null) {
        return Map<String, dynamic>.from(body['data'] as Map);
      }
      final msg =
          (body is Map ? body['message'] : null) ??
          'Failed to convert booking code';
      throw Exception(msg);
    } on TimeoutException {
      throw Exception('Conversion engine timed out.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Booking code conversion failed: $e');
    }
  }
}
