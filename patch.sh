#!/usr/bin/env bash
# GitCracken Patcher — Linux / macOS
# Run from the root of this repo: ./patch.sh
# Or with a specific feature:     ./patch.sh standalone
# Or targeting a specific asar:   ./patch.sh pro /path/to/app.asar

set -euo pipefail

FEATURE="${1:-pro}"
ASAR="${2:-}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
PKG="$ROOT/GitCracken"

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

# ── Install dependencies ───────────────────────────────────────────────────────
title "Installing dependencies"
cd "$PKG"
if [ "$PM" = "yarn" ]; then
    yarn install --frozen-lockfile
else
    npm install
fi
ok "Dependencies installed"

# ── Build TypeScript ───────────────────────────────────────────────────────────
title "Building"
if [ "$PM" = "yarn" ]; then
    yarn build
else
    npm run build
fi
ok "Build complete"

# ── Run patcher ────────────────────────────────────────────────────────────────
title "Patching GitKraken (feature: $FEATURE)"

SCRIPT="$PKG/dist/bin/gitcracken.js"
if [ ! -f "$SCRIPT" ]; then
    err "Build output not found at $SCRIPT — did the build step fail?"
fi

PATCH_ARGS=("patcher" "-f" "$FEATURE")
if [ -n "$ASAR" ]; then
    info "Using custom asar: $ASAR"
    PATCH_ARGS+=("-a" "$ASAR")
else
    info "Auto-detecting GitKraken installation..."
fi

node "$SCRIPT" "${PATCH_ARGS[@]}"

printf "\n\033[32mDone! Re-launch GitKraken and re-login to apply the license.\033[0m\n"
