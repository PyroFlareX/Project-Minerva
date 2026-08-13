#!/bin/sh
# Controller-friendly system helpers for Torchform QuickShell panels.
# Output is line-oriented and QML parses it; no external JSON tools required.
set -eu
cmd=${1:-}
PATH="$HOME/userpkgs/usr/bin:$PATH"
export PATH
MEDIA_LIBS="$HOME/userpkgs/usr/lib:$HOME/userpkgs/usr/lib/pulseaudio"
LD_LIBRARY_PATH="$MEDIA_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH


find_wifi_station() {
  if command -v iwctl >/dev/null 2>&1; then
    iwctl station list 2>/dev/null | awk '/^[[:space:]]/ && $2 != "" { print $2; exit }'
  elif command -v iw >/dev/null 2>&1; then
    iw dev 2>/dev/null | awk '$1 == "Interface" { print $2; exit }'
  fi
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
  cpu_state=/tmp/torchform-sysmon-cpu
  cpu_tmp="${cpu_state}.$$"
  cpu_metrics=$(awk -v state="$cpu_state" '
    BEGIN {
      while ((getline line < state) > 0) {
        split(line, p, " ")
        previous[p[1]] = line
      }
      close(state)
    }
    /^cpu([0-9]+)?[[:space:]]/ {
      total = 0
      idle = $5 + $6
      for (i = 2; i <= NF; i++) total += $i
      key = $1
      if (previous[key] != "") {
        split(previous[key], p, " ")
        old_total = 0
        old_idle = p[5] + p[6]
        for (i = 2; i <= 8; i++) old_total += p[i]
        delta_total = total - old_total
        delta_idle = idle - old_idle
        usage = delta_total > 0 ? (100 * (delta_total - delta_idle) / delta_total) : 0
        if (usage < 0) usage = 0
        if (usage > 100) usage = 100
        printf "%s=%.0f|", key, usage
      } else {
        printf "%s=0|", key
      }
    }' /proc/stat 2>/dev/null || true)
  awk '/^cpu([0-9]+)?[[:space:]]/ { print $1, $2, $3, $4, $5, $6, $7, $8 }' /proc/stat >"$cpu_tmp"
  mv -f "$cpu_tmp" "$cpu_state"

  total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || printf 0)
  available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || printf 0)
  swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || printf 0)
  swap_free=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo 2>/dev/null || printf 0)
  if [ "${total:-0}" -gt 0 ]; then
    memory=$(( (total - available) * 100 / total ))
    memory_used_mb=$(( (total - available) / 1024 ))
    memory_total_mb=$(( total / 1024 ))
    memory_available_mb=$(( available / 1024 ))
  else
    memory=0
    memory_used_mb=0
    memory_total_mb=0
    memory_available_mb=0
  fi
  if [ "${swap_total:-0}" -gt 0 ]; then
    swap=$(( (swap_total - swap_free) * 100 / swap_total ))
  else
    swap=0
  fi

  disk_line=$(df -P / 2>/dev/null | awk 'NR == 2 {print $3, $2, $5}')
  disk_used=$(printf '%s\n' "$disk_line" | awk '{printf "%.1fG", $1 / 1048576}')
  disk_total=$(printf '%s\n' "$disk_line" | awk '{printf "%.1fG", $2 / 1048576}')
  disk=$(printf '%s\n' "$disk_line" | awk '{print $3}')
  [ -n "${disk:-}" ] || disk='?'
  [ -n "${disk_used:-}" ] || disk_used='?'
  [ -n "${disk_total:-}" ] || disk_total='?'

  net_state=/tmp/torchform-sysmon-net
  net_tmp="${net_state}.$$"
  net_totals=$(awk -F: '
    NR > 2 {
      gsub(/^[[:space:]]+/, "", $1)
      if ($1 != "lo") { rx += $2; tx += $10 }
    }
    END { printf "%.0f %.0f", rx + 0, tx + 0 }' /proc/net/dev 2>/dev/null || printf '0 0')
  old_net=$(cat "$net_state" 2>/dev/null || printf '0 0 0')
  now=$(date +%s)
  set -- $net_totals
  rx=${1:-0}
  tx=${2:-0}
  set -- $old_net
  old_rx=${1:-0}
  old_tx=${2:-0}
  old_time=${3:-$now}
  elapsed=$(( now - old_time ))
  [ "$elapsed" -gt 0 ] || elapsed=1
  net_rx_kbps=$(( (rx - old_rx) / elapsed / 1024 ))
  net_tx_kbps=$(( (tx - old_tx) / elapsed / 1024 ))
  [ "$net_rx_kbps" -ge 0 ] || net_rx_kbps=0
  [ "$net_tx_kbps" -ge 0 ] || net_tx_kbps=0
  printf '%s %s %s\n' "$rx" "$tx" "$now" >"$net_tmp"
  mv -f "$net_tmp" "$net_state"
  disk_state=/tmp/torchform-sysmon-disk
  disk_tmp="${disk_state}.$$"
  disk_totals=$(awk '$3 !~ /^(loop|ram|sr|zram)/ { read += $6; write += $10 } END { printf "%.0f %.0f", read + 0, write + 0 }' /proc/diskstats 2>/dev/null || printf '0 0')
  old_disk=$(cat "$disk_state" 2>/dev/null || printf '0 0 0')
  set -- $disk_totals
  disk_read_sectors=${1:-0}
  disk_write_sectors=${2:-0}
  set -- $old_disk
  old_disk_read=${1:-0}
  old_disk_write=${2:-0}
  old_disk_time=${3:-$now}
  disk_elapsed=$(( now - old_disk_time ))
  [ "$disk_elapsed" -gt 0 ] || disk_elapsed=1
  disk_read_kbps=$(( (disk_read_sectors - old_disk_read) / disk_elapsed / 2 ))
  disk_write_kbps=$(( (disk_write_sectors - old_disk_write) / disk_elapsed / 2 ))
  [ "$disk_read_kbps" -ge 0 ] || disk_read_kbps=0
  [ "$disk_write_kbps" -ge 0 ] || disk_write_kbps=0
  printf '%s %s %s\n' "$disk_read_sectors" "$disk_write_sectors" "$now" >"$disk_tmp"
  mv -f "$disk_tmp" "$disk_state"


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
  process_count=$(ps -e 2>/dev/null | awk 'NR > 1 {count++} END {print count + 0}')
  cpu_speed=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || printf 0)
  if [ "${cpu_speed:-0}" -gt 0 ] 2>/dev/null; then
    cpu_speed=$(awk -v khz="$cpu_speed" 'BEGIN {printf "%.2f GHz", khz / 1000000}')
  else
    cpu_speed='—'
  fi
  cpu_load=${cpu_metrics#cpu=}
  cpu_load=${cpu_load%%|*}
  printf 'sys|load=%s|memory=%s%%|memory_used=%s MB|memory_total=%s MB|memory_available=%s MB|swap=%s%%|disk=%s|disk_used=%s|disk_total=%s|disk_read=%s KB/s|disk_write=%s KB/s|temperature=%s|battery=%s|battery_status=%s|uptime=%s|processes=%s|cpu_speed=%s|net_rx=%s KB/s|net_tx=%s KB/s|%s\n' \
    "$cpu_load" "$memory" "$memory_used_mb" "$memory_total_mb" "$memory_available_mb" "$swap" "$disk" "$disk_used" "$disk_total" "$disk_read_kbps" "$disk_write_kbps" "$temperature" "$battery" "$battery_status" "$uptime" "$process_count" "$cpu_speed" "$net_rx_kbps" "$net_tx_kbps" "$cpu_metrics"
}
# External Wayland apps must run in the FOREGROUND of this helper so the caller
# (QuickShell) owns their lifetime: the shell drops its overlay layer while an
# external surface is mapped and restores it when the process exits.
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

