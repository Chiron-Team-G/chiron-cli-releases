# chiron one-paste installer + onboarding — Windows (PowerShell).
#
# The agent wizard renders this exact command for the user:
#   irm <RAW_URL>/install.ps1 | iex                 (update-only, no code)
#   & ([scriptblock]::Create((irm <RAW_URL>/install.ps1))) -Code CHIR-… -Server <url>
#
# Mirrors install.sh (bash) for macOS/Linux:
#   1. chiron installed?  no  → download the release .exe, add to PATH
#                          yes → `chiron update` (the CLI's own self-update)
#   2. with -Code → `chiron setup --code … --server …` (login + pairing)
#
# User-scoped: installs to %LOCALAPPDATA%\chiron\bin and edits the USER PATH —
# never needs admin.

param(
  [string]$Code = "",
  [string]$Server = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # speeds up Invoke-WebRequest a lot

$RepoBase = "https://github.com/Chiron-Team-G/chiron-cli-releases/releases/latest/download"
$Asset    = "chiron-windows-x64.exe"
$BinDir   = Join-Path $env:LOCALAPPDATA "chiron\bin"
$ExePath  = Join-Path $BinDir "chiron.exe"

function Info($m)  { Write-Host "→ $m" -ForegroundColor Cyan }
function Ok($m)    { Write-Host "✓ $m" -ForegroundColor Green }
function Warn($m)  { Write-Host "⚠ $m" -ForegroundColor Yellow }
function Fail($m)  { Write-Host "✗ $m" -ForegroundColor Red; exit 1 }

# ── Architecture guard ───────────────────────────────────────────────────────
if (-not [Environment]::Is64BitOperatingSystem) {
  Fail "chiron ships a 64-bit Windows build only — this machine isn't 64-bit."
}

# ── Download + verify the release binary into %LOCALAPPDATA%\chiron\bin ───────
function Install-Binary {
  New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
  $tmp = Join-Path $env:TEMP "chiron-dl-$PID.exe"

  Info "Downloading $Asset…"
  # Prefer curl.exe (ships with Windows 10 1803+): its --progress-bar shows
  # live progress — the binary is ~112MB and a silent download reads as HUNG
  # on a slow link (operator request 2026-07-06). IWR stays as the fallback
  # (its own progress is disabled above because it slows downloads a lot).
  $curlExe = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curlExe) {
    & curl.exe -fL --progress-bar "$RepoBase/$Asset" -o $tmp
    if ($LASTEXITCODE -ne 0) {
      Fail "Download failed: $RepoBase/$Asset  (curl exit $LASTEXITCODE)"
    }
  } else {
    try {
      Invoke-WebRequest -Uri "$RepoBase/$Asset" -OutFile $tmp -UseBasicParsing
    } catch {
      Fail "Download failed: $RepoBase/$Asset  ($($_.Exception.Message))"
    }
  }

  # Integrity: compare against the release's checksums.txt.
  try {
    $sums = (Invoke-WebRequest -Uri "$RepoBase/checksums.txt" -UseBasicParsing).Content
    $want = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($Asset) }) -split "\s+" | Select-Object -First 1
    $got  = (Get-FileHash -Algorithm SHA256 -Path $tmp).Hash.ToLower()
    if ($want -and $got -ne $want.ToLower()) {
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue
      Fail "Checksum mismatch for $Asset — aborting."
    }
  } catch {
    Warn "Could not verify checksum ($($_.Exception.Message)) — continuing."
  }

  # The .exe isn't running during install, so a plain move/overwrite is fine
  # (the running-exe shuffle only matters for `chiron update`).
  Move-Item -Path $tmp -Destination $ExePath -Force
  Ok "chiron installed at $ExePath"

  # PATH (USER scope — no admin). Prepend so this chiron wins.
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($userPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$BinDir;$userPath", "User")
    Ok "Added to your PATH: $BinDir"
  } else {
    Info "PATH already configured"
  }
  # Refresh the CURRENT session too (registry change isn't picked up live).
  $env:Path = "$BinDir;$env:Path"
}

