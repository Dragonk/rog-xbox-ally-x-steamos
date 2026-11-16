#!/usr/bin/env bash
# Mikrofon: WebRTC noise suppression + AGC + high-pass (modul echo-cancel).
# Stan trzymany w mic.state, zeby przetrwal restart i aktualizacje.
set -u
FIX=/home/deck/ally-dsp-fix
STATE="$FIX/mic.state"
export XDG_RUNTIME_DIR=/run/user/1000
RAW_SRC=alsa_loopback_device.alsa_input.pci-0000_64_00.6.analog-stereo

loaded() { pactl list short modules 2>/dev/null | grep -q module-echo-cancel; }

mic_on() {
  echo on > "$STATE"
  if ! loaded; then
    pactl load-module module-echo-cancel source_name=AllyMic aec_method=webrtc \
      "aec_args=noise_suppression=1 digital_gain_control=1 high_pass_filter=1" >/dev/null 2>&1
    sleep 1
  fi
  pactl set-default-source AllyMic 2>/dev/null
  echo "MIC: ON  (WebRTC NS + AGC + high-pass, zrodlo: AllyMic)"
}

mic_off() {
  echo off > "$STATE"
  for m in $(pactl list short modules 2>/dev/null | awk '/module-echo-cancel/ {print $1}'); do
    pactl unload-module "$m" 2>/dev/null
  done
  pactl set-default-source "$RAW_SRC" 2>/dev/null
  echo "MIC: OFF (surowy mikrofon)"
}

case "${1:-status}" in
  on) mic_on ;;
  off) mic_off ;;
  apply) [ "$(cat "$STATE" 2>/dev/null || echo on)" = "on" ] && mic_on || mic_off ;;
  status)
    echo "  stan:   $(cat "$STATE" 2>/dev/null || echo on)"
    echo "  modul:  $(loaded && echo zaladowany || echo brak)"
    echo "  domyslne zrodlo: $(pactl get-default-source 2>/dev/null)"
    ;;
  *) echo "uzycie: mic.sh on|off|apply|status" >&2; exit 1 ;;
esac
