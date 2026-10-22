# Coffee Tracker

Shared coffee accounting for research groups: one tap per coffee, a cash box
everyone can trust, and balances that always add up.

Coffee Tracker 1.0 is a Flutter app for Android, iOS, the web, Windows, macOS
and Linux, backed by Supabase (PostgreSQL, Auth, Realtime, Storage). All
financial rules live in the database as an append-only, double-entry ledger in
integer cents.

## Features

- **+1 Coffee** with animation, haptic feedback and undo; several coffees at
  once; works offline and syncs later without double counting.
- **Payments**: deposits into the cash box (confirmed by a treasurer),
  personally funded or box-funded bean purchases, direct payments between
  members (confirmed by the recipient), reimbursements from the box, disputes.
- **Clear balances**: debts, credits, net position, cash in the box and pending
  money are always shown separately.
- **Accounting cycles** with carry-forward, immutable closed periods and
  reports.
- **Settle up** assistant that suggests reimbursements and payments.
- **Coffee Heroes**: podium (Coffee Legend, Espresso Engine, Caffeine
  Commander), monthly hero, streaks and achievements, with an opt-out.
- **Analytics** computed on the server.
- **Administration**: members, roles and invitations, coffee price
  (including scheduled changes), cash counts, reversals and corrections, CSV
  exports, audit log, ledger integrity check.
- **Realtime** updates and an in-app notification center.
- Responsive layouts for phone, tablet and desktop, keyboard shortcuts, light
  and dark themes, English and Spanish.

## Architecture in brief

```
Flutter app (Riverpod, GoRouter, Material 3)
   │  RPC + RLS-protected reads            │  Realtime (RLS applies)
   ▼                                       ▼
Supabase: Auth · PostgREST · Realtime · Storage
   ▼
PostgreSQL: public (read-only tables + API functions) · private (ledger engine)
```

Clients cannot write any table directly. Every change goes through a
`SECURITY DEFINER` function that authorizes, validates, locks the group,
checks an idempotency key and posts balanced ledger entries. Details:
[ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md) and
[ACCOUNTING.md](docs/accounting/ACCOUNTING.md).

## Getting started (Windows)

Requirements: Git, Node.js 20+, Docker Desktop, and Flutter 3.47.7 (the
script can download it).

```powershell
powershell -ExecutionPolicy Bypass -File tool\setup.ps1
flutter run -d chrome --web-port 3000 --dart-define-from-file=config/development.json
```

The script checks the tools, fetches packages, starts a minimal local
Supabase stack in Docker (migrations and demo data are applied on the first
start) and writes `config/development.json` with the local URL and
publishable key. Useful switches: `-InstallFlutter`, `-AddFlutterToPath`,
`-WithoutDeveloperMode` (web/Android only, if Windows Developer Mode is off),
`-FullStack` (includes Supabase Studio), `-SkipSupabase`.

### Other systems

```bash
flutter pub get
npx supabase@2.121.0 start -x studio,imgproxy,edge-runtime,logflare,vector,supavisor,postgres-meta
npx supabase@2.121.0 status          # copy API_URL and PUBLISHABLE_KEY
cp config/development.example.json config/development.json   # and fill them in
flutter run -d chrome --web-port 3000 --dart-define-from-file=config/development.json
```

### Demo data (local stack only)

`supabase/seed.sql` creates the group "Demo Research Lab" with Alice (admin),
Bob (treasurer), Charlie, Diana and Emma, a closed cycle, an open cycle and a
few pending items. Sign in as `alice@example.com` (or bob, charlie, diana,
emma) with the password `coffee-demo-1`. The invitation code is `LABCAFE2`.
Emails sent by the local stack are not delivered; read them in the local email viewer at
http://127.0.0.1:54324. The seed never runs against hosted projects.

## Commands

| Task | Command |
|------|---------|
| Static analysis | `flutter analyze` |
| Formatting check | `dart format --output=none --set-exit-if-changed lib test tool` |
| Translation keys | `python tool/l10n_keys.py lib/l10n/app_en.arb lib/l10n/app_es.arb` |
| Unit and widget tests | `flutter test` |
| Database tests (pgTAP) | `npx supabase@2.121.0 test db` |
| Backend tests (real API) | set `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY` from `supabase status`, then `flutter test test/backend/backend_test.dart` |
| Reset the local database | `npx supabase@2.121.0 db reset` |
| Web build | `flutter build web --release --dart-define-from-file=config/production.json` |
| Stop the local stack | `npx supabase@2.121.0 stop` |

CI (`.github/workflows/ci.yml`) runs the analysis, formatting, translation,
Flutter, database and backend checks on every push and pull request, and builds
the web, Android, Windows and Linux apps. iOS and macOS builds run on demand.

## Repository layout

```
lib/app        bootstrap, router, global providers
lib/core       config, theme, money, errors, shared widgets
lib/features   one folder per feature: data / domain / application / presentation
lib/l10n       English and Spanish translations
supabase/      migrations, pgTAP tests, auth email templates, demo seed
test/          unit, widget and backend tests
tool/          setup script, icon generation, translation check
docs/          architecture, accounting, security, deployment, user guide
```

## Documentation

- [Architecture](docs/architecture/ARCHITECTURE.md) and [decision records](docs/architecture/adr)
- [Accounting model](docs/accounting/ACCOUNTING.md)
- [Security](docs/security/SECURITY.md)
- [Deployment](docs/deployment/DEPLOYMENT.md)
- [User guide](docs/user-guide/USER_GUIDE.md)
- [Running costs](docs/COSTS.md)
- [Moving from the prototype](docs/migration/PROTOTYPE_MIGRATION.md)
- [Progress and verification status](docs/PROGRESS.md)
- [Changelog](CHANGELOG.md)

## License

No license has been chosen yet, so all rights are reserved by the author until
a `LICENSE` file is added. The bundled Inter and Fraunces fonts are licensed
under the SIL Open Font License (see `assets/fonts`).
