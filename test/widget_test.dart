import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/main.dart';

void main() {
  testWidgets('starts with the branded logo splash', (tester) async {
    await tester.pumpWidget(const ZentryApp());
    expect(find.text('ZENTRY'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}




