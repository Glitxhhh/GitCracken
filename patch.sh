#!/usr/bin/env bash
# GitCracken Patcher — Linux / macOS
# Run locally:    ./patch.sh [feature] [/path/to/app.asar]
# One-liner:      curl -sL https://raw.githubusercontent.com/Glitxhhh/GitCracken/dev/patch.sh | bash

set -euo pipefail

FEATURE="${1:-pro}"
ASAR="${2:-}"

# ── One-liner detection (curl url | bash) ──────────────────────────────────────
# When piped, BASH_SOURCE[0] is not a real file path on disk.
if [[ ! -f "${BASH_SOURCE[0]:-}" ]]; then
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    printf "\033[36mDownloading GitCracken...\033[0m\n"
    if command -v curl &>/dev/null; then
        curl -sL "https://github.com/Glitxhhh/GitCracken/archive/refs/heads/dev.tar.gz" \
            | tar -xz -C "$TMP_DIR"
    elif command -v wget &>/dev/null; then
        wget -qO- "https://github.com/Glitxhhh/GitCracken/archive/refs/heads/dev.tar.gz" \
            | tar -xz -C "$TMP_DIR"
    else
        printf "\033[31m  [!!] curl or wget required\033[0m\n"; exit 1
    fi
    REPO_DIR=$(ls -d "$TMP_DIR"/GitCracken-* | head -1)
    bash "$REPO_DIR/patch.sh" "$@"
    exit
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colour helpers ─────────────────────────────────────────────────────────────
info()  { printf "  --> %s\n" "$*"; }
ok()    { printf "\033[32m  [ok] %s\033[0m\n" "$*"; }
err()   { printf "\033[31m  [!!] %s\033[0m\n" "$*"; exit 1; }
title() { printf "\n\033[1m==> %s\033[0m\n" "$*"; }

# ── Check Node.js ──────────────────────────────────────────────────────────────
title "Checking prerequisites"
if ! command -v node &>/dev/null; then
    err "Node.js not found. Install from https://nodejs.org (v16 LTS or later)"
fi
ok "Node.js $(node --version)"

# ── Pick package manager ───────────────────────────────────────────────────────
if command -v yarn &>/dev/null; then
    PM="yarn"
    ok "Package manager: yarn"
else
    PM="npm"
    ok "Package manager: npm (yarn not found, that's fine)"
fi

# ── Smart install ──────────────────────────────────────────────────────────────
title "Installing dependencies"
cd "$ROOT"

if [ "$PM" = "yarn" ]; then
    INSTALLED_MARKER="node_modules/.yarn-integrity"
else
    INSTALLED_MARKER="node_modules/.package-lock.json"
fi

NEEDS_INSTALL=true
if [ -f "$INSTALLED_MARKER" ] && [ "package.json" -ot "$INSTALLED_MARKER" ]; then
    NEEDS_INSTALL=false
fi

if [ "$NEEDS_INSTALL" = false ]; then
    ok "Dependencies already up to date (skipping install)"
else
    if [ "$PM" = "yarn" ]; then
        yarn install --frozen-lockfile
    else
        npm install
    fi
    ok "Dependencies installed"
fi

# ── Smart build ────────────────────────────────────────────────────────────────
title "Building"
DIST_ENTRY="$ROOT/dist/bin/gitcracken.js"
NEEDS_BUILD=true
if [ -f "$DIST_ENTRY" ]; then
    if ! find "$ROOT" -name "*.ts" -not -path "*/node_modules/*" -newer "$DIST_ENTRY" | grep -q .; then
        NEEDS_BUILD=false
    fi
fi

if [ "$NEEDS_BUILD" = false ]; then
    ok "Build already up to date (skipping build)"
else
    rm -rf "$ROOT/dist"
    if [ "$PM" = "yarn" ]; then
        yarn build
    else
        node "$ROOT/node_modules/typescript/bin/tsc"
    fi
    ok "Build complete"
fi

# ── Run patcher ────────────────────────────────────────────────────────────────
title "Patching GitKraken (feature: $FEATURE)"

SCRIPT="$ROOT/dist/bin/gitcracken.js"
if [ ! -f "$SCRIPT" ]; then
    err "Build output not found at $SCRIPT — did the build step fail?"
fi

PATCH_ARGS=("patcher" "-f" "$FEATURE")
RESOLVED_ASAR=""

if [ -n "$ASAR" ]; then
    info "Using custom asar: $ASAR"
    PATCH_ARGS+=("-a" "$ASAR")
    RESOLVED_ASAR="$ASAR"
else
    info "Auto-detecting GitKraken installation..."
    # Common install paths
    for CANDIDATE in \
        "/opt/gitkraken/resources/app.asar" \
        "/usr/share/gitkraken/resources/app.asar" \
        "$HOME/.local/share/gitkraken/resources/app.asar" \
        "/Applications/GitKraken.app/Contents/Resources/app.asar"
    do
        if [ -f "$CANDIDATE" ]; then
            RESOLVED_ASAR="$CANDIDATE"
            info "Found: $RESOLVED_ASAR"
            PATCH_ARGS+=("-a" "$RESOLVED_ASAR")
            break
        fi
    done
fi

# ── Check if already patched ───────────────────────────────────────────────────
if [ -n "$RESOLVED_ASAR" ]; then
    ASAR_DIR="$(dirname "$RESOLVED_ASAR")"
    if ls "$ASAR_DIR"/app.asar.*.backup 2>/dev/null | grep -q .; then
        LATEST_BACKUP=$(ls -t "$ASAR_DIR"/app.asar.*.backup | head -1 | xargs basename)
        info "Existing patch backup found: $LATEST_BACKUP"
        if [ -t 0 ]; then
            read -rp "  --> GitKraken appears already patched. Re-patch anyway? (y/N): " resp
            if [[ ! "${resp:-}" =~ ^[yY]$ ]]; then
                printf "\nSkipping — GitKraken is already patched.\n"
                exit 0
            fi
            info "Re-patching..."
        fi
    fi
fi

node "$SCRIPT" "${PATCH_ARGS[@]}"

printf "\n\033[32mDone! Re-launch GitKraken and re-login to apply the license.\033[0m\n"
