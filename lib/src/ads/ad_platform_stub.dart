import 'package:flutter/material.dart';

import 'ad_config.dart';

class PlatformAdBanner extends StatelessWidget {
  const PlatformAdBanner({super.key, required this.placement, this.onDismiss});
  final AdPlacement placement;
  final VoidCallback? onDismiss;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class AdPrivacyButton extends StatelessWidget {
  const AdPrivacyButton({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
