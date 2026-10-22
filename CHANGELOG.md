# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - unreleased

First version of the rewrite. It replaces the prototype; no data is migrated
automatically (see `docs/migration/PROTOTYPE_MIGRATION.md`).

### Added

- Double-entry ledger in integer cents with append-only history, posting
  rules for coffees, deposits, personal and box-funded purchases, transfers,
  reimbursements, cash and balance adjustments, and reversals.
- Transaction lifecycle with confirmations, rejections, cancellations,
  disputes and reversals; idempotency keys and a per-group lock for safe
  retries and concurrent requests; post-conditions for the cash box and
  reimbursements.
- Accounting cycles with snapshots, carry-forward and protected closed
  periods; cycle reports.
- Groups with invitations, roles (member, treasurer, admin), Row Level
  Security isolation and account deletion that keeps history anonymized.
- Flutter app for Android, iOS, web, Windows, macOS and Linux: personal
  dashboard with one-tap coffee and undo, group balances, activity feed with
  filters and cursor pagination, transaction details, forms for every
  operation, settle-up assistant, Coffee Heroes with achievements and streaks,
  analytics, cycles, administration (members, invitations, price, cash box,
  exports, audit log, integrity check, group settings), notifications and
  settings.
- Offline queue for coffees, tied to the member who recorded them.
- Realtime refresh of group data.
- English and Spanish translations; light and dark themes; responsive layouts
  and keyboard shortcuts.
- pgTAP suites for the database, unit and widget tests for the app, backend
  tests against a local Supabase stack, and a CI workflow.
- Windows setup script, demo seed data for the local stack, platform icons
  and documentation.
