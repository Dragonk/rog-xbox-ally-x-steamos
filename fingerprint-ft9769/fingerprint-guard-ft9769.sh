#!/usr/bin/env bash
# =============================================================================
#  fingerprint-guard: straznik czytnika odciskow palcow (FocalTech FT9769 ESS)
#  na ASUS ROG Xbox Ally X (RC73XA) pod SteamOS. Wzorzec: straznik paddle.
#
#  Update SteamOS wymazuje /usr (fprintd, libfprint, pam_fprintd.so, reguły
#  udev). Naprawa NIE wymaga zlotej kopii: wszystko jest w repo SteamOS
#  (holo/core/extra; pacman-key zainicjalizowany raz przy instalacji), wiec
#  straznik robi czysta reinstalacje paczek i dopilnowuje wpisow PAM.
#  Przezywa update: odciski (/var/lib/fprint), baza pacmana, klucze pacman-key,
#  wpisy PAM w /etc/pam.d, plugin Decky w /home.
#
#  v2 (13.11.2026): polkit-1 szukany takze w /usr/lib{,64}/pam.d (SteamOS nie
#  ma /etc/pam.d/polkit-1); straznik tworzy trwaly override w /etc.
#
#  v3 (13.11.2026, po pierwszym duzym update): wzmocniona kaskada reinstalacji
#  4 proby: -S -> naprawa kluczy -> -Sy (odswiezenie bazy sync; po update baza
#  lokalna i repo sie rozjezdzaja) -> SigLevel=Never na configu systemowym.
#  Dodatkowe ostrzezenie, gdy czytnik dziala, ale zniknely zapisane odciski.
#
#  Fail-safe: wpisy PAM sa typu 'sufficient' - gdyby modulu zabraklo, sudo
#  nadal dziala na haslo; straznik dodaje wpisy tylko gdy modul istnieje.
#
#  Uzycie:
#    ./fingerprint-guard.sh status              raport (bez roota)
#    sudo ./fingerprint-guard.sh run           weryfikacja + naprawa
#    sudo ./fingerprint-guard.sh install       usluga + timer systemd
#    sudo ./fingerprint-guard.sh uninstall     usuniecie uslug (dane zostaja)
# =============================================================================

set -u

GUARD_BASE="/home/deck/fingerprint-guard"
LOG_FILE="$GUARD_BASE/guard.log"
SELF_PATH="$GUARD_BASE/fingerprint-guard.sh"
UNIT_SERVICE="/etc/systemd/system/fingerprint-guard.service"
UNIT_TIMER="/etc/systemd/system/fingerprint-guard.timer"

# paczka fprintd na SteamOS lduje w lib64 (modul PAM) i lib (binarki) - sprawdzamy obie
LIBFPRINT_PATHS="/usr/lib/libfprint-2.so.2 /usr/lib64/libfprint-2.so.2"
PAMMOD_PATHS="/usr/lib/security/pam_fprintd.so /usr/lib64/security/pam_fprintd.so"
# SteamOS moze nie miec /etc/pam.d/polkit-1 (konfiguracja pakietowa lezy w /usr/lib/pam.d)
POLKIT_PAM_CANDIDATES="/usr/lib/pam.d/polkit-1 /usr/lib64/pam.d/polkit-1"

log() {
  local level="$1"; shift
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
  echo "$line"
  mkdir -p "$GUARD_BASE" 2>/dev/null || true
  echo "$line" >> "$LOG_FILE" 2>/dev/null || true
  if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 5000 ]; then
    tail -n 4000 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi
}

ro_disable() { steamos-readonly disable >/dev/null 2>&1 || true; }
ro_enable()  { steamos-readonly enable  >/dev/null 2>&1 || true; }
need_root()  { [ "$(id -u)" = "0" ] || { echo "Ta komenda wymaga roota: sudo $0 $1" >&2; exit 1; }; }

have_any() {
  local p
  for p in "$@"; do [ -e "$p" ] && return 0; done
  return 1
}

