import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'session_manager.dart';

const _channel = AndroidNotificationChannel(
  'zentry_notifications',
  'Zentry notifications',
  description: 'Match reminders, mentions, and account activity',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isNotEmpty) return;
  await AppConfig.load();
  if (AppConfig.hasFirebaseConfig) {
    await Firebase.initializeApp(options: AppConfig.firebaseOptions);
  }
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  bool _initialized = false;
  bool _syncing = false;
  String? _registeredToken;
  String? _registeredUserID;

  Future<void> initialize() async {
    if (_initialized || !AppConfig.hasFirebaseConfig) return;
    try {
      await Firebase.initializeApp(options: AppConfig.firebaseOptions);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _initializeForegroundNotifications();

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _tokenSubscription = messaging.onTokenRefresh.listen(
        (token) => unawaited(_registerToken(token)),
      );
      _messageSubscription = FirebaseMessaging.onMessage.listen(
        (message) => unawaited(_showForegroundNotification(message)),
      );
      SessionManager.instance.beforeLogout = unregisterCurrentDevice;
      SessionManager.instance.addListener(_sessionChanged);
      _initialized = true;
      if (SessionManager.instance.isLoggedIn) await syncCurrentToken();
    } catch (error) {
      debugPrint('[Push] Firebase initialization failed: $error');
    }
  }

  Future<void> _initializeForegroundNotifications() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('zentry_logo'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _local.initialize(settings: settings);
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
  }

  void _sessionChanged() {
    if (SessionManager.instance.isLoggedIn) unawaited(syncCurrentToken());
  }

  Future<void> syncCurrentToken() async {
    if (!_initialized || _syncing || !SessionManager.instance.isLoggedIn) {
      return;
    }
    _syncing = true;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _registerToken(token);
    } catch (error) {
      debugPrint('[Push] Could not obtain the Firebase token: $error');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _registerToken(String token) async {
    final userID = SessionManager.instance.currentUser?.id ?? '';
    if (userID.isEmpty || !SessionManager.instance.isLoggedIn) return;
    if (_registeredToken == token && _registeredUserID == userID) return;
    final accessToken = await SessionManager.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) return;

    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/api/v1/notifications/devices'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'token': token, 'platform': _platformName}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _registeredToken = token;
      _registeredUserID = userID;
    } else {
      debugPrint('[Push] Device registration failed (${response.statusCode})');
    }
  }

  Future<void> unregisterCurrentDevice() async {
    if (!_initialized) return;
    final token =
        _registeredToken ?? await FirebaseMessaging.instance.getToken();
    final accessToken = await SessionManager.getAccessToken();
    if (token == null || token.isEmpty || accessToken == null) return;
    try {
      await http
          .delete(
            Uri.parse('${AppConfig.apiBaseUrl}/api/v1/notifications/devices'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 10));
    } finally {
      _registeredToken = null;
      _registeredUserID = null;
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      id:
          (message.messageId?.hashCode ??
              DateTime.now().millisecondsSinceEpoch) &
          0x7fffffff,
      title: notification.title ?? 'Zentry Predict',
      body: notification.body ?? '',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'zentry_notifications',
          'Zentry notifications',
          channelDescription: 'Match reminders, mentions, and account activity',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'zentry_logo',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'unknown',
    };
  }

  Future<void> dispose() async {
    SessionManager.instance.removeListener(_sessionChanged);
    SessionManager.instance.beforeLogout = null;
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
  }
}
