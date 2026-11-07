import 'package:flutter/material.dart';

import '../services/session_manager.dart';
import 'ad_config.dart';
import 'ad_policy.dart';
import 'native_ad.dart';
import 'ad_platform_stub.dart'
    if (dart.library.io) 'ad_platform_mobile.dart'
    if (dart.library.js_interop) 'ad_platform_web.dart';

export 'ad_config.dart' show AdPlacement;
export 'ad_platform_stub.dart'
    if (dart.library.io) 'ad_platform_mobile.dart'
    if (dart.library.js_interop) 'ad_platform_web.dart'
    show AdPrivacyButton;

typedef AdContentBuilder =
    Widget Function(BuildContext context, VoidCallback? onDismiss);

class AdSlot extends StatefulWidget {
  const AdSlot({
    super.key,
    required this.placement,
    this.dismissible = false,
    this.contentBuilder,
    this.useNativeTemplate = false,
  });
  final AdPlacement placement;
  final bool dismissible;
  final bool useNativeTemplate;
  // Allows placement/entitlement tests without loading an advertising SDK.
  final AdContentBuilder? contentBuilder;

  @override
  State<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends State<AdSlot> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: SessionManager.instance,
    builder: (context, _) {
      if (_dismissed ||
          !shouldShowAds(
            widget.placement,
            SessionManager.instance.currentUser,
          )) {
        return const SizedBox.shrink();
      }
      final VoidCallback? close = widget.dismissible
          ? () => setState(() => _dismissed = true)
          : null;
      return widget.contentBuilder?.call(context, close) ??
          (widget.useNativeTemplate
              ? PlatformNativeAd(placement: widget.placement, onDismiss: close)
              : PlatformAdBanner(
                  placement: widget.placement,
                  onDismiss: close,
                ));
    },
  );
}