sensor_pid() {
  local d vid pid
  command -v lsusb >/dev/null 2>&1 && {
    pid="$(lsusb 2>/dev/null | grep -oE '2808:a75[38]|2808:a78a' | head -1)"
    [ -n "$pid" ] && { echo "${pid#2808:}"; return 0; }
  }
  for d in /sys/bus/usb/devices/*/; do
    [ -f "$d/idVendor" ] || continue
    vid="$(cat "$d/idVendor" 2>/dev/null)"; pid="$(cat "$d/idProduct" 2>/dev/null)"
    case "$vid:$pid" in 2808:a753|2808:a78a) echo "$pid"; return 0 ;; esac
  done
  return 1
}

# pacman z kaskada jak w fingerprint-ft9769-setup (klucze powinny byc juz ok,
# ale straznik musi dzialac tez po resecie, w ktorym cokolwiek sie psulo)
fix_keys() {
  log WARN "Pęk kluczy pacmana niegotowy; pacman-key --init/--populate..."
  pacman-key --init >> "$LOG_FILE" 2>&1 || true
  pacman-key --populate >> "$LOG_FILE" 2>&1 \
    || pacman-key --populate archlinux >> "$LOG_FILE" 2>&1 \
    || log WARN "pacman-key --populate nieudane; jesli pacman dalej pada, zobacz log."
}

# systemowy pacman.conf z wylaczona weryfikacja podpisow (zachowuje DBPath/GPGDir)
nosig_conf() {
  sed -e 's/^[[:space:]]*SigLevel[[:space:]]*=.*/SigLevel = Never/' \
      -e 's/^[[:space:]]*LocalFileSigLevel[[:space:]]*=.*/LocalFileSigLevel = Never/' \
      /etc/pacman.conf > /tmp/pacman-nosig-guard.conf 2>>"$LOG_FILE"
}

# Kaskada 4 prob: zwykle -S -> naprawa kluczy pacman-key -> odswiezenie bazy
# sync (-Sy; typowe po duzym update SteamOS) -> SigLevel=Never.
pacman_install_retry() {
  local pkg="$1"
  pacman -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>&1 && return 0
  fix_keys
  pacman -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>&1 && return 0
  log WARN "Repo dalej nie wspolpracuje; odswiezam baze sync (proba 3/4)..."
  pacman -Sy --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>&1 && return 0
  log WARN "Ostatnia proba (4/4): SigLevel=Never na configu systemowym."
  nosig_conf
  pacman --config /tmp/pacman-nosig-guard.conf -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>&1 && return 0
  return 1
}

# reinstall_pkg PKG SCIEZKA... : gdy zadna ze sciezek nie istnieje, a baza
# pacmana twierdzi, ze pakiet jest (typowy stan po update SteamOS) - usun go,
# by pacman -S zainstalowal od nowa
reinstall_pkg() {
  local pkg="$1"; shift
  if ! have_any "$@" && pacman -Qi "$pkg" >/dev/null 2>&1; then
    log WARN "$pkg w bazie pacmana, ale pliki zniknely (update SteamOS). Czyszacze -R przed reinstalacja."
    pacman -R --noconfirm "$pkg" >> "$LOG_FILE" 2>&1 || true
  fi
}

polkit_target() {
  # Zwraca sciezke pliku PAM polkit-1 do edycji. Gdy w /etc go nie ma, tworzy
  # trwaly override z pliku pakietowego (/usr ginie przy update SteamOS).
  # UWAGA: wywolane w $(...) - zadne logi na stdout (id do stderr)!
  if [ -f /etc/pam.d/polkit-1 ]; then
    echo "/etc/pam.d/polkit-1"
    return 0
  fi
  local p
  for p in $POLKIT_PAM_CANDIDATES; do
    if [ -f "$p" ]; then
      if cp -a "$p" /etc/pam.d/polkit-1 2>/dev/null; then
        log INFO "polkit: utworzony trwaly override /etc/pam.d/polkit-1 (kopia z $p)." >&2
        echo "/etc/pam.d/polkit-1"
      else
        log WARN "polkit: /etc/pam.d niedostepny do zapisu, edytuje plik pakietowy $p (zginie przy update)." >&2
        echo "$p"
      fi
      return 0
    fi
  done
  return 1
}