sway_socket() {
  [ -n "${SWAYSOCK:-}" ] && [ -S "$SWAYSOCK" ] && return 0
  for candidate in "${XDG_RUNTIME_DIR:-/tmp/xdg-hdmi}"/sway-ipc.*.sock; do
    [ -S "$candidate" ] || continue
    SWAYSOCK=$candidate
    export SWAYSOCK
    return 0
  done
  return 1
}

# Focus the upper output so a new toplevel maps on the main display instead of
# the small companion screen, which owns the focused workspace by default.
focus_upper_output() {
  sway_socket || return 0
  command -v swaymsg >/dev/null 2>&1 || return 0
  upper=$(python3 "$SCRIPT_DIR/configure-outputs.py" --role upper 2>/dev/null) || return 0
  [ -n "$upper" ] || return 0
  swaymsg focus output "$upper" >/dev/null 2>&1 || true
}

# ─── External program registry ───────────────────────────────────────────────
# Config files are merged from defaults to user overrides. An older user file
# may omit newly introduced app/service entries; that must not hide the shipped
# defaults for those entries.
config_registry_files() {
  for candidate in \
    "$SCRIPT_DIR/config.toml" \
    "$SCRIPT_DIR/../config/config.toml" \
    /etc/torchform/config.toml \
    "${XDG_CONFIG_HOME:-$HOME/.config}/torchform/config.toml"; do
    [ -f "$candidate" ] && printf '%s\n' "$candidate"
  done
}

controls_map_file() {
  for candidate in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/torchform/controls/$1.toml" \
    "/etc/torchform/controls/$1.toml" \
    "$SCRIPT_DIR/../config/controls/$1.toml" \
    "$SCRIPT_DIR/controls/$1.toml"; do
    [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

# Emits "field<TAB>value" records for one app, or an "error|..." line.
# $2 = "key" (default) to look up an [apps.<key>] entry, or "extension" to find
# whichever app declares that file extension.
app_records() {
  TORCHFORM_CONFIG_REGISTRIES=$(config_registry_files)
  if [ -z "$TORCHFORM_CONFIG_REGISTRIES" ]; then
    echo 'error|No config.toml found; external programs are unconfigured.'
    return 1
  fi
  export TORCHFORM_CONFIG_REGISTRIES
  python3 - "$1" "${2:-key}" <<'PY'
import os, sys, tomllib

wanted, mode = sys.argv[1], sys.argv[2]
registries = os.environ["TORCHFORM_CONFIG_REGISTRIES"].splitlines()
apps = {}
sources = {}

def fail(message):
    print("error|" + message)
    raise SystemExit(1)

for registry in registries:
    try:
        with open(registry, "rb") as handle:
            data = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        fail(f"{registry} is unreadable: {exc}")
    configured = data.get("apps") or {}
    if not isinstance(configured, dict):
        fail(f"{registry} [apps] is not a table.")
    for name, entry in configured.items():
        apps[name] = entry
        sources[name] = registry

def normalise(entry):
    # Legacy flat form: apps.terminal = "/path/to/kitty"
    return {"command": entry} if isinstance(entry, str) else dict(entry)

if mode == "extension":
    key = next((name for name, raw in apps.items()
                if wanted.lower() in [str(e).lower()
                                      for e in normalise(raw).get("extensions", [])]), None)
    if key is None:
        fail(f"No configured program handles .{wanted}")
else:
    if wanted not in apps:
        fail(f"No [apps.{wanted}] entry in merged config.toml files")
    key = wanted

entry = normalise(apps[key])
label = str(entry.get("label", key))

def expand(value):
    return os.path.expanduser(str(value)) if value not in (None, "") else ""

config_dir = expand(entry.get("config_dir", ""))

def substitute(value):
    return str(value).replace("{config_dir}", config_dir)

command = substitute(expand(entry.get("command", "")))
if not command:
    fail(f"[apps.{key}] in {sources[key]} has no command.")

def executable(path):
    return os.path.isfile(path) and os.access(path, os.X_OK)

if "/" not in command:
    found = next((os.path.join(d, command)
                  for d in os.environ.get("PATH", "").split(os.pathsep)
                  if executable(os.path.join(d, command))), None)
    if found is None:
        fail(f"{label} is not installed: {command}")
    command = found
elif not executable(command):
    fail(f"{label} is not installed: {command}")

records = [
    ("key", key),
    ("label", label),
    ("command", command),
    ("config_dir", config_dir),
    ("config_env", str(entry.get("config_env", ""))),
    ("controls", str(entry.get("controls", key))),
    ("directory", expand(entry.get("directory", ""))),
]
records += [("arg", substitute(str(v))) for v in entry.get("args", [])]
records += [("env", f"{n}={substitute(str(v))}")
            for n, v in (entry.get("env") or {}).items()]
records += [("extension", str(e)) for e in entry.get("extensions", [])]

for field, value in records:
    if "\n" in value:
        fail(f"[apps.{key}] {field} must not contain a newline.")
    print(f"{field}\t{value}")
PY
}

records_field() {
  printf '%s\n' "$1" | awk -F'\t' -v want="$2" '$1 == want { print $2; exit }'
}

records_values() {
  printf '%s\n' "$1" | awk -F'\t' -v want="$2" '$1 == want { print $2 }'
}

# Terminates a process group started by run_foreground.  Group-wide because a
# launcher may be a wrapper script whose real UI is a child: KOReader's
# koreader.sh runs reader.lua as a child, so signalling only the direct child
# orphans the reader and leaves its window mapped forever.
stop_group() {
  kill -TERM "-$1" 2>/dev/null || kill -TERM "$1" 2>/dev/null || true
  attempt=0
  while kill -0 "-$1" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
      kill -KILL "-$1" 2>/dev/null || true
      break
    fi
    sleep 0.1
  done
}

# Runs an external program in the FOREGROUND of this script so the QuickShell
# Process owns its lifetime, but in its own process group so termination is
# group-wide.  Never background or detach: the shell drops its overlay layer
# for exactly as long as this call blocks.
run_foreground() {
  setsid "$@" &
  supervised=$!
  trap 'stop_group "$supervised"; exit 143' TERM INT HUP
  wait "$supervised"
  status=$?
  stop_group "$supervised"
  return "$status"
}

# Shared launch path for every external program.
# $1 = records block, remaining arguments are appended after the configured ones.
launch_records() {
  records=$1
  shift

  label=$(records_field "$records" label)
  key=$(records_field "$records" key)
  command=$(records_field "$records" command)
  config_dir=$(records_field "$records" config_dir)
  config_env=$(records_field "$records" config_env)

  focus_upper_output || exit 3

  if [ -n "$config_dir" ]; then
    TORCHFORM_APP_CONFIG_DIR=$config_dir
    export TORCHFORM_APP_CONFIG_DIR
    [ -n "$config_env" ] && export "$config_env=$config_dir"
  fi

  saved_ifs=$IFS
  # Split records on newlines only, so arguments keep embedded spaces; disable
  # globbing so an argument containing * is passed through untouched.
  IFS='
'
  set -f
  for assignment in $(records_values "$records" env); do
    [ -n "$assignment" ] && export "$assignment"
  done
  # shellcheck disable=SC2046
  set -- $(records_values "$records" arg) "$@"
  set +f
  IFS=$saved_ifs

  printf 'ok|%s|%s\n' "$key" "$label"
  run_foreground "$command" "$@"
}

media_exec() {
  target=${1:-}
  if [ -z "$target" ]; then
    echo 'error|No media file was selected.'
    exit 3
  fi
  if [ ! -e "$target" ]; then
    echo "error|Media file not found: $target"
    exit 3
  fi
  extension=${target##*.}
  extension=$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')
  records=$(app_records "$extension" extension) || {
    printf '%s\n' "$records"
    exit 3
  }
  launch_records "$records" "$target"
}

media_directory_exec() {
  records=$(app_records "$1") || {
    printf '%s\n' "$records"
    exit 3
  }
  label=$(records_field "$records" label)
  directory=$(records_field "$records" directory)
  if [ -z "$directory" ]; then
    echo "error|$label has no directory configured."
    exit 3
  fi
  if [ ! -d "$directory" ]; then
    echo "error|$label directory not found: $directory"
    exit 3
  fi
  has_entry=0
  for entry in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
    if [ -e "$entry" ] || [ -L "$entry" ]; then
      has_entry=1
      break
    fi
  done
  if [ "$has_entry" -eq 0 ]; then
    echo "error|$label directory is empty: $directory"
    exit 3
  fi
  launch_records "$records" "$directory"
}

launch_exec() {
  if [ -z "${1:-}" ]; then
    echo 'error|No application was requested.'
    exit 3
  fi
  records=$(app_records "$1") || {
    printf '%s\n' "$records"
    exit 3
  }
  launch_records "$records"
}

# Emits "button<TAB>keys<TAB>label" for an app's controller map.  east, start
# and mode are reserved by Torchform for Close/Home and are never returned, so
# an external program can never capture the way out.
app_controls() {
  records=$(app_records "$1") || {
    printf '%s\n' "$records"
    return 1
  }
  name=$(records_field "$records" controls)
  map=$(controls_map_file "$name") || return 0
  python3 - "$map" <<'PY'
import sys, tomllib

RESERVED = {"east", "start", "mode"}
try:
    with open(sys.argv[1], "rb") as handle:
        buttons = (tomllib.load(handle).get("buttons") or {})
except (OSError, tomllib.TOMLDecodeError) as exc:
    print(f"error|Control map is unreadable: {exc}")
    raise SystemExit(1)

for button, spec in buttons.items():
    if button in RESERVED or not isinstance(spec, dict):
        continue
    keys = str(spec.get("keys", "")).strip()
    if not keys:
        continue
    print(f"{button}\t{keys}\t{spec.get('label', button)}")
PY
}

# Translates one controller button into the key the running program expects.
# "keys" is [mod+]*keysym, or text:<literal> to type text verbatim.
app_key() {
  app=${1:-}
  button=${2:-}
  case "$button" in
    east|start|mode)
      echo "error|$button is reserved by Torchform."
      return 1
      ;;
    '')
      echo 'error|No button was given.'
      return 1
      ;;
  esac
  if ! command -v wtype >/dev/null 2>&1; then
    echo 'error|wtype is not installed; external programs cannot receive controller input.'
    return 1
  fi
  mapping=$(app_controls "$app") || {
    printf '%s\n' "$mapping"
    return 1
  }
  line=$(printf '%s\n' "$mapping" | awk -F'\t' -v want="$button" '$1 == want { print; exit }')
  if [ -z "$line" ]; then
    echo "error|$app has no mapping for $button."
    return 1
  fi
  keys=$(printf '%s' "$line" | cut -f2)
  label=$(printf '%s' "$line" | cut -f3)

  case "$keys" in
    text:*)
      wtype -- "${keys#text:}" || {
        echo "error|wtype failed to type text for $button."
        return 1
      }
      printf 'ok|%s\n' "$label"
      return 0
      ;;
  esac

  # Press each modifier, send the keysym, then release in reverse order.
  keysym=${keys##*+}
  mods=""
  rest=$keys
  while [ "$rest" != "${rest#*+}" ]; do
    modifier=${rest%%+*}
    rest=${rest#*+}
    case "$modifier" in
      shift|ctrl|alt|logo|altgr|capslock) ;;
      *)
        echo "error|Unknown modifier '$modifier' in control map for $app.$button."
        return 1
        ;;
    esac
    mods="$mods $modifier"
  done

  set --
  for modifier in $mods; do
    set -- "$@" -M "$modifier"
  done
  set -- "$@" -k "$keysym"
  for modifier in $(printf '%s\n' $mods | tac); do
    set -- "$@" -m "$modifier"
  done

  if ! wtype "$@"; then
    echo "error|wtype failed to send $keys for $button."
    return 1
  fi
  printf 'ok|%s\n' "$label"
}

