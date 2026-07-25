#!/bin/bash
# z13-tablet-kit — uninstaller
set -euo pipefail
KEYD_CONF=/etc/keyd/default.conf
KEYD_BACKUP=/etc/keyd/default.conf.z13-tablet-kit.bak
DEST=org.kde.KWin
IF=org.kde.KWin.InputDevice
NAME="ELAN9008:00 04F3:43C7"
Z13CTL="$HOME/.local/bin/z13ctl"
if [ ! -x "$Z13CTL" ]; then Z13CTL=$(command -v z13ctl 2>/dev/null || true); fi

echo "==> removing z13-tablet-kit"

# Stop publishers before sending final intent so they cannot overwrite it.
systemctl --user disable --now asus-dock.service asus-dock.timer z13-tablet-switch.service z13-touch-scroll.service 2>/dev/null || true
# Legacy: older kit versions installed z13-tablet-switch as a root service.
sudo systemctl disable --now z13-tablet-switch 2>/dev/null || true

if [ -n "$Z13CTL" ]; then
	"$Z13CTL" display posture laptop || echo "WARNING: z13ctl unavailable; display state left unchanged"
	"$Z13CTL" display rotation none || echo "WARNING: z13ctl unavailable; rotation state left unchanged"
else
	echo "WARNING: z13ctl unavailable; display state left unchanged"
fi

# Ensure the touchscreen is enabled before its management service is removed.
for path in $(qdbus6 "$DEST" 2>/dev/null | grep -E 'InputDevice/event'); do
	nm=$(gdbus call --session --dest "$DEST" --object-path "$path" \
		--method org.freedesktop.DBus.Properties.Get "$IF" name 2>/dev/null || true)
	if [[ "$nm" == *"$NAME"* ]] && [[ "$nm" != *stylus* ]]; then
		gdbus call --session --dest "$DEST" --object-path "$path" \
			--method org.freedesktop.DBus.Properties.Set "$IF" enabled '<true>' >/dev/null || true
		break
	fi
done

sudo rm -f /etc/udev/rules.d/99-asus-dock.rules \
            /etc/udev/rules.d/99-elan-touchscreen-uaccess.rules \
            /etc/udev/rules.d/99-disable-asus-touchpad.rules
rm -f ~/.local/bin/asus-dock ~/.local/bin/z13-tablet-switch ~/.local/bin/z13-touch-scroll \
      ~/.config/systemd/user/asus-dock.service \
      ~/.config/systemd/user/asus-dock.timer \
      ~/.config/systemd/user/z13-tablet-switch.service \
      ~/.config/systemd/user/z13-touch-scroll.service
# Legacy cleanup: older kit versions installed these as root.
sudo rm -f /usr/local/bin/z13-tablet-switch /etc/systemd/system/z13-tablet-switch.service
# Drop any legacy z13-rotate left by a previous install of this kit.
rm -f ~/.local/bin/z13-rotate ~/.config/systemd/user/z13-rotate.service
rm -f ~/.cache/asus-dock-state ~/.cache/asus-dock-touch.path
rm -rf "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/z13-tablet-kit"
rm -f ~/asus-dock.log

# Removing the inhibit rule does not update an already-present touchpad.
for device in /sys/class/input/event*/device; do
	[ -r "$device/name" ] || continue
	[ "$(cat "$device/name")" = "ASUSTeK Computer Inc. GZ302EA-Keyboard Touchpad" ] || continue
	if [ -w "$device/inhibited" ] || sudo test -w "$device/inhibited"; then
		echo 0 | sudo tee "$device/inhibited" >/dev/null
	fi
done

if sudo test -e "$KEYD_BACKUP"; then
	sudo cp --preserve=all -- "$KEYD_BACKUP" "$KEYD_CONF"
	sudo rm -f "$KEYD_BACKUP"
	sudo keyd reload
fi

systemctl --user daemon-reload
sudo udevadm control --reload-rules
sudo systemctl daemon-reload
echo "==> removed. (maliit-keyboard left installed — remove with: pacman -Rns maliit-keyboard)"
