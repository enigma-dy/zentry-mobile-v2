import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/session_manager.dart';
import 'ad_config.dart';
import 'full_screen_ad_policy.dart';
import 'mobile_ads_service.dart';

class AdRouteObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];
  bool get rootPageVisible =>
      _routes.length == 1 && _routes.single is PageRoute;
  void reset() => _routes.clear();
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
  }
}

final adRouteObserver = AdRouteObserver();

class AdAppLifecycle extends StatefulWidget {
  const AdAppLifecycle({super.key, required this.child});
  final Widget child;
  @override
  State<AdAppLifecycle> createState() => _AdAppLifecycleState();
}

class _AdAppLifecycleState extends State<AdAppLifecycle>
    with WidgetsBindingObserver {
  AppOpenAd? _ready;
  DateTime? _loadedAt;
  DateTime? _backgroundAt;
  bool _loading = false;
  int _generation = 0;
  int _sessions = 0;

  bool get _eligibleUser =>
      SessionManager.instance.isLoggedIn &&
      !(SessionManager.instance.currentUser?.hasPredictionAccess ?? false);

  @override
  void initState() {
    super.initState();
    if (!MobileAdsService.instance.supported) return;
    WidgetsBinding.instance.addObserver(this);
    SessionManager.instance.addListener(_sessionChanged);
    MobileAdsService.instance.addListener(_permissionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _sessions = (prefs.getInt('ads_app_sessions') ?? 0) + 1;
      await prefs.setInt('ads_app_sessions', _sessions);
      if (mounted) unawaited(_load());
    } catch (_) {
      /* Storage/ad failures do not hold startup. */
    }
  }

  void _sessionChanged() {
    if (!mounted) return;
    if (!_eligibleUser) {
      _discard();
    } else {
      unawaited(_load());
    }
  }

  void _permissionChanged() {
    if (!mounted) return;
    if (!MobileAdsService.instance.canLoadAds) {
      _discard();
    } else if (!_loading) {
      unawaited(_load());
    }
  }

  void _discard() {
    _generation++;
    _ready?.dispose();
    _ready = null;
    _loadedAt = null;
  }

  Future<void> _load() async {
    if (!mounted ||
        !MobileAdsService.instance.supported ||
        !_eligibleUser ||
        !adRouteObserver.rootPageVisible ||
        _loading) {
      return;
    }
    if (_ready != null &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(hours: 4)) {
      return;
    }
    _discard();
    _loading = true;
    final generation = _generation;
    try {
      if (!await MobileAdsService.instance.ensureInitialized() ||
          !mounted ||
          !_eligibleUser ||
          generation != _generation) {
        _loading = false;
        return;
      }
      await AppOpenAd.load(
        adUnitId: defaultTargetPlatform == TargetPlatform.iOS
            ? AdConfig.iosAppOpen
            : AdConfig.androidAppOpen,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            _loading = false;
            if (!mounted || !_eligibleUser || generation != _generation) {
              ad.dispose();
              return;
            }
            _ready = ad;
            _loadedAt = DateTime.now();
          },
          onAdFailedToLoad: (_) {
            _loading = false;
          },
        ),
      );
    } catch (_) {
      _loading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundAt = _backgroundAt;
      _backgroundAt = null;
      if (backgroundAt != null) {
        unawaited(_showIfAvailable(DateTime.now().difference(backgroundAt)));
      }
      unawaited(_load());
    }
  }

  Future<void> _showIfAvailable(Duration away) async {
    if (fullScreenAdGate.consumeAppOpenSkip()) return;
    final now = DateTime.now();
    final ad = _ready;
    if (!mounted ||
        !MobileAdsService.instance.canLoadAds ||
        ad == null ||
        _loadedAt == null ||
        now.difference(_loadedAt!) >= const Duration(hours: 4) ||
        !appOpenAdEligible(
          signedIn: SessionManager.instance.isLoggedIn,
          hasPredictionAccess:
              SessionManager.instance.currentUser?.hasPredictionAccess ?? false,
          rootPageVisible: adRouteObserver.rootPageVisible,
          sessions: _sessions,
          away: away,
        ) ||
        !fullScreenAdGate.tryBegin(now)) {
      return;
    }
    // Show only an already loaded ad on this foreground event. The load callback
    // never interrupts the user later, after content has become interactive.
    _ready = null;
    final closed = Completer<void>();
    void finish() {
      if (!closed.isCompleted) closed.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdClicked: (_) => fullScreenAdGate.skipNextAppOpen(),
      onAdShowedFullScreenContent: (_) =>
          fullScreenAdGate.didShow(DateTime.now()),
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, _) => finish(),
    );
    try {
      await ad.show();
      await closed.future;
    } catch (_) {
      /* Resume proceeds when no ad can be displayed. */
    } finally {
      ad.dispose();
      fullScreenAdGate.finish();
      if (mounted) unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SessionManager.instance.removeListener(_sessionChanged);
    MobileAdsService.instance.removeListener(_permissionChanged);
    _discard();
    adRouteObserver.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
