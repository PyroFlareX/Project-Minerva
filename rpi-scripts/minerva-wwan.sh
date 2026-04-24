#!/bin/sh
# minerva-wwan — WWAN modem management for Minerva (Sierra Wireless EM7565)
# Alpine Linux / OpenRC / NetworkManager
# Usage: minerva-wwan <command> [args]

set -e

MODEM_DEV="/dev/cdc-wdm0"
MODEM_TTY="/dev/ttyUSB2"
IFACE="usb0"

# Known SIM profiles
# Format: NAME|APN|DESCRIPTION
PROFILES="
tmobile|fast.t-mobile.com|T-Mobile US (primary)
att|broadband|AT&T US
iijmio|iijmio.jp|IIJmio Japan (Docomo)
docomo|spmode.ne.jp|NTT Docomo direct
"

# ─────────────────────────────────────────
# Color helpers
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; BLD='\033[1m'; RST='\033[0m'

info()  { printf "${BLU}[minerva-wwan]${RST} %s\n" "$*"; }
ok()    { printf "${GRN}[  OK  ]${RST} %s\n" "$*"; }
warn()  { printf "${YLW}[ WARN ]${RST} %s\n" "$*"; }
fail()  { printf "${RED}[ FAIL ]${RST} %s\n" "$*" >&2; }
header(){ printf "\n${BLD}${CYN}━━━ %s ━━━${RST}\n" "$*"; }

# ─────────────────────────────────────────
usage() {
    cat <<EOF
${BLD}minerva-wwan${RST} — WWAN modem manager for Minerva

${BLD}SETUP${RST}
  setup               First-time modem setup (ECM mode + deps)
  init-ecm            Switch modem to ECM mode via AT commands

${BLD}CONNECTION${RST}
  up [profile]        Bring up WWAN connection (default: tmobile)
  down                Bring down WWAN connection
  switch <profile>    Switch to a different SIM profile
  auto                Auto-detect carrier from SIM and connect

${BLD}STATUS & MONITORING${RST}
  status              Show modem + connection status
  signal              Show signal strength and band info
  watch               Live signal monitor (refreshes every 3s)
  usage               Show data usage for current session
  test                Run connectivity test (ping + speed check)

${BLD}SIM PROFILES${RST}
  profiles            List known SIM profiles
  profile-add         Add a custom SIM profile
  profile-show <name> Show profile details

${BLD}DIAGNOSTICS${RST}
  info                Full modem hardware info
  logs                Show recent ModemManager logs
  at <command>        Send raw AT command to modem

${BLD}EXAMPLES${RST}
  minerva-wwan up                   # Connect with T-Mobile (default)
  minerva-wwan switch iijmio        # Switch to Japan SIM
  minerva-wwan watch                # Live signal monitor
  minerva-wwan at 'AT+CSQ'          # Raw AT command

EOF
}

# ─────────────────────────────────────────
check_deps() {
    for cmd in mmcli nmcli minicom ip ping; do
        command -v "$cmd" >/dev/null 2>&1 || {
            fail "Missing dependency: $cmd"
            info "Run: minerva-wwan setup"
            exit 1
        }
    done
}

check_modem() {
    if [ ! -c "$MODEM_DEV" ]; then
        fail "Modem device $MODEM_DEV not found"
        info "Check: lsusb | grep -i sierra"
        exit 1
    fi
}

get_modem_idx() {
    mmcli -L 2>/dev/null | grep -o 'Modem/[0-9]*' | head -1 | cut -d/ -f2
}

get_profile_apn() {
    # $1 = profile name
    echo "$PROFILES" | grep "^$1|" | cut -d'|' -f2
}

get_profile_desc() {
    echo "$PROFILES" | grep "^$1|" | cut -d'|' -f3
}

# ─────────────────────────────────────────
cmd_setup() {
    header "First-time WWAN Setup"
    info "Installing dependencies..."
    apk add --quiet modemmanager minicom libqmi-utils udhcpc networkmanager-modemmanager || {
        fail "apk install failed — are you root?"
        exit 1
    }
    rc-update add modemmanager default 2>/dev/null || true
    rc-service modemmanager start 2>/dev/null || rc-service modemmanager restart
    ok "ModemManager started"

    sleep 2
    if [ -c "$MODEM_DEV" ]; then
        ok "Modem detected at $MODEM_DEV"
    else
        warn "Modem not yet detected. Try: lsusb | grep -i sierra"
        warn "If missing, check M.2 slot seating and USB 2.0 pin wiring"
    fi

    info "Checking modem mode..."
    IDX=$(get_modem_idx)
    if [ -n "$IDX" ]; then
        ok "Modem index: $IDX"
        info "Run 'minerva-wwan init-ecm' to switch to ECM mode (recommended)"
    fi
}