# ─── Background services ─────────────────────────────────────────────────────
# Quick Settings can only be honest about a control if whatever backs it is
# actually running.  Services are declared in config.toml and started
# asynchronously so bringing them up never delays the shell.
service_records() {
  TORCHFORM_CONFIG_REGISTRIES=$(config_registry_files)
  if [ -z "$TORCHFORM_CONFIG_REGISTRIES" ]; then
    echo 'error|No config.toml found; services are unconfigured.'
    return 1
  fi
  export TORCHFORM_CONFIG_REGISTRIES
  python3 - <<'PY'
import os, tomllib

services = {}
for registry in os.environ["TORCHFORM_CONFIG_REGISTRIES"].splitlines():
    try:
        with open(registry, "rb") as handle:
            data = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        print(f"error|{registry} is unreadable: {exc}")
        raise SystemExit(1)
    configured = data.get("services") or {}
    if not isinstance(configured, dict):
        print(f"error|{registry} [services] is not a table.")
        raise SystemExit(1)
    services.update(configured)

for name, entry in services.items():
    if not isinstance(entry, dict):
        continue
    command = os.path.expanduser(str(entry.get("command", "")))
    if not command:
        continue
    fields = [
        name,
        str(entry.get("label", name)),
        command,
        str(entry.get("check", "")),
        ",".join(str(v) for v in entry.get("requires", [])),
        ",".join(str(v) for v in entry.get("provides", [])),
        "\x1f".join(str(v) for v in entry.get("args", [])),
    ]
    print("\t".join(f.replace("\n", " ") for f in fields))
PY
}

# Emits "name<TAB>state<TAB>label<TAB>detail".  States: running, started,
# missing (binary absent), failed.
services_status() {
  records=$(service_records) || {
    printf '%s\n' "$records"
    return 1
  }
  printf '%s\n' "$records" | while IFS='	' read -r name label command check requires provides args; do
    [ -n "$name" ] || continue
    if [ -n "$check" ] && sh -c "$check" >/dev/null 2>&1; then
      printf '%s\trunning\t%s\t\n' "$name" "$label"
    elif ! command -v "$command" >/dev/null 2>&1 && [ ! -x "$command" ]; then
      if [ -n "$requires" ]; then
        printf '%s\tmissing\t%s\tInstall %s\n' "$name" "$label" "$requires"
      else
        printf '%s\tmissing\t%s\t%s is not installed\n' "$name" "$label" "$command"
      fi
    else
      printf '%s\tstopped\t%s\t\n' "$name" "$label"
    fi
  done
}

# Starts every configured service that is installed and not already running.
# Services are daemons, so unlike an external app they are detached on purpose:
# they must outlive the command that started them and must never block startup.
services_start() {
  records=$(service_records) || {
    printf '%s\n' "$records"
    return 1
  }
  log_dir="${XDG_RUNTIME_DIR:-/tmp}/torchform"
  mkdir -p "$log_dir"
  printf '%s\n' "$records" | while IFS='	' read -r name label command check requires provides args; do
    [ -n "$name" ] || continue
    if [ -n "$check" ] && sh -c "$check" >/dev/null 2>&1; then
      printf 'ok|%s|%s is already running\n' "$name" "$label"
      continue
    fi
    if ! command -v "$command" >/dev/null 2>&1 && [ ! -x "$command" ]; then
      if [ -n "$requires" ]; then
        printf 'error|%s needs a package that is not installed: %s\n' "$label" "$requires"
      else
        printf 'error|%s is not installed: %s\n' "$label" "$command"
      fi
      continue
    fi
    saved_ifs=$IFS
    IFS=''
    set -f
    set --
    if [ -n "$args" ]; then
      IFS=''
      # Arguments are unit-separator joined so spaces inside one survive.
      old=$IFS
      IFS=$(printf '\037')
      # shellcheck disable=SC2086
      set -- $args
      IFS=$old
    fi
    set +f
    IFS=$saved_ifs
    setsid "$command" "$@" >"$log_dir/$name.log" 2>&1 </dev/null &
    printf 'ok|%s|%s starting\n' "$name" "$label"
  done
}

NOTES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/torchform/notes"

