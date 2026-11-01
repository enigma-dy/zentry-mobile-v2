import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:predict/src/ads/web_ad_preview.dart';
import 'package:predict/src/ads/ad_slot.dart';
import 'package:predict/src/services/session_manager.dart';

import 'ad_policy_test.dart' show adTestUser;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SessionManager.instance.updateUser(adTestUser());
  });

  testWidgets('upgrading to Pro removes ordinary ads immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdSlot(
            placement: AdPlacement.home,
            contentBuilder: (_, _) => const WebAdPreview(),
          ),
        ),
      ),
    );
    expect(find.text('Test advertisement'), findsOneWidget);
    await SessionManager.instance.updateUser(
      adTestUser(
        tier: 'pro',
        expiry: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    await tester.pump();
    expect(find.text('Test advertisement'), findsNothing);
  });

  testWidgets('Pro viewers can close Live TV ads for the page session', (
    tester,
  ) async {
    await SessionManager.instance.updateUser(
      adTestUser(
        tier: 'pro',
        expiry: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdSlot(
            placement: AdPlacement.liveTvPlayer,
            dismissible: true,
            contentBuilder: (_, close) => WebAdPreview(onDismiss: close),
          ),
        ),
      ),
    );
    expect(find.text('Test advertisement'), findsOneWidget);
    await tester.tap(find.byTooltip('Close advertisement'));
    await tester.pump();
    expect(find.text('Test advertisement'), findsNothing);
    await SessionManager.instance.updateUser(adTestUser());
    await tester.pump();
    expect(find.text('Test advertisement'), findsNothing);
  });
}
