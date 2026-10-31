# Multimarché maintenance

There is no scheduled expiry of this app. Its continued operation depends on the GitHub, Vercel and Supabase accounts remaining available, usable limits, working integrations and an owner reviewing maintenance.

## Current ownership and services

- Source: https://github.com/arthurrylance/Multimarche
- Production: https://multimarche.vercel.app
- Vercel project: `prj_tAmKVt1tb5NnsXIbgUznfCY5E5t0`, team `team_sEvlSXA41t4JLoozQD9xnSDr`
- Supabase project: `vakkbgsooubqpmdekixr`, organization `hczfzvxlwjbtamefpnts`
- Supabase's organization was verified to be on the **Free** plan during setup. No plan upgrade or spending commitment was made.

## What is automated

- GitHub CI installs exact locked dependencies, runs application tests, and builds TypeScript/Vite on pushes and PRs.
- Availability checks run on Mondays at 07:17 UTC and can be run manually in Actions. They check the public website, its JavaScript entry and Supabase Auth health. They do not exercise a signed-in user's complete workflow, validate every database table, back up data or guarantee uptime.
- Dependabot opens weekly npm and GitHub Actions update PRs. Updates are not automatically merged or deployed. Review compatibility and passing CI before accepting them.
- GitHub may disable scheduled workflows on public repositories after 60 days without repository activity. Check that Actions remains enabled. GitHub's workflow notifications depend on your account notification settings.

Reference: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows

## What can stop it working

1. **Low activity on Supabase Free.** Supabase can pause free projects after low database activity over seven days. This is especially relevant during school holidays. Watch the owner's Supabase emails and resume a paused project promptly in the dashboard. Paid plans avoid inactivity pausing, but quotas, billing, outages and other failure modes still apply.
2. **Usage limits or account changes.** Traffic, database size, egress limits, an expired paid plan, an account suspension, or deleting/pausing a project can interrupt operation.
3. **Credentials/configuration.** Rotating the public key or moving the database requires updating the app's Supabase URL/key. Never expose service keys through `VITE_` variables.
4. **Breaking changes.** Dependency or provider changes can require code and migration updates. Keep the lockfile, tests, migration history and versioned source.
5. **Owner access.** Losing access to the service accounts can block maintenance. Retain account recovery methods privately.

Vercel's current production deployment is protected from normal age-based deployment-retention deletion. Older deployment history can be removed; retention is not a guarantee against deletion by an owner, account restrictions, quota problems or outages.

Provider references:

- https://supabase.com/docs/guides/platform/free-project-pausing
- https://supabase.com/docs/guides/platform/backups
- https://vercel.com/changelog/hobby-projects-now-retain-fewer-deployments-to-free-up-storage
- https://vercel.com/docs/plans

## Backups

Keep a private, restorable database backup at least weekly while the game is active and before applying migrations. Follow the current Supabase backup/export guide; include the application's public schema, its private accounting/admin/invitation tables, and the Auth data needed for account recovery. Test a restore into a separate non-production project.

Free-tier transaction exports from this app are **not** complete database backups. They verify financial history but do not restore users/password identities, markets, permissions, functions, invitations or settings.

Supabase recommends manual off-site exports for Free projects. Paid plans offer daily backups with plan-specific retention. No automatic full database backup has been configured here, because it requires owner-level credentials and a private storage destination. Never put database dumps, connection passwords, service keys or Auth password hashes into this public repository or public Actions artifacts.

## Deploying updates

The Vercel project was created with source uploads. A previous attempt to connect GitHub failed because the Vercel account lacked a GitHub Login Connection. No Git-push auto-deployment is assumed.

In the existing Vercel project's **Settings → Git**, connect `arthurrylance/Multimarche` with `main` as the production branch. Complete GitHub authorization in your Vercel account when requested. Preserve the existing project/domain and do not create a duplicate project. Verify a push produces a deployment of the expected commit before relying on automatic deployment.

Until that connection is made, source changes need a deliberate Vercel deployment. Keep Node 24, the Vite framework preset, `npm ci`, `npm run build` and output directory `dist`. A passing GitHub build alone does not prove that production has been updated.

## Update/recovery routine

1. Review failed health checks and provider quota/pause emails.
2. Back up privately before schema changes.
3. Review dependency-update PRs, run tests/build and check compatibility.
4. Apply new migrations exactly once, preserving existing data and accounting.
5. Deploy the intended commit; verify the public page and a signed-in account's market, balance, admin and notification flows.
6. Confirm the ledger verifies and total accounts still equal issued supply.

If the frontend breaks, roll back to a known compatible Vercel deployment. A frontend rollback does not undo database migrations. If the database is lost or corrupted, restore a verified private backup and test before reconnecting production. Preserve audit history rather than editing past transfers.

For dependable long-term use, an owner should budget for reliable database hosting and backups, keep update reviews active and periodically test recovery. This setup does not promise unattended maintenance forever.

## Order-book compatibility

Migration `20261031173324_matched_orderbook.sql` adds orders, fills, reservations and matching RPCs. At that upgrade, existing markets stayed AMM and the public creation APIs created CLOB markets. The later v6 API below explicitly supports both systems. Deploy a compatible frontend after this migration: old clients cannot use the AMM trade RPC on new order-book markets. Do not roll production back to a frontend predating this migration without considering that restriction.

Use `tests/orderbook.sql` for rollback-only database regression checks. Include orders, order events, fills, reserved wallet/share columns and the private financial ledger in private backups. Expiry is checked at execution time and cleaned up on authenticated reads/sync/placement; no cron or always-running server is required. A reservation may remain stored while nobody uses the app, but is released on the next sync and cannot execute past its deadline.

Migration `20261031192923_market_modes_disputes_avatars.sql` restores optional Automatic market creation through v6, adds dispute-aware resolution and saved avatar colours. Earlier public creation endpoints retain their order-book behaviour. A contested market has status `proposed`, `resolution_disputed=true` and no single `outcome`; keep a frontend that supports that state. Backups must include profile avatar colours and current resolution votes. Models cannot be converted after creation.

Grouped markets (`20261031194535_grouped_markets.sql`) add `public.market_groups` and group/option fields on existing markets. Include these in private backups. A group is organisational: each child remains its own financial market. Do not merge collateral, positions or results between children. Creation request IDs and hashes prevent duplicate groups after retries; preserve them with group metadata. The parent table is member-readable only when at least one child is readable, and cannot be written by app clients.
