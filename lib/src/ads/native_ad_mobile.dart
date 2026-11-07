import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_frame.dart';
import 'ad_platform_mobile.dart' show AdPrivacyButton;
import 'mobile_ads_service.dart';
import 'full_screen_ad_policy.dart';

class PlatformNativeAd extends StatefulWidget {
  const PlatformNativeAd({super.key, required this.placement, this.onDismiss});
  final AdPlacement placement;
  final VoidCallback? onDismiss;
  @override
  State<PlatformNativeAd> createState() => _PlatformNativeAdState();
}

class _PlatformNativeAdState extends State<PlatformNativeAd> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    MobileAdsService.instance.addListener(_privacyChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  void _privacyChanged() {
    if (!mounted) return;
    if (!MobileAdsService.instance.canLoadAds) {
      _generation++;
      final old = _ad;
      _ad = null;
      _loaded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    } else if (_ad == null && !_loading) {
      unawaited(_load());
    }
    setState(() {});
  }

  Future<void> _load() async {
    if (_loading || !MobileAdsService.instance.supported) return;
    _loading = true;
    final generation = ++_generation;
    try {
      if (!await MobileAdsService.instance.ensureInitialized() ||
          !mounted ||
          generation != _generation) {
        return;
      }
      final ad = NativeAd(
        adUnitId: defaultTargetPlatform == TargetPlatform.iOS
            ? AdConfig.iosNative
            : AdConfig.androidNative,
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.small,
          mainBackgroundColor: const Color(0xFF190F2E),
          cornerRadius: 10,
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: Colors.black,
            backgroundColor: const Color(0xFFFFD700),
            size: 14,
          ),
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: Colors.white,
            size: 14,
          ),
          secondaryTextStyle: NativeTemplateTextStyle(
            textColor: Colors.white70,
            size: 12,
          ),
        ),
        listener: NativeAdListener(
          onAdClicked: (_) => fullScreenAdGate.skipNextAppOpen(),
          onAdLoaded: (ad) {
            if (!mounted || generation != _generation) {
              ad.dispose();
              return;
            }
            setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            if (!mounted || generation != _generation) return;
            setState(() {
              _ad = null;
              _loaded = false;
            });
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (_) {
      _ad?.dispose();
      _ad = null;
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    MobileAdsService.instance.removeListener(_privacyChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!MobileAdsService.instance.supported || !_loaded || ad == null) {
      return const SizedBox.shrink();
    }
    return AdFrame(
      onDismiss: widget.onDismiss,
      privacy: const AdPrivacyButton(),
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: AdWidget(ad: ad),
      ),
    );
  }
}
