# Security

## Threat model

| Actor | Trust | Must not be able to |
|-------|-------|---------------------|
| Anyone on the internet | none | read or change anything |
| Signed-in user of another group | none for this group | see this group's members, balances or history; act in it |
| Member | trusted with their own actions | change history, approve their own submissions, act for others, see another group |
| Treasurer | trusted with the cash box | approve their own submissions, rewrite history, change roles |
| Administrator | trusted with the group | rewrite or delete history (corrections are new, audited records) |
| The app on a user's device | untrusted | bypass any rule above; every rule is enforced in the database |

## Authentication

- Supabase Auth with email and password. Email confirmation is required
  (`enable_confirmations = true`); sessions are only created for confirmed
  addresses.
- Passwords need at least 8 characters with letters and digits.
- The app uses the PKCE flow. Email links (confirmation, recovery, email
  change) return to the configured web URL or to the mobile deep link
  `io.github.mamir1998.coffeetracker://login-callback`. Each email also
  contains a one-time code, so a link opened on another device is not needed.
- Refresh tokens rotate; access tokens expire after one hour.
- Changing the email address requires confirming both the old and the new
  address (`double_confirm_changes = true`).
- Account deletion (`delete_my_account`) removes the Auth user, anonymizes the
  profile and ends all memberships. Financial history stays, because other
  members' balances depend on it. A member must be settled before leaving a
  group.

## Authorization

| Action | Member | Treasurer | Admin |
|--------|:------:|:---------:|:-----:|
| Record own coffee, deposit, purchase, transfer | yes | yes | yes |
| Record a coffee, deposit or purchase for another member | | yes | yes |
| Confirm or reject deposits, purchases and reimbursement requests of others | | yes | yes |
| Pay out reimbursements, reconcile the cash box | | yes | yes |
| Confirm a transfer addressed to them | yes | yes | yes |
| Confirm a transfer on behalf of the recipient (with a note) | | | yes |
| Reverse transactions, adjust balances, resolve disputes | | | yes |
| Close cycles, change the price, manage members, roles and invitations | | | yes |
| Read the audit log and run the integrity check | | treasurer: integrity check | yes |

Rules that apply to everyone: nobody decides on their own submission, and
nobody resolves a dispute they are involved in while another administrator is
available. Functions check membership and role before they validate input, so
a caller without access learns nothing from validation errors.

## Data isolation

- **Row Level Security** is enabled on every table. Policies use
  `group_id in (select private.my_group_ids())`, so a user only sees rows of
  groups they are an active member of. Some data is further restricted by role
  (for example invitations and the audit log are visible to administrators).
- **Privileges**: `anon` and `authenticated` have no privileges on tables
  except `SELECT` for `authenticated`. Nobody can `INSERT`, `UPDATE` or
  `DELETE` through the API. Functions in `public` are executable by
  `authenticated` only; functions in `private` are not executable by API
  roles, except three membership helpers used by the policies. New tables
  are private by default (`alter default privileges ... revoke`, and
  `auto_expose_new_tables = false`).
- **Realtime** only publishes tables that have RLS, and Realtime applies the
  same policies to each subscriber.
- **Storage**: receipts live in a private bucket under `<group_id>/...`; only
  members of that group can upload or read them (5 MB, images and PDF).
  Avatars live under `<user_id>/...`; only the owner can write them (1 MB).
  Both buckets are prepared for future use; the app does not upload files yet.

Tests: `supabase/tests/database/090_rls_isolation.test.sql` (40 assertions:
reads, API calls, direct writes, role-restricted data, anonymous access) and
`test/backend/backend_test.dart` (the same rules over HTTP and Realtime with
real users).

## Database function hygiene

- Every `SECURITY DEFINER` function sets `search_path = ''` and uses fully
  qualified names, so objects in other schemas cannot be substituted.
- No function builds SQL from user input.
- Inputs are validated with explicit limits: amounts are positive and at most
  5,000.00 per operation, quantities 1 to 20 coffees, names and notes have
  length limits, dates must be within a window (coffees up to 7 days back,
  deposits 31 days, purchases 365 days, never in the future).
- `supabase db lint --level error` runs in CI.

## Integrity and audit

- Financial tables are append-only and cannot be truncated (guard triggers
  that even the table owner cannot bypass without dropping them in a
  migration).
- Every status change is recorded by a trigger; administrative actions
  (role changes, removals, price changes, reversals, adjustments, cycle
  closings, overrides) are written to the audit log.
- Idempotency keys make retries safe; a per-group lock serializes writes.
- `verify_ledger_integrity` recomputes the ledger invariants on demand.

## Secrets

- The app only ever contains the Supabase URL and the **publishable** key.
  Both are public by design; RLS and privileges protect the data.
- The app refuses to start if it is given a secret key (`sb_secret_...`) or a
  legacy `service_role` JWT (`AppConfig.problems`, covered by a unit test).
- `config/*.json`, `.env*`, `android/key.properties`, `*.jks` and
  `*.keystore` are ignored by Git. Only `*.example.json` files with
  placeholders are committed. CI builds use a placeholder configuration.
- The backend tests use the local stack's secret key from the environment, only
  to create test users, and must never be pointed at a production project.
- Release signing keys and deployment tokens belong in the CI secret store or
  on the release machine, never in the repository.

## Client-side measures

- CSV exports neutralize spreadsheet formulas (cells starting with `=`, `+`,
  `-`, `@`, tab or carriage return are prefixed), while plain numbers stay
  numeric.
- The UI never shows raw backend errors; messages come from stable error keys.
- Coffee Heroes respects the opt-out: hidden members only see their own row.

## Production checklist (Supabase dashboard)

- Keep email confirmation on. Configure a custom SMTP server; the built-in
  email service is rate-limited and meant for testing.
- Set the Site URL and the redirect allow-list to the production web URL and
  the mobile deep link only.
- Consider enabling CAPTCHA protection for sign-up and sign-in, leaked-password
  protection (plan dependent) and multi-factor authentication for
  administrators. None of these are enabled by this repository.
- `secure_password_change` is off in `supabase/config.toml`: a signed-in user
  can change their password without re-entering it. Turn it on if the app's
  password change is extended with reauthentication.
- Enable backups or point-in-time recovery according to the plan.
- Restrict who can access the Supabase dashboard and use separate projects for
  staging and production. Never run `supabase/seed.sql` against production.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability reporting
for this repository, or contact the maintainer directly.
