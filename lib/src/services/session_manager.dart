import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'app_config.dart';

class SessionManager extends ChangeNotifier {
  static final SessionManager instance = SessionManager._internal();
  factory SessionManager() => instance;
  SessionManager._internal();

  UserModel? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  bool _isInitialized = false;
  Future<String?>? _refreshInProgress;
  Future<void> Function()? beforeLogout;

  UserModel? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;

  static const String _keyAccessToken = 'zentry_access_token';
  static const String _keyRefreshToken = 'zentry_refresh_token';
  static const String _keyUserProfile = 'zentry_user_profile';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    _accessToken = await _secureStorage.read(key: _keyAccessToken);
    _refreshToken = await _secureStorage.read(key: _keyRefreshToken);

    // Migrate sessions created by older app versions out of plain preferences.
    _accessToken ??= prefs.getString(_keyAccessToken);
    _refreshToken ??= prefs.getString(_keyRefreshToken);
    if (_accessToken != null) {
      await _secureStorage.write(key: _keyAccessToken, value: _accessToken);
    }
    if (_refreshToken != null) {
      await _secureStorage.write(key: _keyRefreshToken, value: _refreshToken);
    }
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);

    final userJsonStr = prefs.getString(_keyUserProfile);
    if (userJsonStr != null && userJsonStr.isNotEmpty) {
      try {
        final Map<String, dynamic> userMap = jsonDecode(userJsonStr);
        _currentUser = UserModel.fromJson(userMap);
      } catch (_) {}
    }

    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      await getValidAccessToken();
    } else if (!_isTokenUsable(_accessToken)) {
      _accessToken = null;
      _currentUser = null;
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> saveSession({
    required UserModel user,
    required AuthTokens tokens,
  }) async {
    _currentUser = user;
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;

    await _writeTokens(tokens.accessToken, tokens.refreshToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserProfile, jsonEncode(user.toJson()));

    notifyListeners();
  }

  Future<void> updateUser(UserModel user) async {
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserProfile, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> logout({bool unregisterDevice = true}) async {
    if (unregisterDevice) {
      try {
        await beforeLogout?.call();
      } catch (_) {}
    }
    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;

    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserProfile);

    notifyListeners();
  }

  static Future<String?> getAccessToken() async {
    return instance.getValidAccessToken();
  }

  /// Returns a usable access token, silently renewing it when it is expired or
  /// close to expiry. Concurrent requests share the same refresh operation.
  Future<String?> getValidAccessToken({bool forceRefresh = false}) async {
    if (!forceRefresh && _isTokenUsable(_accessToken)) return _accessToken;
    if (_refreshToken == null || _refreshToken!.isEmpty) {
      await logout(unregisterDevice: false);
      return null;
    }

    final existing = _refreshInProgress;
    if (existing != null) return existing;

    final refresh = _renewAccessToken();
    _refreshInProgress = refresh;
    try {
      return await refresh;
    } finally {
      _refreshInProgress = null;
    }
  }

  Future<String?> _renewAccessToken() async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/v1/auth/refresh'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refresh_token': _refreshToken}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await logout(unregisterDevice: false);
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Invalid response');
      final envelope = Map<String, dynamic>.from(decoded);
      final rawData = envelope['data'];
      if (rawData is! Map) throw const FormatException('Missing token data');
      final tokens = AuthTokens.fromJson(Map<String, dynamic>.from(rawData));
      if (tokens.accessToken.isEmpty) {
        throw const FormatException('Missing access token');
      }
      final nextRefresh = tokens.refreshToken.isEmpty
          ? _refreshToken!
          : tokens.refreshToken;
      _accessToken = tokens.accessToken;
      _refreshToken = nextRefresh;
      await _writeTokens(tokens.accessToken, nextRefresh);
      notifyListeners();
      return _accessToken;
    } catch (_) {
      // Network failures should not erase a still-valid local session. An
      // invalid/expired refresh token is handled by the non-2xx branch above.
      return _isTokenUsable(_accessToken) ? _accessToken : null;
    }
  }

  Future<void> _writeTokens(String accessToken, String refreshToken) async {
    await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
  }

  bool _isTokenUsable(String? token) {
    if (token == null || token.isEmpty) return false;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map || payload['exp'] is! num) return false;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        (payload['exp'] as num).toInt() * 1000,
        isUtc: true,
      );
      return expiresAt.isAfter(
        DateTime.now().toUtc().add(const Duration(seconds: 60)),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveUser(UserModel user) async {
    await instance.updateUser(user);
  }

  static Future<void> clearSession() async {
    await instance.logout();
  }
}
