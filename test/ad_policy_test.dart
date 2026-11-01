import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/ads/ad_config.dart';
import 'package:predict/src/ads/ad_policy.dart';
import 'package:predict/src/models/user_model.dart';

UserModel adTestUser({
  String tier = 'none',
  DateTime? expiry,
  String role = 'user',
}) => UserModel(
  id: 'ads-test',
  username: 'viewer',
  email: 'viewer@example.com',
  isVerified: true,
  vipTier: tier,
  vipExpiresAt: expiry?.toIso8601String(),
  role: role,
);

void main() {
  test(
    'Free and signed-out viewers have ads in ordinary screens and Live TV',
    () {
      for (final user in [null, adTestUser()]) {
        for (final placement in AdPlacement.values) {
          expect(
            shouldShowAds(placement, user),
            isTrue,
            reason: placement.name,
          );
        }
      }
    },
  );

  test('Active Pro and administrators only have Live TV ads', () {
    for (final user in [
      adTestUser(
        tier: 'pro',
        expiry: DateTime.now().add(const Duration(days: 1)),
      ),
      adTestUser(role: 'admin'),
    ]) {
      for (final placement in AdPlacement.values) {
        expect(
          shouldShowAds(placement, user),
          placement == AdPlacement.liveTvList ||
              placement == AdPlacement.liveTvPlayer,
          reason: placement.name,
        );
      }
    }
  });

  test('Expired or invalid subscriptions do not suppress ordinary ads', () {
    for (final user in [
      adTestUser(
        tier: 'pro',
        expiry: DateTime.now().subtract(const Duration(days: 1)),
      ),
      adTestUser(tier: 'pro'),
    ]) {
      expect(shouldShowAds(AdPlacement.home, user), isTrue);
    }
  });

  test('AdSense stays disabled without publisher configuration', () {
    for (final placement in AdPlacement.values) {
      expect(AdConfig.webEnabled(placement), isFalse);
    }
  });
}