pam_ensure() {
  local f
  # sudo
  f=/etc/pam.d/sudo
  if [ -f "$f" ] && ! grep -q "^[^#].*pam_fprintd.so" "$f" 2>/dev/null; then
    cp -a "$f" "$f.fingerprint-guard-bak"
    sed -i "1a auth sufficient pam_fprintd.so" "$f"
    grep -q "^[^#].*pam_fprintd.so" "$f" 2>/dev/null \
      && log OK "Przywrocono wpis pam_fprintd w $f (kopia: $f.fingerprint-guard-bak)" \
      || log ERROR "Nie udalo sie dodac wpisu PAM do $f"
  fi
  # polkit (plik moze wymagać utworzenia w /etc)
  f="$(polkit_target)" || { log WARN "polkit: nie znaleziono pliku PAM polkit-1 (ani /etc/pam.d, ani $POLKIT_PAM_CANDIDATES). Pomijam polkit."; return 0; }
  if ! grep -q "^[^#].*pam_fprintd.so" "$f" 2>/dev/null; then
    cp -a "$f" "$f.fingerprint-guard-bak"
    sed -i "1a auth sufficient pam_fprintd.so" "$f"
    grep -q "^[^#].*pam_fprintd.so" "$f" 2>/dev/null \
      && log OK "Przywrocono wpis pam_fprintd w $f (kopia: $f.fingerprint-guard-bak)" \
      || log ERROR "Nie udalo sie dodac wpisu PAM do $f"
  fi
}

# --------------------------------------------------------------------------- #
cmd_run() {
  need_root run
  log INFO "--- fingerprint-guard start ---"
  local SPID
  if ! SPID="$(sensor_pid)"; then
    log ERROR "Sensor FOCAL niewidoczny na USB (BIOS/UEFI?). Nie robie nic wiecej."
    return 1
  fi

  ro_disable
  trap 'ro_enable' EXIT
  local failed=0

  # 1. fprintd (narzedzia + demon)
  if [ ! -x /usr/bin/fprintd-list ] || [ ! -x /usr/lib/fprintd ]; then
    log WARN "Brak fprintd (update wymazal /usr). Reinstalacja z repo SteamOS..."
    reinstall_pkg fprintd /usr/bin/fprintd-list /usr/lib/fprintd
    pacman_install_retry fprintd || { log ERROR "Reinstalacja fprintd nieudana (siec/repo)."; failed=1; }
  fi

  # 2. libfprint
  if ! have_any $LIBFPRINT_PATHS; then
    log WARN "Brak libfprint. Reinstalacja..."
    reinstall_pkg libfprint $LIBFPRINT_PATHS
    pacman_install_retry fprintd || log WARN "pacman nie dal rady z libfprint (sprawdzam dalej)."
    have_any $LIBFPRINT_PATHS || { log ERROR "libfprint nadal niedostepna."; failed=1; }
  fi

  # 3. modul PAM
  if ! have_any $PAMMOD_PATHS; then
    log ERROR "Brak pam_fprintd.so (powinien wrocic z fprintd). Palec w sudo/polkit nie zadziala do reinstalacji."
    failed=1
  fi

  # 4. wpisy PAM (tylko gdy modul istnieje - fail-safe dla sudo)
  if have_any $PAMMOD_PATHS; then
    pam_ensure
  else
    log WARN "Modulu PAM brak - nie ruszam wpisow (sudo i tak dziala na haslo, 'sufficient' nie blokuje)."
  fi

  systemctl daemon-reload >/dev/null 2>&1 || true

  # 5. test wykrycia sensora
  if [ "$failed" = "0" ]; then
    pkill -x fprintd 2>/dev/null || true
    sleep 1
    local out DECKUSER
    DECKUSER="${SUDO_USER:-deck}"
    out="$(fprintd-list "$DECKUSER" 2>&1)"
    echo "$out" >> "$LOG_FILE"
    if echo "$out" | grep -qiE "no devices|NoSuchDevice|Impossible"; then
      log ERROR "fprintd nie widzi sensora mimo reinstalacji. Diagnoza: fingerprint-diag.sh"
      return 1
    fi
    if echo "$out" | grep -qi "no fingers enrolled"; then
      log WARN "Czytnik dziala, ale brak zapisanych odciskow (/var/lib/fprint puste?). Enroll: sudo ./fingerprint-ft9769-setup.sh enroll"
    fi
    log OK "Czytnik gotowy: fprintd widzi sensor (2808:$SPID)."
  else
    log ERROR "Stan niedomkniony; sprobuj recznie: sudo $SELF_PATH run albo fingerprint-ft9769-setup.sh install"
    return 1
  fi
  return 0
}

