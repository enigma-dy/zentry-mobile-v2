import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'full_screen_ad_policy.dart';
import 'mobile_ads_service.dart';

InterstitialAd? _ready;
DateTime? _loadedAt;
bool _preparing = false;

Future<void> preparePreWatchAd() async {
  if (!MobileAdsService.instance.supported ||
      _preparing ||
      fullScreenAdGate.isShowing) {
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
  // Only a preloaded ad may delay playback. A slow consent/network request
  // never starts on the Watch tap itself.
  if (!MobileAdsService.instance.supported ||
      !MobileAdsService.instance.canLoadAds) {
    return;
  }
  final ad = _ready;
  final now = DateTime.now();
  if (ad == null ||
      _loadedAt == null ||
      now.difference(_loadedAt!) >= const Duration(minutes: 55) ||
      !fullScreenAdGate.tryBegin(now)) {
    return;
  }
  _ready = null;
  final closed = Completer<void>();
  void finish() {
    if (!closed.isCompleted) closed.complete();
  }

  ad.fullScreenContentCallback = FullScreenContentCallback(
    onAdClicked: (_) => fullScreenAdGate.skipNextAppOpen(),
    onAdShowedFullScreenContent: (_) =>
        fullScreenAdGate.didShow(DateTime.now()),
    onAdDismissedFullScreenContent: (_) => finish(),
    onAdFailedToShowFullScreenContent: (_, _) => finish(),
  );
  try {
    await ad.show();
    await closed.future;
  } catch (_) {
    /* Playback proceeds when the SDK cannot display the ad. */
  } finally {
    ad.dispose();
    fullScreenAdGate.finish();
  }
}
