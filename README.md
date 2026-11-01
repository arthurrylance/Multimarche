# Multimarché

Private prediction markets for friends. React/Vite on Vercel, Supabase Auth/Postgres/Realtime, virtual credits only.

## Use

Open https://multimarche.vercel.app. The signed-out page only shows login and invite registration. No market previews, navigation or member data are shown. Join with an invitation, then log in with your username and password. New accounts receive 1,000 credits from treasury.

- **Moon / sun button:** switch dark mode; your choice is saved on this device.
- **Escape ×3:** redirect to the school’s itslearning CourseCards page; signed-in members also broadcast to other open app tabs.
- **Notifications bell:** ended markets, pending confirmations and recent outcomes; unread updates appear in a top banner on reload/home. Click the banner or its cross to acknowledge them; opening the bell marks visible items read. Clear notifications removes them from the menu persistently. Read and cleared state sync across devices.
- **Footer question mark:** market, order book, trading, settlement and counter help.
- **Account icon:** edit nickname, username or password. Changing username/password requires your current password. Nicknames are displayed to the group; usernames are used for login.
- **Create market:** choose Single bet or Several options. A group has one heading and 2–10 independent binary options, initially sharing a deadline, pricing model, confirmation count and optional counters. Each option counts toward the existing 10-markets-per-creator daily cap. Enter a binary question and explicit Yes/No meanings and a confirmation count (minimum/default 2). There are no app-level character limits on event questions, meanings or resolution notes. Choose a quick interval, tomorrow, a school-period end, a custom interval or a specific date/time. There is no emoji selection.
- **Profile pictures:** one of the eight supplied PNGs is initially assigned from each random account UUID. The reload button on Account saves a different random colour to `profiles.avatar_color`, consistently across devices/reloads and nickname changes. Presence, account, leaderboard, comments and admin users all use the same picture. Files are served as static assets, with no external image service.
- **Online avatars:** authenticated members see other recently active members. Server-owned, per-tab presence leases update with Supabase Realtime, heartbeat every 20 seconds and expire after 60 seconds. Hidden tabs go offline; closing one tab does not remove another device. Guests cannot read or publish presence.
- **Home → Your bets:** a countdown, estimated P/L at current prices, and net Yes/No settlement results for up to six active markets; View portfolio shows all positions.
- **History:** all settled markets, including archived ones, with confirmers, admin overrides, final holdings, spend, sales, payouts and net profit/loss.
- **Markets:** choose Yes/No, enter a credit amount and press Bet. Automatic matching handles prices and share quantities. A preview shows return and profit; unmatched amounts wait and can be cancelled. Cash out 25%, 50% or all of the available bet before trading closes. Advanced reveals manual prices, quantities, expiry and order-book depth. A winning share pays one credit. The selected number of distinct members must agree on normal results. A confirmed Void pays 0.5 credits per share.
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

Normal results require the market’s selected confirmation count (at least two accounts), with no current opposing votes. Members may vote Yes/No/Void independently, change their own vote, or withdraw before settlement. Conflicting votes mark the result disputed and block trading and payouts even if one side meets the count. Changing/withdrawing the last opposition can settle an otherwise sufficient consensus. Withdrawing all votes removes the proposal; the deadline and manual admin pause still apply. Cancelled book orders are not resurrected. Admins may override a dispute, with the override recorded. Admin overrides are labeled in the market and appear in the member-visible admin history. Settled markets cannot be paid a second time or edited. To undo an error after settlement, use a reasoned treasury allocation; historical payouts are not rewritten.

## Matched order book

At creation, choose **Automatic** (AMM, the default for quick/small-group bets) or **Order book** (matched member orders for longer bets). The model stays fixed for that market. Existing markets and positions are not converted. Order-book markets use a simple credit-budget betting panel. Existing AMM markets retain their positions, prices and settlement; their trading panel is marked **Automatic**. The creation UI uses `create_market_v6` with an explicit execution model. Earlier public creation API versions still create order-book markets for compatibility. There is no price-sensitivity setting on new markets.

The default **Bet** view takes only credits and an outcome. It selects the best executable offer for that outcome, otherwise its current marked price (50/50 if none exists). Credit amounts are converted into four-decimal share quantities using integer budget arithmetic and rounded down, so the reservation cannot exceed the entered stake. It uses a GTC order: available matches execute at that price or better and the remainder waits at the previewed price. It does not chase more expensive offers or silently change the reviewed price. Cancel the unmatched part in the market or Portfolio. Payout previews assume full matching; the panel explicitly identifies unmatched amounts. Cash out selects 25/50/100% of unreserved holdings and uses the best current bid, otherwise the marked price, with any remainder pending.

