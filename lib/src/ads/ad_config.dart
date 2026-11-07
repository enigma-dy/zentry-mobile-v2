import 'package:flutter/foundation.dart';

enum AdPlacement { home, match, prediction, liveTvList, liveTvPlayer }

class AdConfig {
  AdConfig._();

  static const androidAppId = 'ca-app-pub-5393431054971185~4713556926';
  static const androidProductionBanner =
      'ca-app-pub-5393431054971185/4275619406';
  static const androidTestBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const androidBanner = kReleaseMode
      ? androidProductionBanner
      : androidTestBanner;
  // iOS keeps its own Google sample banner until an iOS unit is supplied.
  static const iosAppId = 'ca-app-pub-3940256099942544~1458002511';
  static const iosBanner = 'ca-app-pub-3940256099942544/2934735716';
  static const _sampleUnits = {
    'ca-app-pub-3940256099942544/6300978111',
    'ca-app-pub-3940256099942544/2934735716',
  };

  // Derive the consent fallback from the actual configured units, so adding
  // any production unit cannot accidentally retain the demo-only bypass.
  static bool usesOnlyDemoUnits(Iterable<String> units) =>
      units.isNotEmpty && units.every(_sampleUnits.contains);

  static bool get demoUnitsOnly => usesOnlyDemoUnits(
    defaultTargetPlatform == TargetPlatform.iOS
        ? const [iosBanner]
        : const [androidBanner],
  );
  static const webTestMode = bool.fromEnvironment(
    'ADS_WEB_TEST_MODE',
    defaultValue: true,
  );

  static const adsenseEnabled = bool.fromEnvironment('ADSENSE_ENABLED');
  static const adsensePublisherId = String.fromEnvironment(
    'ADSENSE_PUBLISHER_ID',
  );
  static const _defaultSlot = String.fromEnvironment('ADSENSE_SLOT_ID');

  static String webSlot(AdPlacement placement) => switch (placement) {
    AdPlacement.home => const String.fromEnvironment(
      'ADSENSE_HOME_SLOT',
      defaultValue: _defaultSlot,
    ),
    AdPlacement.match => const String.fromEnvironment(
      'ADSENSE_MATCH_SLOT',
      defaultValue: _defaultSlot,
    ),
    AdPlacement.prediction => const String.fromEnvironment(
      'ADSENSE_PREDICTION_SLOT',
      defaultValue: _defaultSlot,
    ),
    AdPlacement.liveTvList => const String.fromEnvironment(
      'ADSENSE_LIVE_TV_SLOT',
      defaultValue: _defaultSlot,
    ),
    AdPlacement.liveTvPlayer => const String.fromEnvironment(
      'ADSENSE_PLAYER_SLOT',
      defaultValue: _defaultSlot,
    ),
  };

  static bool webEnabled(AdPlacement placement) =>
      !webTestMode &&
      kReleaseMode &&
      adsenseEnabled &&
      RegExp(r'^ca-pub-\d{16}$').hasMatch(adsensePublisherId) &&
      RegExp(r'^\d+$').hasMatch(webSlot(placement));
}
