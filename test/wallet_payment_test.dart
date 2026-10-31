import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:predict/src/models/user_model.dart';
import 'package:predict/src/services/session_manager.dart';
import 'package:predict/src/services/fpl_duel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionManager.instance.saveSession(
      user: UserModel(
        id: 'wallet-owner',
        username: 'tester',
        email: 'test@example.com',
        isVerified: true,
      ),
      tokens: AuthTokens(
        accessToken: 'test-token',
        refreshToken: 'refresh',
        expiresIn: 900,
      ),
    );
  });
  test(
    'checkout reference survives service recreation and only paid clears it',
    () async {
      var paid = false;
      final api = FplDuelService(
        baseUrl: 'https://example.test',
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer test-token');
          if (r.url.path.endsWith('/checkout')) {
            expect(jsonDecode(r.body)['item_type'], 'wallet_deposit');
            return http.Response(
              jsonEncode({
                'data': {
                  'reference': 'ZEN-test',
                  'checkout_url': 'https://checkout.example',
                },
              }),
              200,
            );
          }
          expect(r.method, 'POST');
          expect(r.url.path, '/api/v1/billing/transactions/ZEN-test/verify');
          return http.Response(
            jsonEncode({
              'data': {
                'reference': 'ZEN-test',
                'status': paid ? 'paid' : 'pending',
              },
            }),
            200,
          );
        }),
      );
      await api.createWalletCheckout(provider: 'paystack', amountNgn: 5000);
      expect(
        await FplDuelService(
          baseUrl: 'https://example.test',
        ).pendingWalletReference(),
        'ZEN-test',
      );
      expect((await api.verifyWalletPayment('ZEN-test'))['status'], 'pending');
      expect(await api.pendingWalletReference(), 'ZEN-test');
      paid = true;
      expect((await api.verifyWalletPayment('ZEN-test'))['status'], 'paid');
      expect(await api.pendingWalletReference(), isNull);
    },
  );
  test(
    'failed verification retains reference and does not retry automatically',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'wallet_pending_reference_wallet-owner',
        'ZEN-test',
      );
      var calls = 0;
      final api = FplDuelService(
        baseUrl: 'https://example.test',
        client: MockClient((r) async {
          calls++;
          return http.Response('{"message":"Please retry"}', 502);
        }),
      );
      await expectLater(api.verifyWalletPayment('ZEN-test'), throwsException);
      expect(calls, 1);
      expect(await api.pendingWalletReference(), 'ZEN-test');
    },
  );
}