Manual controls remain under **Advanced**:

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
- Automatic AMM markets retain their funded `b × ln(2)` seed, automatic cost pricing and unused-reserve return to treasury.
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

Guest access is limited to a dedicated login/invite page. User help covers normal game use, limit/market orders, reservations, direction changes and payouts. Transactions and activity logs are collapsed by default.

Themes use black/white/neutral grays with green Yes and red No hover/focus states, with full-page backgrounds and a footer at the viewport bottom on short pages. Categories are hidden for now; stored category values remain for future restoration. Large buys (100+ credits or 25% of cash) require a review showing direction, amount, net position and possible results. A confirmed trade uses the reviewed parameters and an idempotent request ID.

Normal result notes are optional. One current vote per account and the selected confirmation count are enforced in PostgreSQL. Votes can be changed before settlement. Withdrawing a vote keeps trading paused while other confirmations remain. Admin overrides, role changes and credit actions stay recorded. Notification read markers are private to each account.

Weekly availability checks and Dependabot PRs are configured in GitHub. See [MAINTENANCE.md](MAINTENANCE.md) for hosting limitations, private backups, update reviews, recovery and the remaining GitHub-to-Vercel connection step. No paid upgrade or automatic full database backup was configured.

## Realised-loss joke prompt

Before a buy, the app obtains the caller’s server-calculated 24-hour realised P/L. Average acquisition cost is allocated proportionally to sold shares, and remaining basis is realised at settlement. Open purchases and unrealised price changes are not treated as losses. Effective bankroll is current cash plus open acquisition basis minus the period’s realised net result, including external funding. A cent-rounded net loss of at least 50% triggers the virtual-only satire prompt with “Yes” and “Hell yeah!”; either continues the ordinary trade review. A per-user session acknowledgement suppresses repeats until the realised result changes. This does not alter pricing, funds or normal large-bet confirmation.

`tests/economy-v6.sql` verifies nickname/admin authorization, timeouts and automatic expiry, legacy API guards, deleted/restored history, settlement during a timeout, realised-loss accounting, open-buy exclusion, presence ownership/multiple tabs/expiry and guest denial, entirely inside a rolled-back transaction.

Online avatar hover/focus cards include the most recent buy time (“Last bet … ago”) in italics, independently of the foreground-tab online signal. The activity RPC is member-only, aggregates complete history rather than a truncated trade feed, and excludes inactive accounts. Tab metadata uses a black-and-white favicon and no description. User help is limited to core market, order-book, payout, history, counter and notification behaviour.

Starred markets are pinned first in Markets, with the selected sort applied within starred and unstarred groups. There is no separate Watchlist navigation tab; saved stars remain intact.

Share prices use the same ◈ credit unit as balances (e.g. ◈0.73 per share), with no cent notation or balance conversion. Pricing and settlement amounts are unchanged.

Market creation has quick 15/30/40-minute, one-hour and calendar-tomorrow choices, a compact school-period grid with the supplied timetable, a school date selector and custom time/interval controls. All fixed times use Europe/Zurich regardless of device timezone. Past periods are disabled, and school dates default to the next weekday when today has ended or is a weekend (holiday calendars are not inferred). The chosen deadline is validated again at submission.

## Order-book verification

`tests/orderbook.sql` is a transaction-only fixture that ends with ROLLBACK. It checks funded mint/merge/direct matching, price/time priority, improvement, partial fills, atomic FOK failure, FAK remainder cancellation, reservation and idempotency guards, self-trade prevention, expiry, access controls, timeout/pause/proposal cleanup, settlement and audit conservation. Legacy SQL suites explicitly create legacy AMM fixtures through private helpers; public creation compatibility is tested in the order-book suite. Node tests check quote/depth arithmetic, exact budget conversion, simple directional predictions, weighted AMM quotes, reductions and flips, virtual borrowing, advanced price/expiry controls and captured confirmations. Authenticated browser trading still requires a member login; database fixtures do not create persistent test accounts or alter real bets.

## Market modes, disputes and saved pictures

Migration `20261031192923_market_modes_disputes_avatars.sql` adds explicit creation choices, immutable execution models, conflict-aware resolution and a member-only own-account avatar reroll RPC. Automatic markets use the original funded LMSR with b=400 and no price-sensitivity setting; they reserve treasury collateral, trade immediately and return unused reserves to treasury. Order-book markets retain the matched-player, no-treasury-seed economy.

