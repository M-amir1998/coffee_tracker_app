# ADR 0003: Double-entry ledger in integer cents

Status: accepted (2026-10-22)

## Context

The previous prototype stored running balances and edited them in place,
which made mistakes hard to find and impossible to audit. The requirements ask
for an immutable, auditable ledger in which debts, credits, net position, cash
and pending money are distinct.

## Decision

- Amounts are `bigint` cents everywhere; no floating-point money.
- A transaction (the business event, with a status) is separate from its
  ledger entries (the accounting effect). Only posted transactions have
  entries, and the entries of a transaction sum to zero.
- Five accounts: per-member receivables, the cash box, consumption, supplies
  and adjustments. Balances are always computed from entries.
- History is append-only. Corrections are reversals or audited adjustments.

## Consequences

- Every balance can be explained line by line, and integrity can be verified
  at any time (`verify_ledger_integrity`).
- Reads aggregate entries; an index on (group, account, member, cycle) and cycle
  snapshots keep this fast.
- Deleting a user cannot delete their financial history; the profile is
  anonymized instead.
