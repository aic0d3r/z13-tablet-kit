# z13-tablet-kit

Posture-aware tablet stack for the **ASUS ROG Flow Z13 (GZ302, AMD Strix Halo)** on
**KDE Plasma 6 / Wayland** (Arch / CachyOS). Turns the Z13 into a proper 3-mode device:
it detects whether you're **docked**, using the **keyboard folio (laptop)**, or holding it
as a **tablet**, and adapts the touchscreen, display, and auto-rotate accordingly — with no
kernel hacks and only two udev rules needing root.

## Stack

This kit is one of three cooperating repos. Install all three on the same machine:

| Repo | Role |
|---|---|
| [z13-tablet-kit](https://github.com/aic0d3r/z13-tablet-kit) | posture detection and touch input — **this repo** |
| [z13ctl-plus](https://github.com/aic0d3r/z13ctl-plus) | daemon that owns display state and persists tablet settings |
| [z13gui-plus](https://github.com/aic0d3r/z13gui-plus) | optional GTK4 overlay drawer: live posture/health chip and tablet toggles |

How they work together:

1. `z13-tablet-switch` detects dock/folio/tablet posture and applies it through
   `dock` (touchscreen toggle, virtual tablet-mode switch).
2. `dock` publishes posture to the `z13ctl-plus` daemon, which serializes scale
   and rotation changes via `kscreen-doctor` (tablet uses scale 1.75).
3. `z13gui-plus` shows the live posture/health chip and exposes the tablet
   toggles: desktop touch policy, two-finger context menus, folio touchpad
   opt-in, scroll speed.
4. `z13ctl-plus` persists those settings and projects them to
   `$XDG_RUNTIME_DIR/z13ctl-plus/tablet-settings.json`; `z13-tablet-switch` and
   `z13-touch-scroll` read the projection and apply changes live, without
   restarts.

Ownership is one-directional: only the kit writes the posture file, only
`z13ctl-plus` writes tablet settings, and the GUI is a read/write client of the
daemon — no repo reaches into another's state directly.

## Posture model

| Posture | Detected by | Touch | Tablet mode | Auto-rotate |
|---|---|---|---|---|
| **desktop** | dock hub `0b05:1ac1` (external monitor) | off | off | off |
| **laptop** | folio `0b05:1a30`, no dock | on | off | off |
| **tablet** | neither | on | **on** | **on** |

Priority: docked > folio > tablet. Attaching the folio never triggers tablet features.

## Components

- `dock` (user) — applies posture changes supplied by `z13-tablet-switch`: it toggles the
  internal touchscreen (ELAN9008) through KWin D-Bus and publishes posture to `z13ctl-plus`.
  Failed applications are retried, and posture is republished every 30 seconds to recover
  cleanly from KWin or controller restarts.
- **Auto-rotate** — Plasma-native, gated on the virtual `SW_TABLET_MODE` switch below.
  `iio-sensor-proxy` (default on CachyOS) reads the accel; enable once via Quick Settings →
  Auto-rotate → right-click → "Rotate only in tablet mode". No separate rotation daemon is needed.
- [`z13ctl-plus`](https://github.com/aic0d3r/z13ctl-plus) display coordinator — owns scale and refresh changes. Desktop and laptop use
  scale `1.5`; tablet posture uses scale `1.75`. Plasma retains tablet rotation unless an
  explicit rotation intent is sent. This kit never invokes `kscreen-doctor` directly. Dock
  posture waits ten seconds for DRM topology to settle, and external outputs remain KDE-owned.
- `z13-tablet-switch` (user) — polls the dock hub, folio, and DRM connectors every two seconds,
  then calls `dock` when posture changes. A non-eDP external display counts as `desktop`,
  so any USB-C dock or HDMI cable works. It also creates a virtual `SW_TABLET_MODE` uinput
  switch flipped on only in tablet posture. The GZ302's WMI path advertises the switch but
  never emits it, so Plasma otherwise has nothing to gate "rotate only in tablet mode" on.
  Runs as a **user service**; logind grants `/dev/uinput` to the active session. The on-screen
  keyboard remains a separate Plasma setting that needs no tablet-mode signal. (Plasma 6.7
  intentionally dropped the old "force bigger UI in tablet mode" behavior,
  [bugs.kde.org #521550](https://bugs.kde.org/show_bug.cgi?id=521550).)
- [`z13gui-plus`](https://github.com/aic0d3r/z13gui-plus) (optional) — shows live posture and health when the kit is active and exposes
  desktop touch policy, two-finger context menus, guarded folio-touchpad opt-in, and 1–5
  touch-scroll controls. Settings are persisted by `z13ctl-plus` and apply without restarts.
- `z13-touch-scroll` (user) — reads the ELAN9008 touchscreen and detects 2-finger vertical
  swipes, injecting mouse wheel events via evdev UInput. Works in **any** app: terminal
  scrollback, opencode TUI, browsers, and document viewers. It follows the desktop touch policy.
  An opt-in stationary two-finger hold moves the pointer to the touch point and right-clicks,
  providing a context menu where KDE Wayland has no touch right-click.
- `maliit-keyboard` — on-screen keyboard (AUR), auto-pops on touch-focus. The kit
  restarts the active keyboard (`plasma-keyboard` or `maliit-keyboard`) on every
  posture change, because it caches output geometry and would otherwise render
  against a stale screen and clip keys after the panel/scale switch.
- **Folio touchpad** defaults to inhibited via udev because its firmware emits jumping-cursor
  events that libinput cannot filter. Members of `users` can explicitly opt in through
  `z13gui-plus`; every enable presents a warning.

## Requirements

- KDE Plasma 6 / Wayland, systemd, Arch or CachyOS (`kscreen-doctor`, `qdbus6`, and `gdbus`).
- `iio-sensor-proxy` (default on CachyOS) — for Plasma auto-rotate.
- `z13ctl-plus` with its user socket and display coordinator commands available.
- Membership in `users` (configured by `z13ctl-plus setup`) for the guarded touchpad toggle.
- `python-evdev` (official repo) — for the uinput switch and touch scroll.
- `maliit-keyboard` (AUR) — for the OSK.
- `/dev/uinput` write access for `z13-tablet-switch` and `z13-touch-scroll` is auto-granted
  by logind for the active graphical session — no group membership, no root daemon.
- Touchscreen read access is granted via a udev `uaccess` rule (logind auto-sets ACL).

## Install / uninstall

```bash
sudo pacman -S python-evdev
paru -S maliit-keyboard
cd ~/z13-tablet-kit
./install.sh        # idempotent; uses sudo for system cleanup and udev rules
./uninstall.sh      # removes everything (leaves maliit-keyboard installed)
# Then enable auto-rotate once: Quick Settings → Auto-rotate → right-click →
# "Rotate only in tablet mode". The kit's virtual SW_TABLET_MODE gates it.
```

Uninstall requests laptop defaults (scale 1.5, normal rotation, touchscreen on,
tablet mode off) and uninhibits the folio touchpad.

Logs/state: `journalctl --user -u z13-tablet-switch`,
`cat "$XDG_RUNTIME_DIR/z13-tablet-kit/posture"`.

## Notes / optional tweaks

- **Touch scrolling:** 2-finger vertical swipe scrolls any focused app (terminal,
  browser, opencode TUI). `z13gui-plus` exposes sensitivity and speed levels 1–5;
  defaults 3 and 2 preserve the original behavior.
- **Touch context menus:** a stationary two-finger hold (~650 ms) moves the pointer to the
  touch point and sends a real right-click; moving either finger cancels into scrolling.
- **Page Up/Down without dedicated keys:** the Z13 folio keyboard has no Page Up/Down
  keycaps, but **Fn+Up / Fn+Down** are mapped at firmware level and work everywhere.
- **3-finger gestures** are reserved by KWin (desktop overview / virtual desktop
  switching). Touch scroll deliberately uses 2 fingers to avoid conflict.
- **Auto-rotate:** driven by Plasma + `iio-sensor-proxy`, gated by the virtual tablet-mode
  switch. If a portrait direction comes out mirrored on another unit, that's a sensor-mount
  quirk to fix in `iio-sensor-proxy`, not this kit.
- Configure optional edge gestures in **System Settings → Workspace → Touchscreen Gestures**.