`tests/market-modes.sql` uses only rollback fixtures. It checks both creation modes, automatic odds movement, funded book settlement, disagreement blocking, changed/withdrawn votes, consensus reconciliation, admin overrides, mode immutability, account-scoped persistent rerolls, guest denial and supply/audit conservation. Component tests cover the model picker, independent No votes, changing/withdrawing votes, notification opposition controls and saved picture refresh.

## Grouped markets

Choose **Several options** when creating a market. Enter the common question and 2–10 option labels; optional per-option Yes/No meanings override the generated defaults. Choose Automatic or Order book and the shared initial deadline, confirmations and counter settings. Each option is a complete independent binary market with its own collateral, prices, orders, positions, counter, votes and payout. Several can resolve Yes; percentages are not normalised to 100%, and there is no combined/parlay payout.

The home page renders one group card with option rows. Starring any option pins its group; filtering/search matches a relevant option while retaining visible sibling context. The detail page has sibling navigation and remounts the trading form when switching options. Portfolio, notifications, admin and history retain the full group-question/option title. Admin edits to a child question update its option label while preserving the group prefix and identity. Actions on one option do not change its siblings.

Migration `20261031194535_grouped_markets.sql` adds member-only group metadata and an atomic, idempotent creation RPC. It uses existing market creation functions and the existing economy lock. Insufficient treasury funding, invalid options or daily-limit failure cannot leave a partial group or partially seeded markets. Group metadata is invisible to ordinary members when all its children are hidden from history. No existing markets are regrouped.

`tests/grouped-markets.sql` rolls back all fixtures. It covers both models, repeated and conflicting request IDs, late reserve-funding failure, independent prices/counters/orders/disputes/results, several Yes payouts, admin label edits, model/group identity, hidden history and guest/timeout access, and exact financial conservation. Component/helper tests cover grouped creation and retries, option navigation, star/search/sort behaviour and independent percentages.

## Directional positions, starting likelihood and virtual borrowing

Creation uses a compact Automatic / Order book toggle and a wider two-column dialog. A 1–99% Yes likelihood slider defaults to 50%. Automatic uses a weighted LMSR prior with b=400 and a treasury-funded reserve sufficient for either outcome. Order-book priors are explicitly labelled starting estimates, never synthetic liquidity. Group children inherit the slider value; the group API also accepts an individual option probability. Existing market priors remain 50%.

The prediction panel only asks for direction and credit amount. Opposite purchases reduce existing units first and cross zero before opening the new side. AMM reductions use the complementary LMSR identity; order-book reductions execute real sales of opposite units, preserving maker price/time priority and actual trade records. There is one positive side per user per unresolved market, enforced by deferred database checks. The preview distinguishes directional amount from actual cash used/returned and includes both outcome net results. Historical settled holdings remain unchanged. Existing pending orders are preserved and acquire netting reservations only if needed when matched. A new prediction replaces the caller’s other pending orders in the same market.

5× and 10× are **virtual borrowing requiring only the initial stake**. Stake S produces exposure L×S; treasury lends (L−1)×S. Principal is repaid when the position is flat with no pending orders, or when its market resolves. Losses may leave the wallet negative. For example, an account with 10 credits can risk 100 using 10× and end at −90 after losing. Normal trading cannot overdraw a wallet; only repayment of a recorded active loan may do so. Treasury and market reserves remain funded, and signed account balances still sum to the fixed issued supply. Negative balances are receivables, not spendable funds. One active leveraged market per user is enforced in PostgreSQL. New borrowing must start flat and requires a positive funded stake. Repayment cancels pending buy reservations if necessary. The legacy internal `loan_collateral` column now records debt only; `borrowed_balance` is its explicit read alias. Equity subtracts outstanding borrowing, but cash availability does not reserve it. Every draw and repayment is audited, and client ledger verification validates repayments against prior borrowing from the same creditor.

Admin → Credits → Reset all money requires an acknowledgement and exact **RESET ALL** confirmation. It cancels open orders, Voids unresolved markets, repays borrowing, archives existing markets and redistributes 1,000 credits to each active account (zero to removed accounts). It preserves accounts, history, the audit and total supply. New-round creation limits and realised-loss warnings exclude prior testing rounds. The shared emergency signal has a global two-minute cooldown; the person using Escape still leaves immediately.

`tests/net-predictions.sql` and `tests/net-predictions-edge.sql` are rollback-only integration fixtures covering priors, net AMM/book reductions and flips, direct/mint/merge matches, loan wins/losses/voids/cancellation/partial fills, idempotency, FOK failure, no-fill FAK repayment, one-loan guards, permissions, cooldown, reset, financial audit and exact conservation. No live balances were reset to test this feature.


