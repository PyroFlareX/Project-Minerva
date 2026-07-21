#!/bin/sh
# Controller-friendly system helpers for Torchform QuickShell panels.
# Output is line-oriented and QML parses it; no external JSON tools required.
set -eu
cmd=${1:-}

find_wifi_station() {
  iwctl station list 2>/dev/null | awk '/^[[:space:]]/ && $2 != "" { print $2; exit }'
}

case "$cmd" in
  wifi-list)
    if ! command -v iwctl >/dev/null 2>&1; then
      echo 'status|Wi-Fi tools missing: install and enable iwd (iwctl).'
      exit 0
    fi
    sta=$(find_wifi_station || true)
    if [ -z "${sta:-}" ]; then
      echo 'status|No Wi-Fi station found.'
      exit 0
    fi
    iwctl station "$sta" scan >/dev/null 2>&1 || true
    iwctl station "$sta" get-networks 2>/dev/null |
      awk '
        /^[[:space:]]*>/ || /^[[:space:]][[:space:]][^-[:space:]]/ {
          connected = ($1 == ">") ? 1 : 0
          start = connected ? 2 : 1
          ssid = $start
          for (i = start + 1; i <= NF - 2; i++) ssid = ssid " " $i
          signal = $(NF-1)
          security = $NF
          if (ssid != "" && ssid != "Available") printf "network|%s|%s|%s|%s\n", ssid, signal, security, connected
        }'
    ;;
  wifi-connect)
    ssid=${2:-}
    if [ -z "$ssid" ]; then echo 'error|No SSID selected.'; exit 0; fi
    if ! command -v iwctl >/dev/null 2>&1; then echo 'error|iwctl is not installed.'; exit 0; fi
    sta=$(find_wifi_station || true)
    if [ -z "${sta:-}" ]; then echo 'error|No Wi-Fi station found.'; exit 0; fi
    if iwctl station "$sta" connect "$ssid" >/tmp/torchform-wifi-connect.log 2>&1; then
      echo "ok|Connected to $ssid"
    else
      msg=$(tail -1 /tmp/torchform-wifi-connect.log 2>/dev/null || true)
      echo "error|${msg:-Failed to connect to $ssid}"
    fi
    ;;
  bluetooth-list)
    if ! command -v bluetoothctl >/dev/null 2>&1; then
      echo 'status|Bluetooth tools missing: install and enable bluez (bluetoothctl).'
      exit 0
    fi
    bluetoothctl devices 2>/dev/null | while read -r _ addr name; do
      [ -n "${addr:-}" ] || continue
      info=$(bluetoothctl info "$addr" 2>/dev/null || true)
      paired=$(printf '%s\n' "$info" | awk '/Paired:/ {print $2; exit}')
      connected=$(printf '%s\n' "$info" | awk '/Connected:/ {print $2; exit}')
      icon='📱'
      printf '%s\n' "$info" | grep -qi 'Audio' && icon='🔊'
      printf '%s\n' "$info" | grep -qiE 'Keyboard|Input|HID|Gamepad|Joystick' && icon='🎮'
      printf 'device|%s|%s|%s|%s|%s\n' "$addr" "${name:-$addr}" "${paired:-no}" "${connected:-no}" "$icon"
    done
    ;;
  bluetooth-scan)
    if ! command -v bluetoothctl >/dev/null 2>&1; then echo 'error|bluetoothctl is not installed.'; exit 0; fi
    bluetoothctl scan on >/tmp/torchform-bt-scan.log 2>&1 &
    echo 'ok|Bluetooth scan started.'
    ;;
  bluetooth-stop-scan)
    command -v bluetoothctl >/dev/null 2>&1 && bluetoothctl scan off >/dev/null 2>&1 || true
    echo 'ok|Bluetooth scan stopped.'
    ;;
  bluetooth-connect)
    addr=${2:-}
    if [ -z "$addr" ]; then echo 'error|No Bluetooth device selected.'; exit 0; fi
    if ! command -v bluetoothctl >/dev/null 2>&1; then echo 'error|bluetoothctl is not installed.'; exit 0; fi
    if bluetoothctl connect "$addr" >/tmp/torchform-bt-connect.log 2>&1 || bluetoothctl pair "$addr" >/tmp/torchform-bt-connect.log 2>&1; then
      bluetoothctl trust "$addr" >/dev/null 2>&1 || true
      echo "ok|Connected to $addr"
    else
      msg=$(tail -1 /tmp/torchform-bt-connect.log 2>/dev/null || true)
      echo "error|${msg:-Failed to connect to $addr}"
    fi
    ;;
  launch)
    app=${2:-}
    case "$app" in
      browser) for c in firefox chromium epiphany qutebrowser; do command -v "$c" >/dev/null 2>&1 && { nohup "$c" >/tmp/torchform-$c.log 2>&1 & echo "ok|Launching $c"; exit 0; }; done; echo 'error|No Wayland browser installed.' ;;
      files)   for c in pcmanfm thunar dolphin; do command -v "$c" >/dev/null 2>&1 && { nohup "$c" "$HOME" >/tmp/torchform-$c.log 2>&1 & echo "ok|Launching $c"; exit 0; }; done; echo 'error|No Wayland file manager installed.' ;;
      terminal) for c in foot alacritty; do command -v "$c" >/dev/null 2>&1 && { nohup "$c" >/tmp/torchform-$c.log 2>&1 & echo "ok|Launching $c"; exit 0; }; done; echo 'error|No Wayland terminal installed.' ;;
      *) echo "error|Unknown launcher: $app" ;;
    esac
    ;;
  *)
    echo 'error|usage: torchform-control.sh wifi-list|wifi-connect SSID|bluetooth-list|bluetooth-scan|bluetooth-stop-scan|bluetooth-connect ADDR|launch APP'
    ;;
esac
