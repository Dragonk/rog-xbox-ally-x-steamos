#!/usr/bin/env bash
# =============================================================================
#  fingerprint-ft9769-setup (v7): czytnik FocalTech FT9769 ESS (2808:a78a)
#  na ASUS ROG Xbox Ally X (RC73XA) pod SteamOS.
#
#  WSPIARCIE UPSTREAM: libfprint >= 1.94.100 ma w driverze focaltech_moc
#  wpis { vid 2808, pid a78a }. Zadnych laczek ani budowania.
#
#  Zakres: instaluje fprintd (repo SteamOS ma go! core/extra/multilib sa
#  wlaczone) i ewentualnie podmienia libfprint na 1.94.100 z mirroru Arch,
#  gdy stockowa (repo daje 1.94.10) nie widzi sensora.
#
#  v4: naprawia pęk kluczy pacmana (SteamOS nie inicjalizuje pacman-key;
#  symptomy: "zestaw kluczy jest niezapisywalny", "brak wymaganego klucza").
#  Kaskada: zwykly pacman -> pacman-key --init/--populate + retry ->
#  SigLevel=Never na bazie SYSTEMOWEGO pacman.conf (zachowuje DBPath/GPGDir
#  Valve; paczki i tak ida z repo Valve/officialnego mirroru po HTTPS).
#
#  v7 (13.11.2026): PAM polkit: plik polkit-1 szukany takze w /usr/lib{,64}/pam.d
#  (SteamOS moze nie miec /etc/pam.d/polkit-1); gdy tylko istnieje wersja
#  pakietowa, setup tworzy trwaly override /etc/pam.d/polkit-1 (przezywa
#  update). reinstall_if_wiped przyjmuje wiele sciezek (lib + lib64).
#
#  Sensor = przycisk zasilania, wiec enroll/verify ida pod
#  systemd-inhibit handle-power-key.
#
#  Uzycie:
#    sudo ./fingerprint-ft9769-setup.sh install     fprintd + libfprint + test
#    sudo ./fingerprint-ft9769-setup.sh enroll      rejestracja + 2x verify + PAM/plugin
#    sudo ./fingerprint-ft9769-setup.sh status      raport
#    sudo ./fingerprint-ft9769-setup.sh uninstall   revert (odciski zostaja)
# =============================================================================

set -u

WORKDIR="/home/deck/fingerprint-ft9769"
LOG_FILE="$WORKDIR/setup.log"
MIRROR="https://geo.mirror.pkgbuild.com/extra/os/x86_64"

log() {
  local level="$1"; shift
  local line
  line="[$(date '+%H:%M:%S')] [$level] $*"
  echo "$line"
  mkdir -p "$WORKDIR" 2>/dev/null || true
  echo "$line" >> "$LOG_FILE" 2>/dev/null || true
}
die() { log ERROR "$*"; log ERROR "Przerywam. Readonly zostanie przywrocony."; exit 1; }

ro_disable() { steamos-readonly disable >/dev/null 2>&1 || true; }
ro_enable()  { steamos-readonly enable  >/dev/null 2>&1 || true; }
need_root()  { [ "$(id -u)" = "0" ] || { echo "Uruchom przez: sudo $0 $1" >&2; exit 1; }; }

# --- pacman z kaskada naprawy kluczy -----------------------------------------
# systemowy pacman.conf z wylaczona weryfikacja podpisow (zachowuje DBPath/GPGDir)
nosig_conf() {
  sed -e 's/^[[:space:]]*SigLevel[[:space:]]*=.*/SigLevel = Never/' \
      -e 's/^[[:space:]]*LocalFileSigLevel[[:space:]]*=.*/LocalFileSigLevel = Never/' \
      /etc/pacman.conf > /tmp/pacman-nosig.conf 2>>"$LOG_FILE"
}

fix_keys() {
  log WARN "Pęk kluczy pacmana niegotowy (typowe dla SteamOS). Inicjalizuje pacman-key..."
  pacman-key --init >> "$LOG_FILE" 2>&1 || log WARN "pacman-key --init zwrocil blad, ciagnej dalej."
  pacman-key --populate >> "$LOG_FILE" 2>&1 \
    || pacman-key --populate archlinux >> "$LOG_FILE" 2>&1 \
    || log WARN "pacman-key --populate nie udal sie; sprobuje SigLevel=Never."
}