## Simple betting panel

The default panel is Yes/No, Amount, return if correct and profit. Raw positions, borrowing controls, both-outcome results, manual prices/expiry and book depth are under Advanced. Positions are shown as Backing Yes/No and rounded credit payouts. Opening Advanced does not switch from automatic to manual pricing; an explicit checkbox enables a limit price. Leverage remains visibly marked on the submit button when Advanced is collapsed. Leveraged returns deduct principal so borrowed funds are not advertised as winnings. Existing-position previews retain netting and total market P/L. Pending orders appear only when present.

`tests/borrowed-leverage.sql` ends in ROLLBACK and covers stake-only borrowing, negative settlements, replay/one-loan guards, failed FOK and cancellation, top-ups, negative-account resets and exact supply conservation. Component tests check the compact default panel, hidden/rounded positions, no implicit repricing and captured loan confirmations.


## Appearance and cancellation controls

Account → Display settings includes Light/Dark and Performance mode. Preferences are stored on the current device and synchronize between its tabs. Performance mode disables animations/transitions and smooth scrolling; operating-system reduced motion always takes precedence. Motion uses short, finite CSS opacity/transform effects with fine-pointer-only card hover movement. Rendering and financial actions never wait for animation events. The cancel label slides out without changing page width, appears on keyboard focus, and leaves neighboring Yes/No controls clickable. Touch uses a normal 44px tap target.

The X next to Yes/No clears an unsubmitted draft. With placed bets it opens a confirmation: pending orders are cancelled, and an active position is closed at current prices. AMM exits are protected by a minimum return and may repay borrowing; book exits are funded closing orders that still require a real buyer. Closed markets/timeouts only permit cancellation of unmatched orders. The RPC uses the existing trading core, owns-account checks, an economy lock and an idempotent receipt. No trade history is deleted. `tests/cancel-prediction.sql` rolls back its cancellation/repayment/matching/access/conservation fixtures; component tests cover confirmation and draft-only behavior. Appearance tests cover persistence, tab sync, blocked storage and device reduced-motion changes.


## Small-credit games

The footer Games button opens Blackjack, Roulette and Plinko using the existing theme and performance preference. Stakes are whole credits from 1 to 5; each member can wager at most 100 per Europe/Zurich calendar day and economy round. Only available owned credits may be wagered; outstanding borrowing is excluded. Games can win or lose credits. No issued supply is added: stakes, payout reserves and returns transfer existing credits through the immutable ledger.

Blackjack uses a fresh cryptographically shuffled 52-card deck per hand, flexible Aces, dealer stand on all 17s, 1:1 ordinary wins, 3:2 two-card naturals and stake refunds on pushes. Dealer naturals are checked immediately; a hit to 21 automatically stands. Hit/Stand only: no split, double or insurance. Dealer hole cards and the remaining deck stay in a private table. One active hand per member survives reloads; action versions prevent two tabs applying the same turn twice.

Roulette uses a single-zero European wheel with Red/Black and Odd/Even bets paying 1:1. Zero loses these bets. Plinko makes eight independent 50/50 server-side deflections; the nine visible return multipliers are 8, 3, 1.5, 0.7, 0.4, 0.7, 1.5, 3, 8 (expected return 99.375%). Returns include the stake. Game randomness uses pgcrypto bytes with unbiased rejection sampling, never browser randomness.

Each round reserves its maximum possible payout before play. Private idempotent request receipts prevent duplicate charges/draws/payouts; only validated own-account RPCs mutate rounds. Deferred constraints reconcile each active escrow and the existing total supply. A future admin economy reset refunds unfinished blackjack hands before collecting wallets; final rounds and ledger history remain. Timeouts prevent play while allowing state/history reads. Animation completion is never required for settlement or controls; roulette has a short CSS spin and plinko uses a result-derived SVG path disabled by performance/reduced-motion settings.

`tests/games.sql` is rollback-only and verifies hidden cards, scoring, ownership, stale/repeated actions, roulette/plinko outcomes and payouts, stake/daily limits, reserve failures, reset and conservation. Component/helper tests cover resumed hands, guarded starts, retry nonces, stake/timeout/budget restrictions, animation-independent play and result/visual mappings. All visual preview data is synthetic and separate from production accounts.

The expanded full-reset regression is an owner-run staging check. `tests/games-refund.sql` provides a narrower rollback-only refund/duplicate-finish/conservation test for a single synthetic hand without invoking the economy reset. Browser visual verification of the protected synthetic preview requires an approved temporary preview access link.