# --------------------------------------------------------------------------- #
cmd_status() {
  echo "== fingerprint-guard: status =="
  echo "Sensor FOCAL:        $(SPID="$(sensor_pid)" && echo "2808:$SPID" || echo BRAK)"
  echo "fprintd narzedzia:    $([ -x /usr/bin/fprintd-list ] && echo OK || echo BRAK)"
  echo "fprintd demon:        $([ -x /usr/lib/fprintd ] && echo OK || echo BRAK)"
  echo "libfprint:            $(have_any $LIBFPRINT_PATHS && echo OK || echo BRAK)"
  echo "pam_fprintd.so:       $(have_any $PAMMOD_PATHS && echo OK || echo BRAK)"
  echo "PAM sudo:             $(grep -q '^[^#].*pam_fprintd.so' /etc/pam.d/sudo 2>/dev/null && echo 'ma wpis' || echo 'brak wpisu')"
  local PKT
  PKT="/etc/pam.d/polkit-1"
  [ -f "$PKT" ] || PKT="$(ls /usr/lib/pam.d/polkit-1 /usr/lib64/pam.d/polkit-1 2>/dev/null | head -n1)"
  if [ -n "$PKT" ] && [ -f "$PKT" ]; then
    grep -q '^[^#].*pam_fprintd.so' "$PKT" 2>/dev/null && echo "PAM polkit:           ma wpis ($PKT)" || echo "PAM polkit:           brak wpisu ($PKT)"
  else
    echo "PAM polkit:           plik nie znaleziony"
  fi
  echo "kde-fingerprint:      $([ -f /usr/lib/pam.d/kde-fingerprint ] && echo 'usluga obecna' || echo BRAK)"
  local P
  P="$(ls /home/deck/homebrew/plugins 2>/dev/null | grep -i finger | head -n1)"
  echo "Plugin Decky:         ${P:-nie znaleziono}"
  echo "Usługa systemd:       $([ -f "$UNIT_SERVICE" ] && echo OK || echo 'nie zainstalowana (sudo ./fingerprint-guard.sh install)')"
  echo "Timer:                $([ -f "$UNIT_TIMER" ] && echo OK || echo BRAK)"
  echo "Log:                  $LOG_FILE"
}

cmd_install() {
  need_root install
  mkdir -p "$GUARD_BASE"
  if [ "$(readlink -f "$0" 2>/dev/null)" != "$SELF_PATH" ]; then
    cp "$0" "$SELF_PATH" && chmod 755 "$SELF_PATH"
  fi

  cat > "$UNIT_SERVICE" <<EOF
[Unit]
Description=fingerprint-guard: straznik czytnika odciskow palcow (fprintd/FT9769)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$SELF_PATH run
EOF

  cat > "$UNIT_TIMER" <<EOF
[Unit]
Description=fingerprint-guard: cykliczna weryfikacja stosu czytnika odciskow

[Timer]
OnBootSec=2min
OnUnitActiveSec=6h
Persistent=true
Unit=fingerprint-guard.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now fingerprint-guard.timer >/dev/null 2>&1
  log OK "Instalacja uslugi fingerprint-guard (timer: 2 min po starcie, potem co 6 h)."
  echo "Zainstalowane. Raport: $SELF_PATH status; pierwszy run zaraz po starcie timera."
}

cmd_uninstall() {
  need_root uninstall
  systemctl disable --now fingerprint-guard.timer >/dev/null 2>&1 || true
  rm -f "$UNIT_SERVICE" "$UNIT_TIMER"
  systemctl daemon-reload
  log INFO "Uslugi fingerprint-guard usuniete (dane i log zostaly w $GUARD_BASE)."
  echo "Uslugi usuniete."
}

case "${1:-help}" in
  run)       cmd_run ;;
  status)    cmd_status ;;
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  help|--help|-h) sed -n '2,25p' "$0" | sed 's/^# \{0,2\}//' ;;
  *) echo "Nieznana komenda: $1" >&2; exit 1 ;;
esac
