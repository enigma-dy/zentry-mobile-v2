import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/bet_machine_sheet.dart';
import 'support/test_app_config.dart';

void main() {
  setUpAll(initializeTestApi);

  testWidgets('Bet Machine renders valid responsive dropdowns', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BetMachineSheet())),
    );

    expect(find.byType(DropdownButton<String>), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
