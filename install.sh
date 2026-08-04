#!/bin/bash
# z13-tablet-kit — installer
# ASUS ROG Flow Z13 (GZ302, Strix Halo) posture + tablet stack for KDE Plasma/Wayland.
# Installs: posture manager (desktop/laptop/tablet) + touch toggle,
# a virtual SW_TABLET_MODE switch (gates Plasma auto-rotate to tablet posture),
# and 2-finger touch scroll. Auto-rotate itself is Plasma-native: enable
# "Auto-rotate → only in tablet mode" once.
# Idempotent — safe to re-run. Run as your normal user.
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
UNITS="$HOME/.config/systemd/user"

echo "==> z13-tablet-kit install"

# --- dependencies ---
command -v python3 >/dev/null || { echo "ERROR: python3 required"; exit 1; }
command -v qdbus6 >/dev/null || { echo "ERROR: qdbus6 required"; exit 1; }
command -v gdbus >/dev/null || { echo "ERROR: gdbus required"; exit 1; }
command -v kscreen-doctor >/dev/null || { echo "ERROR: kscreen-doctor required"; exit 1; }
Z13CTL_PLUS="$HOME/.local/bin/z13ctl-plus"
if [ ! -x "$Z13CTL_PLUS" ]; then Z13CTL_PLUS=$(command -v z13ctl-plus 2>/dev/null || true); fi
[ -n "$Z13CTL_PLUS" ] || { echo "ERROR: z13ctl-plus required"; exit 1; }
"$Z13CTL_PLUS" display --help >/dev/null || { echo "ERROR: z13ctl-plus display coordinator required"; exit 1; }
systemctl --user cat z13ctl-plus.socket >/dev/null 2>&1 || { echo "ERROR: z13ctl-plus.socket required"; exit 1; }
id -nG | grep -qw users || echo "NOTE: log out and back in after 'sudo usermod -aG users $USER' to enable touchpad control"
pacman -Q python-evdev >/dev/null 2>&1 || { echo "ERROR: python-evdev required  ->  sudo pacman -S python-evdev"; exit 1; }
pacman -Q maliit-keyboard >/dev/null 2>&1 || echo "NOTE: on-screen keyboard not installed  ->  paru -S maliit-keyboard"
pacman -Q iio-sensor-proxy >/dev/null 2>&1 || echo "NOTE: iio-sensor-proxy not installed (Plasma auto-rotate needs it)  ->  sudo pacman -S iio-sensor-proxy"

# Restore the keyd configuration changed by older kit versions.
if sudo test -e /etc/keyd/default.conf.z13-tablet-kit.bak; then
	sudo mv -f -- /etc/keyd/default.conf.z13-tablet-kit.bak /etc/keyd/default.conf
	if command -v keyd >/dev/null; then sudo keyd reload; fi
fi

# A previous kit version installed z13-tablet-switch as root.
if [ -e /usr/local/bin/z13-tablet-switch ] || [ -e /etc/systemd/system/z13-tablet-switch.service ]; then
	sudo systemctl disable --now z13-tablet-switch 2>/dev/null || true
	sudo rm -f /usr/local/bin/z13-tablet-switch /etc/systemd/system/z13-tablet-switch.service
	sudo systemctl daemon-reload
fi

# --- user components (posture manager + tablet switch + touch scroll) ---
install -Dm755 "$KIT/bin/dock"                      "$BIN/dock"
install -Dm755 "$KIT/bin/z13-tablet-switch"         "$BIN/z13-tablet-switch"
install -Dm755 "$KIT/bin/z13-touch-scroll"          "$BIN/z13-touch-scroll"
install -Dm644 "$KIT/systemd/z13-tablet-switch.service" "$UNITS/z13-tablet-switch.service"
install -Dm644 "$KIT/systemd/z13-touch-scroll.service" "$UNITS/z13-touch-scroll.service"

# --- system components (udev access/inhibit rules only) ---
sudo install -Dm644 "$KIT/udev/99-elan-touchscreen-uaccess.rules"  "/etc/udev/rules.d/99-elan-touchscreen-uaccess.rules"
sudo install -Dm644 "$KIT/udev/99-disable-asus-touchpad.rules"     "/etc/udev/rules.d/99-disable-asus-touchpad.rules"

# --- reload + enable ---
systemctl --user daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input
systemctl --user enable z13-tablet-switch.service z13-touch-scroll.service
systemctl --user restart z13-tablet-switch.service z13-touch-scroll.service

echo "==> Done. Active now:"
echo "    • desktop/laptop/tablet posture + touch toggle + posture-gated auto-rotate (z13-tablet-switch)"
echo "    • 2-finger touch scroll everywhere               (z13-touch-scroll)"
echo "    • folio touchpad disabled (jumping-cursor bug)   (udev inhibited)"
echo "    Enable once: Quick Settings → Auto-rotate → right-click → 'Rotate only in tablet mode'"
echo "    Log: journalctl --user -u z13-tablet-switch   |   posture: cat ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/z13-tablet-kit/posture"
