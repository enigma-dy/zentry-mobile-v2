import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps rotation available in both the native and provider players.
mixin PlayerOrientation<T extends StatefulWidget> on State<T> {
  Orientation? _orientation;
  bool get managesPlayerOrientation => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!managesPlayerOrientation) return;
    final orientation = MediaQuery.orientationOf(context);
    if (_orientation == orientation) return;
    _orientation = orientation;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        orientation == Orientation.landscape
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge,
      ),
    );
  }

  Widget rotationButton(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return IconButton(
      tooltip: landscape ? 'Switch to portrait' : 'Switch to landscape',
      icon: Icon(
        landscape ? Icons.stay_current_portrait : Icons.stay_current_landscape,
      ),
      onPressed: () => SystemChrome.setPreferredOrientations(
        landscape
            ? [DeviceOrientation.portraitUp]
            : [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
      ),
    );
  }

  @override
  void dispose() {
    if (managesPlayerOrientation) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(SystemChrome.setPreferredOrientations([]));
    }
    super.dispose();
  }
}
