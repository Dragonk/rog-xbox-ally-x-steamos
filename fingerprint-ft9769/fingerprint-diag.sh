#!/usr/bin/env bash
# =============================================================================
#  fingerprint-diag: diagnostyka czytnika linii papilarnych na SteamOS
#  (ASUS ROG Xbox Ally X / RC73XA, ale zadzial tez na innych handheldach).
#
#  Calkowicie bezpieczny: TYLKO odczyt, nic nie instaluje ani nie zmienia.
#  Uruchomienie: ./fingerprint-diag.sh          (bez roota, sekcja dmesg moze byc pusta)
#               sudo ./fingerprint-diag.sh      (pelny dmesg)
#  Na koncu wklej CALY raport z powrotem do Vibego.
# =============================================================================

echo "== fingerprint-diag: diagnostyka czytnika =="
echo "Data: $(date '+%Y-%m-%d %H:%M:%S')"

echo "-- 1. Sprzet"
echo "Produkt:      $(cat /sys/class/dmi/id/product_name 2>/dev/null) ($(cat /sys/class/dmi/id/product_version 2>/dev/null))"
echo "BIOS:         $(cat /sys/class/dmi/id/bios_version 2>/dev/null) ($(cat /sys/class/dmi/id/bios_date 2>/dev/null))"
echo "Kernel:       $(uname -r)"
echo "Arch:         $(uname -m)"

echo "-- 2. lsusb"
if command -v lsusb >/dev/null 2>&1; then
  lsusb 2>&1
else
  echo "UWAGA: brak polecenia lsusb w systemie (usbutils nie zainstalowane)."
  echo "To nie znaczy, ze sensora nie ma - patrz skan /sys nizej."
fi

echo "-- 3. Inwentarz USB z /sys (vid:pid | opis)"
for d in /sys/bus/usb/devices/*/; do
  [ -f "$d/idVendor" ] || continue
  vid="$(cat "$d/idVendor" 2>/dev/null)"
  pid="$(cat "$d/idProduct" 2>/dev/null)"
  prod=""
  [ -f "$d/product" ] && prod="$(cat "$d/product" 2>/dev/null)"
  man=""
  [ -f "$d/manufacturer" ] && man="$(cat "$d/manufacturer" 2>/dev/null)"
  printf '%s:%s  %s  %s\n' "$vid" "$pid" "$man" "$prod"
done

echo "-- 4. Szukanie sensorow odciskow palcow"
found=0
for d in /sys/bus/usb/devices/*/; do
  [ -f "$d/idVendor" ] || continue
  vid="$(cat "$d/idVendor" 2>/dev/null)"
  pid="$(cat "$d/idProduct" 2>/dev/null)"
  case "$vid:$pid" in
    1c7a:*) echo "EGIS/LighTuning: $vid:$pid ($d)"; found=1 ;;
    06cb:*|138a:*) echo "SYNAPTICS/Validity: $vid:$pid ($d)"; found=1 ;;
    04f3:*) echo "ELAN: $vid:$pid ($d) - moze byc touchpad, sprawdz opis"; found=1 ;;
    2808:*) echo "FOCALTECH: $vid:$pid ($d)"; found=1 ;;
  esac
done
if [ "$found" = "0" ]; then
  echo "Na szynie USB nie widze zadnego znanego vendora sensorow odciskow."
fi

echo "-- 5. dmesg (wpisy o czytniku)"
if dmesg >/dev/null 2>&1; then
  dmesg | grep -iE "1c7a|finger|fprint|egismoc|ft9[0-9]|touchpower" | tail -n 20
  echo "(koniec wpisow dmesg; puste = brak innych niz powyzsze)"
else
  echo "dmesg niedostepny bez uprawnien. Uruchom: sudo ./fingerprint-diag.sh"
fi

echo "-- 6. Istniejacy stack fprint (jesli byl wczesniej instalowany)"
command -v fprintd >/dev/null 2>&1 && echo "fprintd: $(command -v fprintd)" || echo "fprintd: brak w PATH"
[ -f /usr/lib64/libfprint-2.so.2 ] && echo "libfprint system: $(ls /usr/lib64/libfprint-2.so.2 2>/dev/null) (sdcp: $(strings /usr/lib64/libfprint-2.so.2 2>/dev/null | grep -ci sdcp))"
[ -f /usr/local/lib/libfprint-2.so.2 ] && echo "libfprint /usr/local: jest (sdcp: $(strings /usr/local/lib/libfprint-2.so.2 2>/dev/null | grep -ci sdcp))"
[ -d /var/lib/fprint ] && echo "Rejestracja: katalog /var/lib/fprint istnieje" || echo "Rejestracja: brak /var/lib/fprint"

echo "== KONIEC RAPORTU: wklej caly ponizej do Vibego =="

