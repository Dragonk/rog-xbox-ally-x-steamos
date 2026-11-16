#!/usr/bin/env bash
# Ally DSP render - utrzymuje dzialajacy lancuch Dolby bez trybu smart-filter.
#
# Dlaczego: na tym stosie (PipeWire 1.6.8 / WirePlumber 0.5.18) wdrozenie jako
# smart filter konczy sie passthrough (zmierzone: 0,00 dB w kazdym pasmie), a przy
# LV2_PATH ze spacja bez cudzyslowow graf w ogole sie nie laduje. Dlatego lancuch
# dziala jako klasyczny sink wirtualny: aplikacje -> allydsp_in -> DSP -> glosniki.
#
# Uruchamiany: przy starcie sesji (timer), po zmianie presetu (path unit) i po
# resume. Jest idempotentny: restartuje lancuch TYLKO gdy conf jest nieaktualny
# albo wezel nie zyje, zeby nie przerywac dzwieku bez potrzeby.
set -u
HOME_DIR=/home/deck
SRC="$HOME_DIR/homebrew/data/Ally DSP/active/chain.conf"
FIX="$HOME_DIR/ally-dsp-fix"
OUT="$FIX/render.conf"
TARGET=${ALLYDSP_TARGET:-alsa_output.pci-0000_64_00.6.analog-stereo}
IN_NODE=allydsp_in
OUT_NODE=allydsp_out
UNIT=ally-dsp.service
export XDG_RUNTIME_DIR=/run/user/1000

log() { echo "[$(date -Is)] $*"; }

# Jedno zrodlo prawdy: przelacznik "DSP Enabled" w pluginie Ally DSP (Decky).
# Gdy jest OFF, lancuch nie dziala i dzwiek idzie prosto na glosniki.
SETTINGS="/home/deck/homebrew/settings/Ally DSP/settings.json"
enabled=1
if [ -f "$SETTINGS" ]; then
  enabled=$(python3 -c "import json;print(1 if json.load(open('$SETTINGS')).get('enabled',True) else 0)" 2>/dev/null || echo 1)
fi
if [ "$enabled" != "1" ]; then
  systemctl --user stop ally-dsp.service 2>/dev/null
  pactl set-default-sink alsa_output.pci-0000_64_00.6.analog-stereo 2>/dev/null
  exit 0
fi

[ -f "$SRC" ] || { log "brak $SRC - nic nie robie"; exit 0; }
mkdir -p "$FIX"

stale=0
if [ ! -f "$OUT" ]; then
  stale=1
elif [ "$SRC" -nt "$OUT" ]; then
  stale=1
fi

if [ "$stale" = 1 ]; then
  python3 - "$SRC" "$OUT" "$IN_NODE" "$OUT_NODE" "$TARGET" <<'PY' || exit 1
import re, sys
src, out, in_node, out_node, sink = sys.argv[1:6]
text = open(src).read()
text = text.replace('node.name = "effect_input.ally_dsp"', f'node.name = "{in_node}"')
text = text.replace('node.name = "effect_output.ally_dsp"', f'node.name = "{out_node}"')
text = text.replace('node.link-group = "ally_dsp"', 'node.link-group = "ally_dsp_render"')
text = text.replace("filter.smart = true", "filter.smart = false")
text = re.sub(r"\n\s*filter\.smart\.target = \{.*?\}", "", text, flags=re.S)
text = text.replace(f'playback.props = {{\n                    node.name = "{out_node}"',
                    f'playback.props = {{\n                    node.name = "{out_node}"\n                    node.target = "{sink}"')
header = ("# Wygenerowane przez ~/ally-dsp-fix/apply.sh - nie edytuj recznie.\n"
          "# Zrodlo: active/chain.conf (plugin Ally DSP); roznica: brak smart-filter,\n"
          "# wlasne nazwy wezlow, jawne wyjscie na sink fizyczny.\n")
open(out, "w").write(header + text)
PY
  log "render.conf przeliczony z presetu"
fi

# (re)start tylko gdy trzeba - inaczej tylko pilnujemy linkow
if [ "$stale" = 1 ] || ! systemctl --user is-active --quiet "$UNIT"; then
  systemctl --user restart "$UNIT"
  sleep 3
fi

link_out() {
  local port
  for ch in FL FR; do
    port="output_$ch"
    pw-link "$OUT_NODE:$port" "$TARGET:playback_$ch" 2>/dev/null
  done
}

if ! pw-dump 2>/dev/null | grep -q "$OUT_NODE"; then
  log "wezel $OUT_NODE nie zyje - restart"
  systemctl --user restart "$UNIT"
  sleep 3
fi

link_out
sleep 1
if ! pw-link -l 2>/dev/null | grep -q "$TARGET:playback_FL"; then
  link_out
fi

if pactl list short sinks | grep -q "$IN_NODE"; then
  # Wejscie lancucha na 100%: skrecenie PRZED DSP leveler by skompensowal,
  # a glosnosc ma byc regulowana za lancuchem (sink fizyczny).
  pactl set-sink-volume "$IN_NODE" 100% 2>/dev/null
  pactl set-sink-mute "$IN_NODE" 0 2>/dev/null
  # Domyslny sink to GLOSNIK, nie wezel lancucha: klawisze glosnosci maja
  # dzialac za DSP (inaczej leveler kompensuje skrecenie i glosnosc "nie dziala").
  current=$(pactl get-default-sink 2>/dev/null)
  [ "$current" = "$TARGET" ] || pactl set-default-sink "$TARGET"
  log "ok: lancuch zyje, domyslny sink = $TARGET (glosnosc za DSP), wejscie = $IN_NODE"
else
  log "UWAGA: brak wezla $IN_NODE"
fi
