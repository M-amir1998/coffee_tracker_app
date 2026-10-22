# Running costs

Coffee Tracker needs no server of its own: a Supabase project and static web
hosting are enough. The figures below are the providers' published prices as
known when this was written (2025 price lists). Prices change; check the
linked pages before budgeting.

## Expected usage

A busy group of 20 people drinking 3 coffees a day on 230 working days records
about 14,000 coffees a year. Each coffee is one transaction, two ledger entries
and one status event, roughly 1-2 KB including indexes, so about **15-30 MB
of database per group and year**. Realtime traffic and API calls are small
(a few requests per tap, plus refreshes). Receipts are optional uploads of up
to 5 MB each and are the only thing that can grow storage noticeably.

## Recommended setups

| Setup | Monthly cost | Suitable for |
|-------|--------------|--------------|
| Supabase Free + Cloudflare Pages Free | 0 | a pilot, or a few groups that accept the free-plan limits |
| Supabase Pro + Cloudflare Pages Free | about 25 USD | production use with backups and no pausing |

### Supabase ([pricing](https://supabase.com/pricing))

- **Free**: two projects, 500 MB database, 1 GB file storage, 50,000 monthly
  active users, limited egress. Free projects are **paused after a week
  without activity** (for example during holidays) and must be restored from
  the dashboard; there are no automatic backups you can download.
- **Pro**: about 25 USD per month per organization, including compute credit
  for one small project; 8 GB database, 100 GB storage, daily backups, no
  pausing. Usage above the included quotas is billed.
- Use a separate free project for staging.

### Web hosting ([Cloudflare Pages](https://pages.cloudflare.com/))

The free plan covers static sites with unlimited bandwidth and enough builds
for this project. Any static host works; it only has to serve `index.html` for
unknown paths.

### Email

Supabase's built-in email sender is for testing only. A transactional email
provider (Resend, Postmark, Amazon SES, Brevo, ...) has free or very low-cost
tiers that cover sign-up and password-reset emails of a few groups.

### App stores and signing (only if you publish native apps)

| Item | Cost |
|------|------|
| Google Play developer account | one-time 25 USD |
| Apple Developer Program (iOS, TestFlight, macOS notarization) | 99 USD per year |
| Windows code signing certificate (optional, avoids SmartScreen warnings) | roughly 100-400 USD per year, depending on the vendor and type |
| A Mac for iOS builds | existing hardware, or a cloud Mac / CI macOS minutes |

The web app works on every platform without any store fees; native builds are
optional.

### Continuous integration ([GitHub Actions](https://github.com/features/actions))

Free for public repositories. Private repositories get a monthly allowance of
free minutes; Linux jobs use it at the base rate, Windows jobs at 2x and macOS
jobs at 10x. A full CI run of this project uses several Linux jobs plus one
Windows job; the macOS job only runs when started manually.

### Domain

Optional; a domain name costs about 10-20 USD per year. Cloudflare Pages
provides a free `*.pages.dev` address.
