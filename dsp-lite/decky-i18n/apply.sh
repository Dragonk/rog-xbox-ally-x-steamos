#!/usr/bin/env bash
# Installs the PL/EN strings into a checkout of decky-ally-dsp and rebuilds the panel.
# The Decky panel has no automatic translation: the plugin ships src/strings.ts and the
# built dist/index.js, so a locale-aware strings.ts has to be compiled into the bundle.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:-}
[ -n "$SRC" ] || { echo "usage: $0 /path/to/decky-ally-dsp" >&2; exit 1; }
[ -f "$SRC/src/strings.ts" ] || { echo "not a decky-ally-dsp checkout: $SRC" >&2; exit 1; }
cp -n "$SRC/src/strings.ts" "$SRC/src/strings.ts.orig" || true
install -m 644 "$HERE/strings.ts" "$SRC/src/strings.ts"
echo "strings.ts replaced (original kept as strings.ts.orig)"
cd "$SRC"
if command -v npm >/dev/null; then
  npm ci
  npm run build
  echo "built: dist/index.js — copy it to ~/homebrew/plugins/Ally DSP/dist/ and reload Decky"
else
  echo "npm not found: install Node.js, then run 'npm ci && npm run build' in $SRC" >&2
  exit 2
fi
