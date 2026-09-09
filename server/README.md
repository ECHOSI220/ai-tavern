# AI Tavern Multiplayer Backend

Cloudflare Worker and Durable Objects backend for the Flutter application.

- The Worker handles HTTPS routing, Supabase JWT verification, and request limits.
- A Durable Object manages each live room's players, turns, dice, reconnect state, and private views.
- Supabase provides account authentication and cloud persistence.
- The shared protocol is documented in `../shared/protocol/protocol.schema.json`.

## Local development

Use Node.js 24+ and pnpm. Install dependencies, copy `.env.example` to `.dev.vars`, and configure a development Supabase project.

```sh
pnpm install --frozen-lockfile
pnpm run typecheck
pnpm test
pnpm run dev
```

`pnpm run test:runtime` exercises local workerd and room workflows. Review test setup first; it does not replace deployed authentication, AI-provider, or device acceptance tests.

## Configuration and deployment

Use your own Worker project name in `wrangler.toml`. Set Supabase settings through Cloudflare environment variables and `wrangler secret put`. `SUPABASE_SERVICE_ROLE_KEY` is server-only and must never be compiled into Flutter or the web client.

Health endpoints are `/health` and `/version`; application APIs are under `/v1`. SQL changes are in `../supabase/migrations`. They extend a pre-existing schema: inspect dependencies before bootstrapping a new database.

The multiplayer implementation is still evolving. Local tests do not establish complete production readiness or validate every multi-device workflow. Runtime-test entry points that bypass authentication must never be deployed.

An optional Supabase HTTP/WebSocket gateway is included at `../supabase/functions/game-server-proxy/index.ts`. Set its `GAME_SERVER_UPSTREAM_URL` environment variable to your own HTTPS Worker origin before deployment. Gateway configuration must preserve the backend's authentication requirements.
