# Test report: BCR LeadBook 1.0.0

Date: 2026-10-03. Toolchain: Flutter 3.47.6 / Dart 3.13.5, Android SDK 36, Windows 10.

## Headline

- `flutter analyze`: no issues.
- `flutter test`: **167 automated tests passing, 1 skipped** (searching "émile" does not find "Émile": SQLite folds only ASCII case; documented limitation).
- Release APK built and signed with the release upload key (`dist/BCR-LeadBook-1.0.0.apk`).
- **Not done:** no test on a physical phone or emulator (this PC has no working emulator: hardware virtualisation is off in its BIOS), no iOS compile (no Mac), no usability test with real users. Nothing below claims otherwise.

## QA and business acceptance (BAT) passes

Two independent review passes were run by AI agents playing roles. **They are not real QA staff or a real salesperson, they could not use a phone, and their findings do not replace the device checklist below.**

- **QA pass** (wrote exploratory tests, `test/qa_*.dart`): 8 confirmed defects, all fixed: crash when expanding an existing product in Add Meeting; "Open it" overwriting existing rapport notes; resumed drafts failing on a since-deleted person; layout overflows (long location, empty state, follow-up time at 320 px / 2x text); company delete leaving its draft; backup with a Notepad BOM rejected; date-picker assertion for dates far in the past. Extras: drafts flush when the app goes to the background; "+971 (0) 50…" WhatsApp links; Arabic digits in phone numbers.
- **Sales-executive BAT** (8 scenarios, `test/bat_*.dart`): verdict was "accept after fixing renewals filtering, national phone search and the false renewal-reminder claim". All 3 major and 7 of 8 minor items fixed: renewals filter by insurance line and lead-row expiry follows the line filter; `0501234567` finds `+971 50 123 4567`; welcome text no longer promises renewal reminders; prompt to close open follow-ups when a new meeting is saved; "Other people here" and policy insurer/notes on the Pre-call page; one-tap Call/WhatsApp and contact name in follow-up lists; Undo after deletes and Merge duplicate companies; reschedule quick dates, weekday chips, Snooze for a week; last-backup date, 30-day nudge and "back up first" on restore; `renewals.csv`.
- **Not done / by design:** the company tab bar could not be confirmed as clipped on a real screen (the test font is wider than real fonts); extra product fields (premium, lives, policy number), automatic renewal reminders and a pipeline view are wish-list items for a future version.

## What the automated tests actually exercise

| Area | How it is tested | File |
|---|---|---|
| Dates: expiry labels (unknown / today / N days / expired), month and year boundaries, leap day, DST-safe day counting, overdue / today / upcoming buckets, add-month clamping | Unit tests with a fixed clock | `test/core_test.dart` |
| Phone and email hints, WhatsApp/tel links, similar-company-name detection | Unit tests | `test/core_test.dart` |
| Database + data layer: company-only save, required-name rule, full entry (contacts, two products with different expiries, person met ≠ next-call contact), history instead of overwrite, created vs updated stamps, rapport notes persistence, product removal, task create/reschedule/complete/reopen/snooze/delete, target month untouched by rescheduling, cascade and set-null rules, rollback on failed save, search (company, contact, phone in any format, notes, wildcards), every filter and sort, 4,000-company load | In-memory SQLite (real SQL), controllable clock | `test/repository_test.dart` |
| Drafts: encode/decode, resume exact state, corrupt draft ignored | In-memory SQLite | `test/repository_test.dart` |
| **Persistence across restart** | Real database *file*, closed and reopened, full snapshot compared | `test/backup_persistence_test.dart` |
| Migrations: fresh DB, idempotent, newer DB refused, failing migration rolls back | Real SQLite | `test/backup_persistence_test.dart` |
| **Backup / restore**: versioned file, round trip into a fresh install gives identical rows and relationships (person met, next-call contact, task→product/contact links), replace semantics, each kind of bad file rejected (not JSON, wrong format, missing version, newer version, missing section, damaged record, count mismatch, orphaned references, duplicate ids), a restore that fails midway leaves old data intact | Real SQLite | `test/backup_persistence_test.dart` |
| CSV export: all products/contacts present, rapport notes absent when excluded, quoting, BOM, formula protection, empty DB | Unit tests with an RFC-4180 parser | `test/backup_persistence_test.dart` |
| Demo data only on request and removable without touching real records | Unit tests | `test/backup_persistence_test.dart` |
| **Reminder scheduling logic**: future-only, soonest-first, 50-item cap (< iOS 64), discreet text, company name opt-in, reschedule / snooze / complete / delete / delete-company cancel or move the notification, permission requested on demand, **permission denied** leaves data usable and due tasks listed, platform exceptions swallowed, rebuild after restart / time-zone refresh, queued syncs | `ReminderService` against a **fake** notification gateway | `test/reminder_test.dart` |
| UI flows through the real widgets (phone-width, in-memory DB): welcome + dashboard + About show exactly `BCR (BibinCutRiver)`; empty states; save with company name only; empty-name message; full realistic entry incl. two products, two different contacts, notes, next action; draft keep / resume / discard; similar-company suggestion and "Open it"; Add Meeting keeps history; Leads search + filter; follow-up snooze / complete / undo / reopen; permission denied flow; delete confirmation; expired / "10 days left" / "Expiry unknown" labels; **no layout overflow at 2× text size** on every tab, the entry form and the company page | Flutter widget tests | `test/ui_test.dart` |

