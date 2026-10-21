import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'services/logging_client.dart';

class StartupSlide {
  const StartupSlide({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    this.imageUrl,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final String? imageUrl;

  factory StartupSlide.fromJson(Map<String, dynamic> json, int index) {
    final fallback = StartupContent
        .fallback
        .slides[index % StartupContent.fallback.slides.length];
    return StartupSlide(
      title: json['title'] as String? ?? fallback.title,
      subtitle: json['subtitle'] as String? ?? fallback.subtitle,
      icon: fallback.icon,
      colors: [
        _parseColor(json['start_color'] as String?, fallback.colors.first),
        _parseColor(json['end_color'] as String?, fallback.colors.last),
      ],
      imageUrl: json['image_url'] as String?,
    );
  }
}

class StartupContent {
  const StartupContent({
    required this.slides,
    this.logoUrl,
    this.logoDuration = const Duration(milliseconds: 1800),
  });
  final String? logoUrl;
  final Duration logoDuration;
  final List<StartupSlide> slides;

  static const fallback = StartupContent(
    slides: [
      StartupSlide(
        title: 'Smarter football predictions',
        subtitle:
            'Data-backed picks, live form and match insights in one place.',
        icon: Icons.query_stats_rounded,
        colors: [Color(0xFF08785B), Color(0xFF082D27)],
      ),
      StartupSlide(
        title: 'Follow every big moment',
        subtitle: 'Track fixtures, scores and the competitions you care about.',
        icon: Icons.sports_soccer_rounded,
        colors: [Color(0xFF174A75), Color(0xFF0A1C2D)],
      ),
      StartupSlide(
        title: 'Build winning confidence',
        subtitle: 'Compare markets and keep your best selections organized.',
        icon: Icons.workspace_premium_rounded,
        colors: [Color(0xFF705318), Color(0xFF2E2109)],
      ),
    ],
  );

  factory StartupContent.fromJson(Map<String, dynamic> json) {
    final raw = json['slides'];
    final slides = raw is List
        ? raw
              .whereType<Map>()
              .toList()
              .asMap()
              .entries
              .map(
                (entry) => StartupSlide.fromJson(
                  Map<String, dynamic>.from(entry.value),
                  entry.key,
                ),
              )
              .toList()
        : <StartupSlide>[];
    final duration = json['logo_duration_ms'];
    return StartupContent(
      logoUrl: json['logo_url'] as String?,
      logoDuration: Duration(
        milliseconds:
            duration is int ? duration.clamp(900, 5000).toInt() : 1800,
      ),
      slides: slides.isEmpty ? fallback.slides : slides,
    );
  }
}

class StartupContentService {
  final http.Client? _client;
  const StartupContentService({http.Client? client}) : _client = client;
  static const endpoint = String.fromEnvironment('STARTUP_CONTENT_URL');

  Future<StartupContent> load() async {
    if (endpoint.isEmpty) return StartupContent.fallback;
    final client = _client ?? LoggingClient();
    try {
      final response = await client
          .get(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return StartupContent.fallback;
      }
      return StartupContent.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (_) {
      return StartupContent.fallback;
    }
  }
}

Color _parseColor(String? value, Color fallback) {
  if (value == null) return fallback;
  final normalized = value.replaceFirst('#', '');
  final parsed = int.tryParse(
    normalized.length == 6 ? 'FF$normalized' : normalized,
    radix: 16,
  );
  return parsed == null ? fallback : Color(parsed);
}
