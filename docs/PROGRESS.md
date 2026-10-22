# Progress and verification status

Last updated: 2026-10-22. This page records what has actually been run and
what has not. "Implemented" means the code exists; "verified" means the check
in the table below was run and passed on the date given.

## Verification log (2026-10-22, Windows 11 development machine)

| Check | Command | Result |
|-------|---------|--------|
| Static analysis | `flutter analyze` | no issues |
| Formatting | `dart format --output=none --set-exit-if-changed lib test tool` | clean |
| Translation keys | `python tool/l10n_keys.py lib/l10n/app_en.arb lib/l10n/app_es.arb` | 799 keys used and defined in English and Spanish, none missing or unused |
| Unit and widget tests | `flutter test` | 117 passed, 10 skipped (the backend tests skip without a running stack) |
| Web release build | `flutter build web --release --dart-define-from-file=config/ci.json` | succeeded (placeholder backend); `build/web` 43 MB, `main.dart.js` 4.5 MB |
| Database migrations and demo seed | `supabase db reset` (Supabase CLI 2.121.0, PostgreSQL 17) | all 6 migrations and `seed.sql` applied; seeded group checked by SQL: 5 members, one closed and one open cycle, 180 transactions, 3 pending items, all 8 integrity checks pass |
| Database lint | `supabase db lint --level error` | no findings |
| Database tests (pgTAP) | `supabase test db` | 13 files, 321 assertions, all passed (with the demo seed loaded) |
| Backend tests against the local stack | `flutter test test/backend/backend_test.dart` with the local URL and keys | 10 passed: API coffee pricing, 10 parallel retries recorded once, competing reimbursements (exactly one succeeds), deposit and transfer confirmation, cross-group isolation, anonymous access, direct table writes refused, Realtime isolation, ledger integrity |
| Windows setup script | `powershell -ExecutionPolicy Bypass -File tool\setup.ps1` (Windows PowerShell 5.1) | completed: tools detected, packages fetched, Docker Desktop started, minimal stack started, `config/development.json` written (valid JSON without BOM, ignored by Git) |
| CI workflow lint | `actionlint` (Docker image `rhysd/actionlint`) | 0 errors |

## Not verified

| Item | Why |
|------|-----|
| Android APK / App Bundle | no Android SDK on the development machine (disk space); prepared for CI (`android` job) |
| Windows desktop build | requires Windows Developer Mode (admin rights), which is off on the development machine; prepared for CI (`windows` job) |
| Linux desktop build | requires Linux; prepared for CI (`linux` job) |
| iOS and macOS builds | require macOS with Xcode; prepared for CI (`apple` job, manual trigger, iOS without code signing) |
| CI workflow runs | the repository has not been pushed, so GitHub Actions has never run it |
| Hosted Supabase project, web hosting, store listings | nothing has been deployed (see [DEPLOYMENT.md](deployment/DEPLOYMENT.md)) |
| Running the app interactively in a browser or on a device | not done in this environment; screens are covered by widget tests at phone, tablet and desktop sizes |

## Feature status

| Area | Status |
|------|--------|
| Ledger, posting rules, lifecycle, idempotency, locking, post-conditions | implemented, covered by pgTAP |
| Accounting cycles, snapshots, carry-forward, protected history | implemented, covered by pgTAP |
| Groups, invitations, roles, membership, account deletion | implemented, covered by pgTAP |
| RLS isolation and privileges | implemented, covered by pgTAP and the backend tests |
| Read models (dashboard, balances, activity, analytics, heroes, reports, exports) | implemented; balances and overview covered by pgTAP (`110`), dashboard, heroes, awards, activity pagination, analytics and statistics by `120_read_models`; screens by widget tests |
| Flutter screens (auth, home, group, activity, details, forms, settle up, heroes, analytics, cycles, admin, notifications, settings) | implemented, covered by widget tests |
| Offline coffee queue (per member) | implemented, covered by unit tests |
| Realtime refresh | implemented; delivery and RLS isolation covered by the backend test, the app's refresh wiring is not tested |
| English and Spanish | implemented, key coverage checked |
| Light and dark themes, responsive layouts, keyboard shortcuts, accessibility | implemented, covered by widget tests (contrast, large text, semantics) |
| CSV exports | implemented, CSV safety unit-tested; file saving per platform not run on devices |
| Receipt and avatar uploads | backend only (buckets, policies); no app UI |
| PDF export | not implemented (optional in the requirements) |
| Push or email notifications | not implemented; notifications are in-app |
| Prototype data migration | documented as a manual, approval-gated procedure; no import tool |

## Known limitations

- The web app needs a connection to load (Flutter's default service worker
  no longer caches the app). Once loaded, coffees are queued offline.
- The settlement assistant is greedy; it does not guarantee the minimum number
  of payments.
- Receipt attachments and profile pictures are prepared in the backend
  (private `receipts` and public `avatars` buckets with policies, an
  `evidence_path` on purchases), but the app has no upload or viewer for them
  yet.
- No license has been chosen for the repository.