cmd_init_ecm() {
    header "Switching Modem to ECM Mode"
    check_modem
    warn "This will reboot the modem. It will briefly disappear from USB."
    printf "Continue? [y/N] "
    read -r yn
    [ "$yn" = "y" ] || { info "Aborted."; exit 0; }

    info "Sending AT commands via $MODEM_TTY..."
    # Use expect-style here-doc via minicom in script mode
    if [ ! -c "$MODEM_TTY" ]; then
        fail "$MODEM_TTY not found. Is the modem in QMI mode?"
        info "Try: ls /dev/ttyUSB*"
        exit 1
    fi

    # Send AT commands non-interactively
    (
        sleep 1; echo "AT"
        sleep 1; echo 'AT!USBCOMP=1,3,100D'
        sleep 1; echo "AT!RESET"
        sleep 3
    ) | minicom -D "$MODEM_TTY" -b 115200 -o -C /tmp/minerva-ecm.log >/dev/null 2>&1 || true

    info "Waiting for modem to reboot (10s)..."
    sleep 10

    if ip link show "$IFACE" >/dev/null 2>&1; then
        ok "ECM mode active — $IFACE interface is up"
    else
        warn "$IFACE not yet visible. Wait a few more seconds and run: ip link show usb0"
        info "Log: cat /tmp/minerva-ecm.log"
    fi
}

cmd_up() {
    PROFILE="${1:-tmobile}"
    APN=$(get_profile_apn "$PROFILE")
    DESC=$(get_profile_desc "$PROFILE")

    if [ -z "$APN" ]; then
        fail "Unknown profile: $PROFILE"
        info "Run: minerva-wwan profiles"
        exit 1
    fi

    header "Connecting: $DESC"
    info "APN: $APN"

    # Check if connection already exists in NM
    if nmcli connection show "minerva-$PROFILE" >/dev/null 2>&1; then
        info "Connection profile exists, bringing up..."
        nmcli connection up "minerva-$PROFILE" || {
            fail "Failed to bring up connection"
            exit 1
        }
    else
        info "Creating new NetworkManager connection..."
        nmcli connection add \
            type ethernet \
            ifname "$IFACE" \
            con-name "minerva-$PROFILE" \
            ipv4.route-metric 700 \
            -- \
            gsm.apn "$APN" 2>/dev/null || \
        nmcli connection add \
            type ethernet \
            ifname "$IFACE" \
            con-name "minerva-$PROFILE" \
            ipv4.route-metric 700
        nmcli connection up "minerva-$PROFILE"
    fi

    sleep 2
    IP=$(ip -4 addr show "$IFACE" 2>/dev/null | grep 'inet ' | awk '{print $2}')
    if [ -n "$IP" ]; then
        ok "Connected: $IP on $IFACE"
    else
        warn "Interface up but no IP yet — check with: minerva-wwan status"
    fi
}

cmd_down() {
    header "Disconnecting WWAN"
    ACTIVE=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$IFACE" | cut -d: -f1)
    if [ -n "$ACTIVE" ]; then
        nmcli connection down "$ACTIVE"
        ok "Disconnected: $ACTIVE"
    else
        warn "No active WWAN connection found"
    fi
}

cmd_switch() {
    PROFILE="$1"
    if [ -z "$PROFILE" ]; then
        fail "Usage: minerva-wwan switch <profile>"
        info "Run: minerva-wwan profiles"
        exit 1
    fi
    header "Switching SIM Profile → $PROFILE"
    warn "Make sure you have inserted the correct SIM for: $(get_profile_desc "$PROFILE")"
    printf "SIM inserted and ready? [y/N] "
    read -r yn
    [ "$yn" = "y" ] || { info "Aborted."; exit 0; }
    cmd_down 2>/dev/null || true
    sleep 1
    cmd_up "$PROFILE"
}

cmd_auto() {
    header "Auto-detecting Carrier"
    check_modem
    IDX=$(get_modem_idx)
    if [ -z "$IDX" ]; then
        fail "No modem found by ModemManager"
        exit 1
    fi

    OPERATOR=$(mmcli -m "$IDX" 2>/dev/null | grep 'operator name' | awk -F"'" '{print $2}')
    info "Detected operator: ${OPERATOR:-unknown}"

    case "$OPERATOR" in
        *T-Mobile*|*TMobile*)  cmd_up tmobile ;;
        *AT&T*|*ATT*)          cmd_up att ;;
        *Docomo*|*NTT*)        cmd_up iijmio ;;
        *)
            warn "Unknown operator: $OPERATOR"
            info "Available profiles:"
            cmd_profiles
            printf "Enter profile name: "
            read -r p
            cmd_up "$p"
            ;;
    esac
}

