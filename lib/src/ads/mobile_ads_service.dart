import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'full_screen_ad_policy.dart';

class MobileAdsService extends ChangeNotifier {
  MobileAdsService._();
  static final instance = MobileAdsService._();
  Future<bool>? _initialization;
  bool _sdkInitialized = false;
  bool privacyOptionsRequired = false;
  bool canLoadAds = false;

  bool get supported =>
      !kIsWeb &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<bool> ensureInitialized() {
    if (!supported) return Future.value(false);
    if (canLoadAds) return Future.value(true);
    return _initialization ??= _initialize();
  }

  Future<bool> _initialize() async {
    try {
      final consent = Completer<void>();
      var formStarted = false;
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          if (consent.isCompleted) return;
          formStarted = true;
          ConsentForm.loadAndShowConsentFormIfRequired((_) {
            if (!consent.isCompleted) consent.complete();
          });
        },
        (_) {
          if (!consent.isCompleted) consent.complete();
        },
      );
      await consent.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          if (!formStarted && !consent.isCompleted) consent.complete();
        },
      );
      // Finish any visible consent form before a Watch transition can start video.
      if (formStarted && !consent.isCompleted) await consent.future;
    } catch (_) {
      // Consent/SDK failures must never block navigation or live playback.
    }
    try {
      return await _refreshPermission();
    } catch (error) {
      debugPrint('Advertising unavailable: $error');
      return false;
    }
  }

  Future<bool> _refreshPermission() async {
    privacyOptionsRequired =
        await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
    final allowed =
        await ConsentInformation.instance.canRequestAds() ||
        AdConfig.demoUnitsOnly;
    if (allowed && !_sdkInitialized) {
      await MobileAds.instance.initialize();
      _sdkInitialized = true;
    }
    canLoadAds = allowed && _sdkInitialized;
    notifyListeners();
    return canLoadAds;
  }

  Future<void> showPrivacyOptions() async {
    if (!supported || !privacyOptionsRequired) return;
    fullScreenAdGate.skipNextAppOpen();
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    await _refreshPermission();
  }
}
