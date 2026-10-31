# Multimarché

A private prediction game for friends, built with React, Vite, Supabase and Vercel. All balances are fictional credits with no cash value. The interface follows the familiar prediction-market layout under its own Multimarché branding.

## Implemented

- Invitation-only registration, username/password login and persistent Supabase Auth sessions.
- 1,000 starting credits, granted exactly once in the account-creation transaction.
- Create binary markets with categories, icons, trading deadlines and explicit resolution rules.
- Search, category filters, volume/newest/deadline sorting, watchlists and resolved/pending markets.
- Dynamic Yes/No prices, buy with a credit budget, sell owned shares, live quotes and slippage protection.
- Portfolios, credit ledger, group leaderboard, trade activity, comments and executed-price charts.
- Supabase Realtime subscriptions for markets, trades, wallets, positions, comments, votes and watchlists; 30-second refresh fallback.
- Two distinct members must agree on a result. The first proposal freezes trading; the second settles all wallets in one transaction. The original proposer can withdraw an unconfirmed proposal.
- Yes/No winning shares pay 1 credit each. A jointly confirmed Void pays 0.5 per outstanding share.
- Member-only row-level security. Clients cannot directly edit balances, trades, positions, markets, votes or payouts.
- Atomic, idempotent trades and serialized economy operations prevent concurrent overspending and duplicate settlements.

This is a functional small-group prediction game, not full Polymarket feature parity. It uses a binary LMSR market maker rather than a central limit order book. It does not include limit orders, multi-outcome markets, crypto wallets, real-money deposits/withdrawals, rewards, or external result oracles. The group itself confirms results. Both confirmers may hold shares; this is a trust-based game among friends.

## Connected backend

- Supabase project: `vakkbgsooubqpmdekixr` (Multimarche, Zurich region).
- Schema: [`supabase/schema.sql`](supabase/schema.sql), already applied to this project.
- Registration function: [`supabase/functions/register/index.ts`](supabase/functions/register/index.ts), already deployed as `register`.
- The public URL and publishable key have safe defaults in `src/db.ts`, so this repository works on Vercel without adding secrets. To connect a different project, set the two variables in `.env.example`.
- The Supabase service role key is used only inside the Edge Function through Supabase's runtime environment. Never add it to `VITE_` variables or the repository.

The schema is a bootstrap for a fresh project, not an idempotent upgrade script. Do not rerun it on the connected database. Future schema changes should be versioned as migrations. The `private` schema must remain absent from the exposed Data API schemas.

## Run locally

Use Node.js 24:

```sh
npm ci
npm run dev
```

```sh
npm test
npm run build
```

The logged-out screen contains explicitly labeled illustrative market examples. Real group markets and activity are returned only after login. New member accounts start with a blank market list until someone creates a market.

## Deploy to Vercel

Import `arthurrylance/Multimarche` in Vercel, select the `main` branch and keep the detected Vite preset. The root `vercel.json` sets `npm run build`, the `dist` output directory, SPA routing and response headers. No Vercel server or database secrets are required for the connected project. Enable automatic production deployments from `main`.

The GitHub Actions workflow runs pricing tests and a TypeScript/production build on pushes and pull requests. Browser verification and Vercel deployment must be checked separately.

## Invite friends

The initial secret invitation is supplied privately in the setup conversation, never committed. It allows 30 registrations and expires in 30 days. Ask each friend to choose **Join with invite**, a username containing 3–24 lowercase letters/numbers/underscores, and a password of at least 10 characters.

To issue another code as the project owner, generate a long random secret and run this parameterized SQL in the Supabase SQL editor, replacing the placeholder locally:

```sql
insert into private.invites(code_hash, remaining, expires_at)
values (
  encode(extensions.digest('REPLACE_WITH_A_LONG_RANDOM_SECRET', 'sha256'), 'hex'),
  10,
  now() + interval '7 days'
);
```

Only the digest is stored. Revoke a code by setting `remaining = 0` for its digest. Avoid sharing invitations publicly.

Accounts use synthetic private email identifiers derived from usernames, not real inboxes. There is no email password-reset flow. A project owner can reset a member's password in Supabase Authentication. Passwords themselves are managed and hashed by Supabase Auth.

## Market mechanics

For outstanding shares `qYes` and `qNo` and liquidity `b = 100`, the cost function is:

```text
C(qYes, qNo) = max(qYes, qNo) + b * ln(1 + exp(-abs(qYes - qNo) / b))
P(Yes) = 1 / (1 + exp((qNo - qYes) / b))
```

A buy costs the increase in `C`; a sell receives the decrease. The browser inverts the cost function to estimate shares for a credit budget. PostgreSQL recomputes the authoritative cost under a transaction lock. Buy orders enforce a maximum cost; sells enforce a minimum receipt. The UI uses a 0.5% slippage bound. Shares are limited to 10,000 per trade, with no short selling or credit borrowing. There are no fees.

The virtual market maker subsidizes liquidity; this is not a fixed-sum betting pool. Portfolio value marks outstanding shares at marginal prices, so selling a large position can receive less than that mark. Resolution pays exactly once and keeps settled positions visible for history, excluding them from current portfolio value.

The economy uses one transaction-level advisory lock. This makes correctness straightforward for a small friend group, but it is not intended for exchange-scale throughput. Member market creation is capped at 10 per day. The UI displays the latest 500 trades per market, 100 comments and 100 ledger entries; older records remain in the database.

## Verification

- `tests/math.test.mjs`: symmetric pricing, budget inversion, buy/sell reversibility, numeric stability.
- `tests/economy.sql`: rollback-only database tests for trade idempotency, changing odds, selling, overspending/overselling rejection, NaN rejection, wallet/position RLS, paused trading, independent confirmation, conflicting outcomes, one-time payout, ledger reconciliation and anonymous denial.
- `tests/live.mjs`: optional live test of registration/login, two-client Realtime, concurrency and settlement. Feed a **temporary** two-use invitation on stdin. It prints fixture IDs for owner cleanup and signs test clients out. It creates real temporary rows; do not run without arranging cleanup.

All application data is private to signed-in invited members. The GitHub repository is public; never commit user data, invitation secrets, passwords, service keys or database backups.
