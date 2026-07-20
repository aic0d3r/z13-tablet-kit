#!/bin/bash
# z13-tablet-kit — installer
# ASUS ROG Flow Z13 (GZ302, Strix Halo) posture + tablet stack for KDE Plasma/Wayland.
# Installs: posture manager (desktop/laptop/tablet) + touch toggle, auto-rotate,
# virtual SW_TABLET_MODE switch (real Plasma tablet mode), and the OSK hook.
# Idempotent — safe to re-run. Run as your normal user (uses sudo for system bits).
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
UNITS="$HOME/.config/systemd/user"

echo "==> z13-tablet-kit install"

# --- dependencies ---
command -v python3 >/dev/null || { echo "ERROR: python3 required"; exit 1; }
pacman -Q python-evdev >/dev/null 2>&1 || { echo "ERROR: python-evdev required  ->  sudo pacman -S python-evdev"; exit 1; }
pacman -Q maliit-keyboard >/dev/null 2>&1 || echo "NOTE: on-screen keyboard not installed  ->  paru -S maliit-keyboard"

# --- user components (posture manager + auto-rotate + touch scroll) ---
install -Dm755 "$KIT/bin/asus-dock"                 "$BIN/asus-dock"
install -Dm755 "$KIT/bin/z13-rotate"                "$BIN/z13-rotate"
install -Dm755 "$KIT/bin/z13-touch-scroll"          "$BIN/z13-touch-scroll"
install -Dm644 "$KIT/systemd/asus-dock.service"     "$UNITS/asus-dock.service"
install -Dm644 "$KIT/systemd/asus-dock.timer"       "$UNITS/asus-dock.timer"
install -Dm644 "$KIT/systemd/z13-rotate.service"    "$UNITS/z13-rotate.service"
install -Dm644 "$KIT/systemd/z13-touch-scroll.service" "$UNITS/z13-touch-scroll.service"

# --- system components (udev rules + virtual tablet-mode switch) ---
sudo install -Dm755 "$KIT/bin/z13-tablet-switch"             "/usr/local/bin/z13-tablet-switch"
sudo install -Dm644 "$KIT/systemd/z13-tablet-switch.service" "/etc/systemd/system/z13-tablet-switch.service"
sudo install -Dm644 "$KIT/udev/99-asus-dock.rules"            "/etc/udev/rules.d/99-asus-dock.rules"
sudo install -Dm644 "$KIT/udev/99-elan-touchscreen-uaccess.rules" "/etc/udev/rules.d/99-elan-touchscreen-uaccess.rules"
sudo install -Dm644 "$KIT/udev/99-disable-asus-touchpad.rules"    "/etc/udev/rules.d/99-disable-asus-touchpad.rules"

# --- reload + enable ---
systemctl --user daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo systemctl daemon-reload
systemctl --user enable --now asus-dock.service 2>/dev/null
systemctl --user enable --now asus-dock.timer    2>/dev/null
systemctl --user enable --now z13-rotate.service 2>/dev/null
systemctl --user enable --now z13-touch-scroll.service 2>/dev/null
sudo  systemctl enable --now z13-tablet-switch   2>/dev/null

echo "==> Done. Active now:"
echo "    • desktop/laptop/tablet posture + touch toggle   (asus-dock)"
echo "    • accelerometer auto-rotate (tablet only)        (z13-rotate)"
echo "    • Plasma tablet mode via virtual SW_TABLET_MODE  (z13-tablet-switch)"
echo "    • 2-finger touch scroll everywhere               (z13-touch-scroll)"
echo "    • folio touchpad disabled (jumping-cursor bug)   (udev inhibited)"
echo "    Log: tail ~/asus-dock.log   |   posture: cat ~/.cache/asus-dock-state"
