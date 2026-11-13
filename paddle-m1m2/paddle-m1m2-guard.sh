#!/usr/bin/env bash
# =============================================================================
#  paddle-m1m2-guard: strażnik tylnych przycisków (paddles M1/M2) na SteamOS
#  Urządzenie: ASUS ROG Xbox Ally X (RC73XA)
#
#  Paddle M1/M2 potrzebują InputPlumbera >= 0.79 (pierwsza wersja z mapowaniem
#  RC73XA), a stock SteamOS 3.9.x ma 0.78.0. Dlatego InputPlumber 0.83.1
#  siedzi jako overlay systemd-sysext nakładany na /usr przy boocie.
#
#  Po dużym update SteamOS (11.2026) paddle padły z trzech powodów, które
#  ten strażnik pilnuje:
#   1. nowy systemd skanuje /var/lib/extensions (oraz /etc/extensions,
#      /run/extensions, /var/lib/extensions.mutable), a NIE już starego
#      /var/lib/extensions.systemd: sysext trzeba przenieść,
#   2. plik release jest szukany w usr/lib/extension-release.d/ (ścieżka
#      upstream), a sama pakietowa ścieżka usr/lib/extensions/systemd/
#      extension-release.d/ już nie wystarcza,
#   3. release musi zawierać ID i VERSION_ID zgodne z /etc/os-release hosta
#      (po każdym update VERSION_ID hosta się zmienia, więc strażnik
#      przepisuje plik release przy każdym uruchomieniu).
#
#  Naprawa jest w pełni offline: sysext żyje w /var (przeżywa update SteamOS),
#  strażnik tylko dopasowuje metadatę, robi merge i przywraca usługę.
#
#  Fail-safe: nic nie instaluje z sieci; gdy sysextu brak, loguje błąd
#  i wychodzi bez ruszania systemu.
#
#  Użycie:
#    ./paddle-m1m2-guard.sh status            raport (bez roota)
#    sudo ./paddle-m1m2-guard.sh run          weryfikacja + naprawa
#    sudo ./paddle-m1m2-guard.sh install      usługa + timer systemd
#    sudo ./paddle-m1m2-guard.sh uninstall    usunięcie usług (sysext zostaje)
# =============================================================================

set -u

GUARD_BASE="/home/deck/paddle-m1m2-guard"
LOG_FILE="$GUARD_BASE/guard.log"
SELF_PATH="$GUARD_BASE/paddle-m1m2-guard.sh"
UNIT_SERVICE="/etc/systemd/system/paddle-m1m2-guard.service"
UNIT_TIMER="/etc/systemd/system/paddle-m1m2-guard.timer"

EXT_NAME="inputplumber"
EXT_ROOT="/var/lib/extensions"
EXT_LEGACY_ROOT="/var/lib/extensions.systemd"
EXT_PRIMARY="$EXT_ROOT/$EXT_NAME"
EXT_LEGACY="$EXT_LEGACY_ROOT/$EXT_NAME"
EXT_USER="/home/deck/.var/lib/extensions/$EXT_NAME"
EXT_RELEASE_SUB="usr/lib/extension-release.d/extension-release.$EXT_NAME"
BIN_MERGED="/usr/bin/$EXT_NAME"
STOCK_DB_DIR="/usr/lib/holo/pacmandb/local"
OS_RELEASE="/etc/os-release"
GOLDEN_VERSION="0.79"

# Tryb mock (testy E2E): nadpisuje ścieżki katalogiem testowym ze zmiennej MOCK.
if [ -n "${MOCK:-}" ]; then
  EXT_ROOT="$MOCK/var/lib/extensions"
  EXT_LEGACY_ROOT="$MOCK/var/lib/extensions.systemd"
  EXT_PRIMARY="$EXT_ROOT/$EXT_NAME"
  EXT_LEGACY="$EXT_LEGACY_ROOT/$EXT_NAME"
  EXT_USER="$MOCK/home/deck/.var/lib/extensions/$EXT_NAME"
  BIN_MERGED="$MOCK/usr/bin/$EXT_NAME"
  STOCK_DB_DIR="$MOCK/usr/lib/holo/pacmandb/local"
  OS_RELEASE="$MOCK/etc/os-release"
  GUARD_BASE="$MOCK/home/deck/paddle-m1m2-guard"
  LOG_FILE="$GUARD_BASE/guard.log"
  SELF_PATH="$GUARD_BASE/paddle-m1m2-guard.sh"
  UNIT_SERVICE="$MOCK/etc/systemd/system/paddle-m1m2-guard.service"
  UNIT_TIMER="$MOCK/etc/systemd/system/paddle-m1m2-guard.timer"
fi

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

need_root() { [ "$(id -u)" = "0" ] || { echo "Ta komenda wymaga roota: sudo $0 $1" >&2; exit 1; }; }

ip_version() {
  local p="$1"
  [ -x "$p" ] || return 0
  "$p" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1
}

