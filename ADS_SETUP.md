# Advertising

Android and iOS use the official `google_mobile_ads` plugin and Google's sample
app/ad unit IDs. Android's manifest contains
`ca-app-pub-3940256099942544~3347511713`. Banner, interstitial and rewarded test
IDs are centralized in `lib/src/ads/ad_config.dart`; ordinary pages and lists use banners. Live TV may show a preloaded test
interstitial after an explicit Watch tap, before the player opens. Rewarded ads
are not shown and no reward benefits are invented.

| Placement | Free / signed out | Active Pro |
| --- | --- | --- |
| Home and match pages | Ads | No ads |
| Predictions | Ads | No ads |
| Live TV channel and fixture lists | Ads | Ads |
| Live TV Watch tap | Pre-playback ad, if ready | Pre-playback ad, if ready |
| During playback | No app ads | No app ads |

Eligibility uses the existing user VIP tier and expiry (`hasPredictionAccess`).
An upgrade updates visible ad slots immediately. Live TV list banners appear
between blocks of up to 12 cards, with at most three slots. The player routes contain no app ad widgets. A Watch tap can show one preloaded
interstitial; playback opens only after it is dismissed. If an ad is not ready
or fails, watching proceeds immediately. A two-minute frequency cap avoids
repeated ads during server retries. There are no in-play timers or halftime
triggers because a reliable break signal is not available.
Ad failures leave playback and navigation usable. Desktop targets show no ads.

## Mobile testing and consent

Run `flutter pub get`, then rebuild the app. Hot reload cannot install the native
plugin or manifest changes. Google sample ads have a Test Ad label and do not
generate revenue. iOS uses its own Google sample app and unit IDs.

The service requests Google's UMP consent information before loading ads and
provides an Ad privacy choices entry in the menu when Google requires it.
Google's demonstration app has no publisher privacy message, so the service
allows only these hard-coded Google sample units if UMP cannot complete. When
switching to real IDs, disable `demoUnitsOnly`, configure AdMob Privacy &
messaging, replace the native app IDs as well as the ad unit IDs, and configure
the current iOS SKAdNetwork entries from Google's integration guide.

## Flutter web / AdSense

Web uses a real DOM AdSense display unit through a conditional implementation,
never the native AdMob plugin. No AdSense script is added globally to index.html,
so Pro users' ordinary pages do not initialize it. Keep Auto ads **off** in your
AdSense account: automatically inserted ads cannot follow this app's Pro rule.

Web test mode is enabled by default and renders clearly labelled local demo
ad cards. It does not request any Google ads or require an account. Test cards
follow the same Pro exemptions and Live TV exception as live ads. Disable test
mode with `--dart-define=ADS_WEB_TEST_MODE=false` when using your own AdSense IDs.

Live web ad requests stay disabled until a release build has valid publisher and slot
IDs. AdMob test IDs cannot be used as AdSense publisher IDs. Example:

```powershell
& 'C:\flutter\bin\flutter.bat' build web --release --dart-define=ADS_WEB_TEST_MODE=false --dart-define=ADSENSE_ENABLED=true --dart-define=ADSENSE_PUBLISHER_ID=ca-pub-YOUR_16_DIGIT_ID --dart-define=ADSENSE_SLOT_ID=YOUR_NUMERIC_SLOT_ID
```

Optional placement overrides: `ADSENSE_HOME_SLOT`, `ADSENSE_MATCH_SLOT`,
`ADSENSE_PREDICTION_SLOT`, `ADSENSE_LIVE_TV_SLOT`, `ADSENSE_PLAYER_SLOT`.
The DOM units use fixed 320x50 or 728x90 display slots; they are not disguised as
play buttons or overlaid on content. Pre-watch interstitials use the SDK's standard dismissal controls; standard
AdSense display code is left unmodified.

Approve the website in AdSense, configure Google's consent messages for the
applicable regions, and publish the exact `ads.txt` / `app-ads.txt` publisher
records supplied by your account. Those records and live ads cannot be enabled
without your publisher ID. Existing Flutter web Live TV playback remains
Android-only; ads do not change playback support.

References: https://developers.google.com/admob/flutter/quick-start,
https://developers.google.com/admob/flutter/privacy,
https://developers.google.com/admob/flutter/test-ads,
https://support.google.com/adsense/answer/1354736.

### Windows builds with packages on a different drive

If Kotlin reports that plugin source files and the Android project have different
roots (for example, packages on C: and the app on F:), build with per-run flags:

```powershell
& 'C:\flutter\bin\flutter.bat' build apk --debug --no-pub --android-project-arg=kotlin.incremental=false --android-project-arg=kotlin.compiler.execution.strategy=in-process
```

These flags avoid the cross-drive incremental cache failure without changing the
project's permanent Gradle settings.
