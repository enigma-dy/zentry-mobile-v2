import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_frame.dart';
import 'mobile_ads_service.dart';

class PlatformAdBanner extends StatefulWidget {
  const PlatformAdBanner({super.key, required this.placement, this.onDismiss});
  final AdPlacement placement;
  final VoidCallback? onDismiss;
  @override
  State<PlatformAdBanner> createState() => _PlatformAdBannerState();
}

class _PlatformAdBannerState extends State<PlatformAdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  int _width = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    MobileAdsService.instance.addListener(_privacyChanged);
  }

  void _privacyChanged() {
    if (!mounted) return;
    if (!MobileAdsService.instance.canLoadAds) {
      _generation++;
      _ad?.dispose();
      _ad = null;
      _loaded = false;
    }
    setState(() {});
  }

  Future<void> _load(int width) async {
    final generation = ++_generation;
    // The old platform view is removed during build before it is disposed.
    final oldAd = _ad;
    _ad = null;
    _loaded = false;
    await oldAd?.dispose();
    if (!await MobileAdsService.instance.ensureInitialized() ||
        !mounted ||
        generation != _generation) {
      return;
    }
    try {
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
      if (size == null || !mounted || generation != _generation) return;
      final ad = BannerAd(
        adUnitId: defaultTargetPlatform == TargetPlatform.iOS
            ? AdConfig.iosBanner
            : AdConfig.androidBanner,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted || generation != _generation) {
              ad.dispose();
              return;
            }
            setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, error) {
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
    } catch (error) {
      debugPrint('Banner unavailable: $error');
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
    if (!MobileAdsService.instance.supported) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 336 ? 0.0 : 8.0;
        final width = (constraints.maxWidth.clamp(0, 728) - padding * 2)
            .floor();
        if (width < 320) return const SizedBox.shrink();
        if (width != _width) {
          _width = width;
          _loaded = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _width == width) unawaited(_load(width));
          });
        }
        final ad = _ad;
        if (!_loaded || ad == null) return const SizedBox.shrink();
        return AdFrame(
          horizontalPadding: padding,
          onDismiss: widget.onDismiss,
          privacy: const AdPrivacyButton(),
          child: Center(
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        );
      },
    );
  }
}

class AdPrivacyButton extends StatelessWidget {
  const AdPrivacyButton({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: MobileAdsService.instance,
    builder: (context, _) => MobileAdsService.instance.privacyOptionsRequired
        ? TextButton(
            onPressed: MobileAdsService.instance.showPrivacyOptions,
            child: const Text('Ad privacy choices'),
          )
        : const SizedBox.shrink(),
  );
}
