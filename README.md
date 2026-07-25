# z13-tablet-kit

Posture-aware tablet stack for the **ASUS ROG Flow Z13 (GZ302, AMD Strix Halo)** on
**KDE Plasma 6 / Wayland** (Arch / CachyOS). Turns the Z13 into a proper 3-mode device:
it detects whether you're **docked**, using the **keyboard folio (laptop)**, or holding it
as a **tablet**, and adapts the touchscreen, display, and auto-rotate accordingly — with no
kernel hacks and only three udev rules needing root.

## Posture model

| Posture | Detected by | Touch | Tablet mode | Auto-rotate |
|---|---|---|---|---|
| **desktop** | dock hub `0b05:1ac1` (external monitor) | off | off | off |
| **laptop** | folio `0b05:1a30`, no dock | on | off | off |
| **tablet** | neither | on | **on** | **on** |

Priority: docked > folio > tablet. Attaching the folio never triggers tablet features.

## Components

- `asus-dock` (user) — computes posture from the dock hub / folio USB devices; toggles the
  internal touchscreen (ELAN9008) via KWin D-Bus `enabled`. A non-eDP external display also
  counts as `desktop`, so any USB-C dock or HDMI cable works. Triggered by a udev rule
  (DRM hotplug + ASUS USB add/remove) that bridges into the session, plus a 30s safety timer
  (the folio-detach USB event is unreliable on this device). Every run publishes the posture
  to `z13ctl`; failed publications return an error and are retried rather than falling back
  to direct display writes.
- **Auto-rotate** — Plasma-native, gated on the virtual `SW_TABLET_MODE` switch below.
  `iio-sensor-proxy` (default on CachyOS) reads the accel; enable once via Quick Settings →
  Auto-rotate → right-click → "Rotate only in tablet mode". No kit daemon needed.
- `z13ctl` display coordinator — owns all KScreen changes. Desktop and laptop use scale `1.5`,
  tablet posture uses scale `2.0`; this kit never invokes `kscreen-doctor` directly. Dock
  posture waits ten seconds for DRM topology to settle. External outputs remain entirely
  KDE-owned, and a disabled internal panel is never reconfigured.
- `z13-tablet-switch` (user) — creates a virtual `SW_TABLET_MODE` uinput switch flipped on
  only in tablet posture. The GZ302's WMI path advertises the switch but never emits it, so
  without this daemon Plasma's "rotate only in tablet mode" checkbox has nothing to gate on
  and the screen won't auto-rotate in tablet posture. Runs as a **user service** (logind
  grants `/dev/uinput` to the active session, same mechanism as `z13-touch-scroll`). This is
  the daemon's *only* job — the on-screen keyboard is a separate Plasma setting that pops on
  touch with no tablet-mode signal needed. (Plasma 6.7 intentionally dropped the old "force
  bigger UI in tablet mode" behavior, [bugs.kde.org #521550](https://bugs.kde.org/show_bug.cgi?id=521550).)
- `z13-touch-scroll` (user) — reads the ELAN9008 touchscreen and detects 2-finger vertical
  swipes, injecting mouse wheel events via evdev UInput. Works in **any** app: terminal
  scrollback, opencode TUI, browsers, document viewers. Single-finger touch is left to the
  app/terminal (Konsole scrolls natively; other terminals treat it as text selection).
- `maliit-keyboard` — on-screen keyboard (AUR), auto-pops on touch-focus.
- **Folio touchpad** is permanently inhibited via a udev rule (`inhibited=1`) — the GZ302EA
  folio touchpad has a firmware jumping-cursor bug that libinput cannot filter.

## Requirements

- KDE Plasma 6 / Wayland, systemd, Arch or CachyOS.
- `iio-sensor-proxy` (default on CachyOS) — for Plasma auto-rotate.
- `z13ctl` with the display coordinator commands available.
- `keyd`; installation preserves `/etc/keyd/default.conf` once, then marks the Z13 keyboard
  IDs as keyboard interfaces. Uninstall restores that exact backup and reloads keyd.
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
./install.sh        # idempotent; uses sudo only for udev rules
./uninstall.sh      # removes everything (leaves maliit-keyboard installed)
# Then enable auto-rotate once: Quick Settings → Auto-rotate → right-click →
# "Rotate only in tablet mode". The kit's virtual SW_TABLET_MODE gates it.
```

Uninstall requests laptop defaults (scale 1.5, normal rotation, touchscreen on,
tablet mode off), uninhibits the folio touchpad, and restores the exact keyd
configuration backed up by the installer.

Logs/state: `tail ~/asus-dock.log`, `cat "$XDG_RUNTIME_DIR/z13-tablet-kit/posture"`.

## Notes / optional tweaks

- **Touch scrolling:** 2-finger vertical swipe scrolls any focused app (terminal,
  browser, opencode TUI). Tunable in `bin/z13-touch-scroll`: `STEP` (swipe distance
  per wheel notch, default 90 out of 2064) and `NOTCHES_PER_STEP` (wheel events per
  notch, default 2). Increase either for faster scroll.
- **Page Up/Down without dedicated keys:** the Z13 folio keyboard has no Page Up/Down
  keycaps, but **Fn+Up / Fn+Down** are mapped at firmware level and work everywhere.
- **3-finger gestures** are reserved by KWin (desktop overview / virtual desktop
  switching). Touch scroll deliberately uses 2 fingers to avoid conflict.
- **Auto-rotate:** driven by Plasma + `iio-sensor-proxy`, gated by the virtual tablet-mode
  switch. If a portrait direction comes out mirrored on another unit, that's a sensor-mount
  quirk to fix in `iio-sensor-proxy`, not this kit.
- **Tablet gestures (recommended Plasma defaults, applied to `~/.config/kwinrc`):**
  - Overview effect enabled (`[Plugins] overviewEnabled=true`). Enables the touchpad
    3-finger defaults too: swipe up → Overview, left/right → switch virtual desktop.
  - Touchscreen **top-edge swipe → Overview** (`[Effect-overview] TouchBorderActivate=0`;
    `0` = `ElectricTop`). Swipe down from the top edge to open the window/app grid.
  - These are not deployed by `install.sh` (they're personal Plasma settings). To apply:
    `kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled true` and
    `kwriteconfig6 --file kwinrc --group Effect-overview --key TouchBorderActivate 0`,
    then `qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect overview`
    (hot-load; it auto-loads on later boots). Other edges can be bound in
    System Settings → Workspace → Touchscreen Gestures (`kcmshell6 kwintouchscreen`).
  - Verified: this install uses **Plasma's native tiling** (Meta+T), not Polonium/other
    scripts. Overview was previously disabled; re-enabling it does not conflict with tiling.

## Credits

The virtual `SW_TABLET_MODE` idea follows [m4rw3r/z13-tablet-switch](https://github.com/m4rw3r/z13-tablet-switch);
this kit reuses the concept but adds **dock awareness** (so tablet mode never engages while
docked) and unifies it with posture + touch in one stack.
