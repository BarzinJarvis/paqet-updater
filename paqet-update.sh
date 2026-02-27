#!/usr/bin/env bash
# paqet-update.sh — Auto-updater for paqet
# Repo: https://github.com/hanselime/paqet
# Usage: sudo ./paqet-update.sh [--dry-run] [--install-path /opt/paqet/paqet]

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
REPO="hanselime/paqet"
INSTALL_PATH="${INSTALL_PATH:-/opt/paqet/paqet}"
DRY_RUN=false
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# ── Flags ─────────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --install-path=*) INSTALL_PATH="${arg#*=}" ;;
  esac
done

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[paqet-update]${RESET} $*"; }
success() { echo -e "${GREEN}[paqet-update]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[paqet-update]${RESET} $*"; }
error()   { echo -e "${RED}[paqet-update]${RESET} $*" >&2; exit 1; }

# ── Detect OS / Arch ──────────────────────────────────────────────────────────
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
RAW_ARCH="$(uname -m)"

case "$RAW_ARCH" in
  x86_64)          ARCH="amd64" ;;
  aarch64|arm64)   ARCH="arm64" ;;
  armv7l|armv6l)   ARCH="arm32" ;;
  mips64le)        ARCH="mips64le" ;;
  mips64)          ARCH="mips64" ;;
  mipsle)          ARCH="mipsle" ;;
  mips)            ARCH="mips" ;;
  *) error "Unsupported architecture: $RAW_ARCH" ;;
esac

[[ "$OS" != "linux" ]] && error "Only Linux is supported (detected: $OS)"

info "System: ${BOLD}${OS}/${ARCH}${RESET} (raw: $RAW_ARCH)"

# ── Fetch latest release from GitHub ─────────────────────────────────────────
info "Fetching latest release from github.com/${REPO}…"

RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")"
LATEST_VERSION="$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\(.*\)".*/\1/')"

[[ -z "$LATEST_VERSION" ]] && error "Could not determine latest version from GitHub API"

info "Latest release: ${BOLD}${LATEST_VERSION}${RESET}"

# ── Get installed version ─────────────────────────────────────────────────────
INSTALLED_VERSION=""
if [[ -x "$INSTALL_PATH" ]]; then
  INSTALLED_VERSION="$("$INSTALL_PATH" version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*' | head -1 || true)"
  if [[ -n "$INSTALLED_VERSION" ]]; then
    info "Installed:     ${BOLD}${INSTALLED_VERSION}${RESET}"
  else
    warn "Could not parse version from: $INSTALL_PATH version"
  fi
else
  warn "paqet not found at $INSTALL_PATH — will install fresh"
fi

# ── Compare versions ──────────────────────────────────────────────────────────
# Normalise: strip leading 'v' for comparison
norm() { echo "${1#v}"; }

if [[ "$(norm "$INSTALLED_VERSION")" == "$(norm "$LATEST_VERSION")" && -n "$INSTALLED_VERSION" ]]; then
  success "Already up-to-date: ${BOLD}${INSTALLED_VERSION}${RESET} — nothing to do."
  exit 0
fi

# ── Build asset URL ───────────────────────────────────────────────────────────
ASSET_NAME="paqet-${OS}-${ARCH}-${LATEST_VERSION}.tar.gz"
ASSET_URL="$(echo "$RELEASE_JSON" | grep "browser_download_url" | grep "$ASSET_NAME" | sed 's/.*"browser_download_url": *"\(.*\)".*/\1/')"

[[ -z "$ASSET_URL" ]] && error "No asset found for ${OS}/${ARCH} in release ${LATEST_VERSION}. Expected: ${ASSET_NAME}"

info "Asset: ${ASSET_NAME}"

if $DRY_RUN; then
  warn "--dry-run: would download ${ASSET_URL}"
  warn "--dry-run: would replace ${INSTALL_PATH} with new binary"
  exit 0
fi

# ── Download ──────────────────────────────────────────────────────────────────
info "Downloading…"
curl -fSL --progress-bar "$ASSET_URL" -o "${TMPDIR_WORK}/${ASSET_NAME}"

# ── Extract ───────────────────────────────────────────────────────────────────
info "Extracting…"
tar -xzf "${TMPDIR_WORK}/${ASSET_NAME}" -C "$TMPDIR_WORK"

# Find the paqet binary inside the archive
NEW_BINARY="$(find "$TMPDIR_WORK" -type f -name "paqet" ! -name "*.tar.gz" | head -1)"
[[ -z "$NEW_BINARY" ]] && error "Could not find 'paqet' binary inside ${ASSET_NAME}"

chmod +x "$NEW_BINARY"

# ── Verify the new binary ─────────────────────────────────────────────────────
NEW_REPORTED_VERSION="$("$NEW_BINARY" version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*' | head -1 || true)"
info "New binary reports: ${BOLD}${NEW_REPORTED_VERSION:-unknown}${RESET}"

# ── Atomic replace ────────────────────────────────────────────────────────────
INSTALL_DIR="$(dirname "$INSTALL_PATH")"
mkdir -p "$INSTALL_DIR"

# Backup old binary if it exists
if [[ -f "$INSTALL_PATH" ]]; then
  cp "$INSTALL_PATH" "${INSTALL_PATH}.bak" 2>/dev/null || true
fi

# Atomic swap (mv on same filesystem is atomic)
mv "$NEW_BINARY" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

# ── Done ──────────────────────────────────────────────────────────────────────
if [[ -n "$INSTALLED_VERSION" ]]; then
  success "Updated: ${BOLD}${INSTALLED_VERSION}${RESET} → ${BOLD}${LATEST_VERSION}${RESET}"
else
  success "Installed: ${BOLD}${LATEST_VERSION}${RESET} → ${INSTALL_PATH}"
fi

# Final sanity check
FINAL_VERSION="$("$INSTALL_PATH" version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*' | head -1 || true)"
success "Verified: $INSTALL_PATH version = ${BOLD}${FINAL_VERSION:-?}${RESET}"
