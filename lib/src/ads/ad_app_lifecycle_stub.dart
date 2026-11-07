import 'package:flutter/material.dart';

final NavigatorObserver adRouteObserver = NavigatorObserver();

class AdAppLifecycle extends StatelessWidget {
  const AdAppLifecycle({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
