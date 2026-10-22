# Architecture

Coffee Tracker is one Flutter code base (Android, iOS, web, Windows, macOS,
Linux) on top of a Supabase project (PostgreSQL, Auth, Realtime, Storage). The
database owns every financial rule; the app is a client that calls database
functions and renders the results.

```
 ┌───────────────────────────── Flutter app ─────────────────────────────┐
 │  presentation (pages, widgets)  ←  application (Riverpod providers)    │
 │                                       ↓                               │
 │  domain (pure Dart models and rules)   data (repositories → RPCs)      │
 └───────────────────────────────────────┬───────────────────────────────┘
                     HTTPS (PostgREST RPC, Auth) │ WebSocket (Realtime)
 ┌───────────────────────────────────────┴───────────────────────────────┐
 │ Supabase                                                               │
 │  Auth (email + password, PKCE, email confirmation)                     │
 │  PostgREST  ─ public schema: read-only tables (RLS) + RPC functions    │
 │  Realtime   ─ change notifications for the group (RLS applies)         │
 │  Storage    ─ receipt and avatar buckets (not used by the app yet)     │
 │  PostgreSQL ─ private schema: ledger engine, guards, helpers           │
 └────────────────────────────────────────────────────────────────────────┘
```

## Repository layout

```
lib/
  app/            bootstrap, MaterialApp.router, routes, global providers
  core/           config, theme tokens, Money, errors, JSON helpers, shared widgets, l10n helpers
  features/<name>/
    data/         repositories: the only code that talks to Supabase
    domain/       immutable models and pure logic (unit-tested without Flutter)
    application/  Riverpod providers and notifiers
    presentation/ pages and widgets
  l10n/           app_en.arb, app_es.arb (generated code goes to l10n/generated, not committed)
supabase/
  migrations/     schema, ledger engine, group API, transaction API, read API, security
  tests/database/ pgTAP suites (helpers + 12 suites)
  templates/      branded Auth emails
  seed.sql        demo data for the local stack only
test/             unit, widget and backend tests
tool/             setup script, icon generation, translation key check
docs/             this documentation
```

Features: `auth`, `groups`, `accounting` (ledger models, reports), `coffee`
(one-tap button and offline queue), `dashboard`, `group_overview`,
`transactions` (activity, details, forms), `settlements`, `leaderboard` and
`achievements` (Coffee Heroes), `analytics`, `cycles`, `admin`,
`notifications`, `profile`, `settings`, `realtime`, `shell`.

## Backend design

- **Two schemas.** `public` holds the tables and the RPC functions exposed
  through the API. `private` holds the ledger engine, guards and helpers; it is
  not exposed and client roles cannot execute its functions (except the three
  membership helpers RLS policies need).
- **Reads** use RLS-protected `SELECT` on tables, or read-model functions that
  aggregate on the server (`get_dashboard`, `get_group_overview`,
  `get_member_balances`, `get_activity`, `get_analytics`, `get_leaderboard`,
  `get_cycle_report`, `export_transactions`, ...). Aggregation never happens
  by downloading the ledger to the client.
- **Writes** only through `SECURITY DEFINER` functions with
  `set search_path = ''`. Each one authenticates, authorizes, validates, takes
  the per-group advisory lock, checks the idempotency key, writes through the
  ledger engine and checks the post-conditions. See
  [ACCOUNTING.md](../accounting/ACCOUNTING.md).
- **Errors** are raised with SQLSTATE `P0001` and a stable machine key as the
  message (`insufficient_cash`, `not_member`, ...) plus an English detail. The
  app maps the key to a translated message and never shows raw backend errors.
- **Triggers** enforce immutability, the status state machine, the status
  history, profile creation on sign-up and account deletion clean-up.
- **No Edge Functions.** Everything, including account deletion, is plain SQL,
  so there is no server code to deploy besides migrations.

## App design

- **State**: Riverpod 3. Read models are `FutureProvider.autoDispose.family`
  keyed by group (and period or filter). After a successful write, or when a
  Realtime event arrives (debounced by 700 ms), `dataRevisionProvider` is
  bumped and the visible read models refetch. There is no client-side cache of
  balances that could disagree with the server.
- **Navigation**: GoRouter with a `StatefulShellRoute.indexedStack`, so each
  section keeps its own stack. Redirects handle the splash screen, signed-out
  users, password recovery links, invitation links (`/join/<code>`, preserved
  through sign-in with `next=`) and users without a group (welcome screen).
- **Layout**: Material 3 window size classes. Phones (< 600 px) use a bottom
  navigation bar and cards; tablets and desktops use a navigation rail, wider
  multi-column pages and sortable tables. Keyboard shortcuts on desktop and web:
  Alt+1...9 for sections, Alt+C to record a coffee, Alt+R to refresh, Alt+/ for
  the shortcut list.
- **Offline coffees**: the coffee button never loses a tap. When the network
  is unavailable, the coffee is stored locally (`shared_preferences`) with its
  idempotency key and the time it was drunk, and sent later: on reconnect, on
  app resume and with a backoff of 5 s, 15 s, 30 s and 1 min. The server
  accepts coffees up to 7 days late and charges the price that was valid at
  that time. Because the key is reused, a coffee that did reach the server
  before the connection dropped is not counted twice. Other operations
  (deposits, transfers, ...) require a connection, because they involve other
  people's confirmation.
- **Realtime**: one channel per group listens to `transactions`,
  `accounting_cycles`, `group_members`, `coffee_prices` and the user's
  `notifications`. RLS applies to Realtime, so members only receive changes of
  their own groups.
- **Money in the UI**: `Money.parse` / `Money.format` convert between cents and
  localized text; negative amounts use a real minus sign. The UI never does
  balance arithmetic that the server has not already done.
- **Localization**: English and Spanish ARB files (799 keys each) with ICU
  plurals and selects; `tool/l10n_keys.py` fails CI if a key is missing in
  either language.
- **Theme**: design tokens (`core/theme/tokens.dart`) with the coffee palette,
  light and dark color schemes and a `FinanceColors` extension for owes / owed
  / settled / pending colors. Contrast of the text colors is checked by a test.

## Testing

| Layer | Tooling | What it proves |
|-------|---------|----------------|
| Database | pgTAP (`supabase test db`) | posting rules, the fifteen accounting scenarios, idempotency, cycles, reversals, membership, RLS isolation, notifications, invariants, read models |
| Domain | `flutter test` | money parsing and formatting, CSV export safety, settlement planner (including randomized property checks), rankings, streaks, achievements, table sorting |
| Widgets | `flutter test` | screens at phone, tablet and desktop sizes, auth flows, forms, the coffee button with undo, offline queue behaviour, semantics and large text |
| Backend | `flutter test test/backend` against a local stack | the public API with real users: RPC flows, parallel retries, competing reimbursements, RLS over HTTP, Realtime isolation |

CI (`.github/workflows/ci.yml`) runs formatting, analysis, the translation
check, all Flutter tests, a web build, the database lint and pgTAP suites, the
backend tests against a local stack, and Android, Windows and Linux builds.
iOS and macOS builds run on demand on a macOS runner.

## Decisions

Architecture decision records are in [`adr/`](adr):

1. [Flutter with Riverpod and GoRouter](adr/0001-flutter-riverpod-gorouter.md)
2. [Supabase with all writes through database functions](adr/0002-database-functions-for-writes.md)
3. [Double-entry ledger in integer cents](adr/0003-double-entry-ledger.md)
4. [Accounting cycles as immutable snapshots](adr/0004-cycles-as-snapshots.md)
5. [Offline queue only for coffees](adr/0005-offline-queue-for-coffees.md)
