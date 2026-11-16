#!/usr/bin/env bash
# Przenosi strumienie aplikacji na wejscie lancucha Ally DSP.
# Domyslny sink pozostaje FIZYCZNY, wiec klawisze glosnosci i OSD Steam reguluja
# glosnosc ZA lancuchem - leveler nie kompensuje skrecenia.
export XDG_RUNTIME_DIR=/run/user/1000
IN_NODE=allydsp_in
PHYS=alsa_output.pci-0000_64_00.6.analog-stereo

while true; do
  pactl list sink-inputs 2>/dev/null | awk '
    /^Sink Input #/ { idx=substr($3,2); name=""; sink="" }
    /^\tSink: / { sink=$2 }
    /application\.name = / { name=$0 }
    /node\.name = / { name=name $0 }
    /^\tProperties:/ { inprops=1 }
    /^$/ { if (idx!="" && sink!="" ) print idx "\t" sink "\t" name; idx=""; name=""; sink="" }
  ' | while IFS=$'\t' read -r idx sink name; do
      [ "$idx" = "" ] && continue
      case "$sink" in
        *"$IN_NODE"*) continue ;;
      esac
      case "$name" in
        *allydsp_out*|*Ally*DSP*) continue ;;
      esac
      pactl move-sink-input "$idx" "$IN_NODE" 2>/dev/null
    done
  sleep 0.7
done
