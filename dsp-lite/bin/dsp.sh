#!/usr/bin/env bash
# Ally DSP - przelacznik i stan. Jedno zrodlo prawdy: "enabled" w ustawieniach
# pluginu Ally DSP (Decky), wiec przelacznik w Decky i ten interfejs sa zgodne.
#
# Uzycie: dsp on|off|toggle|status|json
set -u
FIX=/home/deck/ally-dsp-fix
SETTINGS="/home/deck/homebrew/settings/Ally DSP/settings.json"
PHYS=alsa_output.pci-0000_64_00.6.analog-stereo
VIRT=allydsp_in
UNIT=ally-dsp.service
export XDG_RUNTIME_DIR=/run/user/1000

# jezyk: PL gdy system po polsku, inaczej EN
case "${LANG:-}${LC_ALL:-}${LANGUAGE:-}" in
  pl*) L=pl ;;
  *)   L=en ;;
esac
t() { [ "$L" = pl ] && echo "$1" || echo "$2"; }

plugin_cli() { # $@ = argumenty CLI pluginu (enable/disable) - to samo zrodlo prawdy co Decky
  local P="/home/deck/homebrew/plugins/Ally DSP"
  ( cd "$P" && PYTHONPATH=py_modules ALLYDSP_PLUGIN_DIR="$P" DECKY_USER_HOME=/home/deck \
    DECKY_USER=deck timeout 120 python3 -m allydsp.cli "$@" >/dev/null 2>&1 )
}

set_enabled() { # $1 = true|false
  python3 - "$SETTINGS" "$1" <<'PY'
import json, os, sys
path, value = sys.argv[1], sys.argv[2] == "true"
try:
    data = json.load(open(path))
except Exception:
    data = {}
data["enabled"] = value
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2)
os.replace(tmp, path)
PY
}

get_enabled() {
  python3 -c "import json;print('true' if json.load(open('$SETTINGS')).get('enabled',True) else 'false')" 2>/dev/null || echo true
}

get_preset() { grep -o 'preset=[a-z/]*' "$FIX/render.conf" 2>/dev/null | head -1 | cut -d= -f2; }

apply() { "$FIX/apply.sh" >/dev/null 2>&1; }

case "${1:-status}" in
  on)
    set_enabled true; plugin_cli enable; apply
    echo "$(t 'Ally DSP: WŁĄCZONY' 'Ally DSP: ON')"
    ;;
  off)
    set_enabled false; plugin_cli disable; apply
    echo "$(t 'Ally DSP: WYŁĄCZONY' 'Ally DSP: OFF')"
    ;;
  toggle)
    if [ "$(get_enabled)" = "true" ]; then exec "$0" off; else exec "$0" on; fi
    ;;
  status)
    if [ "$(get_enabled)" = "true" ]; then
      echo "$(t 'Ally DSP: WŁĄCZONY' 'Ally DSP: ON')"
    else
      echo "$(t 'Ally DSP: WYŁĄCZONY' 'Ally DSP: OFF')"
    fi
    echo "  $(t 'preset' 'preset'):   $(get_preset)"
    echo "  $(t 'wyjście' 'output'):  $(pactl get-default-sink 2>/dev/null)"
    echo "  $(t 'głośność' 'volume'): $(pactl get-sink-volume $PHYS 2>/dev/null | head -1 | grep -o '[0-9]*%' | head -1)"
    ;;
  preset)
    prof="${2:-}"; voix="${3:-}"
    if [ -z "$prof" ] || [ -z "$voix" ]; then echo "uzycie: dsp preset <game|dynamic|movie|music|voice> <balanced|detailed|warm>" >&2; exit 1; fi
    P="/home/deck/homebrew/plugins/Ally DSP"
    ( cd "$P" && PYTHONPATH=py_modules ALLYDSP_PLUGIN_DIR="$P" DECKY_USER_HOME=/home/deck \
      DECKY_USER=deck timeout 120 python3 -m allydsp.cli apply "$prof" "$voix" --save >/dev/null 2>&1 )
    apply
    echo "$(t 'Preset' 'Preset'): $prof / $voix"
    ;;
  mic)
    exec /home/deck/ally-dsp-fix/mic.sh "${2:-status}"
    ;;
  json)
    en=$(get_enabled); pr=$(get_preset) || pr=""
    # "active" = lancuch zyje i jest wlaczony; routing robi sie przez przenoszenie
    # strumieni, wiec domyslny sink pozostaje fizyczny i nie jest wyznacznikiem.
    if [ "$en" = "true" ] && systemctl --user is-active --quiet "$UNIT"; then st=1; else st=0; fi
    mic=$(cat /home/deck/ally-dsp-fix/mic.state 2>/dev/null || echo on)
    printf '{"enabled":%s,"active":%s,"preset":"%s","lang":"%s","mic":"%s"}\n' \
      "$en" "$st" "${pr:-game/balanced}" "$L" "$mic"
    ;;
  *)
    echo "uzycie: dsp on|off|toggle|status|json" >&2; exit 1 ;;
esac
