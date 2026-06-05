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
if command -v chiron >/dev/null 2>&1; then
  echo "✓ chiron already installed ($(command -v chiron)) — skipping install"
elif [[ -n "$CHIRON_RELEASE_URL" ]]; then
  echo "→ Installing chiron from release…"
  TMP="$(mktemp -d)"
  curl -fsSL "$CHIRON_RELEASE_URL" -o "$TMP/chiron"
  chmod +x "$TMP/chiron"
  sudo mv "$TMP/chiron" /usr/local/bin/chiron
  echo "✓ chiron installed at /usr/local/bin/chiron"
  FRESH_INSTALL=1
elif [[ -d "$DEV_CHECKOUT" ]] && command -v bun >/dev/null 2>&1; then
  # Dev fallback: wrapper that executes the checkout's source with bun —
  # source changes apply without recompiling (same install used in-house).
  echo "→ Installing chiron (dev wrapper over $DEV_CHECKOUT)…"
  printf '#!/bin/sh\nexec bun %s/src/index.ts "$@"\n' "$DEV_CHECKOUT" | sudo tee /usr/local/bin/chiron >/dev/null
  sudo chmod +x /usr/local/bin/chiron
  echo "✓ chiron installed at /usr/local/bin/chiron (dev mode)"
  FRESH_INSTALL=1
else
  echo "✗ chiron is not installed and no release URL is configured." >&2
  echo "  Dev machines: clone the chiron repo and install bun, then re-run." >&2
  exit 1
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
