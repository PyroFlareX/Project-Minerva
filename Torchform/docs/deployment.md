# Torchform deployment

Torchform targets Minerva's Alpine aarch64 image. The boot service examples in
this document use OpenRC, not systemd.

## Current manual session start

The normal development/deployment path is still:

```sh
make hdmi-restart MINERVA_HOST=Minerva
```

`hdmi-restart` deploys `torchform-guishell/` and starts
`~/projects/torchform-guishell/start-hdmi.sh` on Minerva.

The session uses `XDG_RUNTIME_DIR=/tmp/xdg-hdmi`; after Sway creates its
socket, `WAYLAND_DISPLAY` is set to the discovered socket (normally
`wayland-1`). QuickShell is launched with `QT_QPA_PLATFORM=wayland`, and the
DRM startup unsets `WLR_BACKENDS` and `DISPLAY`.

The production sequence is:

1. Prepare the private `XDG_RUNTIME_DIR=/tmp/xdg-hdmi` and start
   `torchform-inputd` (the virtual gamepad is selected only when
   `TORCHFORM_VIRTUAL_GAMEPAD=1`; production leaves it unset).
2. Start Sway with `sway.conf` on the DRM/KMS backend, with
   `QT_QPA_PLATFORM=wayland` and no `DISPLAY`/`WLR_BACKENDS` override.
3. Run `configure-outputs.py` against the live output geometry. The largest
   active output is the upper role and the smaller output is the lower role.
4. Start QuickShell on the selected Wayland socket.

This target is useful for an operator who wants to restart the current session
without changing boot configuration. It does not install an init script.

## Font provisioning

The shell's typography requires these user-local families:

- Barlow Condensed (display headings and clock)
- Inter (body text)
- JetBrains Mono (monospace fallback)
- DM Mono (Torchform OS theme/system data)

The provisioning script needs no root access. It checks Fontconfig and
`~/.local/share/fonts`, downloads missing files from the first-party Google
Fonts repository into one directory per family, and refreshes the user cache.
Use these targets from `Torchform/`:

```sh
make check-fonts       # status only; non-zero when any family is missing
make install-fonts     # install missing families for the local user
make remote-install-fonts MINERVA_HOST=Minerva
```

Run `make check-fonts` after provisioning. It must report all four families as
present before treating the visual deployment as complete.

## OpenRC boot autostart

The OpenRC files are in `packaging/openrc/`. Copy them to Minerva from the
workstation, then use an interactive Minerva shell so `doas` can prompt:

```sh
scp Torchform/packaging/openrc/torchform-inputd Minerva:/tmp/torchform-inputd
scp Torchform/packaging/openrc/torchform-session Minerva:/tmp/torchform-session
ssh -t Minerva
```

Run these exact commands in that Minerva shell:

```sh
doas install -o root -g root -m 0755 /tmp/torchform-inputd /etc/init.d/torchform-inputd
doas install -o root -g root -m 0755 /tmp/torchform-session /etc/init.d/torchform-session

doas rc-update add torchform-inputd default
doas rc-update add torchform-session default
```

To start the boot services immediately instead of rebooting:

```sh
doas rc-service torchform-inputd start
doas rc-service torchform-session start
```

`torchform-session` has an OpenRC dependency on `torchform-inputd` and runs
`start-hdmi.sh` as the configured dedicated device account (`minerva` by
default). It prepares `/run/torchform` and `/tmp/xdg-hdmi` as mode-0700
directories owned by that account, and explicitly exports
`TORCHFORM_VIRTUAL_GAMEPAD=0` for a production session.

## Verification

After starting the services, and again after a reboot, verify both service
state and the default runlevel:

```sh
rc-service torchform-inputd status
rc-service torchform-session status
rc-status
```

Also inspect the service logs and runtime ownership if needed:

```sh
ls -l /var/log/torchform-inputd.log /var/log/torchform-session.log
ls -ld /run/torchform /tmp/xdg-hdmi
```

**OpenRC installation and boot verification were NOT performed on the device.**
Installing and enabling these files requires an interactive `doas` prompt on
Minerva; the commands above are the operator procedure, not evidence that the
services have already been installed or tested there.
