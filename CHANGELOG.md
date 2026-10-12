# Changelog

All notable changes. Newest first. The kit is unversioned; entries are grouped by date.

## 2026-10-12

- Display scale chosen in System Settings is no longer overwritten every 30 seconds.
  Needs [z13ctl-plus v2.2.1](https://github.com/aic0d3r/z13ctl-plus/releases/tag/v2.2.1):
  each posture restores the scale last used in it (defaults 1.5 desktop/laptop,
  1.75 tablet), and Z13GUI+ v2.2.0 "Keep my display scale" turns scale handling off.
  [#1](https://github.com/aic0d3r/z13-tablet-kit/issues/1)
- Uninstall restores the on-screen keyboard mode saved by the first install.
- The tablet-mode switch follows the detected posture.
- The kit keeps running when the `dock` or `z13ctl-plus` binaries are missing, and warns
  once when the posture file is missing.
- The on-screen keyboard restarts only on a real posture change, not on the 30-second
  re-apply. The re-apply log is quieter.
- A failed health report no longer blocks tablet mode.
- Touch scrolling re-anchors when the finger count changes. Two-finger context-menu
  clicks use the real rotation and scale.
- `install.sh` detects python-evdev via import, so it works outside Arch.
- Offline unit tests (`python3 -m unittest discover tests`), no hardware needed.
- README rewrite.

## 2026-08-10

- README: the kit is distro-agnostic, not Arch/CachyOS-only; device details.

## 2026-08-05

- The on-screen keyboard is gated on posture: off when the folio or a keyboard is
  attached, on in tablet posture.
- The on-screen keyboard restarts on posture change so keys are not clipped.
- Two-finger hold opens the context menu (right-click at the touch point).
- Docs: install steps with the z13ctl-plus dependency, plasma-keyboard recommendation,
  the three-repo stack.

## 2026-08-04

- Tablet settings and health integrate with z13ctl-plus / Z13GUI+.
- Simpler posture integration with z13ctl-plus.
- `dock` helper is installed executable.

## 2026-07-25

- Plasma-native auto-rotate replaces `z13-rotate`.
- Any external display means desktop posture; internal eDP/DSI panels are skipped.
- `z13-tablet-switch` runs as a user service.

## 2026-07-21

- Tablet posture is coordinated through z13ctl.

## 2026-07-20

- Initial release.