# pacman_install NAZWA_PAKIETU: repo -> po naprawie kluczy -> nosig -> false
pacman_install() {
  local pkg="$1"
  pacman -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>&1 && return 0
  fix_keys
  pacman -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>&1 && return 0
  log WARN "Retry z SigLevel=Never (repo Valve/mirror Arch, HTTPS)."
  nosig_conf
  pacman --config /tmp/pacman-nosig.conf -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>&1 && return 0
  return 1
}

# pacman_u PLIK_PACZKI...: lokalne paczki (mirror) -> nosig -> false
pacman_u() {
  pacman -U --noconfirm "$@" >> "$LOG_FILE" 2>&1 && return 0
  log WARN "pacman -U z podpisami nie przeszedl; retry z SigLevel=Never."
  nosig_conf
  pacman --config /tmp/pacman-nosig.conf -U --noconfirm "$@" >> "$LOG_FILE" 2>&1 && return 0
  log ERROR "pacman -U nie udal sie. Ostatnie linie logu:"
  tail -n 20 "$LOG_FILE" 2>/dev/null | grep -v "^\[" | sed 's/^/    /'
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

mirror_fetch() {
  local pkg="$1" url
  ( cd "$WORKDIR" || return 1
    url="$(curl -s --max-time 60 "$MIRROR/" | grep -oE "href=\"$pkg-[^\"]*x86_64\.pkg\.tar\.zst\"" | head -n1 | cut -d'"' -f2)"
    [ -n "$url" ] || { echo "brak $pkg na liscie mirroru" >> "$LOG_FILE"; return 1; }
    curl -sO --max-time 180 "$MIRROR/$url" || return 1
    echo "$WORKDIR/$url"
  )
}

device_visible() {
  local out
  out="$(fprintd-list "$1" 2>&1)"
  echo "$out"
  echo "$out" | grep -qiE "no devices|NoSuchDevice|Impossible" && return 1
  echo "$out" | grep -qi "Fingerprint\|Fprint" && return 0
  return 1
}

