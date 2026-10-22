# Moving from the prototype

Coffee Tracker 1.0 replaces the prototype and uses a new database. It does not
read from, write to or modify the prototype's Supabase project, and nothing is
imported automatically.

The prototype's source code was never part of this repository (before 1.0 it
only contained a `.gitignore`), so the old data model is not known here. The path below therefore carries over
**balances, not history**: each member starts the new system with the balance
they had in the old one, and the cash box starts with the money that is
physically in it. Detailed old history stays in the prototype (or in an
export of it) for reference.

> **Approval required.** Do not touch real records, old or new, until the
> group's administrator (and ideally the treasurer) has approved the figures
> in step 2. Do the whole procedure in a **staging** project first.

## 1. Freeze and export (read-only)

1. Agree on a cut-over moment (for example the first day of a month) and stop
   recording in the prototype at that moment.
2. Export, without changing anything in the old system:
   - every member's name, email and current balance (positive = owes,
     negative = is owed),
   - the expected cash in the box,
   - optionally the full transaction list, kept as an archive file.
3. Count the physical cash in the box.

## 2. Check the figures

Put the export in a spreadsheet and check:

- the balances add up to what the prototype shows as the group total;
- every amount is in cents (no rounding differences);
- members who left and still have a balance are listed separately; decide
  with the administrator whether they are settled outside the app or written
  off;
- the counted cash versus the expected cash, with an explanation for any
  difference.

Have the administrator sign off on this sheet. It is the reference for the
next steps.

## 3. Set up the new group

1. Create the group in Coffee Tracker 1.0 with the current coffee price and
   the group's time zone. The creator becomes administrator.
2. Name the first cycle, for example "Opening balances".
3. Invite every member (invitation link or code) and assign treasurer roles.
   Each member signs up with their own account; balances can only be assigned
   to people who have joined.

## 4. Record the opening position

Use the app's normal, audited operations. They are visible to the members and
appear in the audit log.

- **Members**: for each member with a non-zero balance, an administrator opens
  the member's page and uses **Adjust balance**:
  - *Charge* for a member who owes money, *Credit* for a member who is owed
    money, with the exact amount;
  - note: `Opening balance from the prototype, <date>, approved by <name>`.
- **Cash box**: a treasurer uses **Count the cash** and enters the counted
  amount, with a note such as `Opening cash from the prototype, <date>`. The
  difference to zero is recorded as a cash adjustment.

Each adjustment is posted against the `adjustments` account, so the ledger
stays balanced; see [ACCOUNTING.md](../accounting/ACCOUNTING.md).

## 5. Verify and close the opening cycle

1. Compare every member's balance on the **Group** page with the approved
   sheet, and the cash box with the counted amount.
2. Run **Administration → Ledger integrity**; all checks must pass.
3. Close the "Opening balances" cycle and open the first regular cycle. The
   imported balances become the opening balances of that cycle and the cycle
   report documents them permanently.
4. Export the balances CSV and keep it with the signed-off sheet.

If a figure is wrong after step 4, do not try to edit it: record a correcting
adjustment (or reverse the adjustment and record it again) with a note that
explains why.

## 6. After the cut-over

- Keep the prototype read-only (or archived) for as long as people may want
  to look up old entries. Do not delete its data as part of this migration.
- Announce the switch with the invitation link and the user guide.