note_path() {
  name=$1
  # Notes are flat files; reject anything that escapes the notes directory.
  case "$name" in
    ""|*/*|.|..) return 1 ;;
  esac
  case "$name" in
    *.md) printf '%s/%s\n' "$NOTES_DIR" "$name" ;;
    *)    printf '%s/%s.md\n' "$NOTES_DIR" "$name" ;;
  esac
}

notes_list() {
  mkdir -p "$NOTES_DIR"
  printf 'path\t%s\n' "$NOTES_DIR"
  for note in "$NOTES_DIR"/*.md; do
    [ -f "$note" ] || continue
    size=$(wc -c <"$note" 2>/dev/null | tr -d ' ')
    modified=$(date -r "$note" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '—')
    printf 'note\t%s\t%s\t%s\t%s\n' "$(basename "$note")" "${size:-0}" "$modified" "$note"
  done
}

notes_read() {
  target=$1
  case "$target" in
    "$NOTES_DIR"/*.md) ;;
    *) target=$(note_path "$target") || { echo 'error|Invalid note name.'; return 0; } ;;
  esac
  if [ ! -f "$target" ]; then
    echo 'error|Note not found.'
    return 0
  fi
  printf 'body\t%s\n' "$target"
  cat "$target"
}

notes_write() {
  name=$1
  body=$2
  target=$(note_path "$name") || { echo 'error|Invalid note name.'; return 0; }
  mkdir -p "$NOTES_DIR"
  tmp="$target.$$"
  printf '%s\n' "$body" >"$tmp" || { echo 'error|Unable to write the note.'; return 0; }
  mv -f "$tmp" "$target"
  printf 'ok|Saved %s\n' "$(basename "$target")"
}

notes_delete() {
  target=$(note_path "${1:-}") || { echo 'error|Invalid note name.'; return 0; }
  if [ ! -f "$target" ]; then
    echo 'error|Note not found.'
    return 0
  fi
  rm -f "$target"
  printf 'ok|Deleted %s\n' "$(basename "$target")"
}

# Alpine runs OpenRC with BusyBox syslog, so journalctl does not exist here.
logs_read() {
  source_name=$1
  limit=200
  case "$source_name" in
    kernel)
      if command -v dmesg >/dev/null 2>&1 && dmesg >/dev/null 2>&1; then
        dmesg | tail -n "$limit"
      else
        echo 'status|Kernel log needs elevated access on this device.'
      fi
      ;;
    torchform)
      for log in /tmp/quickshell-hdmi.log /tmp/torchform-inputd.log /tmp/sway-hdmi.log; do
        [ -f "$log" ] || continue
        printf '== %s ==\n' "$log"
        tail -n 60 "$log"
      done
      ;;
    system)
      if [ -r /var/log/messages ]; then
        tail -n "$limit" /var/log/messages
      elif command -v logread >/dev/null 2>&1; then
        logread 2>/dev/null | tail -n "$limit"
      else
        echo 'status|No readable system log; enable syslog (busybox-openrc) to populate /var/log/messages.'
      fi
      ;;
    *)
      echo 'error|Unknown log source.'
      ;;
  esac
}

# Alpine uses apk, not pacman.
pkg_list() {
  query=$1
  if ! command -v apk >/dev/null 2>&1; then
    echo 'status|apk is not available on this system.'
    return 0
  fi
  apk info -v 2>/dev/null | sort | while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
      *-*)
        version=${entry##*-r}
        name=${entry%-*-r*}
        version="${entry#"$name"-}"
        ;;
      *)
        name=$entry
        version='—'
        ;;
    esac
    if [ -n "$query" ]; then
      case "$name" in
        *"$query"*) ;;
        *) continue ;;
      esac
    fi
    printf 'pkg\t%s\t%s\n' "$name" "$version"
  done
}

pkg_info() {
  name=$1
  if [ -z "$name" ]; then
    echo 'error|No package selected.'
    return 0
  fi
  if ! command -v apk >/dev/null 2>&1; then
    echo 'status|apk is not available on this system.'
    return 0
  fi
  apk info -a "$name" 2>/dev/null | head -n 40
}

# Power actions need root. doas without a password is the only safe automatic
# path; otherwise report the exact command the operator must authorize.
power_action() {
  action=$1
  case "$action" in
    poweroff|reboot|suspend) ;;
    *) echo 'error|Unknown power action.'; return 0 ;;
  esac
  if [ "$action" = suspend ]; then
    # CM5 has no working suspend-to-RAM; halting is the supported low-power path.
    echo 'status|This board has no suspend-to-RAM; use Power Off instead.'
    return 0
  fi
  if command -v doas >/dev/null 2>&1 && doas -n true >/dev/null 2>&1; then
    doas -n "$action" >/dev/null 2>&1 &
    printf 'ok|%s requested\n' "$action"
    return 0
  fi
  printf 'error|%s needs authorization: run "doas %s" from a terminal.\n' "$action" "$action"
}
SETTINGS_STORE="${XDG_CONFIG_HOME:-$HOME/.config}/torchform/settings.conf"

settings_schema_file() {
  for candidate in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/torchform/settings-schema.toml" \
    /etc/torchform/settings-schema.toml \
    "$SCRIPT_DIR/../config/settings-schema.toml" \
    "$SCRIPT_DIR/settings-schema.toml"; do
    [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

settings_stored_value() {
  [ -f "$SETTINGS_STORE" ] || return 1
  awk -F'=' -v key="$1" '
    index($0, key "=") == 1 { sub(/^[^=]*=/, ""); value = $0 }
    END { if (value != "") { print value; exit 0 } exit 1 }
  ' "$SETTINGS_STORE"
}

# Live values for the keys that have a real device backend.
settings_live_value() {
  case "$1" in
    display.brightness)
      for candidate in /sys/class/backlight/*/brightness; do
        [ -r "$candidate" ] || continue
        maximum=$(cat "${candidate%/brightness}/max_brightness" 2>/dev/null || echo 0)
        current=$(cat "$candidate" 2>/dev/null || echo 0)
        [ "${maximum:-0}" -gt 0 ] 2>/dev/null || return 1
        printf '%s\n' "$((current * 100 / maximum))"
        return 0
      done
      return 1
      ;;
    audio.volume)
      if command -v amixer >/dev/null 2>&1; then
        amixer sget Master 2>/dev/null | awk -F'[][]' '/%/ { gsub(/%/, "", $2); print $2; exit }'
      elif command -v wpctl >/dev/null 2>&1; then
        wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null |
          awk '/^Volume:/ { printf "%.0f\n", $2 * 100; exit }'
      elif command -v pactl >/dev/null 2>&1; then
        pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null |
          awk '{ for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+%$/) { sub(/%$/, "", $i); print $i; exit } }'
      else
        return 1
      fi
      ;;
    about.hostname) hostname 2>/dev/null ;;
    about.kernel)   uname -r 2>/dev/null ;;
    about.uptime)   uptime 2>/dev/null | sed 's/^ *//' ;;
    *) return 1 ;;
  esac
}

settings_value() {
  settings_stored_value "$1" && return 0
  settings_live_value "$1" && return 0
  printf '\n'
}

