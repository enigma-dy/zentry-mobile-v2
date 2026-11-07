import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/main.dart';
import 'package:predict/src/brand.dart';
import 'package:predict/src/startup_gate.dart';

void main() {
  testWidgets('starts with the branded logo splash', (tester) async {
    await tester.pumpWidget(const ZentryApp());
    expect(find.byType(LogoSplash), findsOneWidget);
    expect(find.byType(BrandLogo), findsOneWidget);
    final logo = tester.widget<Image>(
      find.descendant(of: find.byType(BrandLogo), matching: find.byType(Image)),
    );
    expect(
      (logo.image as AssetImage).assetName,
      'assets/images/zentry_logo.jpg',
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
