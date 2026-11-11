# Architecture

How the kit's pieces fit together. Back to the [README](../README.md).

## The stack

This kit is one of three cooperating repos that run on the same machine:

| Repo | Role |
|---|---|
| [z13-tablet-kit](https://github.com/aic0d3r/z13-tablet-kit) | posture detection and touch input — **this repo** |
| [z13ctl-plus](https://github.com/aic0d3r/z13ctl-plus) | daemon that owns display state and persists tablet settings (**required**) |
| [z13gui-plus](https://github.com/aic0d3r/z13gui-plus) | optional GTK4 overlay drawer: live posture/health chip and tablet settings (also runs on GNOME, in beta) |

How they work together:

1. `z13-tablet-switch` detects dock/folio/tablet posture and applies it through
   `dock` (touchscreen toggle, virtual tablet-mode switch).
2. `dock` publishes posture to the `z13ctl-plus` daemon, which serializes scale
   and rotation changes via `kscreen-doctor`, restoring the scale last used in each posture.
3. `z13gui-plus` shows the live posture/health chip and exposes the tablet
   settings: **Disable touchscreen on desktop**, **Two-finger hold context menu**,
   **Keep scale across postures**, the folio touchpad opt-in, and scroll sensitivity
   and speed.
4. `z13ctl-plus` persists those settings and projects them to
   `$XDG_RUNTIME_DIR/z13ctl-plus/tablet-settings.json`; `z13-tablet-switch` and
   `z13-touch-scroll` read the projection and apply changes live, without
   restarts.

> [!NOTE]
> Ownership is one-directional: only the kit writes the posture file, only `z13ctl-plus`
> writes tablet settings, and the GUI is a read/write client of the daemon. No repo reaches
> into another's state directly.

## Components

| Component | Runs as | Job |
|---|---|---|
| [`z13-tablet-switch`](#z13-tablet-switch) | user service | detects posture, owns the virtual tablet-mode switch |
| [`dock`](#dock) | called by the switch | applies posture: touchscreen, OSK mode, publish to `z13ctl-plus` |
| [`z13-touch-scroll`](#z13-touch-scroll) | user service | two-finger scroll and right-click |
| [Auto-rotate](#auto-rotate) | Plasma | rotation, gated on tablet mode |
| [On-screen keyboard](#on-screen-keyboard) | Plasma | OSK, gated on posture |
| [Folio touchpad](#folio-touchpad) | udev rule | inhibited by default |
| [`z13ctl-plus`](#z13ctl-plus-display-coordinator) | user daemon | scale and refresh changes, persists settings |
| [`z13gui-plus`](#z13gui-plus) | optional GUI | live status and settings |

### `z13-tablet-switch`

Watches the dock hub, folio, and DRM connectors and calls `dock` when posture changes. It
sleeps on kernel hotplug uevents and an inotify watch on the settings file instead of polling,
sends a lightweight heartbeat to `z13ctl-plus` every 45 seconds, retries a failed apply every
10 seconds, and re-applies posture every 5 minutes to recover from KWin or `z13ctl-plus`
restarts. Any non-eDP display counts as `desktop`, so any USB-C dock or HDMI cable works.

It also creates a virtual `SW_TABLET_MODE` uinput switch that is on only in tablet posture. The
GZ302's WMI path advertises the switch but never emits it, so Plasma otherwise has nothing to
gate "rotate only in tablet mode" on.

Runs as a **user service**; logind grants `/dev/uinput` to the active session. The on-screen
keyboard remains a separate Plasma setting that needs no tablet-mode signal. (Plasma 6.7
intentionally dropped the old "force bigger UI in tablet mode" behavior,
[bugs.kde.org #521550](https://bugs.kde.org/show_bug.cgi?id=521550).)

### `dock`

Applies the posture supplied by `z13-tablet-switch`: it toggles the internal touchscreen
(ELAN9008) through KWin D-Bus, sets the on-screen keyboard mode, and publishes posture to
`z13ctl-plus`.

### `z13-touch-scroll`

Reads the ELAN9008 touchscreen, detects two-finger vertical swipes, and injects mouse-wheel
events via evdev UInput. Works in **any** app: terminal scrollback, TUIs, browsers, and document
viewers. It stays idle in desktop posture while **Disable touchscreen on desktop** is on. With
**Two-finger hold context menu** enabled, a stationary two-finger hold moves the pointer to the
touch point and right-clicks, since KDE Wayland has no touch right-click.

### Auto-rotate

Plasma-native, gated on the virtual `SW_TABLET_MODE` switch above. `iio-sensor-proxy` (default
on CachyOS) reads the accelerometer. No separate rotation daemon is needed; just enable
"Rotate only in tablet mode" once (see [Quick start](../README.md#quick-start)).

### On-screen keyboard

`plasma-keyboard` (ships with Plasma 6.7, recommended) or `maliit-keyboard` (AUR, legacy
alternative); it pops up when a text field gets touch focus. The kit gates it on posture:
`TouchOnly` in tablet mode, forced `Off` in laptop and desktop posture
(KWin would otherwise pop the OSK on any touch device). It also restarts the keyboard on every
posture change, because the keyboard caches output geometry and would otherwise clip its keys
after a screen or scale switch.

The kit also enables `plasma-keyboard` on the SDDM login screen, so you can sign in without
the folio: tap the keyboard button in the bottom-left corner. It adds an SDDM config file
(`/etc/sddm.conf.d/10-z13-osk.conf` from `install.sh`,
`/usr/lib/sddm/sddm.conf.d/zzz-z13-osk.conf` from the AUR package) that starts the login
screen's KWin with `--inputmethod plasma-keyboard`. Because SDDM can't add a flag to the
existing command, the file repeats the stock CachyOS compositor command. If you already
customize `CompositorCommand`, add the flag to your own file instead. `install.sh` skips this
step when `plasma-keyboard` isn't installed.

### Folio touchpad

Inhibited by default via udev, because its firmware emits jumping-cursor events that libinput
cannot filter. Members of `users` can opt back in through `z13gui-plus`, which shows a warning
each time.

### `z13ctl-plus` display coordinator

[`z13ctl-plus`](https://github.com/aic0d3r/z13ctl-plus) owns scale and refresh changes. On a posture
change it restores the scale last used in that posture (defaults: desktop/laptop `1.5`, tablet
`1.75`), so a scale you set in System Settings sticks to that posture. Turn on **Keep scale
across postures** to stop scale changes entirely. Plasma keeps the tablet rotation unless an
explicit rotation is requested. The kit itself never changes outputs with `kscreen-doctor`; it
only reads rotation and scale to place touch context-menu clicks. Desktop posture waits ten
seconds for the display topology to settle, and external outputs stay under KDE's control.

### `z13gui-plus`

[`z13gui-plus`](https://github.com/aic0d3r/z13gui-plus) (optional) adds a **Tablet Kit** card
(pictured in the README) while the kit is running: live posture, health and folio status, the
**Disable touchscreen on desktop**, **Two-finger hold context menu** and **Keep scale across
postures** toggles, the guarded folio-touchpad opt-in, and 1–5 **Scroll sensitivity** and
**Scroll speed** sliders. `z13ctl-plus` persists the settings, and they apply without restarts.
