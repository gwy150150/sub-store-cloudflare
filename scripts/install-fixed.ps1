# Deploy Sub-Store Cloudflare through the CLI path that actually works.
# Windows PowerShell 5.1+ / PowerShell 7+
# See docs/deploy-fix.zh-CN.md and PATCH_NOTES.md for background.

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

function Fail([string]$Message) {
  Write-Host "ERROR: $Message" -ForegroundColor Red
  exit 1
}

function Info([string]$Message) {
  Write-Host ""
  Write-Host "==> $Message"
}

foreach ($cmd in @("git", "node", "curl", "corepack")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Fail "$cmd is required"
  }
}

$nodeMajor = [int](& node -p "process.versions.node.split('.')[0]")
if ($nodeMajor -lt 22) {
  Fail "Node.js 22+ is required, found $(& node --version)"
}

Info "Enable pnpm through Corepack"
& corepack enable
if ($LASTEXITCODE -ne 0) { Fail "corepack enable failed" }

Info "Install dependencies and generate the script registry"
& pnpm run setup
if ($LASTEXITCODE -ne 0) { Fail "pnpm run setup failed" }

Info "Check Cloudflare login"
& pnpm --dir cloudflare exec wrangler whoami --json | Out-Null
if ($LASTEXITCODE -ne 0) {
  Info "Cloudflare login required; opening the browser"
  & pnpm --dir cloudflare exec wrangler login
  if ($LASTEXITCODE -ne 0) { Fail "wrangler login failed" }
}

Info "Deploy: D1 + two Worker Secrets + migrations + Worker + HTTP verification"
& pnpm run install:quick
if ($LASTEXITCODE -ne 0) {
  Fail "installer failed; fix the reported step and rerun this script"
}

Info "Verify generated tokens"
& node scripts/verify-secrets.mjs
if ($LASTEXITCODE -ne 0) { Fail "token verification failed" }

Info "Done. Save the Admin URL and both tokens from the installer output in a password manager."
