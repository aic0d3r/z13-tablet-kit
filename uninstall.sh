#!/bin/bash
# z13-tablet-kit — uninstaller
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
DOCK="$KIT/bin/dock"
Z13CTL_PLUS="$HOME/.local/bin/z13ctl-plus"
if [ ! -x "$Z13CTL_PLUS" ]; then Z13CTL_PLUS=$(command -v z13ctl-plus 2>/dev/null || true); fi

echo "==> removing z13-tablet-kit"

# Stop publishers before sending final intent so they cannot overwrite it.
systemctl --user disable --now z13-tablet-switch.service z13-touch-scroll.service 2>/dev/null || true
# Legacy: older kit versions installed z13-tablet-switch as a root service.
sudo systemctl disable --now z13-tablet-switch 2>/dev/null || true

if [ -x "$DOCK" ]; then
	"$DOCK" laptop || echo "WARNING: posture reset incomplete"
else
	echo "WARNING: dock unavailable; touch and posture left unchanged"
fi
# dock's keyboard mode persists in kwinrc; put back the mode saved by install.sh.
OSK_SAVE="${XDG_STATE_HOME:-$HOME/.local/state}/z13-tablet-kit/osk-mode"
if [ -r "$OSK_SAVE" ] && gdbus call --session --dest org.kde.KWin --object-path /VirtualKeyboard \
	--method org.freedesktop.DBus.Properties.Set org.kde.kwin.VirtualKeyboard mode \
	"<int32 $(cat "$OSK_SAVE")>" >/dev/null 2>&1; then
	rm -rf "$(dirname "$OSK_SAVE")"
else
	echo "NOTE: on-screen keyboard mode not restored; re-check the virtual keyboard setting in System Settings"
fi
if [ -n "$Z13CTL_PLUS" ]; then
	"$Z13CTL_PLUS" display rotation none || echo "WARNING: z13ctl-plus unavailable; rotation state left unchanged"
	"$Z13CTL_PLUS" tablet report --posture=laptop --folio-present=false \
		--healthy=true --error= --last-seen=0 --touchscreen-enabled=true \
		--touch-scroll-enabled=false --touchpad-enabled=false >/dev/null 2>&1 || true
else
	echo "WARNING: z13ctl-plus unavailable; display state left unchanged"
fi

sudo rm -f /etc/udev/rules.d/{70-elan-touchscreen-uaccess.rules,99-elan-touchscreen-uaccess.rules,99-disable-asus-touchpad.rules} \
            /usr/local/bin/z13-tablet-switch /etc/systemd/system/z13-tablet-switch.service
rm -f ~/.local/bin/{dock,z13-tablet-switch,z13-touch-scroll,z13-rotate} \
      ~/.config/systemd/user/{z13-tablet-switch.service,z13-touch-scroll.service,z13-rotate.service}
rm -rf "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/z13-tablet-kit"

# Removing the inhibit rule does not update an already-present touchpad.
for device in /sys/class/input/event*/device; do
	[ -r "$device/name" ] || continue
	[ "$(cat "$device/name")" = "ASUSTeK Computer Inc. GZ302EA-Keyboard Touchpad" ] || continue
	if [ -w "$device/inhibited" ] || sudo test -w "$device/inhibited"; then
		echo 0 | sudo tee "$device/inhibited" >/dev/null
	fi
done

# Restore the keyd configuration changed by older kit versions.
if [ -e /etc/keyd/default.conf.z13-tablet-kit.bak ]; then
	sudo mv -f -- /etc/keyd/default.conf.z13-tablet-kit.bak /etc/keyd/default.conf
	if command -v keyd >/dev/null; then sudo keyd reload; fi
fi

systemctl --user daemon-reload
sudo udevadm control --reload-rules
sudo systemctl daemon-reload
echo "==> removed. (on-screen keyboard package left installed — remove with: pacman -Rns plasma-keyboard)"
