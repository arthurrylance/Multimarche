# Multimarché maintenance

There is no scheduled expiry of this app. Its continued operation depends on the GitHub, Vercel and Supabase accounts remaining available, usable limits, working integrations and an owner reviewing maintenance.

## Current ownership and services

- Source: https://github.com/arthurrylance/Multimarche
- Production: https://multimarche.vercel.app
- Vercel project: `prj_tAmKVt1tb5NnsXIbgUznfCY5E5t0`, team `team_sEvlSXA41t4JLoozQD9xnSDr`
- Supabase project: `vakkbgsooubqpmdekixr`, organization `hczfzvxlwjbtamefpnts`
- Supabase's organization was verified to be on the **Free** plan during setup. No plan upgrade or spending commitment was made.

## What is automated

- GitHub CI installs exact locked dependencies, compiles/tests the audit contract, runs application tests, and builds TypeScript/Vite on pushes and PRs.
- Availability checks run on Mondays at 07:17 UTC and can be run manually in Actions. They check the public website, its JavaScript entry and Supabase Auth health. They do not exercise a signed-in user's complete workflow, validate every database table, back up data or guarantee uptime.
- Dependabot opens weekly npm and GitHub Actions update PRs. Updates are not automatically merged or deployed. Review compatibility and passing CI before accepting them.
- GitHub may disable scheduled workflows on public repositories after 60 days without repository activity. Check that Actions remains enabled. GitHub's workflow notifications depend on your account notification settings.

Reference: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows

## What can stop it working

1. **Low activity on Supabase Free.** Supabase can pause free projects after low database activity over seven days. This is especially relevant during school holidays. Watch the owner's Supabase emails and resume a paused project promptly in the dashboard. Paid plans avoid inactivity pausing, but quotas, billing, outages and other failure modes still apply.
2. **Usage limits or account changes.** Traffic, database size, egress limits, an expired paid plan, an account suspension, or deleting/pausing a project can interrupt operation.
3. **Credentials/configuration.** Rotating the public key or moving the database requires updating the app's Supabase URL/key. Never expose service keys through `VITE_` variables.
4. **Breaking changes.** Dependency or provider changes can require code and migration updates. Keep the lockfile, tests, migration history and versioned source.
5. **Owner access.** Losing access to the service accounts or a separately configured blockchain wallet can block maintenance. Retain account recovery methods privately.

Vercel's current production deployment is protected from normal age-based deployment-retention deletion. Older deployment history can be removed; retention is not a guarantee against deletion by an owner, account restrictions, quota problems or outages.

Provider references:

- https://supabase.com/docs/guides/platform/free-project-pausing
- https://supabase.com/docs/guides/platform/backups
- https://vercel.com/changelog/hobby-projects-now-retain-fewer-deployments-to-free-up-storage
- https://vercel.com/docs/plans

## Backups

Keep a private, restorable database backup at least weekly while the game is active and before applying migrations. Follow the current Supabase backup/export guide; include the application's public schema, its private accounting/admin/invitation tables, and the Auth data needed for account recovery. Test a restore into a separate non-production project.

Free-tier transaction exports from this app are **not** complete database backups. They verify financial history but do not restore users/password identities, markets, permissions, functions, invitations or settings. The Sepolia audit contract is likewise not a database backup.

Supabase recommends manual off-site exports for Free projects. Paid plans offer daily backups with plan-specific retention. No automatic full database backup has been configured here, because it requires owner-level credentials and a private storage destination. Never put database dumps, connection passwords, service keys or Auth password hashes into this public repository or public Actions artifacts.

## Deploying updates

The Vercel project was created with source uploads. A previous attempt to connect GitHub failed because the Vercel account lacked a GitHub Login Connection. No Git-push auto-deployment is assumed.

In the existing Vercel project's **Settings → Git**, connect `arthurrylance/Multimarche` with `main` as the production branch. Complete GitHub authorization in your Vercel account when requested. Preserve the existing project/domain and do not create a duplicate project. Verify a push produces a deployment of the expected commit before relying on automatic deployment.

Until that connection is made, source changes need a deliberate Vercel deployment. Keep Node 24, the Vite framework preset, `npm ci`, `npm run build` and output directory `dist`. A passing GitHub build alone does not prove that production has been updated.

## Update/recovery routine

1. Review failed health checks and provider quota/pause emails.
2. Back up privately before schema changes.
3. Review dependency-update PRs, run tests/build and check compatibility. Solidity compiler updates require reviewing the regenerated contract artifact; an already deployed contract does not upgrade itself.
4. Apply new migrations exactly once, preserving existing data and accounting.
5. Deploy the intended commit; verify the public page and a signed-in account's market, balance, admin and notification flows.
6. Confirm the ledger verifies and total accounts still equal issued supply.

If the frontend breaks, roll back to a known compatible Vercel deployment. A frontend rollback does not undo database migrations. If the database is lost or corrupted, restore a verified private backup and test before reconnecting production. Preserve audit history rather than editing past transfers.

For dependable long-term use, an owner should budget for reliable database hosting and backups, keep update reviews active and periodically test recovery. This setup does not promise unattended maintenance forever.
