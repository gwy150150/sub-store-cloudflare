#!/usr/bin/env bash
# Deploy Sub-Store Cloudflare through the CLI path that actually works.
# See docs/deploy-fix.zh-CN.md and PATCH_NOTES.md for background.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
info() { printf '\n==> %s\n' "$1"; }

for cmd in git node curl corepack; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd is required"
done

node_major="$(node -p "process.versions.node.split('.')[0]")"
if [ "$node_major" -lt 22 ]; then
  fail "Node.js 22+ is required, found $(node --version)"
fi

info "Enable pnpm through Corepack"
corepack enable

info "Install dependencies and generate the script registry"
pnpm run setup

info "Check Cloudflare login"
if ! pnpm --dir cloudflare exec wrangler whoami --json >/dev/null 2>&1; then
  info "Cloudflare login required; opening the browser"
  pnpm --dir cloudflare exec wrangler login
fi

info "Deploy: D1 + two Worker Secrets + migrations + Worker + HTTP verification"
pnpm run install:quick || fail "installer failed; fix the reported step and rerun this script"

info "Verify generated tokens"
node scripts/verify-secrets.mjs

info "Done. Save the Admin URL and both tokens from the installer output in a password manager."
