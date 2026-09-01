# Install the chiron CLI from the PROD-BETA channel (Windows).
#
# Same installer as everyone else — this only picks the channel. There is one
# install.ps1, not two: a forked copy would drift, and the half that drifts is
# always the one nobody runs on their own machine.
#
#   & ([scriptblock]::Create((irm <RAW_URL>/install-beta.ps1))) -Code CHIR-… -Server <url>
#
# Prod users cannot reach the dev binary by accident: dev builds are published
# as GitHub PRE-RELEASES, and /releases/latest — what install.ps1 and
# `chiron update` follow — excludes those by definition. This script takes the
# other road on purpose, and install.ps1 records the channel so `chiron update`
# keeps taking it.
$ErrorActionPreference = "Stop"

$Repo      = "Chiron-Team-G/chiron-cli-releases"
$Installer = if ($env:CHIRON_INSTALLER_URL) { $env:CHIRON_INSTALLER_URL } else { "https://raw.githubusercontent.com/$Repo/main/install.ps1" }

try {
  $script = Invoke-RestMethod -Uri $Installer -UseBasicParsing
} catch {
  Write-Error "Could not download the installer from $Installer. Check your network (corporate VPN/proxy?)."
  exit 1
}

# Refuse an installer too old to know about channels: it would install the PROD
# binary and report success, and the person would spend the afternoon wondering
# why no work order shows up.
if ($script -notmatch 'CHIRON_CHANNEL') {
  Write-Error "The published install.ps1 predates channel support. Publish the current scripts/install.ps1 to $Repo first."
  exit 1
}

Write-Host "-> chiron CLI - PROD-BETA channel"
$env:CHIRON_CHANNEL = "beta"
& ([scriptblock]::Create($script)) @args
