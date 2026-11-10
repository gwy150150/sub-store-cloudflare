# Deploy Sub-Store Cloudflare through the CLI path that actually works.
# Windows PowerShell 5.1+ / PowerShell 7+
# See docs/deploy-fix.zh-CN.md and PATCH_NOTES.md for background.
#
# Node and Git are auto-detected: some environments (for example WorkBuddy's
# bundled runtimes) keep them outside the user PATH.

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

function Find-Executable([string]$Name, [string[]]$Patterns) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($pattern in $Patterns) {
    $hit = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

function Resolve-GitExe {
  $paths = @(
    "$env:ProgramFiles\Git\cmd\git.exe",
    "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
    "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
  )
  $roots = @(
    "$env:USERPROFILE\.workbuddy-ai\binaries\PortableGit",
    "D:\work\WorkBuddyAI\resources\vendor\PortableGit",
    "C:\work\WorkBuddyAI\resources\vendor\PortableGit"
  )
  foreach ($root in $roots) {
    if (Test-Path $root) {
      $hit = Get-ChildItem -Path $root -Filter git.exe -Recurse -Depth 4 -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -like "*\cmd\*" -or $_.FullName -like "*\mingw64\bin\*" } |
             Select-Object -First 1
      if ($hit) { $paths += $hit.FullName }
    }
  }
  foreach ($p in $paths) {
    if ($p -and (Test-Path $p)) { return $p }
  }
  return $null
}

$nodeExe = Find-Executable "node.exe" @(
  "$env:ProgramFiles\nodejs\node.exe",
  "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
  "$env:USERPROFILE\.workbuddy-ai\binaries\node\versions\*\node.exe"
)
if (-not $nodeExe) {
  Fail "node.exe not found. Install Node.js 22+ or add it to PATH, then rerun."
}
$nodeDir = Split-Path $nodeExe -Parent
$env:PATH = "$nodeDir;$env:PATH"
Write-Host "Using Node: $nodeExe"

$gitExe = Resolve-GitExe
if ($gitExe) {
  $gitDir = Split-Path $gitExe -Parent
  $env:PATH = "$gitDir;$env:PATH"
  $portableBin = Join-Path (Split-Path $gitDir -Parent) "mingw64\bin"
  if (Test-Path $portableBin) { $env:PATH = "$portableBin;$env:PATH" }
  Write-Host "Using Git:  $gitExe"
} else {
  Write-Host "Warning: git.exe not found; the installer's privacy check may fail." -ForegroundColor Yellow
}

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
  Fail "curl.exe is required"
}

$nodeMajor = [int](& $nodeExe -p "process.versions.node.split('.')[0]")
if ($nodeMajor -lt 22) {
  Fail "Node.js 22+ is required, found $(& $nodeExe --version)"
}

Info "Enable pnpm through Corepack"
$corepackCmd = Join-Path $nodeDir "corepack.cmd"
if (Test-Path $corepackCmd) {
  & $corepackCmd enable
} else {
  & corepack enable
}
if ($LASTEXITCODE -ne 0) { Fail "corepack enable failed" }
if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  Fail "pnpm shim was not created. Restart the terminal and rerun this script."
}

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
& $nodeExe scripts/verify-secrets.mjs
if ($LASTEXITCODE -ne 0) { Fail "token verification failed" }

Info "Done. Save the Admin URL and both tokens from the installer output in a password manager."
