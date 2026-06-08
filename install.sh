#!/usr/bin/env bash
#
# chiron one-paste installer + onboarding.
#
# The agent wizard (Engineers FE) renders this exact command for the user:
#
#   curl -fsSL <RAW_URL>/install.sh | bash -s -- --code CHIR-… --server <url>
#
# Decision tree (manager design, 2026-06-04):
#   1. chiron already installed?  → skip install.
#      not installed?             → install it:
#        a. release binary if CHIRON_RELEASE_URL is configured (prod path),
#        b. dev fallback: a local checkout + bun → /usr/local/bin wrapper.
#   2. run `chiron setup --code … --server …` → exchanges the one-time code:
#      the CLI ends up LOGGED IN (Firebase custom token — no password) and
#      PAIRED with the agent. The wizard detects the link and completes.
#
# Result: one paste = installed + authenticated + agent connected.
set -euo pipefail

# ── Args (forwarded to `chiron setup`) ──────────────────────────────────────
CODE=""
SERVER=""
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --code)   CODE="$2"; shift 2 ;;
    --server) SERVER="$2"; shift 2 ;;
    *)        EXTRA_ARGS+=("$1"); shift ;;
  esac
done

if [[ -z "$CODE" ]]; then
  echo "✗ Missing --code (copy the full command from the agent wizard)" >&2
  exit 1
fi

# ── Step 1 · Install chiron if missing ──────────────────────────────────────
# Release binaries live in the distribution repo (one asset per OS/arch,
# published with the GitHub release). CHIRON_RELEASE_URL overrides for
# pinning a specific version or testing a pre-release asset.
RELEASE_BASE="https://github.com/Chiron-Team-G/chiron-cli-releases/releases/latest/download"
detect_release_url() {
  local os arch
  case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux)  os="linux" ;;
    *)      return 1 ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) arch="arm64" ;;
    x86_64)        arch="x64" ;;
    *)             return 1 ;;
  esac
  # No darwin-arm64/x64 gaps today; linux only ships x64.
  [[ "$os" == "linux" && "$arch" == "arm64" ]] && return 1
  echo "$RELEASE_BASE/chiron-$os-$arch"
}
CHIRON_RELEASE_URL="${CHIRON_RELEASE_URL:-$(detect_release_url || true)}"
DEV_CHECKOUT="${CHIRON_DEV_CHECKOUT:-$HOME/Desktop/chiron}"

FRESH_INSTALL=0
# Set to 1 by install_binary (the release-download path) so the legacy-data
# purge runs ONLY when the real release CLI is what ends up installed — never
# on a dev-wrapper machine.
INSTALLED_RELEASE=0

# What is the `chiron` on this machine, if any? Machines have HISTORY —
# in-vivo 2026-06-05/06: teammates hit different failures because each Mac
# carried a different past (the LEGACY chiron daemon shares the name AND a
# `setup` subcommand; old CLI versions never upgraded; fresh Macs lack
# /usr/local/bin). Classify before deciding:
#   none   → not installed
#   dev    → our bun dev-wrapper (leave it alone — source checkout machines)
#   legacy → the OLD chiron daemon or a broken binary (REPLACE it)
#   x.y.z  → the real CLI at that version (upgrade if a newer release exists)
installed_kind() {
  local bin ver
  bin="$(command -v chiron 2>/dev/null)" || { echo "none"; return; }
  if head -2 "$bin" 2>/dev/null | grep -q "exec bun"; then echo "dev"; return; fi
  ver="$(chiron --version 2>/dev/null | head -1 || true)"
  # The new CLI prints PLAIN semver; the legacy daemon prints
  # "0.0.1 · built … · sha …" and a Gatekeeper-killed binary prints nothing.
  if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$ver"; else echo "legacy"; fi
}

latest_version() {
  # The /releases/latest redirect ends at …/tag/vX.Y.Z — no API token needed.
  curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/Chiron-Team-G/chiron-cli-releases/releases/latest" 2>/dev/null |
    sed 's|.*/tag/v\{0,1\}||'
}

