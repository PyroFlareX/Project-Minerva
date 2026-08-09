#!/bin/sh
# Controller-friendly system helpers for Torchform QuickShell panels.
# Output is line-oriented and QML parses it; no external JSON tools required.
set -eu
cmd=${1:-}
PATH="$HOME/userpkgs/usr/bin:$PATH"
export PATH

find_wifi_station() {
  iwctl station list 2>/dev/null | awk '/^[[:space:]]/ && $2 != "" { print $2; exit }'
}

state_write() {
  json=${2:-}
  if [ -z "$json" ]; then
    echo 'error|state payload is empty'
    return 0
  fi
  state_dir=${XDG_CACHE_HOME:-$HOME/.cache}/torchform
  mkdir -p "$state_dir"
  tmp="$state_dir/state.json.$$"
  printf '%s\n' "$json" >"$tmp"
  mv -f "$tmp" "$state_dir/state.json"
}

expand_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

emit_file_entry() {
  entry=$1
  name=${entry##*/}
  if [ -d "$entry" ]; then
    kind=dir
  elif [ -L "$entry" ]; then
    kind=link
  else
    kind=file
  fi
  size=$(stat -c %s "$entry" 2>/dev/null || printf '?')
  printf 'entry\t%s\t%s\t%s\t%s\n' "$name" "$kind" "$size" "$entry"
}

sample_sysmon() {
  load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || printf '?')
  total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || printf 0)
  available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || printf 0)
  if [ "${total:-0}" -gt 0 ]; then
    memory=$(( (total - available) * 100 / total ))
  else
    memory=0
  fi
  disk=$(df -P / 2>/dev/null | awk 'NR == 2 {print $5}')
  [ -n "${disk:-}" ] || disk='?'
  temperature='?'
  for sensor in /sys/class/thermal/thermal_zone*/temp; do
    if [ -r "$sensor" ]; then
      raw=$(cat "$sensor" 2>/dev/null || printf 0)
      temperature=$(awk -v raw="$raw" 'BEGIN {printf "%.1f°C", raw / 1000}')
      break
    fi
  done
  battery='?'
  battery_status=unknown
  for capacity in /sys/class/power_supply/*/capacity; do
    if [ -r "$capacity" ]; then
      battery=$(cat "$capacity" 2>/dev/null || printf '?')
      status_file=${capacity%/capacity}/status
      [ -r "$status_file" ] && battery_status=$(cat "$status_file")
      break
    fi
  done
  uptime=$(awk '{printf "%ds", int($1)}' /proc/uptime 2>/dev/null || printf '?')
  printf 'sys|load=%s|memory=%s%%|disk=%s|temperature=%s|battery=%s|battery_status=%s|uptime=%s\n' \
    "$load" "$memory" "$disk" "$temperature" "$battery" "$battery_status" "$uptime"
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
  state-write)
    state_write "$@"
    ;;
  files-list)
    requested=$(expand_path "${2:-~}")
    if ! cd "$requested" 2>/dev/null; then
      printf 'status\tUnable to open %s\n' "$requested"
      exit 0
    fi
    directory=$(pwd -P)
    printf 'path\t%s\n' "$directory"
    if [ "$directory" != "/" ]; then
      printf 'entry\t..\tdir\t0\t%s\n' "$(dirname "$directory")"
    fi
    count=0
    for entry in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
      if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
        continue
      fi
      emit_file_entry "$entry"
      count=$((count + 1))
      [ "$count" -ge 200 ] && break
    done
    ;;
  terminal-exec)
    command=${2:-}
    if [ -z "$command" ]; then
      printf '[no command]\n'
      exit 0
    fi
    status=0
    sh -lc "$command" 2>&1 || status=$?
    printf '\n[exit %s]\n' "$status"
    ;;
  sysmon)
    sample_sysmon
    ;;
  brightness-step)
    direction=${2:-up}
    backlight=''
    for candidate in /sys/class/backlight/*/brightness; do
      if [ -w "$candidate" ]; then
        backlight=$candidate
        break
      fi
    done
    if [ -z "$backlight" ]; then
      echo 'error|No writable backlight control is available.'
      exit 0
    fi
    maximum=$(cat "${backlight%/brightness}/max_brightness")
    current=$(cat "$backlight")
    delta=$((maximum / 20))
    [ "$delta" -gt 0 ] || delta=1
    if [ "$direction" = down ]; then current=$((current - delta)); else current=$((current + delta)); fi
    [ "$current" -lt 0 ] && current=0
    [ "$current" -gt "$maximum" ] && current=$maximum
    printf '%s\n' "$current" >"$backlight"
    printf 'ok|Brightness %s%%\n' "$((current * 100 / maximum))"
    ;;
  volume-step)
    direction=${2:-up}
    if command -v amixer >/dev/null 2>&1; then
      if [ "$direction" = down ]; then amixer sset Master 5%- >/dev/null 2>&1; else amixer sset Master 5%+ >/dev/null 2>&1; fi
      echo "ok|Volume adjusted ${direction}"
    elif command -v pactl >/dev/null 2>&1; then
      if [ "$direction" = down ]; then pactl set-sink-volume @DEFAULT_SINK@ -5%; else pactl set-sink-volume @DEFAULT_SINK@ +5%; fi
      echo "ok|Volume adjusted ${direction}"
    else
      echo 'error|No amixer or pactl volume control is available.'
    fi
    ;;
  launch)
    app=${2:-}
    case "$app" in
      browser)
        for c in firefox chromium epiphany qutebrowser; do
          if command -v "$c" >/dev/null 2>&1; then
            nohup "$c" >/tmp/torchform-$c.log 2>&1 &
            pid=$!
            sleep 0.25
            if kill -0 "$pid" 2>/dev/null; then echo "ok|Launching $c"; else echo "error|$c exited during launch"; fi
            exit 0
          fi
        done
        echo 'error|No Wayland browser installed.'
        ;;
      files)
        for c in pcmanfm thunar dolphin; do
          if command -v "$c" >/dev/null 2>&1; then
            nohup "$c" "$HOME" >/tmp/torchform-$c.log 2>&1 &
            pid=$!
            sleep 0.25
            if kill -0 "$pid" 2>/dev/null; then echo "ok|Launching $c"; else echo "error|$c exited during launch"; fi
            exit 0
          fi
        done
        echo 'error|No Wayland file manager installed.'
        ;;
      terminal)
        for c in "$HOME/userpkgs/usr/bin/foot" kitty alacritty; do
          if [ ! -x "$c" ]; then c=$(command -v "$c" 2>/dev/null || true); fi
          [ -x "$c" ] || continue
          name=${c##*/}
          nohup env "LD_LIBRARY_PATH=$HOME/userpkgs/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            "$c" >/tmp/torchform-$name.log 2>&1 &
          pid=$!
          sleep 0.75
          if kill -0 "$pid" 2>/dev/null; then
            echo "ok|Launching $name"
            exit 0
          fi
          wait "$pid" 2>/dev/null || true
        done
        echo 'error|No Wayland terminal installed.'
        ;;
      *) echo "error|Unknown launcher: $app" ;;
    esac
    ;;
  *)
    echo 'error|usage: torchform-control.sh wifi-list|wifi-connect SSID|bluetooth-list|bluetooth-scan|bluetooth-stop-scan|bluetooth-connect ADDR|launch APP'
    ;;
esac