ver_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, xa, "."); nb = split(b, xb, ".");
    if (na < nb) for (i = na+1; i <= nb; i++) xa[i] = 0;
    if (nb < na) for (i = nb+1; i <= na; i++) xb[i] = 0;
    n = (na > nb) ? na : nb;
    for (i = 1; i <= n; i++) {
      if ((xa[i]+0) > (xb[i]+0)) exit 0;
      if ((xa[i]+0) < (xb[i]+0)) exit 1;
    }
    exit 0
  }'
}

host_version_id() {
  grep -h '^VERSION_ID=' "$OS_RELEASE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'
}

stock_version() {
  local d
  d="$(ls "$STOCK_DB_DIR" 2>/dev/null | grep -m1 "^${EXT_NAME}-[0-9]")"
  [ -n "$d" ] || return 0
  echo "$d" | sed "s/^${EXT_NAME}-//; s/-[^-]*\$//"
}

ensure_release() {
  local ext_dir="$1" vid r
  vid="$(host_version_id)"
  if [ -z "$vid" ]; then
    log WARN "Brak VERSION_ID w $OS_RELEASE; nie przepisuję pliku release."
    return 1
  fi
  r="$ext_dir/$EXT_RELEASE_SUB"
  mkdir -p "$ext_dir/usr/lib/extension-release.d" 2>/dev/null || { log ERROR "Nie mogę utworzyć katalogu release w $ext_dir."; return 1; }
  printf 'ID=steamos\nVERSION_ID=%s\n' "$vid" > "$r"
  log OK "Release zgodny z hostem ($r: ID=steamos, VERSION_ID=$vid)."
}

ensure_locations() {
  if [ ! -d "$EXT_PRIMARY" ] && [ -d "$EXT_LEGACY" ]; then
    mkdir -p "$EXT_ROOT" 2>/dev/null || true
    if mv "$EXT_LEGACY" "$EXT_PRIMARY" 2>> "$LOG_FILE"; then
      log OK "Przeniesiono sysext z $EXT_LEGACY do $EXT_PRIMARY (nowy systemd skanuje tylko /var/lib/extensions)."
    else
      log ERROR "Nie udało się przenieść $EXT_LEGACY do $EXT_PRIMARY."
      return 1
    fi
  fi
  if [ ! -d "$EXT_PRIMARY" ] && [ -d "$EXT_USER" ]; then
    mkdir -p "$EXT_ROOT" 2>/dev/null || true
    if cp -a "$EXT_USER" "$EXT_PRIMARY" 2>> "$LOG_FILE"; then
      log OK "Odtworzono sysext z kopii $EXT_USER (kopia, nie ruszam katalogu OpenGamepadUI)."
    else
      log ERROR "Nie udało się skopiować sysext z $EXT_USER."
      return 1
    fi
  fi
}

# --------------------------------------------------------------------------- #
cmd_run() {
  need_root run
  log INFO "--- paddle-m1m2-guard start ---"
  ensure_locations
  if [ ! -d "$EXT_PRIMARY" ]; then
    log ERROR "Brak sysext inputplumber ($EXT_PRIMARY ani kopii w $EXT_LEGACY_ROOT / ~/.var). Offline nie da się odtworzyć; patrz README (procedura pastaq)."
    return 1
  fi

  local want cur merged_now=0 d stock
  want="$(ip_version "$EXT_PRIMARY/usr/bin/$EXT_NAME")"
  if [ -z "$want" ]; then
    log ERROR "Sysext uszkodzony: brak działającej binarki $EXT_PRIMARY/usr/bin/$EXT_NAME."
    return 1
  fi
  if ! ver_ge "$want" "$GOLDEN_VERSION"; then
    log WARN "Sysext $want < $GOLDEN_VERSION (mapowanie paddle pod znakiem zapytania). Kontynuuje."
  fi

  # 1. release zgodny z bieżącym os-release (samonaprawa po zmianie VERSION_ID)
  for d in "$EXT_PRIMARY" "$EXT_USER" "$EXT_LEGACY"; do
    [ -d "$d" ] && ensure_release "$d"
  done

  # 2. merge, gdy w /usr siedzi nie nasza wersja
  cur="$(ip_version "$BIN_MERGED")"
  if [ "$cur" != "$want" ]; then
    log WARN "/usr/bin/$EXT_NAME to ${cur:-nic}, sysext ma $want: robię merge."
    systemd-sysext merge >> "$LOG_FILE" 2>&1
    cur="$(ip_version "$BIN_MERGED")"
    if [ "$cur" = "$want" ]; then
      merged_now=1
      log OK "Merge OK: $EXT_NAME $want na /usr."
    else
      log ERROR "Merge nieudany mimo zgodnego release. Debug ręcznie: SYSTEMD_LOG_LEVEL=debug systemd-sysext merge"
      return 1
    fi
  fi

  # 3. po merge plik unita inputplumbera na dysku mógł się zmienić
  if [ "$merged_now" = "1" ]; then
    systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  fi

  # 4. restart usługi tylko gdy coś się zmieniło albo nie działa (nie ruszam w trakcie gry bez powodu)
  if [ "$merged_now" = "1" ] || ! systemctl is-active --quiet inputplumber.service; then
    systemctl restart inputplumber.service >> "$LOG_FILE" 2>&1 \
      && log OK "Usługa inputplumber zrestartowana (działa $want)." \
      || { log ERROR "Restart inputplumber nieudany."; return 1; }
  fi

  # 5. obserwacja: czy Valve dogoniło stock (wówczas sysext zaczyna maskować nowszy stock)
  stock="$(stock_version)"
  if [ -n "$stock" ] && ver_ge "$stock" "$GOLDEN_VERSION"; then
    log WARN "Stock inputplumber=$stock >= $GOLDEN_VERSION: sysext nie jest już niezbędny i może maskować nowszy stock. Rozważ: uninstall + rm -rf $EXT_PRIMARY + systemd-sysext unmerge (lub reboot)."
  fi

  log OK "Paddle stack gotowy: inputplumber $want."
  return 0
}