cmd_status() {
    header "WWAN Status"
    IDX=$(get_modem_idx)

    if [ -z "$IDX" ]; then
        fail "No modem detected by ModemManager"
        info "Check: rc-service modemmanager status"
        return
    fi

    printf "${BLD}Modem:${RST}\n"
    mmcli -m "$IDX" 2>/dev/null | grep -E '(model|state|power|operator|signal|access tech|bearer)' | \
        sed 's/^[[:space:]]*/  /'

    printf "\n${BLD}Interface:${RST}\n"
    ip -4 addr show "$IFACE" 2>/dev/null | grep -E '(inet |state)' | sed 's/^/  /' || \
        printf "  %s not up\n" "$IFACE"

    printf "\n${BLD}Active NM Connection:${RST}\n"
    nmcli -t -f NAME,DEVICE,STATE connection show --active 2>/dev/null | grep "$IFACE" | \
        sed 's/^/  /' || printf "  none\n"

    printf "\n${BLD}Route:${RST}\n"
    ip route show dev "$IFACE" 2>/dev/null | sed 's/^/  /' || printf "  no routes\n"
}

cmd_signal() {
    header "Signal Info"
    check_modem
    IDX=$(get_modem_idx)
    [ -z "$IDX" ] && { fail "No modem"; exit 1; }

    mmcli -m "$IDX" --signal-get 2>/dev/null || \
    mmcli -m "$IDX" 2>/dev/null | grep -E '(signal|access tech|operator|band)' | \
        sed 's/^[[:space:]]*/  /'

    # Also try raw AT for band info
    if [ -c "$MODEM_TTY" ]; then
        printf "\n${BLD}Band (AT):${RST}\n"
        echo 'AT!GSTATUS?' | timeout 3 minicom -D "$MODEM_TTY" -b 115200 -o 2>/dev/null | \
            grep -E '(Band|RSSI|RSRP|SINR|Mode)' | sed 's/^/  /' || true
    fi
}

cmd_watch() {
    header "Live Signal Monitor  (Ctrl+C to exit)"
    IDX=$(get_modem_idx)
    [ -z "$IDX" ] && { fail "No modem"; exit 1; }
    while true; do
        clear
        printf "${BLD}${CYN}━━━ Minerva WWAN Monitor ━━━${RST}  $(date '+%H:%M:%S')\n\n"
        mmcli -m "$IDX" 2>/dev/null | grep -E '(state|operator|access tech|signal|bearer)' | \
            sed 's/^[[:space:]]*/  /'
        printf "\n${BLD}IP:${RST}\n"
        ip -4 addr show "$IFACE" 2>/dev/null | grep 'inet ' | sed 's/^/  /' || printf "  not connected\n"
        printf "\n${BLD}Ping latency:${RST}\n"
        ping -I "$IFACE" -c 1 -W 2 8.8.8.8 2>/dev/null | grep 'time=' | sed 's/^/  /' || \
            printf "  no response\n"
        sleep 3
    done
}

cmd_usage() {
    header "Data Usage (current session)"
    IDX=$(get_modem_idx)
    [ -z "$IDX" ] && { fail "No modem"; exit 1; }

    BEARERS=$(mmcli -m "$IDX" 2>/dev/null | grep bearer | grep -o '/[0-9]*$' | tr -d '/')
    if [ -z "$BEARERS" ]; then
        warn "No active bearer — not connected?"
        return
    fi
    for B in $BEARERS; do
        printf "${BLD}Bearer $B:${RST}\n"
        mmcli -b "$B" 2>/dev/null | grep -E '(bytes|duration|interface|ip)' | sed 's/^/  /'
    done

    # Also show rx/tx from kernel interface counters
    printf "\n${BLD}Interface counters ($IFACE):${RST}\n"
    if ip link show "$IFACE" >/dev/null 2>&1; then
        RX=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null)
        TX=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null)
        printf "  RX: %s bytes (%.2f MB)\n" "$RX" "$(echo "$RX 1048576" | awk '{printf "%.2f", $1/$2}')"
        printf "  TX: %s bytes (%.2f MB)\n" "$TX" "$(echo "$TX 1048576" | awk '{printf "%.2f", $1/$2}')"
    else
        printf "  $IFACE not up\n"
    fi
}

