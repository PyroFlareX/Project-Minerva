On the CM5 under Alpine the main levers are:

**CPU frequency scaling (biggest win at idle/partial load)**
- Load the cpufreq governor: the RPi kernel exposes `/sys/devices/system/cpu/cpufreq/policy0/scaling_governor`. Default is often `performance` on Alpine â switch to `ondemand` or `schedutil`: `echo ondemand > .../scaling_governor` (persist via an OpenRC local.d script). This alone drops idle power dramatically since the A76s idle at 1.5GHz otherwise.
- Optionally cap max clock when on battery: `echo 1800000 > .../scaling_max_freq` (2.4GHzâ1.8GHz is a large perf/W improvement â A76 power scales superlinearly with clock).

**Firmware/config.txt (in the boot partition)**
- `arm_boost=0` â disables the 2.4GHz boost, keeps 2.2GHz max.
- Undervolt-ish: CM5 doesn't support `over_voltage` reduction officially, but lowering max freq effectively does it (DVFS).
- Disable unused blocks: `dtoverlay=disable-wifi` / `disable-bt` if using WWAN only; `camera_auto_detect=0`, `display_auto_detect=0` if unused.
- HDMI off when using DSI only: `hdmi_blanking=2` or don't enable HDMI at all.

**Peripherals (matters a lot for your board)**
- The EM7565 WWAN modem is a multi-watt device: power it down when idle via its W_DISABLE GPIO on your carrier, or `mmcli -m 0 --set-power-state-low` â add an idle policy to `minerva-wwan.sh`.
- PCIe/NVMe: enable ASPM (`pcie_aspm=force` on cmdline if the link supports it); NVMe APST usually works out of the box on 6.12.
- Backlight is typically the #1 draw on a handheld â wire brightness control early (your PHASE 5 work) and default lower.

**Thermal**
- `dtparam=fan_temp0=...` if you add a fan; otherwise a graphite pad/heatspreader to the shell. Downclocking per above cuts heat at the source; the CM5 throttles at 85Â°C so staying under 2GHz sustained mostly eliminates throttle-induced instability.

Quick test loop: `vcgencmd measure_temp` / `vcgencmd measure_clock arm` (in `raspberrypi-utils` apk) plus a USB power meter to compare governor settings â expect ~0.8â1.5W idle savings from governor + boost-off alone.