# --------------------------------------------------------------------------- #
cmd_status() {
  local want cur stock
  want="$(ip_version "$EXT_PRIMARY/usr/bin/$EXT_NAME")"
  cur="$(ip_version "$BIN_MERGED")"
  stock="$(stock_version)"
  echo "== paddle-m1m2-guard: status =="
  echo "Sysext:                $EXT_PRIMARY: ${want:-BRAK}"
  echo "  kopia legacy:        $([ -d "$EXT_LEGACY" ] && echo obecna || echo brak) ($EXT_LEGACY)"
  echo "  kopia ~/.var:       $([ -d "$EXT_USER" ] && echo obecna || echo brak) ($EXT_USER)"
  if [ -n "$want" ]; then
    [ "$cur" = "$want" ] && echo "Merge do /usr:         OK ($cur)" || echo "Merge do /usr:         BRAK (/usr ma ${cur:-nic}, sysext ma $want)"
  else
    echo "Merge do /usr:         brak sysext do oceny"
  fi
  echo "Stock (pacmandb):      ${stock:-?}"
  echo "Wymagane (paddle RC73XA): >= $GOLDEN_VERSION"
  echo "Release sysext:        $(tr '\n' ' ' < "$EXT_PRIMARY/$EXT_RELEASE_SUB" 2>/dev/null || echo brak)"
  echo "Host VERSION_ID:       $(host_version_id || echo brak) ($OS_RELEASE)"
  echo "Usługa inputplumber:   $(systemctl is-active inputplumber.service 2>/dev/null)"
  echo "Usługa guarda:         $([ -f "$UNIT_SERVICE" ] && echo OK || echo "nie zainstalowana (sudo $SELF_PATH install)")"
  echo "Timer:                  $([ -f "$UNIT_TIMER" ] && echo OK || echo BRAK)"
  echo "Log:                    $LOG_FILE"
}

cmd_install() {
  need_root install
  mkdir -p "$GUARD_BASE" "$(dirname "$UNIT_SERVICE")"
  if [ "$(readlink -f "$0" 2>/dev/null)" != "$SELF_PATH" ]; then
    cp "$0" "$SELF_PATH" && chmod 755 "$SELF_PATH"
  fi

  cat > "$UNIT_SERVICE" <<EOF
[Unit]
Description=paddle-m1m2-guard: strażnik sysext InputPlumber (paddle M1/M2)
After=systemd-sysext.service

[Service]
Type=oneshot
ExecStart=$SELF_PATH run
EOF

  cat > "$UNIT_TIMER" <<EOF
[Unit]
Description=paddle-m1m2-guard: cykliczna weryfikacja sysext InputPlumber

[Timer]
OnBootSec=2min
OnUnitActiveSec=6h
Persistent=true
Unit=paddle-m1m2-guard.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now paddle-m1m2-guard.timer >/dev/null 2>&1
  log OK "Instalacja usługi paddle-m1m2-guard (timer: 2 min po starcie, potem co 6 h)."
  echo "Zainstalowane. Raport: $SELF_PATH status"
}

cmd_uninstall() {
  need_root uninstall
  systemctl disable --now paddle-m1m2-guard.timer >/dev/null 2>&1 || true
  rm -f "$UNIT_SERVICE" "$UNIT_TIMER"
  systemctl daemon-reload
  log INFO "Usługi paddle-m1m2-guard usunięte (sysext i log zostały w $EXT_PRIMARY / $GUARD_BASE)."
  echo "Usługi usunięte."
}

case "${1:-help}" in
  run)       cmd_run ;;
  status)    cmd_status ;;
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  help|--help|-h) sed -n '2,28p' "$0" | sed 's/^# \{0,2\}//' ;;
  *) echo "Nieznana komenda: $1" >&2; exit 1 ;;
esac