# --------------------------------------------------------------------------- #
cmd_install() {
  need_root install
  echo "== fingerprint-ft9769-setup: install (v7) =="
  [ "$(uname -m)" = "x86_64" ] || die "Tylko x86_64."
  local SPID
  SPID="$(sensor_pid)" || die "Nie widze sensora FOCAL (2808:a753/a78a) na USB."
  log OK "Sensor FOCAL 2808:$SPID widoczny (FT9769 ESS, driver focaltech_moc w libfprint >= 1.94.100)."
  ro_disable
  trap 'ro_enable' EXIT
  mkdir -p "$WORKDIR"

  # --- 1. fprintd -----------------------------------------------------------
  # uwaga: paczka fprintd NIE ma pliku /usr/bin/fprintd: demon to /usr/lib/fprintd
  # (dbus-activated), narzedzia to /usr/bin/fprintd-list, -enroll, -verify
  if [ ! -x /usr/bin/fprintd-list ]; then
    reinstall_if_wiped fprintd /usr/lib/fprintd /usr/bin/fprintd-list /usr/lib64/security/pam_fprintd.so /usr/lib/security/pam_fprintd.so
    reinstall_if_wiped libfprint /usr/lib/libfprint-2.so.2 /usr/lib64/libfprint-2.so.2
    log INFO "Instalacja fprintd (repo SteamOS ma core/extra/multilib; w razie czego naprawiam klucze)..."
    if pacman_install fprintd; then
      log OK "fprintd zainstalowany z repo SteamOS."
    else
      log WARN "Repo nie dalo rady, biore paczke fprintd z mirroru Arch."
      local P
      P="$(mirror_fetch fprintd)" || die "Nie udalo sie pobrac fprintd z mirroru."
      pacman_u "$P" || die "Instalacja fprintd nie udala sie (log: $LOG_FILE)."
    fi
  else
    log INFO "fprintd juz zainstalowany."
  fi
  [ -x /usr/bin/fprintd-list ] || die "Narzedzia fprintd (fprintd-list) niedostepne."
  [ -x /usr/lib/fprintd ] && log OK "Demon fprintd: /usr/lib/fprintd (dbus-activated)." \
    || log WARN "Demon /usr/lib/fprintd nie znaleziony (sprawdz log)."
  local M
  M="$(ls /usr/lib/security/pam_fprintd.so /usr/lib64/security/pam_fprintd.so 2>/dev/null | head -n1)"
  [ -n "$M" ] && log OK "Modul PAM: $M" || log WARN "pam_fprintd.so nie znaleziony (PAM bedzie nieaktywne)."
  systemctl daemon-reload >/dev/null 2>&1 || true

  # --- 2. test: czy widziana libfprint ma a78a -------------------------------
  pkill -x fprintd 2>/dev/null || true
  sleep 1
  local DECKUSER
  DECKUSER="${SUDO_USER:-deck}"
  log INFO "Test wykrycia sensora przez fprintd..."
  echo "--- fprintd-list $DECKUSER ---"
  if device_visible "$DECKUSER"; then
    log OK "Sensor widziany przez fprintd. Obecna libfprint wystarcza."
    echo "Wykryto. Nastepny krok: sudo $0 enroll"
    return 0
  fi
  log INFO "Nie wykryto (repo SteamOS daje libfprint 1.94.10, bez a78a). Podmieniam na 1.94.100 z mirroru Arch."

  # --- 3. libfprint 1.94.100 z mirroru --------------------------------------
  local P2
  P2="$(mirror_fetch libfprint)" || die "Nie udalo sie pobrac libfprint z mirroru."
  log INFO "Pobrane: $(basename "$P2")"
  pacman_u "$P2" || die "Podmiana libfprint nie udala sie (log: $LOG_FILE)."
  ldconfig || true
  pkill -x fprintd 2>/dev/null || true
  sleep 1
  echo "--- fprintd-list $DECKUSER (po podmianie) ---"
  if device_visible "$DECKUSER"; then
    log OK "Sensor widziany przez fprintd (libfprint 1.94.100, focaltech_moc)."
    echo "Wykryto. Nastepny krok: sudo $0 enroll"
    return 0
  fi
  die "fprintd nadal nie widzi sensora - wklej caly log: $LOG_FILE"
}