### Bugs found and fixed during development (by tests or my own review)

- The Leads list took 2.7 s for 4,000 companies because of a poorly indexed subquery: fixed with a composite index (now ~150 ms).
- Dashboard did not show a draft right after leaving the form: fixed (screens now refresh).
- Leads toolbar and row badges overflowed at large text size: fixed.
- Sheets closed even if the user cancelled "Delete?": fixed.

## Acceptance criteria

| # | Criterion | Evidence | Status |
|---|---|---|---|
| 1 | Save a lead with only a company name | Data test + UI test | Verified in automated tests |
| 2 | Realistic meeting entry in under five minutes | The full form scripted in a UI test works end to end. **The five-minute timing itself needs a human with a stopwatch.** | Flow verified; timing **not measured** |
| 3 | Two products with different expiries on one company | Data + UI tests; renewals list shows them as separate rows | Verified |
| 4 | Different person met and next-call decision-maker | Data + UI tests | Verified |
| 5 | Another meeting without losing earlier notes | Data + UI tests | Verified |
| 6 | Close and reopen without data loss | Real DB file closed/reopened in test | Verified at database level; **not on a phone** |
| 7 | Recover an unfinished draft | Data + UI tests | Verified |
| 8 | Search and filter accurately | Data + UI tests | Verified |
| 9 | Create, reschedule, complete a follow-up | Data + UI tests | Verified |
| 10 | Notifications on supported devices | Scheduling logic verified against a fake gateway. **No real notification has been delivered by this build.** | **Needs device test** (checklist below) |
| 11 | App usable with notification permission denied | UI + service tests | Verified in automated tests; the real OS prompt is untested |
| 12 | Export and restore backup keeping relationships | Round-trip test | Verified at data level; the share sheet and file picker are **untested on a device** |
| 13 | Month/year boundaries, expired policies, overdue tasks | Unit + data tests | Verified |
| 14 | `BCR (BibinCutRiver)` displayed exactly | UI tests assert the exact string on Welcome, Dashboard (bottom) and About | Verified |

## Device test checklist (do this on a real phone before relying on the app)

Android (install `dist/BCR-LeadBook-1.0.0.apk`) and, separately, iPhone:

1. Install, open, tap Get started. Check the signature on Welcome, bottom of Home, and About.
2. Add a lead with only a company name; kill the app from recents; reopen. The lead is still there.
3. Time a realistic entry (target: under 5 minutes).
4. Create a follow-up for **2 minutes from now** with a reminder. Allow notifications when asked. Lock the phone; confirm the notification arrives and shows only "You have a follow-up due."
5. Create a reminder for tomorrow, **reboot the phone**, confirm it is still delivered (Android: also try after force-stop and after the battery saver is on, since some makers block this, see below).
6. Change the phone's time zone; open the app; confirm the reminder moved to the new local time.
7. Mark a follow-up complete / delete it, and confirm its pending notification does not fire.
8. Deny notifications (or switch them off in system settings) and confirm the app still lists the due follow-up and shows the explanatory message.
9. Settings → Create backup → save it; uninstall/reinstall (or use a second phone); Restore; confirm companies, contacts, products, meetings and follow-ups all return.
10. Export CSV with and without rapport notes; open in Excel/Sheets; confirm columns and that private notes are absent when excluded.
11. Tap Call, WhatsApp, Email on a contact; confirm each opens the right app with nothing sent.
12. Large text: set the phone's font size to maximum; page through every screen.
13. TalkBack / VoiceOver quick pass on Home, the entry form and a company page.
14. (iPhone) Run through IOS_BUILD.md's "What to check on the first Mac build".

## Known platform limitations (honest list)

- **Reminder delivery is the OS's job.** Android uses *inexact, idle-friendly* alarms: no special permission, but a reminder can be a few minutes late. Some phone makers (Xiaomi, Oppo, Vivo, Huawei, Samsung "sleeping apps") kill background alarms; the user may need to exempt the app from battery optimisation. Not tested on any device.
- **Pending-notification limits:** only the soonest 50 reminders are registered (iOS cap is 64); the rest are registered on the next app open. A user who does not open the app for a very long time and has more than 50 future reminders could miss ones beyond that window.
- **Time-zone change:** reminders already registered with the OS fire at their old absolute time until the app is opened once, which re-registers them at the new local time.
- **Android reboot/update:** the plugin's boot receiver restores scheduled alarms; unverified on hardware. The app also rebuilds every reminder at each launch.
- **iPad:** the share sheet is anchored to the screen centre; not tested.
- **Backups are unencrypted JSON.** Android Auto Backup is switched off so records are not copied to Google Drive behind the user's back; iOS device backups (iCloud/iTunes) do include app data (Apple default).
- **Release signing:** the delivered APK is signed with the debug key because no production key exists yet. Fine for personal sideloading; create a release key (README) before distributing to anyone, because changing keys later forces an uninstall.
- **Search** uses SQL `LIKE` (substring, case-insensitive for ASCII). It is not accent-insensitive and has no typo tolerance.
- **No multi-device sync** by design.
