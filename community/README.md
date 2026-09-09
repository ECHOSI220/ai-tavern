# AI Tavern Web Community

A responsive TypeScript/Vite website using Supabase authentication, database access policies, and private storage. It shares the application's account system but runs independently of the Flutter client.

## Development

Use Node.js 24+ and pnpm:

```sh
pnpm install --frozen-lockfile
# Copy .env.example to .env.local and supply your own public settings.
pnpm dev
pnpm test
pnpm build
```

`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, and `VITE_GAME_SERVER_URL` are public client configuration. Never provide a service-role/admin key in a `VITE_` variable.

## Features and access

- Publish and download validated JSON packages up to 2 MB.
- Optional PNG/JPEG/WebP cover images up to 5 MB, including adding or replacing a cover after publication.
- Public discovery, private author content, and by-link content workflows.
- Private preview bucket: bound public covers can be signed for visitors; private and unlisted covers remain owner-only.
- App download links and public multiplayer invitation views.

See `../supabase/migrations` and `../supabase/tests` for database changes and rollback-only access checks. Migrations depend on parts of the pre-existing application schema; review prerequisites before applying them to a new project.

## Verification

`pnpm test` runs local package validation tests. `node test/upload-browser.mjs` uses mocked cloud requests; set `WEB_TEST_URL` to a local preview server and optionally `PW_CHANNEL=msedge`. Browser smoke tests use the configured website URL. `test/cloud-e2e.mjs` is an explicit integration test that requires an administrator credential and creates temporary accounts: review it before running against any deployed service.

## Hosting

The current deployment uses Cloudflare Pages. `public/_headers` contains security headers and `public/_redirects` supports SPA routes. Set your own Pages project name in `wrangler.toml` before deploying a separate site. The parent `tool/deploy_community.ps1` helper expects an untracked `server/.env.production.local` with public configuration; it exports only allowlisted client settings.
