import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'mobile_ads_service.dart';

InterstitialAd? _ready;
DateTime? _loadedAt;
DateTime? _lastShown;
bool _preparing = false;
Future<void>? _displaying;

Future<void> preparePreWatchAd() async {
  if (!MobileAdsService.instance.supported ||
      _preparing ||
      _displaying != null) {
    return;
  }
  if (_ready != null &&
      _loadedAt != null &&
      DateTime.now().difference(_loadedAt!) < const Duration(minutes: 55)) {
    return;
  }
  _ready?.dispose();
  _ready = null;
  _preparing = true;
  try {
    if (!await MobileAdsService.instance.ensureInitialized() ||
        !MobileAdsService.instance.canLoadAds) {
      _preparing = false;
      return;
    }
    await InterstitialAd.load(
      adUnitId: defaultTargetPlatform == TargetPlatform.iOS
          ? AdConfig.iosInterstitial
          : AdConfig.androidInterstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ready = ad;
          _loadedAt = DateTime.now();
          _preparing = false;
        },
        onAdFailedToLoad: (_) {
          _preparing = false;
        },
      ),
    );
  } catch (_) {
    _preparing = false;
  }
}

Future<void> showPreWatchAd() async {
  if (!MobileAdsService.instance.supported ||
      !await MobileAdsService.instance.ensureInitialized() ||
      !MobileAdsService.instance.canLoadAds) {
    return;
  }
  final displaying = _displaying;
  if (displaying != null) return displaying;
  final ad = _ready;
  final now = DateTime.now();
  if (ad == null ||
      _loadedAt == null ||
      now.difference(_loadedAt!) >= const Duration(minutes: 55) ||
      (_lastShown != null &&
          now.difference(_lastShown!) < const Duration(minutes: 2))) {
    return;
  }
  _ready = null;
  return _displaying = _show(ad);
}

Future<void> _show(InterstitialAd ad) async {
  final closed = Completer<void>();
  void finish() {
    if (!closed.isCompleted) closed.complete();
  }

  ad.fullScreenContentCallback = FullScreenContentCallback(
    onAdShowedFullScreenContent: (_) {
      _lastShown = DateTime.now();
    },
    onAdDismissedFullScreenContent: (_) => finish(),
    onAdFailedToShowFullScreenContent: (_, _) => finish(),
  );
  try {
    await ad.show();
    await closed.future;
  } catch (_) {
    // Start the player normally if the SDK cannot display the preloaded ad.
  } finally {
    ad.dispose();
    _displaying = null;
  }
}
