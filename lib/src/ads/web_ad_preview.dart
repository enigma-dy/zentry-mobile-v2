import 'package:flutter/material.dart';

import 'ad_frame.dart';

/// Local preview of an ad placement, without any advertising network requests.
class WebAdPreview extends StatelessWidget {
  const WebAdPreview({super.key, this.onDismiss});
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => AdFrame(
    onDismiss: onDismiss,
    child: Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1C2B),
        border: Border.all(color: const Color(0xFF6B6285)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.campaign_outlined, color: Color(0xFFFFD700)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Test advertisement',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Website preview',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
