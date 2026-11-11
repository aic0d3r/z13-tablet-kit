# Z13 Tablet Kit — Linux Tablet Mode for the ASUS ROG Flow Z13

<div align="center">

[![Device](https://img.shields.io/badge/device-ROG%20Flow%20Z13%20GZ302-red)](#requirements)
[![Desktop](https://img.shields.io/badge/desktop-KDE%20Plasma%206%20%2F%20Wayland-1d99f3)](#requirements)
[![Distro](https://img.shields.io/badge/tested%20on-Arch%20%2F%20CachyOS-1793d1)](#quick-start)
[![AUR](https://img.shields.io/aur/version/z13-tablet-kit)](https://aur.archlinux.org/packages/z13-tablet-kit)
[![Tests](https://img.shields.io/badge/tests-offline%2C%20no%20hardware-brightgreen)](docs/INSTALL.md#verify)

[Features](#features) •
[Quick start](#quick-start) •
[Posture model](#posture-model) •
[Requirements](#requirements) •
[Docs](#docs)

</div>

<img src="docs/z13gui-plus-tablet-kit.png" align="right" width="300"
     alt="Z13GUI+ Tablet Kit card in desktop posture: posture, health and keyboard folio status, toggles for disabling the touchscreen on desktop, two-finger hold context menu and keeping scale across postures, plus scroll sensitivity and speed sliders.">

**Tablet mode for the 2025 ASUS ROG Flow Z13 (GZ302) on KDE Plasma 6 / Wayland.**
It detects whether the Z13 is docked, in laptop mode or held as a tablet, and adapts touch,
scale, rotation and the on-screen keyboard. No kernel patches.

- **Posture detection:** desktop, laptop or tablet, live on plug/unplug.
- **Tablet extras:** auto-rotate, on-screen keyboard, two-finger scroll and right-click.
- **Folio fixes:** jumpy touchpad inhibited; keyboard never covers the folio.

## Features

- **Auto-rotate only in tablet mode** — via a virtual `SW_TABLET_MODE` switch the GZ302
  firmware advertises but never emits.
- **On-screen keyboard that never covers the folio** — on in tablet mode, off otherwise.
- **Two-finger scroll in any app** — terminals, TUIs, browsers, document viewers.
- **Touch right-click** — a two-finger hold opens a context menu (KDE Wayland has no touch
  gesture for it).
- **Per-posture scale** — defaults `1.75` tablet, `1.5` docked and laptop.
- **Folio touchpad fix** — inhibited by default, with a guarded opt-in.
- **Live settings** — toggles in the optional [`z13gui-plus`](https://github.com/aic0d3r/z13gui-plus)
  drawer apply without restarts.

<br clear="right">

## Quick start

Arch / CachyOS (AUR), as your normal user. Stop any other Z13 hardware daemon first.

```bash
paru -S z13-tablet-kit iio-sensor-proxy   # pulls in z13ctl-plus-bin; optional: z13gui-plus-bin
systemctl --user enable --now z13ctl-plus.socket z13ctl-plus.service
systemctl --user enable --now z13-tablet-switch.service z13-touch-scroll.service
```

Then enable auto-rotate once: **Quick Settings → Auto-rotate → right-click → "Rotate only in
tablet mode"**, and reboot (or re-attach the folio) so the folio touchpad rule applies.

Other distros: see [Install from source](docs/INSTALL.md).

## Posture model

| Posture | Detected by | Touch | Tablet mode | Auto-rotate | Virtual keyboard |
|---|---|---|---|---|---|
| **desktop** | dock hub `0b05:1ac1` or any external monitor | off¹ | off | off | off |
| **laptop** | folio `0b05:1a30`, no dock | on | off | off | off |
| **tablet** | neither | on | **on** | **on** | **on** |

¹ Unless **Disable touchscreen on desktop** is turned off in `z13gui-plus`.

Priority: desktop > laptop > tablet. Posture comes from the folio, dock hub and connected
displays, not from keyboards: a Bluetooth keyboard on a bare tablet still gets the on-screen
keyboard, and a tablet on a TV is `desktop`.

## Requirements

- **KDE Plasma 6 / Wayland** and systemd. GNOME isn't supported: posture, touch and OSK
  control go through KWin. (`z13ctl-plus` and `z13gui-plus` do run on GNOME.)
- **[`z13ctl-plus`](https://github.com/aic0d3r/z13ctl-plus)** v2.2.1+ with its user socket
  enabled. Hard dependency; the AUR package pulls it in.
- `iio-sensor-proxy` (auto-rotate), `python-evdev` (touch scroll, tablet-mode switch).
- `plasma-keyboard` (Plasma 6.7, recommended) or `maliit-keyboard` (AUR, legacy).
- A udev `uaccess` rule grants touchscreen read access, so any program you run can read raw
  touch positions, including taps on the on-screen keyboard.

Should work on any Plasma 6 / Wayland distro; the install steps target Arch / CachyOS.

## Docs

- [Architecture](docs/ARCHITECTURE.md) — the three-repo stack and each component
- [Install from source, verify, uninstall](docs/INSTALL.md)
- [Tips](docs/TIPS.md) — touch scrolling, context menus, Page Up/Down, auto-rotate quirks

## Say thanks

[Star it on GitHub](https://github.com/aic0d3r/z13-tablet-kit) or
[sponsor me](https://github.com/sponsors/aic0d3r).

## License

[Apache-2.0](LICENSE)
