# Frontend

This directory contains the Vue admin UI used by Sub-Store Cloudflare.

The production build is generated into `frontend/dist` and served by the Worker through Cloudflare Workers Static Assets. It is not a separate deployment target.

## Development

```bash
pnpm --dir frontend install
pnpm --dir frontend run build
```

`VITE_API_URL` is optional: `src/hooks/useHostAPI.ts` falls back to `/`, which is the production value. The old `VITE_API_URL=/ command` form uses Unix-only shell syntax and fails on Windows.

For full local development, build the frontend and run the Worker from the repository root:

```bash
pnpm run build:frontend
pnpm run dev
```

## Attribution

The UI is based on the original [sub-store-org/Sub-Store](https://github.com/sub-store-org/Sub-Store) frontend and has been trimmed for this Cloudflare-native edition.
