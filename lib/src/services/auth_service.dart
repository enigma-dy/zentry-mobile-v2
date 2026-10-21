import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import 'logging_client.dart';
import 'app_config.dart';

class AuthException implements Exception {
  final String message;
  final int statusCode;
  final dynamic errors;

  AuthException(this.message, {this.statusCode = 400, this.errors});

  @override
  String toString() => message;
}

class AuthService {
  final String baseUrl;
  final http.Client _client;
  static Future<void>? _googleInitialization;

  AuthService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? _getDefaultBaseUrl(),
      _client = client ?? LoggingClient();

  static String _getDefaultBaseUrl() {
    return AppConfig.apiBaseUrl;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Register a new user
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/auth/register');
    final response = await _client.post(
      url,
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
      }),
    );

    final data = _parseResponse(response);
    final userData = data['data'] as Map<String, dynamic>? ?? {};
    return UserModel.fromJson(userData);
  }

  /// Login with a username or email and return tokens + profile.
  Future<({UserModel user, AuthTokens tokens})> login({
    required String identifier,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/auth/login');
    final response = await _client.post(
      url,
      headers: _headers,
      // The backend keeps the legacy `email` key for compatibility while
      // accepting either an email address or username as its value.
      body: jsonEncode({'email': identifier, 'password': password}),
    );

    final data = _parseResponse(response);
    final responseData = data['data'] as Map<String, dynamic>? ?? {};
    final userMap = responseData['user'] as Map<String, dynamic>? ?? {};

    return (
      user: UserModel.fromJson(userMap),
      tokens: AuthTokens.fromJson(responseData),
    );
  }

  Future<({UserModel user, AuthTokens tokens})> googleLogin() async {
    final serverClientId = AppConfig.googleServerClientId;
    if (serverClientId == null) {
      throw AuthException(
        'Google sign-in is not configured. Set GOOGLE_SERVER_CLIENT_ID in the Flutter .env file.',
        statusCode: 503,
      );
    }
    final google = GoogleSignIn.instance;
    _googleInitialization ??= google.initialize(
      clientId: AppConfig.googleClientId,
      serverClientId: serverClientId,
    );
    await _googleInitialization;
    if (!google.supportsAuthenticate()) {
      throw AuthException(
        'Google sign-in on this platform requires the official Google web button.',
        statusCode: 501,
      );
    }

    try {
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw AuthException('Google did not return an identity token.');
      }
      final response = await _client.post(
        Uri.parse('$baseUrl/api/v1/auth/google'),
        headers: _headers,
        body: jsonEncode({'id_token': idToken}),
      );
      final data = _parseResponse(response);
      final responseData = data['data'] as Map<String, dynamic>? ?? {};
      final userMap = responseData['user'] as Map<String, dynamic>? ?? {};
      return (
        user: UserModel.fromJson(userMap),
        tokens: AuthTokens.fromJson(responseData),
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw AuthException('Google sign-in was cancelled.');
      }
      throw AuthException(
        error.description ?? 'Google sign-in failed. Please try again.',
      );
    }
  }

  /// Verify user email with token
  Future<String> verifyEmail(String token) async {
    final url = Uri.parse(
      '$baseUrl/api/v1/auth/verify-email?token=${Uri.encodeComponent(token)}',
    );
    final response = await _client.get(url, headers: _headers);

    final data = _parseResponse(response);
    return data['message'] as String? ?? 'Email verified successfully!';
  }

  /// Request password reset link/token
  Future<String> forgotPassword(String email) async {
    final url = Uri.parse('$baseUrl/api/v1/auth/forgot-password');
    final response = await _client.post(
      url,
      headers: _headers,
      body: jsonEncode({'email': email}),
    );

    final data = _parseResponse(response);
    return data['message'] as String? ?? 'Password reset instructions sent.';
  }

  /// Reset password with token
  Future<String> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/auth/reset-password');
    final response = await _client.post(
      url,
      headers: _headers,
      body: jsonEncode({'token': token, 'new_password': newPassword}),
    );

    final data = _parseResponse(response);
    return data['message'] as String? ?? 'Password reset successfully.';
  }

  /// Fetch user profile using access token
  Future<UserModel> getProfile(String accessToken) async {
    final url = Uri.parse('$baseUrl/api/v1/users/me');
    final response = await _client.get(
      url,
      headers: {..._headers, 'Authorization': 'Bearer $accessToken'},
    );

    final data = _parseResponse(response);
    final userData = data['data'] as Map<String, dynamic>? ?? {};
    return UserModel.fromJson(userData);
  }

  /// Refresh JWT Access Token
  Future<AuthTokens> refreshToken(String refreshToken) async {
    final url = Uri.parse('$baseUrl/api/v1/auth/refresh');
    final response = await _client.post(
      url,
      headers: _headers,
      body: jsonEncode({'refresh_token': refreshToken}),
    );

    final data = _parseResponse(response);
    final responseData = data['data'] as Map<String, dynamic>? ?? {};
    return AuthTokens.fromJson(responseData);
  }

  /// Update user profile
  Future<UserModel> updateProfile(
    String accessToken, {
    required String fullName,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/users/me');
    final response = await _client.put(
      url,
      headers: {..._headers, 'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({'full_name': fullName}),
    );

    final data = _parseResponse(response);
    final userData = data['data'] as Map<String, dynamic>? ?? {};
    return UserModel.fromJson(userData);
  }

  /// Change password
  Future<String> changePassword(
    String accessToken, {
    required String oldPassword,
    required String newPassword,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/users/change-password');
    final response = await _client.post(
      url,
      headers: {..._headers, 'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );

    final data = _parseResponse(response);
    return data['message'] as String? ?? 'Password changed successfully.';
  }

  /// Fetch billing packages (coin packages + vip plans)
  Future<Map<String, dynamic>> getPackages() async {
    final url = Uri.parse('$baseUrl/api/v1/billing/packages');
    final response = await _client.get(url, headers: _headers);

    final data = _parseResponse(response);
    return data['data'] as Map<String, dynamic>? ?? {};
  }

  /// Create payment checkout session
  Future<Map<String, dynamic>> createCheckout(
    String accessToken, {
    required String provider,
    required String itemType,
    required String itemId,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/billing/checkout');
    final response = await _client.post(
      url,
      headers: {..._headers, 'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({
        'provider': provider,
        'item_type': itemType,
        'item_id': itemId,
      }),
    );

    final data = _parseResponse(response);
    return data['data'] as Map<String, dynamic>? ?? {};
  }

  Map<String, dynamic> _parseResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw AuthException(
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

    throw AuthException(
      message,
      statusCode: response.statusCode,
      errors: errors,
    );
  }
}
