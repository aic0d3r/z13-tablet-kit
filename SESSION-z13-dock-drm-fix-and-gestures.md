# Session: z13-dock-drm-fix-and-gestures

Date: 2026-07-16 · Machine: ASUS ROG Flow Z13 (GZ302, AMD Strix Halo) · CachyOS / Plasma 6.7.2 / KWin 6.7.2 / Wayland

Two threads in this session: (A) a docking regression we caused and fixed, (B) tablet gesture defaults.

## A. Docking stopped turning on the external monitor

**Symptom:** after recent kit changes, docking produced
`Couldn't apply display configuration: The driver rejected the output configuration`.
Kernel log showed the dock's MST topology failing to enumerate:
`[drm] DM_MST: DP14, 2-lane link detected` →
`[drm] Failed to read downstream_port_present 0x05 from DFP of branch device`.
The dock link is only **2 DP lanes**, so it's bandwidth-marginal and any
interruption during link training is fatal.

**Root cause:** our own scripts were grabbing the DRM device via `kscreen-doctor`
during the monitor hotplug, colliding with KWin's atomic commit:

- `z13-rotate` — the "self-heal" branch called
  `kscreen-doctor output.eDP-1.rotation.none` **every 2 s, unconditionally** while
  not in tablet posture. Continuous DRM grabs during MST link training corrupted it.
- `asus-dock` — fired `kscreen-doctor output.eDP-1.scale.1.7` on the **desktop**
  (dock) transition, i.e. at the exact moment KWin enables the external monitor.

**Fix (root cause, in `bin/`):**
- `z13-rotate`: not-tablet branch is now **stateful** — only calls `kscreen-doctor`
  when `prev != none` (one-shot self-heal on tablet-exit). Zero DRM grabs while
  stable/docked. Verified `0/8 s`.
- `asus-dock`: scale change no longer fires on `desktop`; only `tablet`/`laptop`
  (which involve no monitor hotplug). Docked keeps the prior scale.

**Recovery (once):** the corrupted MST topology can't be repaired from userspace
(sysfs re-probe needs root). Fix = **unplug the dock cable, wait ~5 s, replug** —
a clean re-enumeration, now unimpeded. After that, dock/undock keeps working.

Lesson: **never call `kscreen-doctor` (any DRM atomic commit) during or around a
display hotplug.** Posture scripts must touch the display only when a value
actually changes, and never on the dock transition itself.

## B. Tablet gesture defaults (Polonium cleanup + Overview)

**Polonium:** confirmed **uninstalled** (`pacman -Qs polonium` empty; no KWin
script in `~/.local/share/kwin/scripts/`). This install uses **Plasma's native
tiling** (Meta+T; the `[Tiling][…]` blocks in `kwinrc`). Removed the dead
`[Script-polonium]` group and the `poloniumEnabled` key from `~/.config/kwinrc`.

**Overview + touch gesture (applied to `~/.config/kwinrc`):**
- `[Plugins] overviewEnabled = true`
- `[Effect-overview] TouchBorderActivate = 0`  (`0` = `ElectricTop` → swipe down
  from the top edge opens Overview)
- Verified: `Meta+W` toggles Overview; top-edge touch swipe opens it. Touchpad
  3-finger defaults are now live too (up→Overview, left/right→desktop switch).

### Gotcha: enabling a builtin effect needs more than `reconfigure`

Setting `<effect>Enabled=true` in `kwinrc` and running
`qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure` does **not** hot-load a
builtin effect (`isEffectLoaded` stays false). Hot-load it explicitly:

```bash
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect overview
# verify:
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded overview   # -> true
```

It then auto-loads on future boots (the `enabled` flag is persisted).

### Notes

- `org.kde.kglobalaccel` is owned by **kwin_wayland itself** in Plasma 6 (no
  separate daemon). `plasma-kglobalaccel.service` exiting cleanly is normal.
- `qdbus` is not on PATH here — use **`qdbus6`** (`/usr/bin/qdbus6`).
- Touch-edge IntList key for builtin togglable effects = `TouchBorderActivate`
  (mirror of the mouse `BorderActivate`). Confirmed working for Overview.
  Other edges can be bound via `kcmshell6 kwintouchscreen` if needed.

## Files touched this session

- `bin/asus-dock` — scale no longer fires on desktop transition
- `bin/z13-rotate` — stateful not-tablet branch (no DRM spam)
- `~/.config/kwinrc` — overviewEnabled, TouchBorderActivate; removed polonium cruft
- `README.md` — "Tablet gestures" subsection
- Backup: `~/.config/kwinrc.bak.<ts>` (pre-change)
