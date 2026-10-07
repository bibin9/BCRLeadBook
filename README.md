# BCR LeadBook

A personal lead and relationship tracker for an insurance sales professional, built with Flutter (Android + iPhone). Record a client meeting in under five minutes, then recall the important details before the next call.

*Crafted by* **BCR (BibinCutRiver)**

- Fully offline. Local SQLite database. No account, no cloud, no analytics, no AI service. The Android app does not even request the INTERNET permission.
- Only **Company Name** is required to save a lead.
- Three generous note areas (meeting summary, personal/rapport notes, company trivia), dated meeting history, multiple contacts and multiple insurance products per company, follow-up tasks with private local reminders, versioned backup/restore and CSV export.

| Doc | What it covers |
|---|---|
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | Short guide for the person using the app |
| [docs/IOS_BUILD.md](docs/IOS_BUILD.md) | Exact iOS build and signing steps (needs a Mac) |
| [docs/TEST_REPORT.md](docs/TEST_REPORT.md) | What was tested, what was **not**, and the device checklist |
| [docs/DATA_AND_EXPORT.md](docs/DATA_AND_EXPORT.md) | Database schema, backup file format, CSV structure |

## Deliverables in this folder

| Item | Location |
|---|---|
| Source code | `lib/`, `test/`, `android/`, `ios/` |
| Android build (release APK, 3 CPU types) | `dist/BCR-LeadBook-1.0.0.apk` |
| iOS project | `ios/` (build on a Mac, see docs/IOS_BUILD.md) |

## Setup and run

Requirements: Flutter 3.47.x (Dart 3.13), JDK 17+ and the Android SDK for Android builds. On this PC the toolchain is in `C:\Bibin\_tools`:

```powershell
. C:\Bibin\_tools\env.ps1      # puts flutter, java and the Android SDK on PATH for this shell
cd C:\Bibin\bcr-leadbook
flutter pub get
flutter test                   # 167 tests (1 skipped, documented)
flutter run                    # on a connected phone or emulator
flutter build apk --release    # -> build/app/outputs/flutter-apk/app-release.apk
```

The APK is signed with the release upload key at `C:/Users/Internet/.bcr-leadbook/upload.jks` (passwords in `android/key.properties`, git-ignored, with a copy in that same folder). **Back that folder up somewhere safe: without the key you cannot publish updates.**

Install the APK on an Android phone: copy `dist/BCR-LeadBook-1.0.0.apk` to the phone, open it and allow "install unknown apps" for your file manager. (Or `adb install -r dist\BCR-LeadBook-1.0.0.apk` with USB debugging on.)

### Signing the Android release

A release keystore already exists on this PC (see above). If `android/key.properties` is missing the build falls back to the **debug key**. To create a new keystore:

```powershell
keytool -genkey -v -keystore $env:USERPROFILE\.bcr-leadbook\upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (never commit it, and back up the `.jks` and its passwords. Losing them means you cannot update the app):

```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=C:/Users/<you>/.bcr-leadbook/upload.jks
```

Changing the signing key later forces users to uninstall (losing local data), so decide this **before** giving the app to other people. Remind them to take a backup first.

## Architecture

```
lib/
  core/        pure Dart helpers: dates (local-calendar maths), phone/email hints, similar-name matching
  data/        models, SQLite schema + migrations, Repository (all SQL), backup/restore, CSV export, demo data
  services/    AppController (state + write entry point), ReminderService (+ platform gateway),
               file picker/share, phone/WhatsApp/email launcher
  ui/          theme, shared widgets, editors (bottom sheets), screens
```

- **UI → AppController → Repository → SQLite.** Screens never contain SQL; every write goes through `AppController.run`, which refreshes lists and re-synchronises notifications.
- **Related records with stable IDs:** `companies` 1—* `contacts`, `products`, `meetings`, `tasks`. Foreign keys are enforced; deleting a company cascades; deleting a contact/product/meeting only clears the link.
- **Migrations:** `PRAGMA user_version` + an ordered list in `lib/data/database.dart`. Each step runs in a transaction; a database from a *newer* app version is refused rather than damaged.
- **Reminders** are rebuilt from the database (`ReminderService.sync`) on launch, on resume, and after every change, so a changed/completed/deleted task can never leave a stale notification behind. The planner is pure Dart and unit-tested through a fake gateway.
- **Performance:** indexed queries; list rows are built lazily; 4,000 companies (with contacts, products and tasks) load in ~150 ms in tests. SQLite calls are synchronous on the UI isolate (fast at this scale; move to a background isolate if you ever expect hundreds of thousands of rows).

### Packages (resolved with `flutter pub add` on 2026-10-03, pinned by `pubspec.lock`)

| Package | Version | Why |
|---|---|---|
| sqlite3 | 3.7.0 | Local database (bundles its own SQLite for Android/iOS) |
| path_provider / path | 2.1.x / 1.9.x | App storage folder, temp files |
| intl | 0.20.3 | Date formatting |
| flutter_local_notifications | 22.3.1 (stable; a 23.0.0-dev prerelease exists and was deliberately not used) | Local reminders |
| timezone + flutter_timezone | 0.11.1 / 5.1.1 | Schedule at the phone's local wall-clock time |
| url_launcher | 6.3.3 | Open Phone / WhatsApp / Email apps |
| file_picker | 13.1.0 | Choose a backup file to restore |
| share_plus | 13.3.1 | System share sheet for backups and CSV |

No paid services. No network code.

## Known limitations

See [docs/TEST_REPORT.md](docs/TEST_REPORT.md) for the full list. In short: this build has been exercised by automated tests only (logic, database, backup/restore, reminder scheduling through a fake, widget-level UI flows, plus AI-simulated QA and sales-executive acceptance passes). It has **not** yet been run on a physical Android or iOS device, and the iOS app has not been compiled (no Mac available).