# --------------------------------------------------------------------------- #
polkit_target() {
  # Zwraca sciezke pliku PAM polkit-1 do edycji. Gdy w /etc go nie ma, tworzy
  # trwaly override z pliku pakietowego (/usr ginie przy update SteamOS).
  # UWAGA: wywolane w $(...) - zadne logi na stdout (id do stderr)!
  if [ -f /etc/pam.d/polkit-1 ]; then
    echo "/etc/pam.d/polkit-1"
    return 0
  fi
  local p
  for p in /usr/lib/pam.d/polkit-1 /usr/lib64/pam.d/polkit-1; do
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

pam_add() {
  local f
  # sudo
  f=/etc/pam.d/sudo
  if [ -f "$f" ] && ! grep -q "^[^#].*pam_fprintd.so" "$f" 2>/dev/null; then
    cp -a "$f" "$f.pre-ft9769"
    sed -i "1a auth sufficient pam_fprintd.so" "$f"
    grep -q "^[^#].*pam_fprintd.so" "$f" 2>/dev/null && log OK "PAM: $f (kopia zapasowa: $f.pre-ft9769)"
  fi
  # polkit (plik moze wymagac utworzenia w /etc)
  f="$(polkit_target)" || { log WARN "polkit: nie znaleziono pliku PAM polkit-1 (ani /etc/pam.d, ani /usr/lib{,64}/pam.d). Pomijam polkit."; return 0; }
  if ! grep -q "^[^#].*pam_fprintd.so" "$f" 2>/dev/null; then
    cp -a "$f" "$f.pre-ft9769"
    sed -i "1a auth sufficient pam_fprintd.so" "$f"
    grep -q "^[^#].*pam_fprintd.so" "$f" 2>/dev/null && log OK "PAM: $f (kopia zapasowa: $f.pre-ft9769)"
  fi
  [ -f /usr/lib/pam.d/kde-fingerprint ] \
    && log OK "Usługa PAM kde-fingerprint jest w systemie (ekran blokady KDE bedzie oferowal palec)."
}

# --------------------------------------------------------------------------- #
install_plugin() {
  local DECKUSER="${SUDO_USER:-deck}"
  if [ ! -d "/home/$DECKUSER/homebrew/plugins" ]; then
    log ERROR "Nie widze /home/$DECKUSER/homebrew/plugins - Decky Loader zainstalowany?"
    return 1
  fi
  curl -sL --max-time 120 -o "$WORKDIR/plugin.tar.gz" \
    "https://github.com/FlightDan/FingerprintUnlock-SteamOS/archive/refs/heads/main.tar.gz" \
    && rm -rf "$WORKDIR/FingerprintUnlock-SteamOS" \
    && mkdir -p "$WORKDIR/FingerprintUnlock-SteamOS" \
    && tar -xzf "$WORKDIR/plugin.tar.gz" -C "$WORKDIR/FingerprintUnlock-SteamOS" --strip-components=1 \
    && ( cd "$WORKDIR/FingerprintUnlock-SteamOS" && sh install.sh >> "$LOG_FILE" 2>&1 ) \
    && log OK "Plugin Decky FingerprintUnlock zainstalowany (przelacznik w menu Decky w game mode)." \
    || { echo "Instalacja pluginu nieudana (log: $LOG_FILE)."; return 1; }
  return 0
}

cmd_plugin() {
  need_root plugin
  echo "== fingerprint-ft9769-setup: plugin =="
  install_plugin || echo "Sprawdz Decky Loader (getdecky.xyz) i sprobuj ponownie."
}

# reinstall po update SteamOS: pliki w /usr znikaja, ale baza pacmana (w /var)
# nadal twierdzi, ze pakiet jest. Wtedy: -R i fresh install.
reinstall_if_wiped() {
  # przyjmuje wiele sciezek; reinstaluje tylko gdy ZADNA nie istnieje
  local pkg="$1"; shift
  local p found=1
  for p in "$@"; do [ -e "$p" ] && found=0; done
  if [ "$found" = "1" ] && pacman -Qi "$pkg" >/dev/null 2>&1; then
    log WARN "$pkg w bazie pacmana, ale brak plikow ($*) (update SteamOS wymazal /usr). Reinstalacja."
    pacman -R --noconfirm "$pkg" >> "$LOG_FILE" 2>&1 || true
  fi
}

cmd_enroll() {
  need_root enroll
  echo "== fingerprint-ft9769-setup: enroll =="
  [ -x /usr/bin/fprintd-list ] || { echo "Najpierw: sudo $0 install" >&2; exit 1; }
  local DECKUSER="${SUDO_USER:-deck}"

  echo "Sensor to PRZYCISK ZASILANIA. W trakcie enroll/verify wstrzymuje obsluge power-key."
  echo "---- fprintd-enroll ----"
  systemd-inhibit --what=handle-power-key --mode=block fprintd-enroll "$DECKUSER" || die "Enroll nieudany."
  echo "---- fprintd-verify (1/2) ----"
  systemd-inhibit --what=handle-power-key --mode=block fprintd-verify "$DECKUSER" || die "Verify 1 nieudany."
  echo "---- fprintd-verify (2/2) ----"
  systemd-inhibit --what=handle-power-key --mode=block fprintd-verify "$DECKUSER" || die "Verify 2 nieudany."
  log OK "Enroll + 2x verify OK."

  local M ANS
  M="$(ls /usr/lib/security/pam_fprintd.so /usr/lib64/security/pam_fprintd.so 2>/dev/null | head -n1)"
  if [ -n "$M" ]; then
    read -r -p "Podpiac palec do sudo/polkit (wpis 'sufficient', haslo zawsze zostaje)? [t/N] " ANS
    case "$ANS" in [tT]*) pam_add ;; *) echo "Pominieto PAM."; ;; esac
  else
    echo "pam_fprintd.so niedostepny, pomijam PAM."
  fi

  read -r -p "Zainstalowac plugin Decky (game mode, FlightDan)? [t/N] " ANS
  case "$ANS" in
    [tT]*) install_plugin || echo "Sprawdz Decky Loader (getdecky.xyz) i: sudo $0 plugin" ;;
    *) echo "Pominieto plugin (pozniej: sudo $0 plugin)." ;;
  esac
  echo "Gotowe. W game mode: menu Decky (...) -> Fingerprint Unlock."
}

