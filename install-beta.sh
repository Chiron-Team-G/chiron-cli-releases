#!/usr/bin/env bash
#
# Install the chiron CLI from the PROD-BETA channel.
#
# prod-beta (1/9) es el entorno de producción del equipo: mismos mecanismos
# que el canal dev — pre-releases con sufijo, /releases/latest nunca las ve —
# pero sus builds se cortan desde la RAMA prod-beta, no desde dev.
#
# Same installer as everyone else — this only picks the channel. There is one
# install.sh, not two: a forked copy would drift, and the half that drifts is
# always the one nobody runs on their own machine.
#
#   curl -fsSL <RAW_URL>/install-beta.sh | bash -s -- --code CHIR-… --server <url>
#
# WHY A SEPARATE SCRIPT AND NOT A FLAG PEOPLE TYPE
# Prod users must not be able to reach a channel binary by accident, and the
# protection cannot rest on them not passing a flag. It rests on GitHub: dev
# builds are published as PRE-RELEASES, and /releases/latest — what install.sh
# and `chiron update` follow — excludes pre-releases by definition. A prod
# machine cannot see a dev build. This script takes the other road on purpose,
# and install.sh records the channel so `chiron update` keeps taking it.
set -euo pipefail

REPO="Chiron-Team-G/chiron-cli-releases"
INSTALLER="${CHIRON_INSTALLER_URL:-https://raw.githubusercontent.com/$REPO/main/install.sh}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL "$INSTALLER" -o "$tmp/install.sh"; then
  echo "✗ Could not download the installer from $INSTALLER" >&2
  echo "  Check your network (corporate VPN/proxy?)." >&2
  exit 1
fi

# Refuse an installer too old to know about channels: it would happily install
# the PROD binary and report success, and the person would spend the afternoon
# wondering why no work order shows up.
if ! grep -q 'CHIRON_CHANNEL' "$tmp/install.sh"; then
  echo "✗ The published install.sh predates channel support." >&2
  echo "  Publish the current scripts/install.sh to $REPO first." >&2
  exit 1
fi

echo "→ chiron CLI · PROD-BETA channel"
CHIRON_CHANNEL=beta bash "$tmp/install.sh" "$@"
