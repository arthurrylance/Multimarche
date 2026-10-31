# Multimarché

Private prediction markets for friends. React/Vite on Vercel, Supabase Auth/Postgres/Realtime, virtual credits only.

## Use

Open https://multimarche.vercel.app. Join with an invitation, then log in with your username and password. New accounts receive 1,000 credits from treasury.

- **Moon / sun button:** switch dark mode; your choice is saved on this device.
- **Account icon:** edit nickname, username or password. Changing username/password requires your current password. Nicknames are displayed to the group; usernames are used for login.
- **Create market:** enter a binary question and resolution rules. Close in 15/40/60/120 minutes, 24 hours, a custom number of minutes, or at a specific date/time. There is no emoji selection.
- **Markets:** buy Yes/No shares, or sell shares you own before trading closes. A winning share pays one credit. Two distinct members must confirm normal results. A jointly confirmed Void pays 0.5 credits per share.
- **Transactions:** inspect transfers, verify the hash chain and supply, export records, view admin actions, and check public-chain publication status.

The existing `arylance` account has admin permissions, managed in a private database table. There is no shared admin password or user-editable role claim.

## Admin

The **Admin** page can:

- Transfer existing treasury credits to a member, with a recorded reason.
- Explicitly issue new credits into treasury. This increases total supply, requires a separate acknowledgement, and creates an issuance record.
- Pause/resume trading, edit market questions/rules/deadlines, and resolve or void a market immediately with a recorded admin override.
- Archive resolved markets without deleting their transaction history.
- Generate private invitation codes with 1–100 uses, expiring after 30 days.

Normal results still require two accounts. Admin overrides are labeled in the market and appear in the member-visible admin history. Settled markets cannot be paid a second time or edited. To undo an error after settlement, use a reasoned treasury allocation; historical payouts are not rewritten.

## Five-person markets

There is always a market maker, so another person does not need to be online to take the other side. New markets default to liquidity `b = 400`, producing more gradual price changes for a small group. The creation form also offers `200` and `100` for greater sensitivity. Existing markets retain their original liquidity, prices, shares and balances.

Binary LMSR pricing:

```text
C(y,n,b) = max(y,n) + b × ln(1 + exp(-abs(y-n)/b))
P(Yes) = 1 / (1 + exp((n-y)/b))
```

Buys pay the increase in cost; sells receive the decrease. The browser estimates shares for a credit budget, while Postgres recomputes the exact authoritative price. Transactions enforce a 0.5% slippage bound, owned-share limits and available funds. A single transaction lock serializes the small group's economy.

Prices in a five-person group describe those participants' trading, not a reliable population forecast. Portfolio values use marginal prices; selling a large position can receive less than that mark.

## Funded credits and audit records

The upgrade establishes an explicit **100,000-credit opening supply**. It preserves the existing wallets and allocates funded reserves to existing markets. The remaining credits are held in treasury.

- Starting balances and admin top-ups transfer from treasury.
- Each new market reserves `b × ln(2)` credits from treasury. Buy payments join its reserve; sales and settlement payments leave it.
- Outstanding payouts are fully funded, even if only one person trades.
- Unused market reserves return to treasury after settlement.
- Deferred database constraints verify that all user balances and reserves sum to the issued supply, and that mirrored wallets agree with the accounting ledger.
- Only explicit genesis and admin issuance increase supply. Buying, selling, allocating and settling do not create credits.

Each financial operation appends a SHA-256-linked record. Updates and deletes of audit/admin history are rejected. Application clients cannot write balances, roles, reserves, trades, results or audit history directly. The exported record chain can be replayed independently with `src/audit.mjs`, which checks hashes, funded transfers, ordering and total supply using exact integer arithmetic.

The upgrade's genesis records opening account balances and a checksum of earlier credit history. It does not pretend that pre-upgrade activity was already on a blockchain. Supabase project owners retain database control; independent public-chain publication makes changes to previously published history detectable.

## Sepolia setup — one wallet step remains

**Blockchain publication is not active until an admin deploys/connects the contract and publishes records.** No deployed address or confirmation is fabricated. Trading and balances remain authoritative in Supabase; the Solidity contract records public audit transactions, not an on-chain currency or betting engine.

1. Use a separate browser test wallet, such as MetaMask, with Sepolia test ETH. Faucet references: https://ethereum.org/developers/docs/networks/#sepolia.
2. Sign in as an admin and open **Transactions**.
3. Choose **Connect wallet & deploy on Sepolia** and approve the wallet transaction. The app switches to chain ID `11155111` and refuses other public networks.
4. Choose **Publish next 10 records**. Each batch is independently verified, signed in the deployment wallet, and marked published only after confirmation.
5. Repeat as new records accumulate. Other members can inspect the contract on Sepolia Etherscan and compare its confirmed hash/height with the local ledger.

Only the deployment wallet can append to the contract. A partial setup can be recovered by entering the confirmed contract address and deployment transaction; the app checks the owner, version and receipt. No wallet private key is requested or stored. The only transaction fees are test-network gas; no real-value tokens are used.

Public payloads include hashed account/market identifiers, amounts, fixed operation types, and supply changes. Usernames, nicknames, school questions, resolution evidence and free-form admin notes are not published. Publishing is manual; there is no automatic relayer holding a server wallet key. Unpublished records are clearly labeled.

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
- `supabase/functions/account/` verifies the caller's JWT, reauthenticates sensitive changes and updates only that user's Auth identity. A database trigger keeps the profile and login username synchronized in the same Auth transaction.
- `contracts/MultimarcheAudit.sol` is the public testnet audit contract; `npm run compile:contract` regenerates its checked-in ABI/bytecode.
- `vercel.json` builds the Vite app into `dist` and configures SPA routing and headers.

For a fresh Supabase project, apply the original bootstrap and both upgrade migrations in order, deploy the two functions, issue an invitation, and grant the intended owner an admin role via the SQL editor:

```sql
insert into private.admins(user_id)
select id from public.profiles where username = 'YOUR_OWNER_USERNAME';
```

Keep the `private` schema out of the exposed Data API schemas. Do not rerun bootstrap/migrations against a database where they have already been applied. Password recovery for synthetic username-based email identities remains a project-owner operation in Supabase Authentication.

Source is saved in https://github.com/arthurrylance/Multimarche. Vercel currently deploys source uploads from this workflow. Automatic Git-triggered deploys require connecting GitHub in the Vercel account; the missing GitHub Login Connection previously blocked linking. Do not assume a GitHub push alone deploys this project.

## Verification and limits

- Pricing tests cover symmetric cost, budget inversion, reversibility and numeric stability.
- Audit tests cover exact balances, explicit issuance, tampering and unfunded transfers.
- Contract tests execute compiled Solidity in a local EVM, checking owner authorization, sequential append, payload hashes, replay rejection and historical events.
- Account endpoint tests check JWT validation, user ownership, current-password requirements, validation and local-only reauthentication-session revocation.
- `tests/economy.sql` and `tests/economy-v2.sql` are owner-run rollback-only SQL tests. The latter checks funded reserves, conservation constraints, role spoofing, profile sync, audited admin operations, and one-time settlement.

Tests do not imply that a public Sepolia contract has been deployed or funded. Browser preview infrastructure has been unavailable in this workspace; production HTTP/assets and service-level checks are separate from visual browser verification.

This remains a small-group virtual game, not full Polymarket parity: no central limit order book, limit orders, crypto deposits/withdrawals, real-money value, automated oracle or multi-outcome markets. The UI displays the latest 500 trades, 100 comments and 100 personal ledger entries. Complete post-upgrade financial records can be exported from Transactions.