# Projects the TOML schema into tab-separated records QML can parse without a
# TOML library:  section<TAB>id<TAB>title  /  row<TAB>section<TAB>key<TAB>...
settings_schema() {
  schema=$(settings_schema_file) || { echo 'error|No settings schema found.'; return 0; }
  awk '
    function flush_row() {
      if (key == "") return
      printf "row\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
             section, key, label, icon, desc, widget, min, max, step, options
      key = ""; label = ""; icon = ""; desc = ""; widget = ""
      min = ""; max = ""; step = ""; options = ""
    }
    function value(line,   v) {
      v = line
      sub(/^[^=]*=[[:space:]]*/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      gsub(/^"|"$/, "", v)
      return v
    }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[\[section\]\]/ { flush_row(); in_row = 0; next }
    /^[[:space:]]*\[\[section\.rows\]\]/ { flush_row(); in_row = 1; next }
    /^[[:space:]]*id[[:space:]]*=/    { if (!in_row) { section = value($0); } next }
    /^[[:space:]]*title[[:space:]]*=/ { if (!in_row) { printf "section\t%s\t%s\n", section, value($0); } next }
    /^[[:space:]]*key[[:space:]]*=/    { key = value($0); next }
    /^[[:space:]]*label[[:space:]]*=/  { label = value($0); next }
    /^[[:space:]]*icon[[:space:]]*=/   { icon = value($0); next }
    /^[[:space:]]*desc[[:space:]]*=/   { desc = value($0); next }
    /^[[:space:]]*widget[[:space:]]*=/ { widget = value($0); next }
    /^[[:space:]]*min[[:space:]]*=/    { min = value($0); next }
    /^[[:space:]]*max[[:space:]]*=/    { max = value($0); next }
    /^[[:space:]]*step[[:space:]]*=/   { step = value($0); next }
    /^[[:space:]]*options[[:space:]]*=/ {
      opts = $0
      sub(/^[^=]*=[[:space:]]*/, "", opts)
      gsub(/[][]/, "", opts)
      gsub(/"/, "", opts)
      gsub(/[[:space:]]*,[[:space:]]*/, "|", opts)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", opts)
      options = opts
      next
    }
    END { flush_row() }
  ' "$schema" | while IFS= read -r record; do
    case "$record" in
      row*)
        record_key=$(printf '%s' "$record" | cut -f3)
        printf '%s\t%s\n' "$record" "$(settings_value "$record_key")"
        ;;
      *) printf '%s\n' "$record" ;;
    esac
  done
}

