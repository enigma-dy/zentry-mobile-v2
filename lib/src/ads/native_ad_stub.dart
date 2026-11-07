import 'package:flutter/material.dart';

import 'ad_config.dart';
import 'ad_platform_stub.dart'
    if (dart.library.js_interop) 'ad_platform_web.dart';

// Web keeps its existing AdSense display implementation; it never loads AdMob.
class PlatformNativeAd extends StatelessWidget {
  const PlatformNativeAd({super.key, required this.placement, this.onDismiss});
  final AdPlacement placement;
  final VoidCallback? onDismiss;
  @override
  Widget build(BuildContext context) =>
      PlatformAdBanner(placement: placement, onDismiss: onDismiss);
}
