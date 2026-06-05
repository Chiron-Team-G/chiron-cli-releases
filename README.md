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

## Binaries

Each release ships per-platform assets, auto-selected by `install.sh`:

| Asset | Platform |
|---|---|
| `chiron-darwin-arm64` | macOS Apple Silicon |
| `chiron-darwin-x64` | macOS Intel |
| `chiron-linux-x64` | Linux x86_64 |

> Note: not related to `chiron-releases` (the legacy daemon). This is the
> CLI-first chiron.
