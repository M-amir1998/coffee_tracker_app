# ADR 0002: Supabase, with every write through database functions

Status: accepted (2026-10-22)

## Context

Money must never be created, lost or changed by a buggy or malicious client.
A shared group ledger needs authentication, per-group isolation and live
updates, without running and securing a custom server.

## Decision

- Supabase provides PostgreSQL, Auth, Realtime and Storage.
- Client roles (`anon`, `authenticated`) have no `INSERT`, `UPDATE` or `DELETE`
  privilege on any table. They can `SELECT` through Row Level Security
  policies, and they call `SECURITY DEFINER` functions for every change.
- Each function authenticates, authorizes before validating input, takes a
  per-group advisory lock, checks an idempotency key and writes through one
  ledger engine in a `private` schema.
- New tables are private by default (`alter default privileges`, and
  `auto_expose_new_tables = false`).

## Consequences

- Business rules live in SQL and are tested with pgTAP; the Flutter app cannot
  bypass them, and other clients would get the same guarantees.
- Changing a rule needs a migration, which is reviewed and tested in CI.
- Serializing writes per group limits throughput per group to one write at a
  time, which is far above what a coffee group needs.
- Only the publishable key is shipped in the app. It is safe to expose because
  every table is protected by RLS and privileges.
