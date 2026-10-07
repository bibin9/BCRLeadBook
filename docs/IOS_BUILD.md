# Building BCR LeadBook for iPhone

**Status:** the iOS project (`ios/`) is generated and configured, but it has **never been compiled or run**. iOS builds need macOS with Xcode, and this project was developed on Windows. Treat the first Mac build as a verification step and expect to fix small things.

## What you need

- A Mac with a current Xcode (and its command-line tools) and CocoaPods (`sudo gem install cocoapods` or `brew install cocoapods`).
- Flutter on that Mac at the same version used here: **3.47.6 (Dart 3.13.5)**. Check with `flutter --version`; install the matching version if different.
- An Apple ID. A free Apple ID can install on your own iPhone, but the app expires after **7 days** and must be re-installed. For TestFlight/App Store you need the paid **Apple Developer Program** (USD 99/year).
- A USB cable and an iPhone with Developer Mode on (Settings → Privacy & Security → Developer Mode).

## One-time setup

```bash
cd bcr-leadbook
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace          # always the .xcworkspace, not .xcodeproj
```

In Xcode:

1. Select **Runner** (project) → **Runner** (target) → **Signing & Capabilities**.
2. Tick **Automatically manage signing** and choose your **Team** (your Apple ID or developer account).
3. Bundle Identifier is `com.bcr.leadbook`. If Apple says it is unavailable, change it to something unique such as `com.<yourname>.leadbook`.
4. Deployment target is iOS 15.0 (already set).
5. No extra capability is required: **do not** add Push Notifications, since reminders are *local*.

## Run on your iPhone

```bash
flutter devices                       # find your iPhone's id
flutter run --release -d <iphone-id>
```

First launch: on the phone open Settings → General → VPN & Device Management → trust your developer certificate if prompted.

## Create a build for TestFlight / App Store

```bash
flutter build ipa --release
```

The archive appears in `build/ios/archive/` and the `.ipa` in `build/ios/ipa/`. Upload with the **Transporter** app (or Xcode → Product → Archive → Distribute App → App Store Connect). In App Store Connect create the app record with the same Bundle ID, add the privacy answers below, then submit to TestFlight / review.

## App Store privacy answers

- Data collection: **none**. No data is collected or sent off the device. No tracking, no third-party SDKs that collect data.
- Encryption: the app uses no custom encryption (set `ITSAppUsesNonExemptEncryption` to `NO` in Info.plist if you want to skip the export-compliance prompt).

## What to check on the first Mac build

- `pod install` resolves; the build succeeds (the `sqlite3` package compiles/bundles its native SQLite through Dart build hooks, so this is the likeliest place for a toolchain hiccup).
- `AppDelegate.swift` sets `UNUserNotificationCenter.current().delegate`; confirm reminders show as banners when the app is open.
- Run the "Device test checklist" in `docs/TEST_REPORT.md`: especially notifications, WhatsApp/Call/Email buttons, backup share sheet and Restore file picker.
- iCloud/iTunes device backups include the app's data by default (Apple behaviour). That is the user's own backup, but mention it if privacy wording matters to a client.

## Platform behaviour to know

- iOS keeps at most **64** pending local notifications; the app schedules the soonest 50 and tops up on every launch/resume.
- Focus / Do Not Disturb modes may silence a reminder; it is then waiting in Notification Centre rather than lost, depending on the user's Focus settings.
- If the user denies notification permission, only Settings → Notifications → BCR LeadBook can re-enable it; the app still shows due follow-ups in-app.
