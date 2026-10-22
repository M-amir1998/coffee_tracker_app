# ADR 0004: Accounting cycles as immutable snapshots

Status: accepted (2026-10-22)

## Context

Groups settle up periodically (for example every month or semester). The old
prototype reset the data by truncating tables, which destroyed history.

## Decision

- A group always has one open cycle. Closing it writes per-member and cash-box
  snapshots whose equations are enforced by `CHECK` constraints, marks the
  cycle closed and opens the next one with the closing balances as opening
  balances.
- Pending and disputed items move to the new cycle with an event in their
  history.
- Closed cycles accept no new postings and their snapshots cannot change.
  `TRUNCATE` is blocked on every financial table.

## Consequences

- Reports for any past cycle stay available and exportable.
- Carry-forward is verifiable: an integrity check compares every opening with
  the previous close and every snapshot with the ledger.
- A mistake discovered after closing is corrected in the open cycle (reversal
  or adjustment), never by reopening the old one.