# Does the installed chiron actually RUN? (prints plain semver). A binary that
# starts and dies silently is the no-AVX2 crash signature — see below.
function Test-ChironRuns {
  try {
    $v = (& $ExePath --version 2>$null | Select-Object -First 1)
  } catch {
    $v = $null
  }
  return ($v -match '^\d+\.\d+\.\d+$')
}

# ── Flow ─────────────────────────────────────────────────────────────────────
$installed = Test-Path $ExePath

if (-not $installed) {
  if (-not $Code) {
    Fail "Missing -Code. Copy the full command from the agent wizard (it carries your one-time code)."
  }
  Install-Binary
  # AVX2 fallback: the standard build needs a ~2013+ CPU; on older machines it
  # crashes SILENTLY (exit 0xC0000005, no output — in-vivo: an i7-3770S,
  # 2026-07-06). If the fresh install doesn't answer, swap in the baseline
  # (compatibility) build automatically — its self-update stays baseline too.
  if (-not (Test-ChironRuns)) {
    Warn "chiron didn't respond — this CPU may not support AVX2 (pre-2013). Installing the compatibility build…"
    $script:Asset = "chiron-windows-x64-baseline.exe"
    Install-Binary
    if (Test-ChironRuns) {
      Ok "Compatibility build working."
    } else {
      Warn "Still no response — this can also be the antivirus scanning the new binary (first run only)."
      Warn "Wait ~60 seconds, open a NEW terminal and try:  chiron --version"
    }
  }
} else {
  # Installed but SILENT (starts and dies, no output) → the no-AVX2 crash
  # signature. Reinstall going straight to the baseline build — re-running
  # `chiron update` from a crashed binary can never fix itself.
  if (-not (Test-ChironRuns)) {
    Warn "chiron is installed but not responding — reinstalling with the compatibility build (pre-2013 CPU / no AVX2)…"
    $script:Asset = "chiron-windows-x64-baseline.exe"
    Install-Binary
    if (Test-ChironRuns) { Ok "Compatibility build working." }
  }

  # Already installed → OFFER the update, never force it (operator decision
  # 2026-07-06: a new release could carry a regression — the user consents;
  # same philosophy as the CLI's own startup y/n prompt). `chiron update`
  # still does the heavy lifting (running-exe shuffle + anti-downgrade).
  $current = (& $ExePath --version 2>$null | Select-Object -First 1)
  $latest = $null
  try {
    $req = [System.Net.HttpWebRequest]::Create("https://github.com/Chiron-Team-G/chiron-cli-releases/releases/latest")
    $req.Method = "HEAD"
    $req.AllowAutoRedirect = $true
    $res = $req.GetResponse()
    if ($res.ResponseUri.AbsoluteUri -match '/tag/v?([0-9][^/]*)') { $latest = $Matches[1] }
    $res.Close()
  } catch { }

  if ($latest -and $current -match '^\d+\.\d+\.\d+$' -and ([version]$latest -gt [version]$current)) {
    $ans = Read-Host "chiron $current installed — $latest is available. Update now? [Y/n]"
    if ($ans -notmatch '^[nN]') {
      & $ExePath update
    } else {
      Info "Keeping chiron $current — update anytime with:  chiron update"
    }
  } elseif ($current -match '^\d+\.\d+\.\d+$') {
    Ok "chiron already installed ($current) — up to date"
  } else {
    # Version unreadable (first-run AV scan / broken binary) — let the CLI's
    # own update flow sort it out, like before.
    Info "chiron already installed — checking for updates…"
    & $ExePath update
  }

  if (-not $Code) {
    # Update-only run (no code): done.
    Ok "Update-only run complete — login/pairing untouched."
    Write-Host "  Tip: you can also just run:  chiron update" -ForegroundColor DarkGray
    exit 0
  }
}

# ── Pairing (login + agent) ──────────────────────────────────────────────────
$setupArgs = @("setup", "--code", $Code)
if ($Server) { $setupArgs += @("--server", $Server) }
& $ExePath @setupArgs

Write-Host ""
Ok "Done."
Write-Host "  If 'chiron' isn't found in this window, open a NEW terminal (PATH refresh)." -ForegroundColor DarkGray
