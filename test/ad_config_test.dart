import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/ads/ad_config.dart';

void main() {
  test('development requests use the Google banner sample', () {
    expect(kReleaseMode, isFalse);
    expect(AdConfig.androidBanner, AdConfig.androidTestBanner);
    expect(AdConfig.androidBanner, isNot(AdConfig.androidProductionBanner));
  });

  test(
    'a production or unknown unit cannot receive the demo consent bypass',
    () {
      expect(
        AdConfig.usesOnlyDemoUnits([
          AdConfig.androidProductionBanner,
          AdConfig.androidTestBanner,
        ]),
        isFalse,
      );
      expect(
        AdConfig.usesOnlyDemoUnits(['ca-app-pub-3940256099942544/unknown']),
        isFalse,
      );
      expect(AdConfig.usesOnlyDemoUnits([]), isFalse);
    },
  );

  test('known demo units retain the testing fallback on each platform', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        expect(AdConfig.demoUnitsOnly, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });
}
