import 'package:flutter/material.dart';

/// The close control is outside the SDK's ad view and its click target.
class AdFrame extends StatelessWidget {
  const AdFrame({
    super.key,
    required this.child,
    this.onDismiss,
    this.privacy,
    this.horizontalPadding = 8,
  });
  final Widget child;
  final VoidCallback? onDismiss;
  final Widget? privacy;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Advertisement',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
              ?privacy,
              if (onDismiss != null)
                IconButton(
                  tooltip: 'Close advertisement',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          child,
        ],
      ),
    ),
  );
}
