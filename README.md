# z13-tablet-kit

Posture-aware tablet stack for the **ASUS ROG Flow Z13 (GZ302, AMD Strix Halo)** on
**KDE Plasma 6 / Wayland** (Arch / CachyOS). Turns the Z13 into a proper 3-mode device:
it detects whether you're **docked**, using the **keyboard folio (laptop)**, or holding it
as a **tablet**, and adapts the touchscreen, on-screen keyboard, auto-rotate, and Plasma's
tablet mode accordingly — with no kernel hacks and (almost) no root.

## Posture model

| Posture | Detected by | Touch | Tablet mode | Auto-rotate |
|---|---|---|---|---|
| **desktop** | dock hub `0b05:1ac1` (external monitor) | off | off | off |
| **laptop** | folio `0b05:1a30`, no dock | on | off | off |
| **tablet** | neither | on | **on** | **on** |

Priority: docked > folio > tablet. Attaching the folio never triggers tablet features.

## Components

- `asus-dock` (user) — computes posture from the dock hub / folio USB devices; toggles the
  internal touchscreen (ELAN9008) via KWin D-Bus `enabled`. Triggered by a udev rule
  (DRM hotplug + ASUS USB add/remove) that bridges into the session, plus a 30s safety timer
  (the folio-detach USB event is unreliable on this device).
- `z13-rotate` (user) — accelerometer auto-rotate of `eDP-1`, **tablet posture only**. Reads
  `accel_3d` directly (iio-sensor-proxy returns `undefined` for this sensor). Axis→rotation
  mapping is calibrated to the GZ302 panel mount.
- `z13-tablet-switch` (root) — creates a virtual `SW_TABLET_MODE` uinput switch flipped on
  only in tablet posture. This is what engages **Plasma's real tablet mode** (bigger
  panel/buttons, auto OSK, maximized windows) — the GZ302's WMI path advertises the switch
  but never emits it.
- `z13-touch-scroll` (user) — reads the ELAN9008 touchscreen and detects 2-finger vertical
  swipes, injecting mouse wheel events via evdev UInput. Works in **any** app: terminal
  scrollback, opencode TUI, browsers, document viewers. Single-finger touch is left to the
  app/terminal (Konsole scrolls natively; other terminals treat it as text selection).
- `maliit-keyboard` — on-screen keyboard (AUR), auto-pops on touch-focus.
- **Folio touchpad** is permanently inhibited via a udev rule (`inhibited=1`) — the GZ302EA
  folio touchpad has a firmware jumping-cursor bug that libinput cannot filter.

## Requirements

- KDE Plasma 6 / Wayland, systemd, Arch or CachyOS.
- `python-evdev` (official repo) — for the uinput switch and touch scroll.
- `maliit-keyboard` (AUR) — for the OSK.
- User not in `uinput` group, so `z13-tablet-switch` runs as a root system service.
- Touchscreen read access is granted via a udev `uaccess` rule (logind auto-sets ACL).
- `/dev/uinput` write access for `z13-touch-scroll` is auto-granted by logind for the
  active session (no group membership needed).

## Install / uninstall

```bash
sudo pacman -S python-evdev
paru -S maliit-keyboard
cd ~/z13-tablet-kit
./install.sh        # idempotent; uses sudo for the udev rule + tablet-switch service
./uninstall.sh      # removes everything (leaves maliit-keyboard installed)
```

Logs/state: `tail ~/asus-dock.log`, `cat ~/.cache/asus-dock-state`.

## Notes / optional tweaks

- **Touch scrolling:** 2-finger vertical swipe scrolls any focused app (terminal,
  browser, opencode TUI). Tunable in `bin/z13-touch-scroll`: `STEP` (swipe distance
  per wheel notch, default 90 out of 2064) and `NOTCHES_PER_STEP` (wheel events per
  notch, default 2). Increase either for faster scroll.
- **Page Up/Down without dedicated keys:** the Z13 folio keyboard has no Page Up/Down
  keycaps, but **Fn+Up / Fn+Down** are mapped at firmware level and work everywhere.
- **3-finger gestures** are reserved by KWin (desktop overview / virtual desktop
  switching). Touch scroll deliberately uses 2 fingers to avoid conflict.
- **Auto-rotate mapping:** if portrait directions come out mirrored on another unit, swap the
  `x<0 → right / x>0 → left` pair in `bin/z13-rotate`.
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
docked) and unifies it with posture + rotate + touch in one stack.
