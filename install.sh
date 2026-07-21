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
CURRENT_USER=$(id -un)
KEYD_CONF=/etc/keyd/default.conf
KEYD_BACKUP=/etc/keyd/default.conf.z13-tablet-kit.bak
RULE_TMP=$(mktemp)
KEYD_TMP=$(mktemp)
trap 'rm -f "$RULE_TMP" "$KEYD_TMP"' EXIT

echo "==> z13-tablet-kit install"

# --- dependencies ---
command -v python3 >/dev/null || { echo "ERROR: python3 required"; exit 1; }
Z13CTL="$HOME/.local/bin/z13ctl"
if [ ! -x "$Z13CTL" ]; then Z13CTL=$(command -v z13ctl 2>/dev/null || true); fi
[ -n "$Z13CTL" ] || { echo "ERROR: z13ctl required"; exit 1; }
"$Z13CTL" display --help >/dev/null || { echo "ERROR: z13ctl display coordinator required"; exit 1; }
command -v keyd >/dev/null || { echo "ERROR: keyd required"; exit 1; }
pacman -Q python-evdev >/dev/null 2>&1 || { echo "ERROR: python-evdev required  ->  sudo pacman -S python-evdev"; exit 1; }
pacman -Q maliit-keyboard >/dev/null 2>&1 || echo "NOTE: on-screen keyboard not installed  ->  paru -S maliit-keyboard"
if [ ! -r "$KEYD_CONF" ]; then
	echo "ERROR: $KEYD_CONF not found or unreadable"
	exit 1
fi

# --- user components (posture manager + auto-rotate + touch scroll) ---
install -Dm755 "$KIT/bin/asus-dock"                 "$BIN/asus-dock"
install -Dm755 "$KIT/bin/z13-rotate"                "$BIN/z13-rotate"
install -Dm755 "$KIT/bin/z13-touch-scroll"          "$BIN/z13-touch-scroll"
install -Dm644 "$KIT/systemd/asus-dock.service"     "$UNITS/asus-dock.service"
install -Dm644 "$KIT/systemd/asus-dock.timer"       "$UNITS/asus-dock.timer"
install -Dm644 "$KIT/systemd/z13-rotate.service"    "$UNITS/z13-rotate.service"
install -Dm644 "$KIT/systemd/z13-touch-scroll.service" "$UNITS/z13-touch-scroll.service"

# --- system components (udev rules + virtual tablet-mode switch) ---
sed -E "s/(--machine=)[^@]+(@\.host)/\1$CURRENT_USER\2/g" \
	"$KIT/udev/99-asus-dock.rules" > "$RULE_TMP"
sudo install -Dm755 "$KIT/bin/z13-tablet-switch"             "/usr/local/bin/z13-tablet-switch"
sudo install -Dm644 "$KIT/systemd/z13-tablet-switch.service" "/etc/systemd/system/z13-tablet-switch.service"
sudo install -Dm644 "$RULE_TMP"                               "/etc/udev/rules.d/99-asus-dock.rules"
sudo install -Dm644 "$KIT/udev/99-elan-touchscreen-uaccess.rules" "/etc/udev/rules.d/99-elan-touchscreen-uaccess.rules"
sudo install -Dm644 "$KIT/udev/99-disable-asus-touchpad.rules"    "/etc/udev/rules.d/99-disable-asus-touchpad.rules"

# Classify these exact IDs as keyboard interfaces in keyd.
if ! sudo test -e "$KEYD_BACKUP"; then
	sudo cp --preserve=all -- "$KEYD_CONF" "$KEYD_BACKUP"
fi
sed -E 's/^([[:space:]]*)(0b05:(1a30|18c6))([[:space:]]*)$/\1k:\2\4/' \
	"$KEYD_CONF" > "$KEYD_TMP"
sudo cp -- "$KEYD_TMP" "$KEYD_CONF"
sudo keyd reload

# --- reload + enable ---
systemctl --user daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input
sudo systemctl daemon-reload
systemctl --user enable --now asus-dock.service
systemctl --user enable --now asus-dock.timer
systemctl --user enable --now z13-rotate.service
systemctl --user enable --now z13-touch-scroll.service
sudo systemctl enable --now z13-tablet-switch
systemctl --user restart z13-rotate.service z13-touch-scroll.service
sudo systemctl restart z13-tablet-switch
systemctl --user start asus-dock.service

echo "==> Done. Active now:"
echo "    • desktop/laptop/tablet posture + touch toggle   (asus-dock)"
echo "    • accelerometer auto-rotate (tablet only)        (z13-rotate)"
echo "    • Plasma tablet mode via virtual SW_TABLET_MODE  (z13-tablet-switch)"
echo "    • 2-finger touch scroll everywhere               (z13-touch-scroll)"
echo "    • folio touchpad disabled (jumping-cursor bug)   (udev inhibited)"
echo "    Log: tail ~/asus-dock.log   |   posture: cat ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/z13-tablet-kit/posture"