install_binary() {
  local tmp
  tmp="$(mktemp -d)"
  if ! curl -fsSL "$CHIRON_RELEASE_URL" -o "$tmp/chiron"; then
    echo "✗ Download failed: $CHIRON_RELEASE_URL" >&2
    echo "  Check your network (corporate VPN/proxy?) and that a release asset" >&2
    echo "  exists for your platform ($(uname -s)/$(uname -m))." >&2
    exit 1
  fi
  chmod +x "$tmp/chiron"
  if command -v sudo >/dev/null 2>&1; then
    # /usr/local/bin does NOT exist on fresh macOS (Apple Silicon Homebrew
    # lives in /opt/homebrew) — mv won't create it (in-vivo 2026-06-05:
    # teammate's one-paste died with "rename …: No such file or directory").
    sudo mkdir -p /usr/local/bin
    sudo mv "$tmp/chiron" /usr/local/bin/chiron
    echo "✓ chiron installed at /usr/local/bin/chiron"
  else
    # No sudo (locked-down corporate machine) → user-writable fallback.
    mkdir -p "$HOME/.local/bin"
    mv "$tmp/chiron" "$HOME/.local/bin/chiron"
    export PATH="$HOME/.local/bin:$PATH"
    echo "✓ chiron installed at ~/.local/bin/chiron (no sudo available)"
    echo "  Add this line to your shell profile to make it permanent:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
  FRESH_INSTALL=1
  INSTALLED_RELEASE=1
}

# ── Legacy daemon cleanup ───────────────────────────────────────────────────
# The OLD chiron daemon (github.com/Chiron-Team-G/chiron-releases) installed a
# binary also named `chiron` to the SAME locations. In-vivo: teammates ended up
# with the daemon in ~/.local/bin (earlier on PATH) SHADOWING the new CLI in
# /usr/local/bin — `chiron --version` kept showing the daemon, never the CLI.
# We remove every legacy `chiron` on PATH (keeping the new CLI + any dev wrapper)
# and the daemon's data dirs. We NEVER touch ~/.chiron/cli/ (the CLI's own
# login/pairing, written by `chiron setup`) or ~/.claude*.

# Is the binary at $1 our bun dev wrapper? (leave those alone — dev machines.)
is_dev_wrapper() { head -2 "$1" 2>/dev/null | grep -q "exec bun"; }

# Remove a file, using sudo only when its directory isn't user-writable.
remove_path() {
  if [[ -w "$(dirname "$1")" ]]; then rm -f "$1"; else sudo rm -f "$1"; fi
}

# Keep the new CLI (and any dev wrapper); remove every other `chiron` on PATH so
# nothing shadows it. Idempotent: a second run finds nothing to remove.
sweep_legacy_binaries() {
  local keep dirs d p
  keep="${INSTALL_PATH:-$(command -v chiron 2>/dev/null || true)}"
  IFS=: read -ra dirs <<< "$PATH"
  for d in "${dirs[@]}"; do
    p="$d/chiron"
    [[ -f "$p" && -x "$p" ]] || continue
    [[ -n "$keep" && "$p" == "$keep" ]] && continue
    is_dev_wrapper "$p" && continue
    if pgrep -f "$p" >/dev/null 2>&1; then
      echo "  ⚠ a chiron process from $p looks like it's running — close it when you can." >&2
    fi
    echo "  · removing shadowing legacy binary: $p"
    remove_path "$p" || echo "  ⚠ could not remove $p — delete it by hand." >&2
  done
}

# Remove the legacy daemon's data dirs. PRESERVE ~/.chiron/cli/ (the new CLI's
# state) — never `rm -rf ~/.chiron`.
purge_legacy_data() {
  local d target
  for d in config.json memory logs sessions runs; do
    target="$HOME/.chiron/$d"
    if [[ -e "$target" ]]; then
      rm -rf "$target" && echo "  · removed legacy daemon data: ~/.chiron/$d"
    fi
  done
}