settings_set() {
  key=$1
  value=$2
  if [ -z "$key" ]; then
    echo 'error|No setting selected.'
    return 0
  fi
  mkdir -p "$(dirname "$SETTINGS_STORE")"
  tmp="$SETTINGS_STORE.$$"
  if [ -f "$SETTINGS_STORE" ]; then
    grep -v "^$key=" "$SETTINGS_STORE" >"$tmp" 2>/dev/null || : >"$tmp"
  else
    : >"$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv -f "$tmp" "$SETTINGS_STORE"
  # Apply the values that have a real backend; report the rest as stored only.
  case "$key" in
    display.brightness)
      for candidate in /sys/class/backlight/*/brightness; do
        [ -w "$candidate" ] || continue
        maximum=$(cat "${candidate%/brightness}/max_brightness")
        printf '%s\n' "$((value * maximum / 100))" >"$candidate"
        printf 'ok|Brightness %s%%\n' "$value"
        return 0
      done
      printf 'ok|Saved %s (no writable backlight; value stored)\n' "$key"
      ;;
    audio.volume)
      if command -v amixer >/dev/null 2>&1 &&
         amixer sset Master "${value}%" >/dev/null 2>&1; then
        printf 'ok|Volume %s%%\n' "$value"
        return 0
      fi
      if command -v wpctl >/dev/null 2>&1 &&
         wpctl set-volume @DEFAULT_AUDIO_SINK@ "${value}%" --limit 1.0 >/dev/null 2>&1; then
        printf 'ok|Volume %s%%\n' "$value"
        return 0
      fi
      if command -v pactl >/dev/null 2>&1 &&
         pactl set-sink-volume @DEFAULT_SINK@ "${value}%" >/dev/null 2>&1; then
        printf 'ok|Volume %s%%\n' "$value"
        return 0
      fi
      printf 'ok|Saved %s (no live mixer; value stored)\n' "$key"
      ;;
    *)
      printf 'ok|Saved %s = %s\n' "$key" "$value"
      ;;
  esac
}

settings_action() {
  case "${1:-}" in
    system.reset_defaults)
      rm -f "$SETTINGS_STORE"
      echo 'ok|Settings reset to defaults'
      ;;
    sysapps.scan)
      count=$(find "${XDG_CONFIG_HOME:-$HOME/.config}" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
      printf 'ok|Found %s entries in ~/.config\n' "$count"
      ;;
    input.remap|keybinds.remap)
      echo 'status|Keybind remapping is edited in ~/.config/torchform/input.toml'
      ;;
    *)
      echo 'status|This action has no device backend yet.'
      ;;
  esac
}



NOTIFY_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/torchform/notifications.log"
NOTIFY_LIMIT=50

# This build of QuickShell has no Quickshell.Services.Notifications module, so
# the shell cannot own org.freedesktop.Notifications. Local programs post here
# instead with torchform-notify; the shell polls the file.
notify_add() {
    app=${1:-System}
    title=${2:-}
    body=${3:-}
    if [ -z "$title" ]; then
        echo 'error|A notification needs a title.'
        return 0
    fi
    mkdir -p "$(dirname "$NOTIFY_LOG")"
    stamp=$(date '+%H:%M')
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$stamp" "$app" "$title" "$body" >>"$NOTIFY_LOG"
    lines=$(wc -l <"$NOTIFY_LOG" 2>/dev/null | tr -d ' ')
    if [ "${lines:-0}" -gt "$NOTIFY_LIMIT" ]; then
        tail -n "$NOTIFY_LIMIT" "$NOTIFY_LOG" >"$NOTIFY_LOG.$$" && mv -f "$NOTIFY_LOG.$$" "$NOTIFY_LOG"
    fi
    printf 'ok|%s: %s\n' "$app" "$title"
}

notify_list() {
    [ -f "$NOTIFY_LOG" ] || return 0
    # Newest first, matching the panel order.
    tac "$NOTIFY_LOG" 2>/dev/null || sed '1!G;h;$!d' "$NOTIFY_LOG"
}

notify_clear() {
    id=${1:-}
    if [ -z "$id" ]; then
        rm -f "$NOTIFY_LOG"
        echo 'ok|Notifications cleared'
        return 0
    fi
    [ -f "$NOTIFY_LOG" ] || { echo 'ok|Notifications cleared'; return 0; }
    grep -v "^$id	" "$NOTIFY_LOG" >"$NOTIFY_LOG.$$" 2>/dev/null || : >"$NOTIFY_LOG.$$"
    mv -f "$NOTIFY_LOG.$$" "$NOTIFY_LOG"
    echo 'ok|Notification dismissed'
}

qs_state() {
  qs_volume_report=''
  qs_volume_level=''
  qs_volume_backend=''
  if command -v amixer >/dev/null 2>&1; then
    qs_volume_status=0
    qs_volume_report=$(amixer get Master 2>/dev/null || qs_volume_status=$?)
    if [ "$qs_volume_status" -eq 0 ]; then
      qs_volume_level=$(printf '%s\n' "$qs_volume_report" | awk '
        {
          for (i = 1; i <= NF; i++) {
            token = $i
            gsub(/[^0-9%]/, "", token)
            if (token ~ /^[0-9][0-9]*%$/) {
              sub(/%$/, "", token)
              print token
              exit
            }
          }
        }' || true)
      case "$qs_volume_level" in
        ''|*[!0-9]*) ;;
        *)
          [ "$qs_volume_level" -le 100 ] || qs_volume_level=100
          printf 'slider|volume|available|%s\n' "$qs_volume_level"
          qs_volume_backend=amixer
          ;;
      esac
    fi
  fi
  if [ -z "$qs_volume_backend" ] && command -v wpctl >/dev/null 2>&1; then
    qs_volume_status=0
    qs_volume_report=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || qs_volume_status=$?)
    if [ "$qs_volume_status" -eq 0 ]; then
      qs_volume_level=$(printf '%s\n' "$qs_volume_report" |
        awk '/^Volume:/ { printf "%.0f\n", $2 * 100; exit }' || true)
      case "$qs_volume_level" in
        ''|*[!0-9]*) ;;
        *)
          [ "$qs_volume_level" -le 100 ] || qs_volume_level=100
          printf 'slider|volume|available|%s\n' "$qs_volume_level"
          qs_volume_backend=wpctl
          ;;
      esac
    fi
  fi
  if [ -z "$qs_volume_backend" ] && command -v pactl >/dev/null 2>&1; then
    qs_volume_status=0
    qs_volume_report=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null || qs_volume_status=$?)
    if [ "$qs_volume_status" -eq 0 ]; then
      qs_volume_level=$(printf '%s\n' "$qs_volume_report" | awk '
        {
          for (i = 1; i <= NF; i++) {
            token = $i
            gsub(/[^0-9%]/, "", token)
            if (token ~ /^[0-9][0-9]*%$/) {
              sub(/%$/, "", token)
              print token
              exit
            }
          }
        }' || true)
      case "$qs_volume_level" in
        ''|*[!0-9]*) ;;
        *)
          [ "$qs_volume_level" -le 100 ] || qs_volume_level=100
          printf 'slider|volume|available|%s\n' "$qs_volume_level"
          qs_volume_backend=pactl
          ;;
      esac
    fi
  fi
  if [ -z "$qs_volume_backend" ]; then
    echo 'slider|volume|unavailable|No live amixer, wpctl, or pactl volume control is available.'
  fi

  qs_backlight=''
  for qs_candidate in /sys/class/backlight/*/brightness; do
    if [ -w "$qs_candidate" ]; then
      qs_backlight=$qs_candidate
      break
    fi
  done
  if [ -z "$qs_backlight" ]; then
    echo 'slider|brightness|unavailable|No writable backlight control is available.'
  else
    qs_brightness_status=0
    qs_brightness_max=$(cat "${qs_backlight%/brightness}/max_brightness" 2>/dev/null) || qs_brightness_status=$?
    qs_brightness_current=$(cat "$qs_backlight" 2>/dev/null) || qs_brightness_status=$?
    if [ "$qs_brightness_status" -ne 0 ]; then
      echo 'slider|brightness|unavailable|No writable backlight control is available.'
    else
      case "$qs_brightness_max:$qs_brightness_current" in
        ''|:*|*:|*[!0-9:]*|*:*:*)
          echo 'slider|brightness|unavailable|No writable backlight control is available.'
          ;;
        *)
          qs_max=${qs_brightness_max%%:*}
          qs_current=${qs_brightness_current##*:}
          if [ "$qs_max" -le 0 ]; then
            echo 'slider|brightness|unavailable|No writable backlight control is available.'
          else
            qs_brightness_percent=$(( (qs_current * 100 + qs_max / 2) / qs_max ))
            [ "$qs_brightness_percent" -ge 0 ] || qs_brightness_percent=0
            [ "$qs_brightness_percent" -le 100 ] || qs_brightness_percent=100
            printf 'slider|brightness|available|%s\n' "$qs_brightness_percent"
          fi
          ;;
      esac
    fi
  fi

  qs_wifi_station=$(find_wifi_station || true)
  if [ -z "$qs_wifi_station" ]; then
    echo 'tile|wifi|unavailable|No Wi-Fi station found.'
  else
    qs_wifi_on=off
    qs_wifi_rfkill=''
    if command -v rfkill >/dev/null 2>&1; then
      qs_wifi_rfkill=$(rfkill list wifi 2>/dev/null || true)
    fi
    if [ -n "$qs_wifi_rfkill" ]; then
      qs_wifi_blocked=$(printf '%s\n' "$qs_wifi_rfkill" | awk '
        /Soft blocked:[[:space:]]+yes|Hard blocked:[[:space:]]+yes/ { blocked = 1 }
        END { print blocked ? "yes" : "no" }' || true)
      [ "$qs_wifi_blocked" = yes ] || qs_wifi_on=on
    else
      qs_wifi_operstate=$(cat "/sys/class/net/$qs_wifi_station/operstate" 2>/dev/null || true)
      qs_wifi_carrier=$(cat "/sys/class/net/$qs_wifi_station/carrier" 2>/dev/null || true)
      qs_wifi_link=$(iw dev "$qs_wifi_station" link 2>/dev/null || true)
      if [ "$qs_wifi_operstate" = up ] || [ "$qs_wifi_carrier" = 1 ]; then
        qs_wifi_on=on
      elif printf '%s\n' "$qs_wifi_link" | awk '
        /^[[:space:]]*Connected to / { found = 1 }
        END { exit found ? 0 : 1 }'; then
        qs_wifi_on=on
      fi
    fi
    printf 'tile|wifi|available|%s\n' "$qs_wifi_on"
  fi

  if ! command -v bluetoothctl >/dev/null 2>&1; then
    echo 'tile|bluetooth|unavailable|Bluetooth tools missing: install and enable bluez (bluetoothctl).'
  elif ! command -v timeout >/dev/null 2>&1; then
    echo 'tile|bluetooth|unavailable|timeout is not installed; Bluetooth controller cannot be verified.'
  else
    qs_bluetooth_status=0
    qs_bluetooth_show=$(timeout 3 bluetoothctl show 2>/dev/null) || qs_bluetooth_status=$?
    # bluetoothctl is only the client. Without the bluetoothd daemon the tile
    # can never work, and telling the user to "start the service" is useless
    # when the package providing it is not installed at all.
    if [ "$qs_bluetooth_status" -ne 0 ] || ! printf '%s\n' "$qs_bluetooth_show" | awk '
      /^[[:space:]]*Controller[[:space:]]/ { found = 1 }
      END { exit found ? 0 : 1 }'; then
      qs_bluetooth_service=$(services_status 2>/dev/null |
        awk -F '\t' '$1 == "bluetooth" { print $2; exit }' || true)
      if [ "$qs_bluetooth_service" = missing ]; then
        echo 'tile|bluetooth|unavailable|Bluetooth needs the package configured for the bluetooth service.'
      else
        echo 'tile|bluetooth|unavailable|Bluetooth is installed; start the privileged bluetooth OpenRC service.'
      fi
    else
      qs_bluetooth_powered=$(printf '%s\n' "$qs_bluetooth_show" | awk '
        /^[[:space:]]*Powered:[[:space:]]*/ { print $2; exit }' || true)
      case "$qs_bluetooth_powered" in
        yes)
          echo 'tile|bluetooth|available|on'
          ;;
        no)
          echo 'tile|bluetooth|available|off'
          ;;
        *)
          echo 'tile|bluetooth|unavailable|Bluetooth controller power state is unavailable.'
          ;;
      esac
    fi
  fi

  qs_airplane_state=off
  qs_airplane_file=$(quick_state_file airplane)
  [ ! -r "$qs_airplane_file" ] || qs_airplane_state=$(cat "$qs_airplane_file")
  if command -v rfkill >/dev/null 2>&1; then
    printf 'tile|airplane|available|%s\n' "$qs_airplane_state"
  else
    echo 'tile|airplane|unavailable|Airplane mode needs rfkill.'
  fi
  qs_dnd_state=off
  qs_dnd_file=$(quick_state_file dnd)
  [ ! -r "$qs_dnd_file" ] || qs_dnd_state=$(cat "$qs_dnd_file")
  printf 'tile|dnd|available|%s\n' "$qs_dnd_state"
  echo 'tile|dark-mode|unavailable|The current theme backend is fixed dark.'
  echo 'tile|rotate|unavailable|No orientation sensor is present.'
}

quick_state_dir() {
  printf '%s/torchform\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

quick_state_file() {
  printf '%s/quick-settings-%s\n' "$(quick_state_dir)" "$1"
}

quick_state_set() {
  state_name=$1
  state_value=$2
  state_dir=$(quick_state_dir)
  mkdir -p "$state_dir"
  printf '%s\n' "$state_value" >"$(quick_state_file "$state_name")"
}

quick_action() {
  action=$1
  target=$2
  case "$action" in
    sys.airplane)
      if ! command -v rfkill >/dev/null 2>&1; then
        echo 'error|Airplane mode unavailable: rfkill is not installed.'
        return 0
      fi
      if [ "$target" = "on" ]; then
        if ! rfkill block all >/tmp/torchform-rfkill.log 2>&1; then
          msg=$(tail -1 /tmp/torchform-rfkill.log 2>/dev/null || true)
          echo "error|Airplane mode failed: ${msg:-permission denied}"
          return 0
        fi
        quick_state_set airplane on
        echo 'state|on|Airplane mode enabled.'
      else
        if ! rfkill unblock all >/tmp/torchform-rfkill.log 2>&1; then
          msg=$(tail -1 /tmp/torchform-rfkill.log 2>/dev/null || true)
          echo "error|Airplane mode failed: ${msg:-permission denied}"
          return 0
        fi
        quick_state_set airplane off
        echo 'state|off|Airplane mode disabled.'
      fi
      ;;
    sys.dnd)
      quick_state_set dnd "$target"
      if [ "$target" = "on" ]; then
        echo 'state|on|Do Not Disturb enabled for Torchform notifications.'
      else
        echo 'state|off|Do Not Disturb disabled.'
      fi
      ;;
    sys.dark-mode)
      echo 'error|Dark mode is unavailable: the current theme backend is fixed dark.'
      ;;
    sys.rotate)
      echo 'error|Auto-rotate is unavailable: no orientation sensor is present.'
      ;;
    *)
      echo "error|Unsupported Quick Settings action: $action"
      ;;
  esac
}

