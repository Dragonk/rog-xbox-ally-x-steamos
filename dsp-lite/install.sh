#!/usr/bin/env bash
# Ally Audio installer: audio + microphone enhancement on native PipeWire, no EasyEffects.
# Installs: scripts, systemd user units, Decky plugin, Plasma applet.
# Prerequisite: a tuning set in ~/ally-dsp-fix/presets (15 presets + ir.irs) and the
# LSP bundle in ~/ally-dsp-fix/lv2. Both are derived from the official ASUS package and
# are therefore NOT redistributed here - see README ("Where the tuning comes from").
set -euo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)
FIX="$HOME/ally-dsp-fix"
PLUGIN_SRC="$SELF/decky-plugin"
PLUGIN_DIR="$HOME/homebrew/plugins/ally-audio"

[ -d "$FIX/presets" ] || { echo "missing $FIX/presets (15 presets). See dsp-lite/README.md" >&2; exit 1; }
[ -d "$FIX/lv2/lsp-plugins.lv2" ] || { echo "missing $FIX/lv2/lsp-plugins.lv2 (LSP bundle)" >&2; exit 1; }

echo "1/5 scripts"
install -d "$FIX"
install -m 755 "$SELF/bin/apply.sh" "$SELF/bin/dsp.sh" "$SELF/bin/mic.sh" "$SELF/bin/streams.sh" "$FIX/"
install -d "$HOME/.local/bin"
ln -sf "$FIX/dsp.sh" "$HOME/.local/bin/dsp"

echo "2/5 chain unit"
install -d "$HOME/.config/systemd/user"
install -m 644 "$SELF/units/ally-dsp.service" "$HOME/.config/systemd/user/"

echo "3/5 helper units"
install -m 644 "$SELF/units/ally-dsp-apply.service" "$SELF/units/ally-dsp-apply.path" \
               "$SELF/units/ally-dsp-apply.timer" "$SELF/units/ally-dsp-mic.service" \
               "$SELF/units/ally-dsp-streams.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now ally-dsp.service ally-dsp-apply.path ally-dsp-apply.timer \
                            ally-dsp-mic.service ally-dsp-streams.service

echo "4/5 Decky plugin"
if [ -d "$HOME/homebrew/plugins" ]; then
  sudo mkdir -p "$PLUGIN_DIR/dist"
  sudo cp "$PLUGIN_SRC/plugin.json" "$PLUGIN_SRC/main.py" "$PLUGIN_DIR/"
  sudo cp "$PLUGIN_SRC/dist/index.js" "$PLUGIN_DIR/dist/"
  sudo chown -R "$USER:$USER" "$PLUGIN_DIR"
  sudo systemctl restart plugin_loader || true
else
  echo "  Decky not found, skipping (the CLI and the applet still work)"
fi

echo "5/5 Plasma applet"
if [ -d "$HOME/.local/share/plasma" ]; then
  install -d "$HOME/.local/share/plasma/plasmoids"
  cp -r "$SELF/plasma/org.deck.allydsp" "$HOME/.local/share/plasma/plasmoids/"
  systemctl --user restart plasma-plasmashell.service || true
fi

"$FIX/apply.sh" || true
echo
echo "Done. Use 'dsp on|off|status|preset <profile> <voicing>' or the Decky panel / tray applet."
