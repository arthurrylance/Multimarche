# Multimarché

Private prediction markets for friends. React/Vite on Vercel, Supabase Auth/Postgres/Realtime, virtual credits only.

## Use

Open https://multimarche.vercel.app. The signed-out page only shows login and invite registration. No market previews, navigation or member data are shown. Join with an invitation, then log in with your username and password. New accounts receive 1,000 credits from treasury.

- **Moon / sun button:** switch dark mode; your choice is saved on this device.
- **Escape ×3:** redirect to the school’s itslearning CourseCards page; signed-in members also broadcast to other open app tabs.
- **Notifications bell:** ended markets, pending confirmations and recent outcomes; unread updates appear in a top banner on reload/home. Click the banner or its cross to acknowledge them; opening the bell marks visible items read. Clear notifications removes them from the menu persistently. Read and cleared state sync across devices.
- **Footer question mark:** market, order book, trading, settlement and counter help.
- **Account icon:** edit nickname, username or password. Changing username/password requires your current password. Nicknames are displayed to the group; usernames are used for login.
- **Create market:** enter a binary question and explicit Yes/No meanings and a confirmation count (minimum/default 2). There are no app-level character limits on event questions, meanings or resolution notes. Choose a quick interval, tomorrow, a school-period end, a custom interval or a specific date/time. There is no emoji selection.
- **Online avatars:** authenticated members see other recently active members. Server-owned, per-tab presence leases update with Supabase Realtime, heartbeat every 20 seconds and expire after 60 seconds. Hidden tabs go offline; closing one tab does not remove another device. Guests cannot read or publish presence.
- **Home → Your bets:** a countdown, estimated P/L at current prices, and net Yes/No settlement results for up to six active markets; View portfolio shows all positions.
- **History:** all settled markets, including archived ones, with confirmers, admin overrides, final holdings, spend, sales, payouts and net profit/loss.
- **Markets:** buy Yes/No shares, or sell shares you own before trading closes. A winning share pays one credit. The selected number of distinct members must agree on normal results. A confirmed Void pays 0.5 credits per share.
- **Admin → Transactions:** inspect transfers, verify the hash chain and supply, export records, and view recorded actions.

The existing `arylance` account has admin permissions, managed in a private database table. There is no shared admin password or user-editable role claim.

## Admin

The **Admin** page opens with all users and current credit balances. Its submenus can:

- Delete a member’s login and group access after confirmation. The caller cannot delete themselves. Financial records, profile identity and votes are retained; usernames stay reserved. Removed accounts are hidden from the leaderboard. Auth soft-deletion is irreversible; a failed Auth cleanup can be retried under Show removed users. Existing JWTs are denied immediately by the active-membership check.
- Change any active member’s nickname. User cards provide search, keyboard/hover statistics and quick nickname, credit, timeout, role and deletion actions.
- Apply 5/15/60-minute, one-day or one-week timeouts, and unfreeze early. Timeouts block trades, creation, results, counters and comments on the server while browsing and automatic payouts remain available. They expire automatically. Admins must be demoted before a timeout; self-timeouts and promotion during a timeout are blocked.
- Delete settled events from history and restore them later. Market content is hidden from ordinary members, while financial records, supply and payouts are preserved.
- Grant/revoke admin access, with a guard that preserves at least one active admin.
- Transfer existing treasury credits to a member, with a recorded reason.
- Explicitly issue new credits into treasury. This increases total supply, requires a separate acknowledgement, and creates an issuance record.
- Pause/resume trading, edit market questions/rules/deadlines, and resolve or void a market immediately with a recorded admin override.
- Archive resolved markets without deleting their transaction history.
- Generate private invitation codes with 1–100 uses, expiring after 30 days.

Normal results require the market’s selected confirmation count (at least two accounts). Admin overrides are labeled in the market and appear in the member-visible admin history. Settled markets cannot be paid a second time or edited. To undo an error after settlement, use a reasoned treasury allocation; historical payouts are not rewritten.

## Matched order book

