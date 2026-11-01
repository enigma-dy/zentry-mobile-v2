import '../models/user_model.dart';
import 'ad_config.dart';

bool shouldShowAds(AdPlacement placement, UserModel? user) {
  if (placement == AdPlacement.liveTvList ||
      placement == AdPlacement.liveTvPlayer) {
    return true;
  }
  return !(user?.hasPredictionAccess ?? false);
}