KIND="$(installed_kind)"
case "$KIND" in
  dev)
    echo "✓ chiron dev wrapper detected ($(command -v chiron)) — leaving it alone"
    ;;
  none | legacy)
    if [[ "$KIND" == "legacy" ]]; then
      echo "→ Found the legacy chiron daemon at $(command -v chiron) — replacing it with the chiron CLI…"
    fi
    if [[ -n "$CHIRON_RELEASE_URL" ]]; then
      echo "→ Installing chiron from release…"
      install_binary
    elif [[ -d "$DEV_CHECKOUT" ]] && command -v bun >/dev/null 2>&1; then
      # Dev fallback: wrapper that executes the checkout's source with bun —
      # source changes apply without recompiling (same install used in-house).
      echo "→ Installing chiron (dev wrapper over $DEV_CHECKOUT)…"
      sudo mkdir -p /usr/local/bin
      printf '#!/bin/sh\nexec bun %s/src/index.ts "$@"\n' "$DEV_CHECKOUT" | sudo tee /usr/local/bin/chiron >/dev/null
      sudo chmod +x /usr/local/bin/chiron
      echo "✓ chiron installed at /usr/local/bin/chiron (dev mode)"
      FRESH_INSTALL=1
    else
      echo "✗ chiron is not installed and no release URL is configured." >&2
      echo "  Dev machines: clone the chiron repo and install bun, then re-run." >&2
      exit 1
    fi
    ;;
  *)
    # Real CLI at version $KIND — self-upgrade when a newer release exists
    # ("already installed — skipping" froze every machine at whatever
    # version it first got; teammates on v0.1.x never saw v0.2.0).
    LATEST="$(latest_version || true)"
    if [[ -n "$LATEST" && "$LATEST" != "$KIND" && -n "$CHIRON_RELEASE_URL" ]]; then
      echo "→ chiron $KIND installed — upgrading to ${LATEST}…"
      install_binary
    else
      echo "✓ chiron already installed ($KIND) — up to date"
    fi
    ;;
esac

# ── Legacy daemon cleanup (dev-wrapper machines are skipped entirely) ───────
if [[ "$KIND" != "dev" ]]; then
  sweep_legacy_binaries
  # Purge daemon DATA only when the real release CLI is what's installed —
  # never on a freshly-made dev wrapper (KIND none/legacy + no release URL).
  if [[ "$KIND" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || "$INSTALLED_RELEASE" == "1" ]]; then
    purge_legacy_data
  fi
fi

# Post-install sanity: the binary must actually answer from PATH.
if ! chiron --version >/dev/null 2>&1; then
  echo "✗ chiron installed but not responding from PATH." >&2
  echo "  Open a NEW terminal tab (or run \`rehash\` on zsh) and re-paste the command." >&2
  exit 1
fi

# And on real-CLI installs, make sure the chiron that WINS on PATH is the new
# CLI (plain semver) — not a legacy daemon we somehow missed. Warning only, so a
# cold-start version hiccup never blocks the install.
if [[ "$KIND" != "dev" ]] && ! is_dev_wrapper "$(command -v chiron)"; then
  RESOLVED_VER="$(chiron --version 2>/dev/null | head -1 || true)"
  if ! [[ "$RESOLVED_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "  ⚠ '$(command -v chiron)' still reports '${RESOLVED_VER:-nothing}' — a legacy daemon may remain ahead on PATH." >&2
    echo "    Open a new terminal; if it persists, delete that binary by hand." >&2
  fi
fi

# ── Step 2 · One-paste setup: login (custom token) + agent pairing ─────────
SETUP_ARGS=(--code "$CODE")
[[ -n "$SERVER" ]] && SETUP_ARGS+=(--server "$SERVER")
# NOT exec: we still print the shell-hash hint after setup finishes.
chiron setup "${SETUP_ARGS[@]}" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

# zsh caches its command table per session — a binary installed mid-session
# isn't found until `rehash` (and with autocd + a same-named folder, typing
# `chiron` silently cd's instead — found in-vivo 2026-06-05). Only relevant
# when this run actually installed the binary; bash users are unaffected.
if [[ "${FRESH_INSTALL:-0}" == "1" && "$(basename "${SHELL:-}")" == "zsh" ]]; then
  echo ""
  echo "  ↻ zsh note: if this shell says 'command not found: chiron', run:  rehash"
fi