New markets use a virtual-credit central limit order book. Existing markets retain their original AMM positions, prices and settlement; their trading panel is marked **Legacy AMM**. All public creation API versions create order-book markets. There is no price-sensitivity setting on new markets.

- **Limit:** buy at a maximum price or sell at a minimum price. The remainder rests until cancelled/market close (GTC), or an earlier chosen expiry (GTD).
- **Market:** execute immediately using opposing liquidity with a 0.5% protection limit beyond the quoted worst price. FOK fills the entire quantity atomically or rolls everything back. Optional FAK fills what is available and cancels the rest.
- **Matching:** best effective price, then FIFO sequence; execution uses the resting order’s price. Same-outcome buys/sells transfer shares directly. Complementary Yes/No buys mint a fully collateralised pair, at prices summing to one credit. Complementary sells merge a pair and release its one-credit collateral.
- **Reservations:** buys reserve limit price × quantity; sells reserve existing shares. Partial fills reduce holds, price improvement releases excess cash, and cancellation releases the unfilled remainder. Available cash excludes reservations; portfolio equity includes total cash. A global transaction lock and deferred reconciliation prevent double spending/pledging, including legacy AMM buys.
- **Protection:** no naked selling, self-trading or fees. A crossing self-order cancels the resting order instead of generating a fill. An idempotent request ID makes placement retries safe. Prices and quantities use 0.0001 increments; price is strictly between zero and one, quantity at most 1,000,000, and a user can hold at most 100 open orders.
- **Display:** the midpoint is used when the spread is at most 0.10; otherwise the last execution is shown. Before either exists, the interface shows no price. Public aggregated depth includes complementary liquidity; executable quotes exclude the caller’s own orders.

An order needs a counterparty, who can have placed their order earlier. With five people, fills may wait and spreads may be wide. Portfolio marks are estimates, not guaranteed sale proceeds. The database computes authoritative matching and amounts with exact Postgres numerics; browser quotes are estimates.

Open orders cancel on proposal/resolution, pause, archive, deadline edits, timeout or account removal. Expired orders cannot execute. Cleanup releases expired reservations when members read/sync the book or place orders; the app also polls the book every five seconds. Realtime market book versions notify members even though individual order records are private. Open orders can be cancelled in the market or Portfolio.

This implements the core binary order-book mechanics in Supabase. It does not connect to Polymarket, wallets, crypto or an external exchange.

## Funded credits and audit records

The upgrade establishes an explicit **100,000-credit opening supply**. It preserves the existing wallets and allocates funded reserves to existing markets. The remaining credits are held in treasury.

- Starting balances and admin top-ups transfer from treasury.
- Order-book markets receive **no treasury seed**. Matched complete pairs fund one credit of collateral, which is fully paid to holders on settlement. Direct resales leave collateral unchanged; merged pairs release it to the two sellers. The treasury takes no trading surplus.
- Legacy AMM markets retain their funded `b × ln(2)` seed, automatic cost pricing and unused-reserve return to treasury.
- Outstanding payouts are fully funded; unfilled orders create no shares.
- Deferred database constraints verify that all user balances and reserves sum to the issued supply, and that mirrored wallets agree with the accounting ledger.
- Only explicit genesis and admin issuance increase supply. Buying, selling, allocating and settling do not create credits.

Each financial operation appends a SHA-256-linked record. Updates and deletes of audit/admin history are rejected. Application clients cannot write balances, roles, reserves, trades, results or audit history directly. The exported record chain can be replayed independently with `src/audit.mjs`, which checks hashes, funded transfers, ordering and total supply using exact integer arithmetic.

The upgrade's genesis records opening account balances and a checksum of earlier credit history. This is a database transaction ledger, not a public blockchain. Supabase project owners retain database control. Wallet connection, public-chain publication and Solidity tooling have been removed. Historical migration definitions are retained so fresh installations still apply in order; the latest migration removes the wallet configuration RPC.

## Live counters and emergency redirect

