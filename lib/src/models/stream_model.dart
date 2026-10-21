String _string(dynamic value) => value?.toString() ?? '';
int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(_string(value)) ?? 0;
bool _bool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final str = _string(value).toLowerCase().trim();
  return str == 'true' || str == '1';
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

Map<String, String> _stringMap(dynamic value) {
  if (value is! Map) return {};
  return value.map((key, val) => MapEntry(_string(key), _string(val)));
}

enum LiveStreamPhase { live, upcoming, ended }

bool _isBinTvUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  final host = uri?.host.toLowerCase() ?? '';
  return host == 'bintv-sources.pages.dev' ||
      host.endsWith('.bintv-sources.pages.dev') ||
      host.contains('bintv');
}

class StreamSourceModel {
  final String label;
  final String url;
  final Map<String, String> headers;
  final DateTime? capturedAt;
  final bool master;
  final String format;
  final String status;

  const StreamSourceModel({
    this.label = '',
    this.url = '',
    this.headers = const {},
    this.capturedAt,
    this.master = false,
    this.format = '',
    this.status = '',
  });

  factory StreamSourceModel.fromJson(Map<String, dynamic> json) =>
      StreamSourceModel(
        label: _string(json['label']),
        url: _string(json['url']),
        headers: _stringMap(json['headers']),
        capturedAt: DateTime.tryParse(_string(json['captured_at'])),
        master: _bool(json['master']),
        format: _string(json['format']),
        status: _string(json['status']),
      );

  Map<String, dynamic> toJson() => {
    if (label.isNotEmpty) 'label': label,
    'url': url,
    'headers': headers,
    if (capturedAt != null) 'captured_at': capturedAt!.toIso8601String(),
    'master': master,
    if (format.isNotEmpty) 'format': format,
    'status': status,
  };
}

class PlayerSourceModel {
  final String embedUrl;

  const PlayerSourceModel({this.embedUrl = ''});

  factory PlayerSourceModel.fromJson(Map<String, dynamic> json) =>
      PlayerSourceModel(embedUrl: _string(json['embed_url']));

  Map<String, dynamic> toJson() => {'embed_url': embedUrl};
}

class LiveStreamEventModel {
  final String id;
  final String title;
  final String category;
  final int date;
  final String homeTeam;
  final String awayTeam;
  final bool live;
  final DateTime? kickoffUtc;
  final List<String> channels;
  final List<StreamSourceModel> streams;
  final List<PlayerSourceModel> players;
  final String streamStatus;
  final DateTime? lastAttemptAt;
  final DateTime? linksUpdatedAt;
  final String resolutionError;

  const LiveStreamEventModel({
    this.id = '',
    this.title = '',
    this.category = '',
    this.date = 0,
    this.homeTeam = '',
    this.awayTeam = '',
    this.live = false,
    this.kickoffUtc,
    this.channels = const [],
    this.streams = const [],
    this.players = const [],
    this.streamStatus = '',
    this.lastAttemptAt,
    this.linksUpdatedAt,
    this.resolutionError = '',
  });

  bool get hasStreams => playbackSources.isNotEmpty;

  LiveStreamPhase get phase {
    if (live) return LiveStreamPhase.live;
    final normalizedStatus = streamStatus.trim().toLowerCase();
    if (normalizedStatus == 'ended' ||
        normalizedStatus == 'finished' ||
        normalizedStatus == 'completed') {
      return LiveStreamPhase.ended;
    }
    return LiveStreamPhase.upcoming;
  }

  bool get hasEnded => phase == LiveStreamPhase.ended;
  bool get isUpcoming => phase == LiveStreamPhase.upcoming;

  /// All anonymous playback choices exposed to the user as Server 1..N.
  /// Native adaptive streams are kept first so their position continues to
  /// match the backend HLS relay source index.
  List<StreamSourceModel> get playbackSources => <StreamSourceModel>[
    ...streams.where((stream) => !_isBinTvUrl(stream.url)),
    ...players
        .where(
          (player) =>
              player.embedUrl.isNotEmpty && !_isBinTvUrl(player.embedUrl),
        )
        .map(
          (player) => StreamSourceModel(
            url: player.embedUrl,
            format: 'embed',
            status: 'available',
          ),
        ),
  ];

  String? get primaryStreamUrl => streams.isNotEmpty ? streams.first.url : null;

