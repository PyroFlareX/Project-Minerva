# Torchform OpenRC services

These service files are for the Alpine aarch64 Minerva image. They run the
production controller/session path as the dedicated `minerva` device account;
the virtual gamepad smoke-test backend is not enabled.

## Install

From the repository checkout, copy the service files to Minerva:

```sh
scp Torchform/packaging/openrc/torchform-inputd Minerva:/tmp/torchform-inputd
scp Torchform/packaging/openrc/torchform-session Minerva:/tmp/torchform-session
```

Open an interactive shell on Minerva and install them with `doas`:

```sh
ssh -t Minerva

doas install -o root -g root -m 0755 /tmp/torchform-inputd /etc/init.d/torchform-inputd
doas install -o root -g root -m 0755 /tmp/torchform-session /etc/init.d/torchform-session
```

The input daemon is enabled first so the session dependency is available at
boot:

```sh
doas rc-update add torchform-inputd default
doas rc-update add torchform-session default
```

To start the services without rebooting:

```sh
doas rc-service torchform-inputd start
doas rc-service torchform-session start
```

`torchform-session` invokes
`$torchform_home/projects/torchform-guishell/start-hdmi.sh`. The
`torchform_user` and `torchform_home` variables at the top of each service file
may be changed before installation when the image uses a different dedicated
account. The startup script launches production `torchform-inputd`, Sway on the
DRM backend, derives the upper/lower output roles from live geometry, and then
starts QuickShell. The service explicitly sets `TORCHFORM_VIRTUAL_GAMEPAD=0`;
do not set it to `1` in the boot environment.

## Verify

```sh
rc-service torchform-inputd status
rc-service torchform-session status
rc-status

ls -ld /run/torchform /tmp/xdg-hdmi
ls -l /var/log/torchform-inputd.log /var/log/torchform-session.log
```

The input daemon is supervised with a bounded restart policy (five respawns in
60 seconds, with a two-second delay). The services create private mode-0700
runtime directories owned by the configured device account before starting.

**Installation needs an interactive `doas` prompt on Minerva, so it was NOT
performed.** This repository change does not install or enable either service
on the device.
