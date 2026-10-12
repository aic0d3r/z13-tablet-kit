# Z13 Tablet Kit — Linux Tablet Mode for the ASUS ROG Flow Z13

<div align="center">

[![Device](https://img.shields.io/badge/device-ROG%20Flow%20Z13%20GZ302-red)](#requirements)
[![Desktop](https://img.shields.io/badge/desktop-KDE%20Plasma%206%20%2F%20Wayland-1d99f3)](#requirements)
[![Distro](https://img.shields.io/badge/tested%20on-Arch%20%2F%20CachyOS-1793d1)](#install)
[![Tests](https://img.shields.io/badge/tests-offline%2C%20no%20hardware-brightgreen)](#verify)

[Features](#features) •
[Quick start](#quick-start) •
[Posture model](#posture-model) •
[The stack](#the-stack) •
[Components](#components) •
[Requirements](#requirements) •
[Install](#install) •
[Uninstall](#uninstall) •
[Tips](#tips)

</div>

A posture-aware tablet stack for the **ASUS ROG Flow Z13 (GZ302, AMD Strix Halo)** on
**KDE Plasma 6 / Wayland**. It detects whether the Z13 is **docked**, used as a **laptop** with
the keyboard folio, or held as a **tablet**, and adapts the touchscreen, display scale,
auto-rotate and on-screen keyboard to match — with **no kernel hacks** and only two udev rules
needing root.

It should run on any distro with Plasma 6 / Wayland and systemd; the install steps use
Arch / CachyOS.

## Features

- **Automatic 3-mode posture** — desktop, laptop and tablet, detected from the dock hub, the
  folio and the connected displays every two seconds.
- **Auto-rotate that only rotates in tablet mode** — via a virtual `SW_TABLET_MODE` switch the
  GZ302 firmware advertises but never emits.
- **On-screen keyboard that never covers a real one** — on in tablet mode, forced off whenever
  the folio or an external keyboard is attached.
- **Two-finger scroll in any app** — terminals, TUIs, browsers, document viewers.
- **Touch right-click** — a two-finger hold opens the context menu KDE Wayland lacks.
- **Tablet scaling** — each posture remembers its scale; defaults are `1.75` in tablet
  posture and `1.5` docked and as a laptop.
- **Folio touchpad fix** — the jumpy touchpad is inhibited by default, with a guarded opt-in.
- **Live settings, no restarts** — toggles in the optional `z13gui-plus` drawer apply instantly.

## Quick start

```bash
sudo pacman -S python-evdev iio-sensor-proxy          # prerequisites
# install z13ctl-plus first (required) — see Install, step 2
git clone https://github.com/aic0d3r/z13-tablet-kit
cd z13-tablet-kit && ./install.sh
```

Then enable auto-rotate once: **Quick Settings → Auto-rotate → right-click → "Rotate only in
tablet mode"**.

## Posture model

| Posture | Detected by | Touch | Tablet mode | Auto-rotate | Virtual keyboard |
|---|---|---|---|---|---|
| **desktop** | dock hub `0b05:1ac1` (external monitor) | off | off | off | off |
| **laptop** | folio `0b05:1a30`, no dock | on | off | off | off |
| **tablet** | neither | on | **on** | **on** | **on** |

Priority: docked > folio > tablet. Attaching the folio never triggers tablet features.
The virtual keyboard (plasma-keyboard / maliit) is gated on posture: it's forced `off`
whenever a physical keyboard (folio or external) is present and only enabled in tablet
mode, so it never pops up over a real keyboard.

## The stack

This kit is one of three cooperating repos. Install all three on the same machine:

| Repo | Role |
|---|---|
| [z13-tablet-kit](https://github.com/aic0d3r/z13-tablet-kit) | posture detection and touch input — **this repo** |
| [z13ctl-plus](https://github.com/aic0d3r/z13ctl-plus) | daemon that owns display state and persists tablet settings (**required**) |
| [z13gui-plus](https://github.com/aic0d3r/z13gui-plus) | optional GTK4 overlay drawer: live posture/health chip and tablet toggles |

How they work together:

1. `z13-tablet-switch` detects dock/folio/tablet posture and applies it through
   `dock` (touchscreen toggle, virtual tablet-mode switch).
2. `dock` publishes posture to the `z13ctl-plus` daemon, which serializes scale
   and rotation changes via `kscreen-doctor` (restoring each posture's last scale; tablet defaults to 1.75).
3. `z13gui-plus` shows the live posture/health chip and exposes the tablet
   toggles: desktop touch policy, two-finger context menus, folio touchpad
   opt-in, scroll speed.
4. `z13ctl-plus` persists those settings and projects them to
   `$XDG_RUNTIME_DIR/z13ctl-plus/tablet-settings.json`; `z13-tablet-switch` and
   `z13-touch-scroll` read the projection and apply changes live, without
   restarts.

> [!NOTE]
> Ownership is one-directional: only the kit writes the posture file, only `z13ctl-plus`
> writes tablet settings, and the GUI is a read/write client of the daemon — no repo reaches
> into another's state directly.

## Components

| Component | Runs as | Job |
|---|---|---|
| [`z13-tablet-switch`](#z13-tablet-switch) | user service | detects posture, owns the virtual tablet-mode switch |
| [`dock`](#dock) | called by the switch | applies posture: touchscreen, publish to `z13ctl-plus` |
| [`z13-touch-scroll`](#z13-touch-scroll) | user service | two-finger scroll and right-click |
| [Auto-rotate](#auto-rotate) | Plasma | rotation, gated on tablet mode |
| [On-screen keyboard](#on-screen-keyboard) | Plasma | OSK, gated on posture |
| [Folio touchpad](#folio-touchpad) | udev rule | inhibited by default |
| [`z13ctl-plus`](#z13ctl-plus-display-coordinator) | user daemon | scale and refresh changes, settings |
| [`z13gui-plus`](#z13gui-plus) | optional GUI | live status and toggles |

### `z13-tablet-switch`

Polls the dock hub, folio, and DRM connectors every two seconds, then calls `dock` when posture
changes. A non-eDP external display counts as `desktop`, so any USB-C dock or HDMI cable works.
It also creates a virtual `SW_TABLET_MODE` uinput switch flipped on only in tablet posture. The
GZ302's WMI path advertises the switch but never emits it, so Plasma otherwise has nothing to
gate "rotate only in tablet mode" on.

Runs as a **user service**; logind grants `/dev/uinput` to the active session. The on-screen
keyboard remains a separate Plasma setting that needs no tablet-mode signal. (Plasma 6.7
intentionally dropped the old "force bigger UI in tablet mode" behavior,
[bugs.kde.org #521550](https://bugs.kde.org/show_bug.cgi?id=521550).)

### `dock`

Applies posture changes supplied by `z13-tablet-switch`: it toggles the internal touchscreen
(ELAN9008) through KWin D-Bus and publishes posture to `z13ctl-plus`. Failed applications are
retried, and posture is republished every 30 seconds to recover cleanly from KWin or controller
restarts.

### `z13-touch-scroll`

Reads the ELAN9008 touchscreen and detects 2-finger vertical swipes, injecting mouse wheel events
via evdev UInput. Works in **any** app: terminal scrollback, opencode TUI, browsers, and document
viewers. It follows the desktop touch policy. An opt-in stationary two-finger hold moves the
pointer to the touch point and right-clicks, providing a context menu where KDE Wayland has no
touch right-click.

### Auto-rotate

Plasma-native, gated on the virtual `SW_TABLET_MODE` switch above. `iio-sensor-proxy` (default
on CachyOS) reads the accelerometer; enable once via Quick Settings → Auto-rotate → right-click →
"Rotate only in tablet mode". No separate rotation daemon is needed.

### On-screen keyboard

`plasma-keyboard` (ships with Plasma 6.7, recommended) or `maliit-keyboard` (AUR, legacy
alternative); auto-pops on touch-focus. The kit gates it on posture — `TouchOnly` in tablet mode,
forced `Off` whenever the folio or an external keyboard is attached (KWin would otherwise pop the
OSK on any touch device). It also restarts the active keyboard on every posture change, because
it caches output geometry and would otherwise render against a stale screen and clip keys after
the panel/scale switch.

### Folio touchpad

Defaults to inhibited via udev because its firmware emits jumping-cursor events that libinput
cannot filter. Members of `users` can explicitly opt in through `z13gui-plus`; every enable
presents a warning.

### `z13ctl-plus` display coordinator

[`z13ctl-plus`](https://github.com/aic0d3r/z13ctl-plus) owns scale and refresh changes. On a posture
change it restores the scale last used in that posture (defaults: desktop/laptop `1.5`, tablet
`1.75`); a scale set in System Settings is never overridden. Plasma retains tablet rotation
unless an explicit rotation intent is sent. This kit never changes outputs with
`kscreen-doctor`; it only reads rotation and scale to place touch context-menu clicks. Dock
posture waits ten seconds for DRM topology to settle, and external outputs remain KDE-owned.

### `z13gui-plus`

[`z13gui-plus`](https://github.com/aic0d3r/z13gui-plus) (optional) shows live posture and health
when the kit is active and exposes desktop touch policy, two-finger context menus, guarded
folio-touchpad opt-in, and 1–5 touch-scroll controls. Settings are persisted by `z13ctl-plus`
and apply without restarts.

## Requirements

- KDE Plasma 6 / Wayland and systemd (`kscreen-doctor`, `qdbus6`, and `gdbus`).
- `iio-sensor-proxy` (default on CachyOS) — for Plasma auto-rotate.
- `z13ctl-plus` with its user socket and display coordinator commands available.
- Membership in `users` (configured by `z13ctl-plus setup`) for the guarded touchpad toggle.
- `python-evdev` (official repo) — for the uinput switch and touch scroll.
- `plasma-keyboard` (included with Plasma 6.7, recommended) for the OSK, or
  `maliit-keyboard` (AUR) as a legacy alternative.
- `/dev/uinput` write access for `z13-tablet-switch` and `z13-touch-scroll` is auto-granted
  by logind for the active graphical session — no group membership, no root daemon.
- Touchscreen read access is granted via a udev `uaccess` rule (logind auto-sets ACL).

## Install

> [!IMPORTANT]
> **`z13ctl-plus` (the display/settings daemon) is a hard dependency** — install it first.
> `z13gui-plus` is optional (a touch overlay for the same toggles).

### 1. Prerequisites

```bash
sudo pacman -S python-evdev iio-sensor-proxy
```

(`pacman` is the Arch / CachyOS package manager — use your distro's own for the
same packages.)

`iio-sensor-proxy` is for Plasma auto-rotate; `python-evdev` powers the virtual
tablet-mode switch and touch scroll. `plasma-keyboard` ships with Plasma 6.7
(recommended OSK); pick `maliit-keyboard` (AUR) only if you want the legacy one.

### 2. Install `z13ctl-plus` (required)

```bash
# release tarball (recommended)
wget https://github.com/aic0d3r/z13ctl-plus/releases/download/v2.1.0/z13ctl-plus_2.1.0_linux_amd64.tar.gz
tar xzf z13ctl-plus_2.1.0_linux_amd64.tar.gz
sudo install -Dm755 z13ctl-plus /usr/local/bin/z13ctl-plus
sudo z13ctl-plus setup

# …or the AUR package (outdated, see below)
paru -S z13ctl-plus-bin
```

> [!WARNING]
> The AUR package (`z13ctl-plus-bin`) trails the GitHub releases (currently 1.3.1 vs.
> **v2.1.0** — AUR updates are paused) and lacks the tablet integration. Prefer the
> **release tarball** above.

Then enable its user daemon (after stopping any other Z13 hardware daemon):

```bash
systemctl --user enable --now z13ctl-plus.socket z13ctl-plus.service
```

### 3. Install the kit

```bash
git clone https://github.com/aic0d3r/z13-tablet-kit
cd z13-tablet-kit
./install.sh
```

`install.sh` is idempotent and safe to re-run. It installs the posture manager,
touch scroll, their user services, and the udev rules, then starts everything.

### 4. Post-install (one-time)

- **Log out and back in** if prompted — your `users` group membership (set up by
  `z13ctl-plus setup`) only takes effect at login and is needed for the guarded
  folio-touchpad toggle.
- **Enable auto-rotate once:** Quick Settings → Auto-rotate → right-click →
  "Rotate only in tablet mode". The kit's virtual `SW_TABLET_MODE` gates it.

### Verify

```bash
systemctl --user status z13-tablet-switch z13-touch-scroll
cat "$XDG_RUNTIME_DIR/z13-tablet-kit/posture"   # one of: desktop / laptop / tablet
```

- Logs: `journalctl --user -u z13-tablet-switch`
- Tests (offline, no hardware needed): `python3 -m unittest discover tests`

## Uninstall

```bash
cd z13-tablet-kit
./uninstall.sh
```

Uninstall returns to laptop defaults (scale 1.5, normal rotation, touchscreen on)
and uninhibits the folio touchpad. The OSK package is left installed. KWin saves the
on-screen keyboard mode the kit switches, so uninstall restores the mode recorded by the
first `install.sh` run; installs that predate this record print a note to re-check it in
System Settings.

## Tips

- **Touch scrolling:** 2-finger vertical swipe scrolls any focused app (terminal,
  browser, opencode TUI). `z13gui-plus` exposes sensitivity and speed levels 1–5;
  defaults 3 and 2 preserve the original behavior.
- **Touch context menus:** a stationary two-finger hold (~650 ms) moves the pointer to the
  touch point and sends a real right-click; moving either finger cancels into scrolling.
  Known limit: with touch enabled in desktop posture and a monitor placed left of or above
  the built-in panel, the click lands offset onto that monitor.
- **Page Up/Down without dedicated keys:** the Z13 folio keyboard has no Page Up/Down
  keycaps, but **Fn+Up / Fn+Down** are mapped at firmware level and work everywhere.
- **3-finger gestures** are reserved by KWin (desktop overview / virtual desktop
  switching). Touch scroll deliberately uses 2 fingers to avoid conflict.
- **Auto-rotate:** driven by Plasma + `iio-sensor-proxy`, gated by the virtual tablet-mode
  switch. If a portrait direction comes out mirrored on another unit, that's a sensor-mount
  quirk to fix in `iio-sensor-proxy`, not this kit.
- Configure optional edge gestures in **System Settings → Workspace → Touchscreen Gestures**.
