import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/sport_model.dart';
import '../models/league_model.dart';
import '../models/fixture_model.dart';
import '../models/paginated_response.dart';
import '../models/ticket_bucket_model.dart';
import '../models/ace_channel_model.dart';
import 'logging_client.dart';
import 'session_manager.dart';
import 'app_config.dart';

class SportsException implements Exception {
  final String message;
  final int statusCode;
  final dynamic errors;

  SportsException(this.message, {this.statusCode = 400, this.errors});

  @override
  String toString() => message;
}

class SportsService {
  final String baseUrl;
  final http.Client _client;

  SportsService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? _getDefaultBaseUrl(),
      _client = client ?? LoggingClient();

  static String _getDefaultBaseUrl() {
    return AppConfig.apiBaseUrl;
  }

  Map<String, String> get _headers {
    final token = SessionManager.instance.accessToken;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, String> get _authenticatedHeaders => _headers;

  Future<Map<String, dynamic>> checkAppVersion(String installedVersion) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/system/app-version',
    ).replace(queryParameters: {'version': installedVersion});
    final response = await _client.get(uri, headers: _headers);
    final decoded = _parseResponse(response);
    final data = decoded['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Fetch all active sports disciplines
  /// `GET /api/v1/sports`
  Future<List<SportModel>> getSports({
    http.Client? client,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/sports');
    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);

      final jsonMap = _parseResponse(response);
      final data = jsonMap['data'];
      if (data is List) {
        return data
            .where((item) => item is Map)
            .map(
              (item) =>
                  SportModel.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Fetch leagues with optional filter criteria (sport_id, date, status)
  /// `GET /api/v1/leagues?sport_id=1&date=2026-09-20&status=prematch`
  Future<List<LeagueModel>> getLeagues({
    int? sportId,
    String? date,
    String? status,
    http.Client? client,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final httpClient = client ?? _client;
    final queryParams = <String, String>{};
    if (sportId != null) queryParams['sport_id'] = sportId.toString();
    if (date != null && date.isNotEmpty) queryParams['date'] = date;
    if (status != null && status.isNotEmpty) queryParams['status'] = status;

    final url = Uri.parse(
      '$baseUrl/api/v1/leagues',
    ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);
      final jsonMap = _parseResponse(response);
      final data = jsonMap['data'];
      if (data is List) {
        return data
            .where((item) => item is Map)
            .map(
              (item) =>
                  LeagueModel.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Fetch daily fixtures filtered by sport_id, page, page_size, date, status, league, country
  /// `GET /api/v1/fixtures?sport_id=1&page=1&page_size=20&status=prematch`
  Future<PaginatedResponse<FixtureModel>> getFixturesPaginated({
    int? sportId,
    int? page,
    int? pageSize,
    String? date,
    String? status,
    String? league,
    String? leagueId,
    String? country,
    String? query,
    http.Client? client,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final httpClient = client ?? _client;
    final queryParams = <String, String>{};
    if (sportId != null) queryParams['sport_id'] = sportId.toString();
    if (page != null) queryParams['page'] = page.toString();
    if (pageSize != null) queryParams['page_size'] = pageSize.toString();
    if (date != null && date.isNotEmpty) queryParams['date'] = date;
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    if (league != null && league.isNotEmpty) queryParams['league'] = league;
    if (leagueId != null && leagueId.isNotEmpty) {
      queryParams['league_id'] = leagueId;
    }
    if (country != null && country.isNotEmpty) queryParams['country'] = country;
    if (query != null && query.trim().isNotEmpty) {
      queryParams['query'] = query.trim();
    }

    final url = Uri.parse(
      '$baseUrl/api/v1/fixtures',
    ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);
      final jsonMap = _parseResponse(response);
      return PaginatedResponse<FixtureModel>.fromJson(
        jsonMap,
        (m) => FixtureModel.fromJson(m),
      );
    } on TimeoutException {
      throw SportsException(
        'Fixtures took too long to load. Please try again.',
      );
    } on SportsException {
      rethrow;
    } catch (error) {
      debugPrint('Unable to load fixtures: $error');
      throw SportsException('Unable to load fixtures. Please try again.');
    }
  }

  /// Read every page for the selected day, including completed fixtures.
  /// Used by the country and league pickers rather than the first home page.
  Future<List<FixtureModel>> getDailyFixtures({
    required int sportId,
    required String date,
    http.Client? client,
  }) async {
    final first = await getFixturesPaginated(
      sportId: sportId,
      date: date,
      page: 1,
      pageSize: 200,
      client: client,
    ).timeout(const Duration(seconds: 60));
    if (!first.success) throw SportsException('Unable to load daily fixtures');
    final fixtures = <String, FixtureModel>{
      for (final fixture in first.data) fixture.id: fixture,
    };
    for (var page = 2; page <= first.totalPages; page += 4) {
      final end = (page + 3).clamp(page, first.totalPages);
      final pages = await Future.wait([
        for (var current = page; current <= end; current++)
          getFixturesPaginated(
            sportId: sportId,
            date: date,
            page: current,
            pageSize: 200,
            client: client,
          ).timeout(const Duration(seconds: 60)),
      ]);
      for (final result in pages) {
        if (!result.success) {
          throw SportsException('Unable to load daily fixtures');
        }
        for (final fixture in result.data) {
          fixtures[fixture.id] = fixture;
        }
      }
    }
    return fixtures.values.toList();
  }

  /// Helper returning just the `List<FixtureModel>`
  Future<List<FixtureModel>> getFixtures({
    int? sportId,
    int? page,
    int? pageSize,
    String? date,
    String? status,
    String? league,
    String? leagueId,
    String? country,
    http.Client? client,
  }) async {
    final paginated = await getFixturesPaginated(
      sportId: sportId,
      page: page,
      pageSize: pageSize,
      date: date,
      status: status,
      league: league,
      leagueId: leagueId,
      country: country,
      client: client,
    );
    return paginated.data;
  }

  /// Fetch path-based sport fixtures:
  /// `GET /api/v1/sports/{sportId}/fixtures?page=1&page_size=10`
  Future<PaginatedResponse<FixtureModel>> getFixturesBySport({
    required int sportId,
    int? page,
    int? pageSize,
    String? date,
    String? status,
    http.Client? client,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final httpClient = client ?? _client;
    final queryParams = <String, String>{};
    if (page != null) queryParams['page'] = page.toString();
    if (pageSize != null) queryParams['page_size'] = pageSize.toString();
    if (date != null && date.isNotEmpty) queryParams['date'] = date;
    if (status != null && status.isNotEmpty) queryParams['status'] = status;

    final url = Uri.parse(
      '$baseUrl/api/v1/sports/$sportId/fixtures',
    ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);
      final jsonMap = _parseResponse(response);
      return PaginatedResponse<FixtureModel>.fromJson(
        jsonMap,
        (m) => FixtureModel.fromJson(m),
      );
    } catch (_) {
      return PaginatedResponse<FixtureModel>(
        success: false,
        count: 0,
        total: 0,
        page: page ?? 1,
        pageSize: pageSize ?? 10,
        totalPages: 1,
        data: const [],
      );
    }
  }

  /// Fetch current live fixtures
  /// `GET /api/v1/fixtures/live`
  Future<List<FixtureModel>> getLiveFixtures({
    http.Client? client,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/fixtures/live');
    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);

      final jsonMap = _parseResponse(response);
      final data = jsonMap['data'];
      if (data is List) {
        return data
            .where((item) => item is Map)
            .map(
              (item) =>
                  FixtureModel.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Fetch enriched fixture details by fixture ID
  /// `GET /api/v1/fixtures/:id`
  Future<EnrichedFixtureDetailModel> getFixtureDetail(
    String fixtureId, {
    bool includeStreams = true,
    bool refresh = false,
    http.Client? client,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse(
      '$baseUrl/api/v1/fixtures/$fixtureId',
    ).replace(queryParameters: refresh ? const {'refresh': 'true'} : null);
    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);

      final jsonMap = _parseResponse(response);
      final data = jsonMap['data'];
      if (data is Map<String, dynamic>) {
        final detail = EnrichedFixtureDetailModel.fromJson(data);
        // Attempt to load associated streaming links if requested
        if (includeStreams) {
          try {
            final streamInfo = await getFixtureStreams(
              fixtureId,
              client: httpClient,
              timeout: const Duration(seconds: 3),
            );
            if (streamInfo.hasStreams) {
              return detail.copyWithStreams(streamInfo);
            }
          } catch (_) {}
        }
        return detail;
      }
      throw SportsException('Fixture data unavailable', statusCode: 404);
    } on TimeoutException {
      throw SportsException(
        'Fixture $fixtureId request timed out',
        statusCode: 408,
      );
    } catch (e) {
      if (e is SportsException) rethrow;
      throw SportsException('Fixture $fixtureId request failed: $e');
    }
  }

  /// Fetch active live streaming catalogue from backend
  /// `GET /api/v1/live-streams?live=true`
  Future<LiveStreamSnapshotModel> getLiveStreams({
    bool live = true,
    String? category,
    http.Client? client,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final httpClient = client ?? _client;
    final queryParams = <String, String>{'live': live ? 'true' : 'false'};
    if (category != null && category.isNotEmpty) {
      queryParams['category'] = category;
    }

    final url = Uri.parse(
      '$baseUrl/api/v1/live-streams',
    ).replace(queryParameters: queryParams);

    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);
      final jsonMap = _parseResponse(response);
      final data = jsonMap['data'];
      if (data is Map<String, dynamic>) {
        return LiveStreamSnapshotModel.fromJson(data);
      }
      return const LiveStreamSnapshotModel();
    } catch (e) {
      if (e is SportsException) rethrow;
      throw SportsException('Live stream catalogue request failed: $e');
    }
  }

  /// Fetch streaming links for a specific fixture UUID
  /// `GET /api/v1/fixtures/:id/streams`
  Future<FixtureStreamsModel> getFixtureStreams(
    String fixtureId, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/fixtures/$fixtureId/streams');

    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);
      final jsonMap = _parseResponse(response);
      final data = jsonMap['data'];
      if (data is Map<String, dynamic>) {
        return FixtureStreamsModel.fromJson(data);
      }
      return FixtureStreamsModel(fixtureId: fixtureId);
    } catch (_) {
      return FixtureStreamsModel(fixtureId: fixtureId);
    }
  }

  /// Fetch stream details by stream ID
  /// `GET /api/v1/live-streams/:id`
  Future<LiveStreamEventModel?> getStreamDetail(
    String id, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/live-streams/$id');

    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);
      final jsonMap = _parseResponse(response);
      final data = jsonMap['data'];
      if (data is Map<String, dynamic>) {
        if (data['fixture'] is Map<String, dynamic>) {
          return LiveStreamEventModel.fromJson(data['fixture']);
        }
        if (data['fixtures'] is List && (data['fixtures'] as List).isNotEmpty) {
          return LiveStreamEventModel.fromJson(
            (data['fixtures'] as List).first,
          );
        }
        return LiveStreamEventModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns AceStream channel metadata only. Playback is always performed by
  /// the Ace Engine running on the user's device.
  Future<List<AceChannelModel>> getAceChannels({
    String category = 'sport',
    String query = '',
    http.Client? client,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/live-streams/ace/channels').replace(
      queryParameters: {
        'category': category,
        if (query.trim().isNotEmpty) 'query': query.trim(),
      },
    );
    final response = await (client ?? _client)
        .get(uri, headers: _headers)
        .timeout(timeout);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is! Map || data['channels'] is! List) return const [];
    return (data['channels'] as List)
        .whereType<Map>()
        .map(
          (item) => AceChannelModel.fromJson(Map<String, dynamic>.from(item)),
        )
        .where(
          (channel) => channel.name.isNotEmpty && channel.infoHash.length == 40,
        )
        .toList();
  }

  /// Fetch sync count statistics for predictions and fixtures
  /// `GET /api/v1/predictions/sync-count`
  Future<Map<String, dynamic>> getPredictionSyncCount({
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/predictions/sync-count');
    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);
      final jsonMap = _parseResponse(response);
      final data = jsonMap['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<List<PredictionModel>> getPredictions({
    int sportId = 1,
    String? date,
    int pageSize = 100,
    http.Client? client,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/predictions').replace(
      queryParameters: {
        'sportId': sportId.toString(),
        'page': '1',
        'page_size': pageSize.toString(),
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    try {
      final response = await httpClient
          .get(url, headers: _headers)
          .timeout(timeout);
      final jsonMap = _parseResponse(response);
      final envelope = jsonMap['data'];
      List items = const [];
      if (envelope is Map && envelope['data'] is List) {
        items = envelope['data'] as List;
      } else if (envelope is List) {
        items = envelope;
      } else if (jsonMap['data'] is List) {
        items = jsonMap['data'] as List;
      }
      return items
          .where((item) => item is Map)
          .map(
            (item) => PredictionModel.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .where((item) => item.prediction.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Trigger on-demand prediction sync (Betmines for Football)
  /// `POST /api/v1/predictions/sync?sportId=1`
  Future<Map<String, dynamic>> syncPredictions({
    int sportId = 1,
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/predictions/sync?sportId=$sportId');
    final response = await httpClient.post(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {};
  }

  /// Trigger evaluation and settlement of finished predictions
  /// `POST /api/v1/predictions/settle`
  Future<Map<String, dynamic>> triggerSettlement({http.Client? client}) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/predictions/settle');
    final response = await httpClient.post(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {};
  }

  /// Generate SportyBet booking code for a list of selections or a ticket bucket
  /// `POST /api/v1/tickets/quick-generate`
  Future<BookingCodeResult> generateBookingCode({
    required List<TicketSelectionModel> selections,
    String platform = 'sportybetng',
    String title = 'AI Predictions Accumulator',
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/tickets/quick-generate');
    final payload = jsonEncode({
      'platform': platform,
      'title': title,
      'selections': selections.map((s) => s.toJson()).toList(),
    });

    final response = await httpClient.post(
      url,
      headers: _headers,
      body: payload,
    );
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return BookingCodeResult.fromJson(data);
    }
    throw SportsException('Failed to generate booking code');
  }

  /// Quick generate SportyBet booking code alias
  Future<BookingCodeResult> quickGenerateSportyBetCode({
    required List<TicketSelectionModel> selections,
    String platform = 'sportybetng',
    String title = 'AI Predictions Accumulator',
    http.Client? client,
  }) => generateBookingCode(
    selections: selections,
    platform: platform,
    title: title,
    client: client,
  );

  /// Create and save a Ticket Bucket on backend
  /// `POST /api/v1/tickets/bucket`
  Future<TicketBucketModel> createTicketBucket({
    required List<TicketSelectionModel> selections,
    String platform = 'sportybetng',
    String title = 'AI Predictions Accumulator',
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/tickets/bucket');
    final payload = jsonEncode({
      'platform': platform,
      'title': title,
      'selections': selections.map((s) => s.toJson()).toList(),
    });

    final response = await httpClient.post(
      url,
      headers: _headers,
      body: payload,
    );
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return TicketBucketModel.fromJson(data);
    }
    throw SportsException('Failed to create ticket bucket');
  }

  /// Unified prediction page feed with market tags and comprehensive filters
  Future<Map<String, dynamic>> getPredictionFeed({
    String? tag,
    String? sport,
    String? market,
    String? source,
    bool? isPopular,
    double? minOdds,
    double? maxOdds,
    int? minConfidence,
    String? date,
    String? league,
    String? query,
    String? status,
    int page = 1,
    int pageSize = 20,
    http.Client? client,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };
    if (tag != null && tag.isNotEmpty && tag != 'All') queryParams['tag'] = tag;
    if (sport != null && sport.isNotEmpty) queryParams['sport'] = sport;
    if (market != null && market.isNotEmpty) queryParams['market'] = market;
    if (source != null && source.isNotEmpty) queryParams['source'] = source;
    if (isPopular != null) queryParams['is_popular'] = isPopular.toString();
    if (minOdds != null && minOdds > 0)
      queryParams['min_odds'] = minOdds.toString();
    if (maxOdds != null && maxOdds > 0)
      queryParams['max_odds'] = maxOdds.toString();
    if (minConfidence != null && minConfidence > 0)
      queryParams['min_confidence'] = minConfidence.toString();
    if (date != null && date.isNotEmpty) queryParams['date'] = date;
    if (league != null && league.isNotEmpty) queryParams['league'] = league;
    if (query != null && query.isNotEmpty) queryParams['query'] = query;
    if (status != null && status.isNotEmpty) queryParams['status'] = status;

    final httpClient = client ?? _client;
    final uri = Uri.parse(
      '$baseUrl/api/v1/predictions/feed',
    ).replace(queryParameters: queryParams);
    final response = await httpClient.get(uri, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return data;
    } else if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {'items': [], 'tags': [], 'total': 0};
  }

  /// Permanently cached daily RatingBet market feed.
  /// The backend decides whether the admin-derived Safe market is visible.
  Future<Map<String, dynamic>> getRatingBetPredictions({
    required String market,
    String? date,
    int page = 1,
    int pageSize = 50,
    http.Client? client,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/predictions/ratingbet').replace(
      queryParameters: {
        'market': market,
        'page': page.toString(),
        'page_size': pageSize.toString(),
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    final response = await (client ?? _client).get(uri, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    return data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{
            'items': <dynamic>[],
            'markets': <dynamic>[],
            'total': 0,
          };
  }

  /// Get active market tags with counts for pill navigation
  Future<List<Map<String, dynamic>>> getPredictionTags({
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/predictions/tags');
    final response = await httpClient.get(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is List) {
      return data
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }

  /// Shortcut for Player Props predictions
  Future<Map<String, dynamic>> getPlayerProps({
    String? query,
    String? date,
    int page = 1,
    int pageSize = 20,
  }) async {
    return getPredictionFeed(
      tag: 'Player Props',
      query: query,
      date: date,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Shortcut for Popular predictions from Scores24
  Future<Map<String, dynamic>> getPopularPredictions({
    String? date,
    int page = 1,
    int pageSize = 20,
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/predictions/popular').replace(
      queryParameters: {
        'page': page.toString(),
        'page_size': pageSize.toString(),
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    final response = await httpClient.get(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return data;
    } else if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {'items': [], 'tags': [], 'total': 0};
  }

  /// Shortcut for Ice Hockey predictions from Scores24
  Future<Map<String, dynamic>> getHockeyPredictions({
    String? date,
    int page = 1,
    int pageSize = 20,
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/predictions/hockey').replace(
      queryParameters: {
        'page': page.toString(),
        'page_size': pageSize.toString(),
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    final response = await httpClient.get(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {'items': [], 'tags': [], 'total': 0};
  }

  /// Shortcut for 2+ Odds predictions
  Future<Map<String, dynamic>> getBest2PlusOdds({
    String? date,
    int page = 1,
    int pageSize = 20,
  }) async {
    return getPredictionFeed(
      tag: '2+ Odds',
      minOdds: 2.0,
      date: date,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Legacy-style high-confidence picks, backed by real v2 provider data.
  Future<Map<String, dynamic>> getBestPicks({
    String? date,
    int page = 1,
    int pageSize = 50,
    int minConfidence = 75,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/predictions/best-picks').replace(
      queryParameters: {
        'page': page.toString(),
        'page_size': pageSize.toString(),
        'min_confidence': minConfidence.toString(),
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    final response = await _client.get(uri, headers: _headers);
    final data = _parseResponse(response)['data'];
    return data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{'items': [], 'tags': [], 'total': 0};
  }

  /// Generates a genuine accumulator close to the requested combined odds.
  Future<Map<String, dynamic>> getAccumulatorPredictions({
    double targetOdds = 2.0,
    int minConfidence = 75,
    String? date,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/predictions/accumulators').replace(
      queryParameters: {
        'target_odds': targetOdds.toStringAsFixed(2),
        'min_confidence': minConfidence.toString(),
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    final response = await _client.get(uri, headers: _headers);
    final data = _parseResponse(response)['data'];
    return data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{'items': [], 'tags': [], 'total': 0};
  }

  Future<Map<String, dynamic>> getTvCatalog() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/live-tv/catalog'), headers: _headers)
        .timeout(const Duration(seconds: 25));
    final data = _parseResponse(response);
    if (data['success'] != true || data['streams'] is! List) {
      throw SportsException('The TV guide is temporarily unavailable');
    }
    return data;
  }

  /// Original BetMachine contract ported from the legacy backend.
  Future<Map<String, dynamic>> getBetMachine({
    int totalOdds = 300,
    double minOdd = 1.2,
    double maxOdd = 5.0,
    bool onlyToday = true,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/vip/betmachine').replace(
      queryParameters: {
        'total_odds': totalOdds.toString(),
        'min_odd': minOdd.toStringAsFixed(2),
        'max_odd': maxOdd.toStringAsFixed(2),
        'only_today': onlyToday.toString(),
      },
    );
    final response = await _client.get(uri, headers: _authenticatedHeaders);
    final data = _parseResponse(response)['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Forebet value-odds feed ported from the legacy backend.
  Future<List<Map<String, dynamic>>> getValueOdds({
    bool refresh = false,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/value-odds',
    ).replace(queryParameters: {if (refresh) 'refresh': 'true'});
    final response = await _client.get(uri, headers: _authenticatedHeaders);
    final data = _parseResponse(response)['data'];
    return data is List
        ? data
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> getAdvancedTeamStats({
    String? country,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/stats/advanced-teams').replace(
      queryParameters: {
        if (country != null && country.trim().isNotEmpty)
          'country': country.trim(),
      },
    );
    final response = await _client.get(uri, headers: _authenticatedHeaders);
    final data = _parseResponse(response)['data'];
    return data is List
        ? data
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
  }

  /// Analyze a booking code with SlipIQ risk diagnostics
  /// `POST /api/v1/slip-analysis/betcode`
  Future<Map<String, dynamic>> analyzeSlipBookingCode({
    required String bookingCode,
    String platform = 'sportybetng',
    bool deepAnalysis = false,
    bool allowAISwap = false,
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/slip-analysis/betcode');
    final payload = jsonEncode({
      'platform': platform,
      'booking_code': bookingCode,
      'deep_analysis': deepAnalysis,
      'allow_ai_swap_predictions': allowAISwap,
    });
    final response = await httpClient.post(
      url,
      headers: _authenticatedHeaders,
      body: payload,
    );
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw SportsException('Failed to analyze betting slip');
  }

  /// Get Community Tickets Feed (Accumulator slips created by users)
  /// `GET /api/v1/tickets/feed?status=all&page=1&page_size=20`
  Future<TicketBucketFeedResponseModel> getTicketsFeed({
    String status = 'all',
    int page = 1,
    int pageSize = 20,
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse(
      '$baseUrl/api/v1/tickets/feed?status=$status&page=$page&page_size=$pageSize',
    );
    final response = await httpClient.get(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return TicketBucketFeedResponseModel.fromJson(data);
    }
    return const TicketBucketFeedResponseModel(
      total: 0,
      page: 1,
      pageSize: 20,
      tickets: [],
    );
  }

  /// Get the signed-in user's generated booking codes.
  /// `GET /api/v1/tickets/my-bookings?page=1&page_size=20`
  Future<TicketBucketFeedResponseModel> getMyBookings({
    String status = 'all',
    int page = 1,
    int pageSize = 20,
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/tickets/my-bookings').replace(
      queryParameters: {
        'status': status,
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
    );
    final response = await httpClient.get(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map) {
      return TicketBucketFeedResponseModel.fromJson(
        Map<String, dynamic>.from(data),
      );
    }
    return const TicketBucketFeedResponseModel(
      total: 0,
      page: 1,
      pageSize: 20,
      totalPages: 0,
      tickets: [],
    );
  }

  /// Load one owned booking with all of its selections.
  Future<TicketBucketModel> getTicketBucket(
    String bucketId, {
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/tickets/bucket/$bucketId');
    final response = await httpClient.get(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map) {
      return TicketBucketModel.fromJson(Map<String, dynamic>.from(data));
    }
    throw SportsException('Booking details could not be loaded.');
  }

  /// Get Stream of Individual User Picks across all community slips
  /// `GET /api/v1/tickets/picks?status=all&page=1&page_size=50`
  Future<List<UserPickFeedItemModel>> getUserPicksFeed({
    String status = 'all',
    int page = 1,
    int pageSize = 50,
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse(
      '$baseUrl/api/v1/tickets/picks?status=$status&page=$page&page_size=$pageSize',
    );
    final response = await httpClient.get(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      final list = data['picks'];
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map((m) => UserPickFeedItemModel.fromJson(m))
            .toList();
      }
    } else if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map((m) => UserPickFeedItemModel.fromJson(m))
          .toList();
    }
    return [];
  }

  /// Trigger settlement across all pending tickets and picks against completed fixture results
  /// `POST /api/v1/tickets/settle`
  Future<TicketSettlementStatsModel> settleTicketBuckets({
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/tickets/settle');
    final response = await httpClient.post(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return TicketSettlementStatsModel.fromJson(data);
    }
    throw SportsException('Failed to settle tickets and picks');
  }

  /// Trigger settlement for a specific ticket by ID
  /// `POST /api/v1/tickets/:id/settle`
  Future<TicketBucketModel> settleTicketBucketById(
    String ticketId, {
    http.Client? client,
  }) async {
    final httpClient = client ?? _client;
    final url = Uri.parse('$baseUrl/api/v1/tickets/$ticketId/settle');
    final response = await httpClient.post(url, headers: _headers);
    final jsonMap = _parseResponse(response);
    final data = jsonMap['data'];
    if (data is Map<String, dynamic>) {
      return TicketBucketModel.fromJson(data);
    }
    throw SportsException('Failed to settle ticket $ticketId');
  }

  Map<String, dynamic> _parseResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw SportsException(
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
    dynamic errors;

    if (decoded is Map<String, dynamic>) {
      message = decoded['message'] as String? ?? message;
      errors = decoded['errors'];
    }

    throw SportsException(
      message,
      statusCode: response.statusCode,
      errors: errors,
    );
  }
}