Enable **Track a live count** when creating a market, with a label such as “Etcetera count”. Creators and admins can also add a counter to existing unresolved markets. Members can increment while trading is open; admins can correct counts while unresolved. Each change has an actor, timestamp and idempotent request ID. Counts never go negative, change prices, or resolve a market automatically.

Triple Escape within 1.5 seconds hides the app immediately and navigates to `https://nordangliaeducation.itslearning.com/CourseCards`. Signed-in members send an authenticated, rate-limited signal before leaving, using a keepalive request with a 900ms navigation fallback. Realtime and a 10-second fallback poll redirect other open app tabs, including signed-out visitors. Same-browser tabs also receive a local storage signal. Guests cannot broadcast globally.

Known devices catch up on a missed signal after reconnecting. A brand-new browser only acts on a signal from the previous two minutes, so an old emergency does not block future visits. Acknowledged versions are stored locally to avoid redirect loops. Browsers that are closed and other applications cannot be controlled; delivery depends on connectivity.

## Development and deployment

Use Node.js 24:

```sh
npm ci
npm run dev
npm test
npm run build
```

The connected Supabase project is `vakkbgsooubqpmdekixr`. Its public URL and publishable key are safe client defaults in `src/db.ts`; `.env.example` allows overriding them. Service keys are used only inside Supabase Edge Functions and are never sent to the browser.

- `supabase/schema.sql` is the original bootstrap, already applied.
- `supabase/migrations/` contains the treasury/profile/admin/audit upgrades, already applied to the connected project.
- `supabase/functions/register/` implements invited registration.
- `supabase/functions/delete-member/` verifies the caller’s JWT, invokes the admin-only deletion transaction using that JWT, then soft-deletes the Auth identity with the server-only service key. Membership is revoked first; partial cleanup cannot leave game access active.
- `supabase/functions/account/` verifies the caller's JWT, reauthenticates sensitive changes and updates only that user's Auth identity. A database trigger keeps the profile and login username synchronized in the same Auth transaction.
- `vercel.json` builds the Vite app into `dist` and configures SPA routing and headers.

For a fresh Supabase project, apply the original bootstrap and all upgrade migrations in filename order, deploy the three functions, issue an invitation, and grant the intended owner an admin role via the SQL editor:

```sql
insert into private.admins(user_id)
select id from public.profiles where username = 'YOUR_OWNER_USERNAME';
```

Keep the `private` schema out of the exposed Data API schemas. Do not rerun bootstrap/migrations against a database where they have already been applied. Password recovery for synthetic username-based email identities remains a project-owner operation in Supabase Authentication.

Source is saved in https://github.com/arthurrylance/Multimarche. Vercel currently deploys source uploads from this workflow. Automatic Git-triggered deploys require connecting GitHub in the Vercel account; the missing GitHub Login Connection previously blocked linking. Do not assume a GitHub push alone deploys this project.

## Verification and limits

- Pricing tests cover symmetric cost, budget inversion, reversibility and numeric stability.
- Audit tests cover exact balances, explicit issuance, tampering and unfunded transfers.
- Emergency tests exercise the actual redirect hook: authenticated keepalive broadcast, local guest navigation, and remote signal acknowledgement.
- Account endpoint tests check JWT validation, user ownership, current-password requirements, validation and local-only reauthentication-session revocation.
- `tests/economy.sql`, `tests/economy-v2.sql`, `tests/economy-v3.sql`, `tests/economy-v4.sql`, and `tests/economy-v5.sql` are owner-run rollback-only SQL tests. The v2 suite checks funded reserves, conservation constraints, role spoofing, profile sync, audited admin operations, and one-time settlement.

The v4 SQL suite checks counter access, idempotency, conservation and the shared emergency signal inside a rolled-back transaction, without redirecting live users. The v5 suite checks stale-token denial, removal guards, preserved credit history, complete historical P/L and outcomes, and private persistent notification clearing. Component tests exercise read, clear, reload and failed acknowledgement behaviour. Private account UI flows are covered by service-level checks; public production UI is checked separately in a browser.