# --------------------------------------------------------------------------- #
cmd_uninstall() {
  need_root uninstall
  echo "== fingerprint-ft9769-setup: uninstall =="
  ro_disable
  trap 'ro_enable' EXIT
  local f
  for f in /etc/pam.d/sudo /etc/pam.d/polkit-1; do
    [ -f "$f.pre-ft9769" ] && cp -a "$f.pre-ft9769" "$f" && log INFO "PAM przywrocony: $f"
  done
  sed -i '/pam_fprintd.so/d' /etc/pam.d/sudo /etc/pam.d/polkit-1 /usr/lib/pam.d/polkit-1 /usr/lib64/pam.d/polkit-1 2>/dev/null || true
  [ -f /etc/pam.d/polkit-1 ] && ! ls /usr/lib/pam.d/polkit-1 /usr/lib64/pam.d/polkit-1 >/dev/null 2>&1 && log INFO "/etc/pam.d/polkit-1 to nadpis stworzony przez setup (mozesz usunac)."
  pkill -x fprintd 2>/dev/null || true
  pacman -R --noconfirm fprintd >> "$LOG_FILE" 2>&1 || log WARN "pacman -R fprintd pominiety."
  log INFO "libfprint 1.94.100 zostaje (nieszkodliwa; update SteamOS i tak przywroci stock)."
  log OK "Revert zakonczony. Odciski zostaly w /var/lib/fprint (usun: sudo rm -rf /var/lib/fprint)."
}

cmd_status() {
  echo "== fingerprint-ft9769-setup: status =="
  echo "Sensor FOCAL:            $(SPID="$(sensor_pid)" && echo "2808:$SPID" || echo BRAK)"
  echo "fprintd:                  $(command -v fprintd-list >/dev/null 2>&1 && echo "narzedzia OK ($(command -v fprintd-list))" || echo BRAK) $([ -x /usr/lib/fprintd ] && echo '| demon OK' || echo '| demon BRAK')"
  echo "pam_fprintd.so:           $(ls /usr/lib/security/pam_fprintd.so /usr/lib64/security/pam_fprintd.so 2>/dev/null | head -n1 || echo BRAK)"
  echo "libfprint (widziana):     $(ldconfig -p 2>/dev/null | grep -m1 'libfprint-2.so.2' | awk '{print $NF}')"
  echo "PAM sudo:                 $(grep -q '^[^#].*pam_fprintd.so' /etc/pam.d/sudo 2>/dev/null && echo 'ma wpis' || echo 'brak wpisu')"
  local PKT
  PKT="/etc/pam.d/polkit-1"
  [ -f "$PKT" ] || PKT="$(ls /usr/lib/pam.d/polkit-1 /usr/lib64/pam.d/polkit-1 2>/dev/null | head -n1)"
  if [ -n "$PKT" ] && [ -f "$PKT" ]; then
    grep -q '^[^#].*pam_fprintd.so' "$PKT" 2>/dev/null && echo "PAM polkit:               ma wpis ($PKT)" || echo "PAM polkit:               brak wpisu ($PKT)"
  else
    echo "PAM polkit:               plik nie znaleziony"
  fi
  echo "Odciski (/var/lib/fprint):$([ -d /var/lib/fprint ] && echo sa || echo brak)"
  echo "Log:                      $LOG_FILE"
}

case "${1:-help}" in
  install)   cmd_install ;;
  enroll)    cmd_enroll ;;
  plugin)    cmd_plugin ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  help|--help|-h) sed -n '2,27p' "$0" | sed 's/^# \{0,2\}//' ;;
  *) echo "Nieznana komenda: $1" >&2; exit 1 ;;
esac
