#!/bin/bash
# z13-tablet-kit — uninstaller
set -euo pipefail

echo "==> removing z13-tablet-kit"
systemctl --user disable --now asus-dock.service asus-dock.timer z13-rotate.service z13-touch-scroll.service 2>/dev/null || true
sudo  systemctl disable --now z13-tablet-switch 2>/dev/null || true

sudo rm -f /etc/systemd/system/z13-tablet-switch.service \
            /etc/udev/rules.d/99-asus-dock.rules \
            /etc/udev/rules.d/99-elan-touchscreen-uaccess.rules \
            /etc/udev/rules.d/99-disable-asus-touchpad.rules \
            /usr/local/bin/z13-tablet-switch
rm -f ~/.local/bin/asus-dock ~/.local/bin/z13-rotate ~/.local/bin/z13-touch-scroll \
      ~/.config/systemd/user/asus-dock.service \
      ~/.config/systemd/user/asus-dock.timer \
      ~/.config/systemd/user/z13-rotate.service \
      ~/.config/systemd/user/z13-touch-scroll.service
rm -f ~/.cache/asus-dock-state ~/.cache/asus-dock-touch.path

systemctl --user daemon-reload
sudo udevadm control --reload-rules
sudo systemctl daemon-reload
echo "==> removed. (maliit-keyboard left installed — remove with: pacman -Rns maliit-keyboard)"
