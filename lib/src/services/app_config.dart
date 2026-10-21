import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

class AppConfig {
  AppConfig._();

  static Map<String, String> _values = const {};

  static Future<void> load() async {
    try {
      final raw = await rootBundle.loadString('.env');
      _values = {
        for (final line in raw.split(RegExp(r'\r?\n')))
          if (_parseLine(line) case final entry?) entry.key: entry.value,
      };
    } catch (_) {
      _values = const {};
    }
  }

  static MapEntry<String, String>? _parseLine(String line) {
    final value = line.trim();
    if (value.isEmpty || value.startsWith('#')) return null;
    final separator = value.indexOf('=');
    if (separator <= 0) return null;
    final key = value.substring(0, separator).trim();
    var item = value.substring(separator + 1).trim();
    if (item.length >= 2 &&
        ((item.startsWith('"') && item.endsWith('"')) ||
            (item.startsWith("'") && item.endsWith("'")))) {
      item = item.substring(1, item.length - 1);
    }
    return MapEntry(key, item);
  }

  static String get apiBaseUrl {
    const buildValue = String.fromEnvironment('API_BASE_URL');
    final configured = buildValue.trim().isNotEmpty
        ? buildValue.trim()
        : (_values['API_BASE_URL'] ?? '').trim();
    if (configured.isNotEmpty) {
      return configured.replaceFirst(RegExp(r'/+$'), '');
    }
    if (kReleaseMode) return 'https://zentry-v2.myco.com.ng';
    return 'http://localhost:8080';
  }

  static String get appVersion => (_values['APP_VERSION'] ?? '1.0.0').trim();

  static String? get googleClientId {
    final value = (_values['GOOGLE_CLIENT_ID'] ?? '').trim();
    return value.isEmpty ? null : value;
  }

  static String? get googleServerClientId {
    final value = (_values['GOOGLE_SERVER_CLIENT_ID'] ?? '').trim();
    return value.isEmpty ? null : value;
  }

  static String _value(String key, String buildValue) {
    return buildValue.trim().isNotEmpty
        ? buildValue.trim()
        : (_values[key] ?? '').trim();
  }

  static bool get hasFirebaseConfig {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appID = String.fromEnvironment('FIREBASE_APP_ID');
    const senderID = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectID = String.fromEnvironment('FIREBASE_PROJECT_ID');
    return _value('FIREBASE_API_KEY', apiKey).isNotEmpty &&
        _value('FIREBASE_APP_ID', appID).isNotEmpty &&
        _value('FIREBASE_MESSAGING_SENDER_ID', senderID).isNotEmpty &&
        _value('FIREBASE_PROJECT_ID', projectID).isNotEmpty;
  }

  static FirebaseOptions get firebaseOptions {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appID = String.fromEnvironment('FIREBASE_APP_ID');
    const senderID = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectID = String.fromEnvironment('FIREBASE_PROJECT_ID');
    return FirebaseOptions(
      apiKey: _value('FIREBASE_API_KEY', apiKey),
      appId: _value('FIREBASE_APP_ID', appID),
      messagingSenderId: _value('FIREBASE_MESSAGING_SENDER_ID', senderID),
      projectId: _value('FIREBASE_PROJECT_ID', projectID),
      authDomain: _optionalValue('FIREBASE_AUTH_DOMAIN'),
      storageBucket: _optionalValue('FIREBASE_STORAGE_BUCKET'),
      iosBundleId: _optionalValue('FIREBASE_IOS_BUNDLE_ID'),
    );
  }

  static String? _optionalValue(String key) {
    final value = (_values[key] ?? '').trim();
    return value.isEmpty ? null : value;
  }
}