This remains a small-group virtual game, not full Polymarket parity: no crypto deposits/withdrawals, real-money value, automated oracle or multi-outcome markets. The UI displays the latest 500 trades, 100 comments and 100 personal ledger entries. Complete post-upgrade financial records can be exported from Admin → Transactions.

## Current interface and maintenance

Guest access is limited to a dedicated login/invite page. User help covers normal game use, limit/market orders, reservations, selling and payouts. Transactions and activity logs are collapsed by default.

Themes use black/white/neutral grays with green Yes and red No hover/focus states, with full-page backgrounds and a footer at the viewport bottom on short pages. Categories are hidden for now; stored category values remain for future restoration. Large buys (100+ credits or 25% of cash) require a review showing cost, slippage, shares and potential payout. A confirmed trade uses the reviewed parameters and an idempotent request ID.

Normal result notes are optional. Voting once per account and the selected confirmation count are enforced in PostgreSQL. Withdrawing a vote keeps trading paused while other confirmations remain. Admin overrides, role changes and credit actions stay recorded. Notification read markers are private to each account.

Weekly availability checks and Dependabot PRs are configured in GitHub. See [MAINTENANCE.md](MAINTENANCE.md) for hosting limitations, private backups, update reviews, recovery and the remaining GitHub-to-Vercel connection step. No paid upgrade or automatic full database backup was configured.

## Realised-loss joke prompt

Before a buy, the app obtains the caller’s server-calculated 24-hour realised P/L. Average acquisition cost is allocated proportionally to sold shares, and remaining basis is realised at settlement. Open purchases and unrealised price changes are not treated as losses. Effective bankroll is current cash plus open acquisition basis minus the period’s realised net result, including external funding. A cent-rounded net loss of at least 50% triggers the virtual-only satire prompt with “Yes” and “Hell yeah!”; either continues the ordinary trade review. A per-user session acknowledgement suppresses repeats until the realised result changes. This does not alter pricing, funds or normal large-bet confirmation.

`tests/economy-v6.sql` verifies nickname/admin authorization, timeouts and automatic expiry, legacy API guards, deleted/restored history, settlement during a timeout, realised-loss accounting, open-buy exclusion, presence ownership/multiple tabs/expiry and guest denial, entirely inside a rolled-back transaction.

Online avatar hover/focus cards include the most recent buy time (“Last bet … ago”) in italics, independently of the foreground-tab online signal. The activity RPC is member-only, aggregates complete history rather than a truncated trade feed, and excludes inactive accounts. Tab metadata uses a black-and-white favicon and no description. User help is limited to core market, order-book, payout, history, counter and notification behaviour.

Starred markets are pinned first in Markets, with the selected sort applied within starred and unstarred groups. There is no separate Watchlist navigation tab; saved stars remain intact.

Share prices use the same ◈ credit unit as balances (e.g. ◈0.73 per share), with no cent notation or balance conversion. Pricing and settlement amounts are unchanged.

Market creation has quick 15/30/40-minute, one-hour and calendar-tomorrow choices, a compact school-period grid with the supplied timetable, a school date selector and custom time/interval controls. All fixed times use Europe/Zurich regardless of device timezone. Past periods are disabled, and school dates default to the next weekday when today has ended or is a weekend (holiday calendars are not inferred). The chosen deadline is validated again at submission.

## Order-book verification

`tests/orderbook.sql` is a transaction-only fixture that ends with ROLLBACK. It checks funded mint/merge/direct matching, price/time priority, improvement, partial fills, atomic FOK failure, FAK remainder cancellation, reservation and idempotency guards, self-trade prevention, expiry, access controls, timeout/pause/proposal cleanup, settlement and audit conservation. Legacy SQL suites explicitly create legacy AMM fixtures through private helpers; public creation compatibility is tested in the order-book suite. Node tests check quote/depth arithmetic and trading controls. Authenticated browser trading still requires a member login; database fixtures do not create persistent test accounts or alter real bets.
