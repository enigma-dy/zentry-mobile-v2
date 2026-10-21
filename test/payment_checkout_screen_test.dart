import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/payment_checkout_screen.dart';

void main() {
  testWidgets('checkout rejects an invalid payment URL', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PaymentCheckoutScreen(checkoutUrl: 'not-a-checkout-url'),
      ),
    );

    expect(find.text('The checkout URL is invalid.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });
}