  /// Returns the first native adaptive-media URL.
  String? get bestPlayableUrl {
    if (streams.isNotEmpty && streams.first.url.isNotEmpty) {
      return streams.first.url;
    }
    return null;
  }

  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (homeTeam.isNotEmpty && awayTeam.isNotEmpty) {
      return '$homeTeam vs $awayTeam';
    }
    return 'Live Match Stream';
  }

  factory LiveStreamEventModel.fromJson(Map<String, dynamic> json) {
    final teams = _map(json['teams']);
    final home = _map(teams['home']);
    final away = _map(teams['away']);

    final streamsList = json['streams'] is List
        ? (json['streams'] as List)
              .whereType<Map<String, dynamic>>()
              .map(StreamSourceModel.fromJson)
              .where((stream) => !_isBinTvUrl(stream.url))
              .toList()
        : <StreamSourceModel>[];

    final playersList = json['players'] is List
        ? (json['players'] as List)
              .whereType<Map<String, dynamic>>()
              .map(PlayerSourceModel.fromJson)
              .where(
                (player) =>
                    player.embedUrl.isNotEmpty && !_isBinTvUrl(player.embedUrl),
              )
              .toList()
        : <PlayerSourceModel>[];

    return LiveStreamEventModel(
      id: _string(json['id']),
      title: _string(json['title']),
      category: _string(json['category']),
      date: _int(json['date']),
      homeTeam: _string(home['name']),
      awayTeam: _string(away['name']),
      live: _bool(json['live']),
      kickoffUtc: DateTime.tryParse(_string(json['kickoff_utc'])),
      channels: json['channels'] is List
          ? (json['channels'] as List)
                .map(_string)
                .where((channel) => channel.isNotEmpty)
                .toList()
          : const [],
      streams: streamsList,
      players: playersList,
      streamStatus: _string(json['stream_status']),
      lastAttemptAt: DateTime.tryParse(_string(json['last_attempt_at'])),
      linksUpdatedAt: DateTime.tryParse(_string(json['links_updated_at'])),
      resolutionError: _string(json['resolution_error']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'date': date,
    'teams': {
      'home': {'name': homeTeam},
      'away': {'name': awayTeam},
    },
    'live': live,
    if (kickoffUtc != null) 'kickoff_utc': kickoffUtc!.toIso8601String(),
    if (channels.isNotEmpty) 'channels': channels,
    'streams': streams.map((e) => e.toJson()).toList(),
    'players': players.map((e) => e.toJson()).toList(),
    'stream_status': streamStatus,
    if (lastAttemptAt != null)
      'last_attempt_at': lastAttemptAt!.toIso8601String(),
    if (linksUpdatedAt != null)
      'links_updated_at': linksUpdatedAt!.toIso8601String(),
    if (resolutionError.isNotEmpty) 'resolution_error': resolutionError,
  };
}

class LiveStreamSnapshotModel {
  final String provider;
  final int refreshIntervalSeconds;
  final DateTime? lastRefreshAt;
  final DateTime? lastSuccessAt;
  final bool stale;
  final String refreshError;
  final List<LiveStreamEventModel> fixtures;

  const LiveStreamSnapshotModel({
    this.provider = '',
    this.refreshIntervalSeconds = 15,
    this.lastRefreshAt,
    this.lastSuccessAt,
    this.stale = false,
    this.refreshError = '',
    this.fixtures = const [],
  });

  factory LiveStreamSnapshotModel.fromJson(Map<String, dynamic> json) {
    final fixturesList = json['fixtures'] is List
        ? (json['fixtures'] as List)
              .whereType<Map<String, dynamic>>()
              .map(LiveStreamEventModel.fromJson)
              .toList()
        : <LiveStreamEventModel>[];

    return LiveStreamSnapshotModel(
      provider: _string(json['provider']),
      refreshIntervalSeconds: _int(json['refresh_interval_seconds']) == 0
          ? 15
          : _int(json['refresh_interval_seconds']),
      lastRefreshAt: DateTime.tryParse(_string(json['last_refresh_at'])),
      lastSuccessAt: DateTime.tryParse(_string(json['last_success_at'])),
      stale: _bool(json['stale']),
      refreshError: _string(json['refresh_error']),
      fixtures: fixturesList,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'refresh_interval_seconds': refreshIntervalSeconds,
    if (lastRefreshAt != null)
      'last_refresh_at': lastRefreshAt!.toIso8601String(),
    if (lastSuccessAt != null)
      'last_success_at': lastSuccessAt!.toIso8601String(),
    'stale': stale,
    'refresh_error': refreshError,
    'fixtures': fixtures.map((e) => e.toJson()).toList(),
  };
}

class FixtureStreamsModel {
  final String fixtureId;
  final List<LiveStreamEventModel> fixtures;
  final bool available;
  final bool stale;
  final int refreshIntervalSeconds;

  const FixtureStreamsModel({
    this.fixtureId = '',
    this.fixtures = const [],
    this.available = false,
    this.stale = false,
    this.refreshIntervalSeconds = 15,
  });

  bool get hasStreams => available && fixtures.any((f) => f.hasStreams);

  LiveStreamEventModel? get primaryEvent =>
      fixtures.isNotEmpty ? fixtures.first : null;

  factory FixtureStreamsModel.fromJson(Map<String, dynamic> json) {
    List<LiveStreamEventModel> list = [];
    if (json['fixtures'] is List) {
      list = (json['fixtures'] as List)
          .whereType<Map<String, dynamic>>()
          .map(LiveStreamEventModel.fromJson)
          .toList();
    } else if (json['fixture'] is Map<String, dynamic>) {
      list = [LiveStreamEventModel.fromJson(_map(json['fixture']))];
    }

    final bool isAvail =
        _bool(json['available']) || list.any((e) => e.streams.isNotEmpty);

    return FixtureStreamsModel(
      fixtureId: _string(json['fixture_id']),
      fixtures: list,
      available: isAvail,
      stale: _bool(json['stale']),
      refreshIntervalSeconds: _int(json['refresh_interval_seconds']) == 0
          ? 15
          : _int(json['refresh_interval_seconds']),
    );
  }

  Map<String, dynamic> toJson() => {
    'fixture_id': fixtureId,
    'fixtures': fixtures.map((e) => e.toJson()).toList(),
    'available': available,
    'stale': stale,
    'refresh_interval_seconds': refreshIntervalSeconds,
  };
}
