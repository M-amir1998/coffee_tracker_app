# Accounting model

This document describes how Coffee Tracker records money. The database is the
single source of truth: every rule below is enforced in PostgreSQL
(`supabase/migrations`), not in the app, and is covered by the pgTAP suites in
`supabase/tests/database`.

## Principles

- **Integer cents.** Every amount is a `bigint` number of cents. Money is never
  stored or computed as a floating-point number. The only divisions are
  percentages and averages in analytics, which are never written back.
- **Append-only history.** Transactions, ledger entries, status events,
  cycle snapshots and the audit log cannot be updated or deleted by anyone,
  including the database owner (guard triggers raise
  `immutable_transaction` / `append_only`). `TRUNCATE` is blocked as well.
  The only mutable field of a transaction is its `status`, and only along the
  allowed transitions (see [Lifecycle](#lifecycle)).
- **Double entry.** A posted transaction writes ledger entries that sum to
  zero. Balances are always derived from those entries; there is no stored
  "balance" column that could drift.
- **One way in.** Client roles have no `INSERT`, `UPDATE` or `DELETE` privilege
  on any table. Every change goes through a `SECURITY DEFINER` function that
  authenticates, authorizes, validates, takes the group lock, checks the
  idempotency key and only then writes.
- **Serialized per group.** All balance-changing functions take the same
  transaction-scoped advisory lock for the group. Two requests for the same
  group run one after the other; requests for different groups do not wait for
  each other.
- **Idempotent.** Each operation carries a client-generated UUID. The pair
  (initiator, key) is unique, so a retry after a timeout returns the original
  result with `replayed: true` instead of recording the operation twice. Reusing
  a key for a different operation fails with `idempotency_conflict`.
- **Price snapshots.** A coffee stores the unit price that was valid when it was
  drunk (`unit_price_cents`). Price changes never alter past coffees.

## Accounts and sign conventions

| Account       | Meaning                                   | Positive amount means            |
|---------------|-------------------------------------------|----------------------------------|
| `member`      | What a member owes the group (per member) | the member owes the group        |
| `cash_box`    | Physical cash in the box                  | money in the box                 |
| `consumption` | Value of coffee consumed                  | (credit side: entries are negative) |
| `supplies`    | Beans and supplies bought                 | money spent on supplies          |
| `adjustments` | Corrections, write-offs, box discrepancies | balancing side of corrections   |

A member's **net balance** is the sum of their `member` entries:

- greater than zero: the member **owes** the group (a debt),
- less than zero: the group **owes** the member (a credit),
- zero: **settled**.

## Posting rules

`private.posting_rule` defines the entries for every transaction kind
(amount `a`, direction `d` = +1 or -1 for adjustments):

| Kind                 | Entries                                                        | Effect |
|----------------------|----------------------------------------------------------------|--------|
| `coffee`             | member +a, consumption -a                                      | the drinker owes more |
| `deposit`            | cash_box +a, member -a                                         | cash in, the member owes less |
| `purchase_personal`  | supplies +a, member -a                                         | the buyer is credited, the box is untouched |
| `purchase_box`       | supplies +a, cash_box -a                                       | the box pays, nobody is credited |
| `transfer`           | sender -a (`transfer_out`), recipient +a (`transfer_in`)       | the sender owes less, the recipient is owed less |
| `reimbursement`      | member +a, cash_box -a                                         | the box pays a member who was owed money |
| `cash_adjustment`    | cash_box +d·a, adjustments -d·a                                | the box is corrected to the counted amount |
| `balance_adjustment` | member +d·a, adjustments -d·a                                  | an audited correction of one member |
| `reversal`           | the exact negation of the reversed transaction's entries       | cancels a posted transaction |

A test proves that every rule sums to zero for both directions and that every
kind has a rule (`110_ledger_invariants`).

## Formulas

For one member in one accounting cycle:

```
net = opening
    + consumption
    - deposits
    - personal_purchases
    - transfers_sent
    + transfers_received
    + reimbursements
    + adjustments
```

For the cash box:

```
box = opening_cash + deposits - box_purchases - reimbursements + cash_adjustments
```

Across the whole group, because every transaction balances:

```
sum(member balances) + box = consumption - supplies - adjustments_account
```

The cycle snapshot tables enforce the member and box equations with `CHECK`
constraints, so a snapshot that does not add up cannot be stored.

## Quantities that are kept apart

The group overview reports these separately and never mixes them:

| Quantity          | Definition |
|-------------------|------------|
| Debts             | sum of positive member balances (what members owe) |
| Credits           | sum of negative member balances, as a positive number (what the group owes) |
| Net position      | sum of all member balances |
| Cash in the box   | expected box balance from posted transactions |
| Pending           | submitted but unconfirmed deposits, purchases, transfers and reimbursements; they change no balance until posted |

Unconfirmed money is never final: a pending deposit does not reduce the
member's debt and does not increase the cash box until a treasurer confirms it.

## Lifecycle

Statuses: `pending`, `posted`, `rejected`, `cancelled`, `disputed`, `reversed`.
The only allowed transitions are enforced by a trigger:

```
pending  -> posted | rejected | cancelled
rejected -> disputed
disputed -> posted | rejected
posted   -> reversed            (by a separate reversal transaction)
```

Only `posted` transactions have ledger entries. Every status change writes a
`transaction_events` row (by trigger, so no code path can skip it).

| Operation | Recorded by | Initial status |
|-----------|-------------|----------------|
| Coffee | the member, or a treasurer/admin on their behalf | posted |
| Deposit | the member | pending while the group requires deposit confirmation (default) |
| Deposit | a treasurer or admin (they hold the box) | posted |
| Personal or box purchase | a member | posted, or pending when the group requires purchase approval (default off) |
| Purchase | a treasurer or admin | posted |
| Transfer | the recipient (acknowledging receipt) | posted |
| Transfer | the sender, or an admin | pending until the recipient (or an admin who is not the sender) confirms |
| Transfer | an admin confirming on behalf of the recipient, with a note | posted, audited |
| Reimbursement | a treasurer or admin (they hand out the cash) | posted |
| Reimbursement request | the member who is owed money | pending until a treasurer pays it |
| Balance adjustment | an admin, with a note | posted |
| Cash adjustment | a treasurer/admin, from a reconciliation | posted |

Nobody decides on their own submission. The person who submitted an item can
cancel it while it is pending, and can dispute a rejection once. A dispute is
resolved by an administrator who is not involved in the transaction (an
involved administrator can only resolve it when there is no other one).

### Post-conditions

Checked after every posting while the group lock is held. If one fails, the
whole operation is rolled back:

- `insufficient_cash`: the cash box can never become negative (deposits,
  box purchases, reimbursements, cash adjustments and their reversals).
- `reimbursement_exceeds_credit`: a reimbursement cannot turn a member's
  credit into a debt. Pending requests are limited to the credit minus requests
  already waiting.

## Corrections

History is never edited. Mistakes are corrected with new, audited records:

- **Undo a coffee**: the member can undo their own coffee within the group's
  undo window (15 minutes by default). The undo is a reversal; the original
  stays visible.
- **Reverse** a posted transaction: administrators, with a mandatory note. Refused when the money is no longer available (for example reversing a
  deposit that was already spent from the box).
- **Balance adjustment**: an admin corrects one member's balance (for example a
  write-off), with a note. It is posted against the `adjustments` account.
- **Cash reconciliation**: a treasurer enters the counted cash. A difference is
  posted as a cash adjustment linked to the reconciliation record.

## Accounting cycles

A group always has exactly one open cycle. An admin closes it by typing its
exact name and naming the next cycle. Closing, under the group lock:

1. writes one `cycle_member_balances` row per member (opening, every
   component of the formula and closing) and one `cycle_cash_snapshots` row;
   the `CHECK` constraints verify the equations;
2. marks the cycle `closed` (immutable from then on: nothing can be posted into
   it, and its snapshots cannot change);
3. opens the next cycle, whose opening balances are the previous closing
   balances (carry-forward);
4. moves items that are still pending or disputed into the new cycle and
   records that move in their event history;
5. writes an audit log entry.

Nothing is truncated or reset; old cycles stay queryable and exportable.
`verify_ledger_integrity` checks that every opening matches the previous close.

## Integrity checks

`verify_ledger_integrity(group)` (treasurers and admins, also on the admin
screen) runs:

| Check | Meaning |
|-------|---------|
| `balanced_transactions` | every posted transaction's entries sum to zero |
| `no_entries_for_open_items` | pending, rejected, cancelled and disputed items have no entries |
| `posted_have_entries` | every posted or reversed transaction has entries |
| `reversals_match` | each reversal exactly negates the transaction it reverses |
| `snapshots_match_ledger` | closed-cycle snapshots equal the figures recomputed from the ledger |
| `opening_matches_previous_close` | carry-forward is exact |
| `cash_never_negative` | the box balance is not negative |
| `ledger_sums_to_zero` | the whole ledger of the group sums to zero |

It also returns the global figures used in the identity above.

## Scenarios

The requirements list fifteen scenarios. Each one is a pgTAP test with the
figures derived by hand in comments.

| # | Scenario | Test file |
|---|----------|-----------|
| 1 | A member drinks coffee and pays exactly what they owe: balance 0.00 | `010_coffee_and_deposits` |
| 2 | A member pays more than they owe: the excess becomes a credit | `010_coffee_and_deposits` |
| 3 | Personal bean purchase: owes 6.00, buys 15.00 of beans, balance -9.00, box unchanged | `020_purchases` |
| 4 | Box-funded purchase: box 20.00, beans 15.00 from the box, box 5.00, nobody credited | `020_purchases` |
| 5 | One member pays another directly; confirmed by the recipient | `030_transfers` |
| 6 | A settlement is rejected, disputed and resolved | `030_transfers` |
| 7 | Reimbursement from the box: A bought 20.00 and drank 10.00; B deposits 10.00; the treasurer gives A 10.00; box -10.00, A settled | `040_reimbursements` |
| 8 | The same submission arrives twice: recorded once, the retry is a replay | `050_idempotency_and_concurrency` |
| 9 | Competing operations: two creditors owed 6.00 each, box holds 10.00, only one reimbursement succeeds | `050_idempotency_and_concurrency`, and with real parallel HTTP requests in `test/backend/backend_test.dart` |
| 10 | The coffee price changes in the middle of a cycle; earlier coffees keep their price | `010_coffee_and_deposits` |
| 11 | A cycle closes with everyone settled | `060_cycles` |
| 12 | A cycle closes with balances carried forward | `060_cycles` |
| 13 | An approved transaction is reversed; corrections are audited | `070_reversals_and_corrections` |
| 14 | A new member joins without affecting historical balances | `080_membership` |
| 15 | Members of different groups cannot see or change each other's data | `090_rls_isolation`, and over the public API in `test/backend/backend_test.dart` |

`110_ledger_invariants` replays a realistic mixed history (coffees, personal and
box purchases, a confirmed and an unconfirmed deposit, a transfer, a
reimbursement, a reconciliation shortfall and a balance adjustment) and checks
every member balance, the cash box, the overview figures, the global identity
and the identity after closing the cycle.

### Worked example (scenario 7)

| Step | A | B | Box |
|------|---|---|-----|
| A buys beans for 20.00 with personal money | -20.00 | 0.00 | 0.00 |
| A drinks 10.00 of coffee | -10.00 | 0.00 | 0.00 |
| B drinks 10.00 of coffee | -10.00 | 10.00 | 0.00 |
| B deposits 10.00 into the box (confirmed) | -10.00 | 0.00 | 10.00 |
| The treasurer reimburses A 10.00 from the box | 0.00 | 0.00 | 0.00 |

A reimbursement of 10.01 at the last step would be refused: the box only holds
10.00, and A is only owed 10.00.

## Settlement assistant

The settle-up screen suggests payments that bring members to zero. It works
on **projected** balances (confirmed balance plus everything already pending),
so money that is on its way is not suggested twice.

The algorithm is greedy and deterministic:

1. Reimbursements from the box go to the members who are owed the most, as far
   as the confirmed cash (minus pending box outflows and an optional reserve)
   allows.
2. Remaining debts are matched with remaining credits, largest first, as
   direct payments between members.
3. Debts that cannot be matched are suggested as deposits into the box.

Credits that neither the box nor the debtors can cover (the group has spent
more than it has collected so far) are listed as unsettled rather than hidden.

The result is a short, explainable plan. It is not guaranteed to use the
minimum possible number of payments, and the screen does not claim it is.
Former members with a non-zero balance are listed for an administrator instead
of being included in suggestions. Suggestions are only proposals: each one has
to be recorded and confirmed like any other transaction.
