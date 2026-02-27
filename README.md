# paqet-updater

Auto-update script for [paqet](https://github.com/hanselime/paqet) — fetches the latest GitHub release, compares with the installed version, and replaces the binary if a newer version is available.

## Supported platforms

| OS    | Architectures |
|-------|--------------|
| Linux | amd64, arm64, arm32, mips, mips64, mips64le, mipsle |

## Usage

```bash
# Basic update (default install path: /opt/paqet/paqet)
sudo ./paqet-update.sh

# Custom install path
sudo INSTALL_PATH=/usr/local/bin/paqet ./paqet-update.sh

# Dry run — shows what would happen without making changes
./paqet-update.sh --dry-run

# Custom path via flag
sudo ./paqet-update.sh --install-path=/usr/local/bin/paqet
```

## What it does

1. **Fetches** the latest release tag from `https://api.github.com/repos/hanselime/paqet/releases/latest`
2. **Gets installed version** by running `/opt/paqet/paqet version`
3. **Compares** — exits cleanly if already up-to-date
4. **Detects arch** via `uname -m` and maps to the correct release asset:
   - `x86_64` → `amd64`
   - `aarch64` / `arm64` → `arm64`
   - `armv7l` / `armv6l` → `arm32`
   - `mips*` → matching mips variant
5. **Downloads** the `.tar.gz` asset from GitHub releases
6. **Extracts** and verifies the binary runs correctly
7. **Atomically replaces** the old binary (`mv` on same filesystem), backs up old as `.bak`

## Example output

```
[paqet-update] System: linux/amd64 (raw: x86_64)
[paqet-update] Fetching latest release from github.com/hanselime/paqet…
[paqet-update] Latest release: v1.0.0-alpha.19
[paqet-update] Installed:     v1.0.0-alpha.18
[paqet-update] Asset: paqet-linux-amd64-v1.0.0-alpha.19.tar.gz
[paqet-update] Downloading…
[paqet-update] Extracting…
[paqet-update] New binary reports: v1.0.0-alpha.19
[paqet-update] Updated: v1.0.0-alpha.18 → v1.0.0-alpha.19
[paqet-update] Verified: /opt/paqet/paqet version = v1.0.0-alpha.19
```

## Run as a cron job

```bash
# Check for updates every day at 02:00
0 2 * * * root /opt/paqet/paqet-update.sh >> /var/log/paqet-update.log 2>&1
```

## Requirements

- `bash` ≥ 4
- `curl`
- `tar`