cmd_test() {
    header "Connectivity Test"
    printf "${BLD}1. Interface check:${RST}\n"
    ip -4 addr show "$IFACE" 2>/dev/null | grep 'inet ' | sed 's/^/  /' || { fail "  $IFACE has no IP"; return; }

    printf "\n${BLD}2. Ping test (8.8.8.8):${RST}\n"
    ping -I "$IFACE" -c 5 8.8.8.8 2>&1 | tail -3 | sed 's/^/  /'

    printf "\n${BLD}3. DNS resolution:${RST}\n"
    nslookup google.com 2>&1 | head -5 | sed 's/^/  /' || \
        host google.com 2>&1 | head -3 | sed 's/^/  /'

    printf "\n${BLD}4. HTTP test:${RST}\n"
    curl -s --interface "$IFACE" --max-time 5 -o /dev/null -w "  HTTP %{http_code} — %{time_total}s\n" \
        https://httpbin.org/get 2>/dev/null || printf "  curl failed\n"
}

cmd_profiles() {
    header "SIM Profiles"
    printf "%-15s %-30s %s\n" "NAME" "APN" "DESCRIPTION"
    printf "%-15s %-30s %s\n" "────────────" "──────────────────────────────" "─────────────────────"
    echo "$PROFILES" | grep '|' | while IFS='|' read -r name apn desc; do
        printf "%-15s %-30s %s\n" "$name" "$apn" "$desc"
    done
    printf "\nActive NM connections:\n"
    nmcli -t -f NAME connection show 2>/dev/null | grep '^minerva-' | sed 's/^/  /'
}

cmd_profile_add() {
    printf "Profile name (no spaces): "; read -r NAME
    printf "APN: "; read -r APN
    printf "Description: "; read -r DESC
    FILE="$HOME/.config/minerva-wwan/profiles.conf"
    mkdir -p "$(dirname "$FILE")"
    echo "$NAME|$APN|$DESC" >> "$FILE"
    ok "Saved: $NAME → $FILE"
    info "To use: minerva-wwan up $NAME"
    info "Note: add nmcli connection manually for custom profiles"
}

cmd_info() {
    header "Modem Hardware Info"
    IDX=$(get_modem_idx)
    [ -z "$IDX" ] && { fail "No modem"; exit 1; }
    mmcli -m "$IDX" 2>/dev/null
    printf "\n${BLD}USB device:${RST}\n"
    lsusb 2>/dev/null | grep -i sierra | sed 's/^/  /'
    printf "\n${BLD}Kernel driver:${RST}\n"
    lsusb -t 2>/dev/null | grep -A2 -i sierra | sed 's/^/  /' || true
}

cmd_logs() {
    header "ModemManager Logs (last 50 lines)"
    journalctl -u ModemManager -n 50 --no-pager 2>/dev/null || \
    logread 2>/dev/null | grep -i modem | tail -50 || \
    dmesg | grep -iE '(sierra|wwan|cdc|qmi|usb)' | tail -30
}

cmd_at() {
    AT_CMD="$1"
    [ -z "$AT_CMD" ] && { fail "Usage: minerva-wwan at '<AT command>'"; exit 1; }
    if [ ! -c "$MODEM_TTY" ]; then
        fail "$MODEM_TTY not found"
        info "Available TTYs: ls /dev/ttyUSB*"
        exit 1
    fi
    info "Sending: $AT_CMD"
    (echo "$AT_CMD"; sleep 1) | minicom -D "$MODEM_TTY" -b 115200 -o 2>/dev/null | \
        grep -v '^$' | tail -10
}

# ─────────────────────────────────────────
# Load user-defined profiles if present
USER_PROFILES="$HOME/.config/minerva-wwan/profiles.conf"
if [ -f "$USER_PROFILES" ]; then
    PROFILES="$PROFILES
$(cat "$USER_PROFILES")"
fi

# ─────────────────────────────────────────
CMD="${1:-}"
shift 2>/dev/null || true

case "$CMD" in
    setup)         cmd_setup ;;
    init-ecm)      cmd_init_ecm ;;
    up)            check_deps; cmd_up "$@" ;;
    down)          check_deps; cmd_down ;;
    switch)        check_deps; cmd_switch "$@" ;;
    auto)          check_deps; cmd_auto ;;
    status)        check_deps; cmd_status ;;
    signal)        cmd_signal ;;
    watch)         cmd_watch ;;
    usage)         cmd_usage ;;
    test)          cmd_test ;;
    profiles)      cmd_profiles ;;
    profile-add)   cmd_profile_add ;;
    profile-show)  get_profile_apn "$1"; get_profile_desc "$1" ;;
    info)          cmd_info ;;
    logs)          cmd_logs ;;
    at)            cmd_at "$@" ;;
    help|--help|-h|"") usage ;;
    *) fail "Unknown command: $CMD"; usage; exit 1 ;;
esac