quick_slider() {
  slider=$1
  direction=$2
  case "$slider" in
    brightness|volume)
      "$0" "${slider}-step" "$direction"
      ;;
    *)
      echo "error|Unsupported Quick Settings slider: $slider"
      ;;
  esac
}

case "$cmd" in
  qs-state)
    qs_state
    ;;
  wifi-scan)
    sta=$(find_wifi_station || true)
    if [ -z "${sta:-}" ]; then
      echo 'error|No Wi-Fi station found.'
      exit 0
    fi
    if command -v iwctl >/dev/null 2>&1; then
      iwctl station "$sta" scan >/dev/null 2>&1 && echo "ok|Wi-Fi scan complete on $sta" ||
        echo "error|Wi-Fi scan failed on $sta"
    elif command -v wpa_cli >/dev/null 2>&1 && wpa_cli -i "$sta" scan >/dev/null 2>&1; then
      echo "ok|Wi-Fi scan started on $sta"
    elif command -v iw >/dev/null 2>&1 && iw dev "$sta" scan >/dev/null 2>&1; then
      echo "ok|Wi-Fi scan complete on $sta"
    else
      echo 'error|Wi-Fi scan needs iwd, wpa_supplicant control, or elevated iw access.'
    fi
    ;;
  wifi-list)
    sta=$(find_wifi_station || true)
    if [ -z "${sta:-}" ]; then
      echo 'status|No Wi-Fi station found.'
      exit 0
    fi
    if command -v iwctl >/dev/null 2>&1; then
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
    elif command -v iw >/dev/null 2>&1; then
      link=$(iw dev "$sta" link 2>/dev/null || true)
      ssid=$(printf '%s\n' "$link" | awk -F': ' '/^[[:space:]]*SSID:/ { print $2; exit }')
      signal=$(printf '%s\n' "$link" | awk '/^[[:space:]]*signal:/ { print $2; exit }')
      if [ -n "${ssid:-}" ]; then
        band=$(iw dev "$sta" info 2>/dev/null | awk '/channel/ { print $2 " MHz"; exit }')
        printf 'network|%s|%s|%s|1\n' "$ssid" "${signal:--}" "${band:-connected}"
        printf 'status|Connected via iw on %s\n' "$sta"
      else
        echo 'status|iw is available, but wlan0 is not connected; scanning requires a privileged Wi-Fi backend.'
      fi
    else
      echo 'status|Wi-Fi tools missing: install/enable iwd or configure wpa_supplicant.'
    fi
    ;;
  wifi-connect)
    ssid=${2:-}
    passphrase=${3:-}
    if [ -z "$ssid" ]; then echo 'error|No SSID selected.'; exit 0; fi
    sta=$(find_wifi_station || true)
    if [ -z "${sta:-}" ]; then echo 'error|No Wi-Fi station found.'; exit 0; fi
    if command -v iwctl >/dev/null 2>&1; then
      if [ -n "$passphrase" ]; then
        iwctl --passphrase "$passphrase" station "$sta" connect "$ssid" >/tmp/torchform-wifi-connect.log 2>&1
      else
        iwctl station "$sta" connect "$ssid" >/tmp/torchform-wifi-connect.log 2>&1
      fi
      if [ "$?" -eq 0 ]; then
        echo "ok|Connected to $ssid"
      else
        msg=$(tail -1 /tmp/torchform-wifi-connect.log 2>/dev/null || true)
        echo "error|${msg:-Failed to connect to $ssid}"
      fi
    else
      echo 'error|Wi-Fi scan/connection backend unavailable; enable iwd or wpa_supplicant.'
    fi
    ;;
  bluetooth-pair)
    addr=${2:-}
    pin=${3:-}
    if [ -z "$addr" ]; then echo 'error|No Bluetooth device selected.'; exit 0; fi
    if ! command -v bluetoothctl >/dev/null 2>&1; then echo 'error|bluetoothctl is not installed.'; exit 0; fi
    if [ -z "$pin" ]; then echo 'error|A pairing PIN is required.'; exit 0; fi
    {
      printf 'agent KeyboardOnly\n'
      printf 'default-agent\n'
      printf 'pair %s\n' "$addr"
      sleep 1
      printf '%s\n' "$pin"
      printf 'trust %s\n' "$addr"
      printf 'connect %s\n' "$addr"
      printf 'quit\n'
    } | timeout 30 bluetoothctl >/tmp/torchform-bt-pair.log 2>&1
    if grep -qiE 'successful|connected: yes' /tmp/torchform-bt-pair.log 2>/dev/null; then
      echo "ok|Paired and connected to $addr"
    else
      msg=$(tail -1 /tmp/torchform-bt-pair.log 2>/dev/null || true)
      echo "error|${msg:-Failed to pair with $addr}"
    fi
    ;;
  bluetooth-list)
    if ! command -v bluetoothctl >/dev/null 2>&1; then
      echo 'status|Bluetooth tools missing: install and enable bluez (bluetoothctl).'
      exit 0
    fi
    devices=$(timeout 4 bluetoothctl devices 2>/dev/null || true)
    if [ -z "${devices:-}" ]; then
      if timeout 3 bluetoothctl show 2>/dev/null | awk '/Controller / { found=1 } END { exit found ? 0 : 1 }'; then
        echo 'status|No Bluetooth devices found.'
      else
        echo 'status|Bluetooth is unavailable; start the BlueZ service before scanning.'
      fi
      exit 0
    fi
    printf '%s\n' "$devices" | while read -r _ addr name; do
      [ -n "${addr:-}" ] || continue
      info=$(timeout 3 bluetoothctl info "$addr" 2>/dev/null || true)
      paired=$(printf '%s\n' "$info" | awk '/Paired:/ {print $2; exit}')
      connected=$(printf '%s\n' "$info" | awk '/Connected:/ {print $2; exit}')
      icon='📱'
      printf '%s\n' "$info" | awk 'BEGIN { IGNORECASE=1 } /Audio/ { found=1 } END { exit found ? 0 : 1 }' && icon='🔊'
      printf '%s\n' "$info" | awk 'BEGIN { IGNORECASE=1 } /Keyboard|Input|HID|Gamepad|Joystick/ { found=1 } END { exit found ? 0 : 1 }' && icon='🎮'
      printf 'device|%s|%s|%s|%s|%s\n' "$addr" "${name:-$addr}" "${paired:-no}" "${connected:-no}" "$icon"
    done
    ;;
  bluetooth-scan)
    if ! command -v bluetoothctl >/dev/null 2>&1; then echo 'error|bluetoothctl is not installed.'; exit 0; fi
    timeout 20 bluetoothctl scan on >/tmp/torchform-bt-scan.log 2>&1 &
    echo 'ok|Bluetooth scan started.'
    ;;
  bluetooth-stop-scan)
    command -v bluetoothctl >/dev/null 2>&1 && timeout 3 bluetoothctl scan off >/dev/null 2>&1 || true
    echo 'ok|Bluetooth scan stopped.'
    ;;
  bluetooth-connect)
    addr=${2:-}
    if [ -z "$addr" ]; then echo 'error|No Bluetooth device selected.'; exit 0; fi
    if ! command -v bluetoothctl >/dev/null 2>&1; then echo 'error|bluetoothctl is not installed.'; exit 0; fi
    if timeout 10 bluetoothctl connect "$addr" >/tmp/torchform-bt-connect.log 2>&1 ||
       timeout 10 bluetoothctl pair "$addr" >/tmp/torchform-bt-connect.log 2>&1; then
      timeout 3 bluetoothctl trust "$addr" >/dev/null 2>&1 || true
      echo "ok|Connected to $addr"
    else
      trust_status=0
      timeout 3 bluetoothctl trust "$addr" >/tmp/torchform-bt-trust.log 2>&1 || trust_status=$?
      if [ "$trust_status" -eq 0 ]; then
        echo "ok|Connected to $addr"
      else
        echo "error|Failed to trust $addr."
      fi
    fi
    ;;
  volume-step)
    direction=${2:-up}
    volume_backend=''
    if command -v amixer >/dev/null 2>&1; then
      if [ "$direction" = down ]; then
        if amixer sset Master 5%- >/dev/null 2>&1; then
          volume_backend=amixer
        fi
      elif amixer sset Master 5%+ >/dev/null 2>&1; then
        volume_backend=amixer
      fi
    fi
    if [ -z "$volume_backend" ] && command -v wpctl >/dev/null 2>&1; then
      if [ "$direction" = down ]; then
        if wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- --limit 1.0 >/dev/null 2>&1; then
          volume_backend=wpctl
        fi
      elif wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ --limit 1.0 >/dev/null 2>&1; then
        volume_backend=wpctl
      fi
    fi
    if [ -z "$volume_backend" ] && command -v pactl >/dev/null 2>&1; then
      if [ "$direction" = down ]; then
        if pactl set-sink-volume @DEFAULT_SINK@ -5% >/dev/null 2>&1; then
          volume_backend=pactl
        fi
      elif pactl set-sink-volume @DEFAULT_SINK@ +5% >/dev/null 2>&1; then
        volume_backend=pactl
      fi
    fi
    if [ -n "$volume_backend" ]; then
      echo "ok|Volume adjusted ${direction}"
    else
      echo 'error|No live amixer, wpctl, or pactl volume control is available.'
    fi
    ;;
  quick-action)
    quick_action "${2:-}" "${3:-off}"
    ;;
  quick-slider)
    quick_slider "${2:-}" "${3:-up}"
    ;;
  quick-state)
    state_name=${2:-}
    state_value=off
    state_file=$(quick_state_file "$state_name")
    if [ -r "$state_file" ]; then
      state_value=$(cat "$state_file")
    fi
    printf 'state|%s|%s\n' "$state_name" "$state_value"
    ;;


  state-write)
    state_write "$@"
    ;;
  media-launch)
    # Categories are app keys; the browser has no media directory so it opens
    # with no target.  Everything else is resolved from config.
    case "${2:-}" in
      '')
        echo 'error|No media launcher was requested.'
        ;;
      browser)
        launch_exec browser
        ;;
      *)
        media_directory_exec "$2"
        ;;
    esac
    ;;
  app-config)
    if ! records=$(app_records "${2:-}"); then
      printf '%s\n' "$records"
      exit 3
    fi
    printf '%s\n' "$records"
    ;;
  app-controls)
    app_controls "${2:-}"
    ;;
  app-key)
    app_key "${2:-}" "${3:-}"
    ;;
  services-start)
    services_start
    ;;
  services-status)
    services_status
    ;;
  applications-list)
    list_file="${TMPDIR:-/tmp}/torchform-launchers.$$"
    trap 'rm -f "$list_file"' EXIT HUP INT TERM

    emit_application() {
      app_name=$1
      app_icon=$2
      app_exec=$3
      app_kind=$4
      [ -n "$app_name" ] && [ -n "$app_exec" ] || return 0
      printf 'app\t%s\t%s\t%s\t%s\n' "$app_name" "$app_icon" "$app_exec" "$app_kind" >>"$list_file"
    }

    desktop_value() {
      key=$1
      file=$2
      awk -F= -v key="$key" '
        $0 == "[Desktop Entry]" { in_entry = 1; next }
        /^\[/ { in_entry = 0 }
        in_entry && $1 == key { print substr($0, index($0, "=") + 1); exit }
      ' "$file"
    }

    icon_for_name() {
      case "$1" in
        *[Tt]erminal*|*[Cc]onsole*|*[Ss]hell*) printf '⬛' ;;
        *[Bb]rowser*|*[Ww]eb*) printf '🌐' ;;
        *[Ff]ile*|*[Dd]olphin*|*[Tt]hunar*) printf '🗂️' ;;
        *[Mm]usic*|*[Mm]edia*) printf '🎵' ;;
        *) printf '🚀' ;;
      esac
    }

    app_dir="$HOME/.local/share/applications"
    for desktop in "$app_dir"/*.desktop; do
      [ -f "$desktop" ] || continue
      type=$(desktop_value Type "$desktop")
      hidden=$(desktop_value Hidden "$desktop")
      no_display=$(desktop_value NoDisplay "$desktop")
      [ "${type:-Application}" = "Application" ] || continue
      [ "${hidden:-false}" = "true" ] && continue
      [ "${no_display:-false}" = "true" ] && continue
      name=$(desktop_value Name "$desktop")
      exec_command=$(desktop_value Exec "$desktop")
      exec_command=$(printf '%s\n' "$exec_command" | sed -E 's/ %[fFuUdDnNickvm]//g; s/%%/%/g')
      emit_application "$name" "$(icon_for_name "$name")" "$exec_command" desktop
    done

    bin_dir="$HOME/.local/bin"
    for executable in "$bin_dir"/*; do
      [ -f "$executable" ] && [ -x "$executable" ] || continue
      name=${executable##*/}
      emit_application "$name" "$(icon_for_name "$name")" "$executable" executable
    done

    if [ -f "$list_file" ]; then
      sort -t '	' -k2,2f "$list_file"
    fi
    exit 0
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
  media-open)
    media_exec "${2:-}"
    ;;
  launch-exec)
    command=${2:-}
    label=${3:-external}
    if [ -z "$command" ]; then
      echo 'error|External command is empty.'
      exit 3
    fi
    focus_upper_output
    printf 'ok|external|%s\n' "$label"
    exec sh -lc "$command"
    ;;
  launch)
    launch_exec "${2:-}"
    ;;
  notes-list)
    notes_list
    ;;
  notes-read)
    notes_read "${2:-}"
    ;;
  notes-write)
    notes_write "${2:-}" "${3:-}"
    ;;
  notes-delete)
    notes_delete "${2:-}"
    ;;
  logs-read)
    logs_read "${2:-system}"
    ;;
  pkg-list)
    pkg_list "${2:-}"
    ;;
  pkg-info)
    pkg_info "${2:-}"
    ;;
  power)
    power_action "${2:-}"
    ;;
  settings-schema)
    settings_schema
    ;;
  settings-set)
    settings_set "${2:-}" "${3:-}"
    ;;
  settings-action)
    settings_action "${2:-}"
    ;;
  notify-add)
    notify_add "${2:-}" "${3:-}" "${4:-}"
    ;;
  notify-list)
    notify_list
    ;;
  notify-clear)
    notify_clear "${2:-}"
    ;;
  *)
    echo 'error|usage: torchform-control.sh applications-list|app-config APP|app-controls APP|app-key APP BUTTON|launch APP|launch-exec COMMAND LABEL|media-open PATH|media-launch APP|files-list PATH|quick-action ACTION STATE|qs-state|services-start|services-status|wifi-list|wifi-connect SSID|bluetooth-list|bluetooth-scan|bluetooth-stop-scan|bluetooth-connect ADDR|notes-list|notes-read PATH|notes-write NAME BODY|notes-delete NAME|logs-read SOURCE|pkg-list [QUERY]|pkg-info NAME|power ACTION|settings-schema|settings-set KEY VALUE|settings-action KEY'
    ;;
esac
