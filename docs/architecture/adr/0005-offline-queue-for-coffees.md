# ADR 0005: Offline queue only for coffees

Status: accepted (2026-10-22)

## Context

People record coffees next to the machine, often with poor connectivity. A
lost tap means lost money; a duplicated tap means a wrong debt.

## Decision

- Only coffees are queued offline. A queued coffee keeps its idempotency key
  and the time it was drunk, and is retried on reconnect, on app resume and
  with backoff.
- The server accepts coffees up to 7 days late, charges the price that applied
  at that time, and treats a repeated key as a replay.
- Deposits, purchases, transfers and reimbursements need a connection, because
  they depend on confirmations and on the current cash in the box.

## Consequences

- Each queued coffee is tagged with the member who recorded it. Only that
  member's session shows and sends it, so a coffee queued on a shared device is
  never charged to the next person who signs in; it waits for its owner.
- Signing out with unsent coffees first tries to send them, then asks for
  confirmation and explains that they stay on the device. Deleting the account
  discards them.
- A refused coffee (for example older than 7 days, or the member has left the
  group) stays visible with the reason, so the member can retry or discard it;
  it is never dropped silently.
- The queue is bounded (50 entries per member) and lives in local storage, so
  coffees queued on one device are not visible on another until they are sent.
