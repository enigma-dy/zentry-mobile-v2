# Advertising

Android and iOS use the official `google_mobile_ads` plugin. Android's manifest
contains the supplied app ID `ca-app-pub-5393431054971185~4713556926` for
publisher `pub-5393431054971185`. iOS still uses Google's sample app ID.
The screenshot confirms `ca-app-pub-5393431054971185/4275619406` is a banner unit.
Android release builds use it for the existing banner placements. Debug/profile
builds use Google's sample banner; iOS keeps its own sample units. IDs are
centralized in `lib/src/ads/ad_config.dart`.

| Android format | Production unit suffix | Placement |
| --- | --- | --- |
| Banner | `4275619406` | Existing home, match and prediction banners; Live TV lists |
| Native Advanced | `3315705612` | Google's small native template after every eighth prediction card, capped at three per list; alternating Live TV list slots |
| Interstitial | `9014754856` | Existing explicit Live TV Watch transition, only if preloaded |
| App open | `4437215591` | Eligible foreground returns to the root page |

The rewarded-interstitial screenshots are duplicates. Rewarded ads are excluded
at the user's request: no reward unit is loaded, no reward prompt is displayed,
and there are no changes to coin balances or the backend.

| Placement | Free / signed out | Active Pro |
| --- | --- | --- |
| Home and match pages | Ads | No ads |
| Predictions | Ads | No ads |
| Live TV channel and fixture lists | Ads | Ads |
| Live TV Watch tap | Preloaded interstitial, if ready | Preloaded interstitial, if ready |
| Eligible app return | App-open ad, if ready | No app-open ad |
| During playback | No app ads | No app ads |

Eligibility uses the existing user VIP tier and expiry (`hasPredictionAccess`).
An upgrade updates visible ad slots immediately. Live TV list banners appear
between blocks of up to 12 cards, with at most three slots. The player routes
contain no app ad widgets. Interstitials use the existing pre-watch template and
wait for dismissal before opening the player. Missing ads never delay playback
while loading. App-open and interstitial formats share a two-minute cooldown and
a single display gate, preventing stacked ads on resume or stream retries.
App-open waits until the third app session and a background interval of at least
30 seconds. It requires a signed-in, non-Pro user with only the root page
visible. Pushed pages and dialogs, including video, authentication and checkout
routes, prevent app-open display. It never shows an ad later just because a
background load completed. Cached app-open ads expire after four hours.
Returning from an ad click or ad privacy settings skips the next app-open
attempt, so those interactions do not cause an extra full-screen ad.
Ad failures leave playback and navigation usable. Desktop targets show no ads.

## Mobile testing and consent

Run `flutter pub get`, then rebuild the app. Hot reload cannot install the native
plugin or manifest changes. Google sample ads have a Test Ad label and do not
generate revenue. iOS uses its own Google sample app and unit IDs.

The service requests Google's UMP consent information before loading ads and
provides an Ad privacy choices entry in the menu when Google requires it.
The consent fallback is computed from an explicit allowlist of Google sample
units for the current platform. It is automatically disabled for Android release
builds because they contain a production banner. Configure Privacy & messaging
for this app in AdMob: production ads load only when UMP's `canRequestAds()`
allows them. Live ad delivery/account approval was not verified from this
workspace. All four Android formats use the supplied production units in release
builds and Google's corresponding sample units during development. iOS retains
its platform-specific sample units. Native cards use the plugin's built-in small
template, with the app's dark background and gold action button.

Validation: 16 ad configuration, entitlement, navigation and display-gate tests
plus the prediction pagination/scroll integration test passed. Static analysis
of the app entry point, ad modules and modified catalog page found no issues.
Live ad delivery still needs verification in a rebuilt Android release app.

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
play buttons or overlaid on content. Standard AdSense display code is left
unmodified.

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
