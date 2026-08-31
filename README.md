# chiron-cli-releases

Distribution channel for the **chiron CLI** — install script + compiled binaries
(GitHub Releases). This repo contains **no source code**.

## Install

Don't run this by hand — the **agent wizard** (Engineers board → create agent)
renders the exact one-paste command for you, with a fresh one-time code:

```sh
curl -fsSL https://raw.githubusercontent.com/Chiron-Team-G/chiron-cli-releases/main/install.sh | bash -s -- --code CHIR-XXXXXX-XXXXXX --server <url>
```

One paste = chiron installed (skipped if present) + signed in (the code
carries your verified web session — no password on the terminal) + agent
paired. The wizard detects the link and completes on its own.

## Channels

Two channels share this repo, told apart by GitHub's pre-release flag.

| | who | how |
|---|---|---|
| **stable** | everyone, prod included | `install.sh` → `/releases/latest` |
| **dev** | the team, against the dev backend | `install-dev.sh` → newest `-dev` tag |

`/releases/latest` **excludes pre-releases by definition**, so a machine on the
stable channel cannot see a dev build even when one was published a minute ago.
That is the whole protection — no flag to get wrong, no backend that has to
answer correctly.

```bash
curl -fsSL https://raw.githubusercontent.com/Chiron-Team-G/chiron-cli-releases/main/install-dev.sh | bash -s -- --code CHIR-XXXXXX-XXXXXX --server <dev url>
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Chiron-Team-G/chiron-cli-releases/main/install-dev.ps1))) -Code CHIR-XXXXXX-XXXXXX -Server <dev url>
```

You should not need to type either one: the agent wizard renders the command for
the environment you are on, dev included.

`install-dev.sh` only picks the channel; it downloads the same `install.sh`. The
install writes `~/.chiron/cli/channel`, which `chiron update` reads — so a dev
machine stays on the dev channel instead of being pulled onto the prod binary
the day prod publishes a higher version.

Publish with `scripts/release.sh --dev` from AF-Chiron-CLI. It requires a
prerelease suffix (`0.14.0-dev.1`) and refuses the reverse: a dev build without
one reaches everybody, a prod build with one reaches nobody.

## Binaries

Each release ships per-platform assets, auto-selected by `install.sh`:

| Asset | Platform |
|---|---|
| `chiron-darwin-arm64` | macOS Apple Silicon |
| `chiron-darwin-x64` | macOS Intel |
| `chiron-linux-x64` | Linux x86_64 |

> Note: not related to `chiron-releases` (the legacy daemon). This is the
> CLI-first chiron.
