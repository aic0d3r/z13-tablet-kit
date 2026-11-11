# Install from source, verify, uninstall

Back to the [README](../README.md). On Arch / CachyOS, the AUR route in the
[Quick start](../README.md#quick-start) is simpler and recommended; if you used `install.sh`
before, run `./uninstall.sh` first, because the copies in `~/.local` would override the package.

## Install from source

For other distros, or to run `master`.

1. **Prerequisites:** `python-evdev` and `iio-sensor-proxy`
   (Arch: `sudo pacman -S python-evdev iio-sensor-proxy`; use your distro's package
   manager elsewhere). For the on-screen keyboard, `plasma-keyboard` ships with Plasma 6.7;
   install `maliit-keyboard` (AUR) only if you prefer the legacy one.
2. **`z13ctl-plus`** (hard dependency) from its release tarball:

   ```bash
   wget https://github.com/aic0d3r/z13ctl-plus/releases/download/v2.2.1/z13ctl-plus_2.2.1_linux_amd64.tar.gz
   tar xzf z13ctl-plus_2.2.1_linux_amd64.tar.gz
   sudo install -Dm755 z13ctl-plus /usr/local/bin/z13ctl-plus
   sudo z13ctl-plus setup
   systemctl --user enable --now z13ctl-plus.socket z13ctl-plus.service
   ```

3. **The kit:**

   ```bash
   git clone https://github.com/aic0d3r/z13-tablet-kit
   cd z13-tablet-kit
   ./install.sh
   ```

   `install.sh` is safe to re-run. It installs the posture manager, touch scroll, their user
   services, the udev rules, and the login-screen keyboard config, then starts everything. To update:
   `git pull && ./install.sh`.

## Post-install (one-time)

- **Log out and back in** if prompted. The `users` group membership added by
  `z13ctl-plus setup` takes effect at login and is needed for the folio-touchpad opt-in.
- **Enable auto-rotate once:** Quick Settings → Auto-rotate → right-click →
  "Rotate only in tablet mode". The kit's virtual `SW_TABLET_MODE` gates it.

## Verify

```bash
systemctl --user status z13-tablet-switch z13-touch-scroll
cat "$XDG_RUNTIME_DIR/z13-tablet-kit/posture"   # one of: desktop / laptop / tablet
```

- Logs: `journalctl --user -u z13-tablet-switch`
- Tests (offline, no hardware needed): `python3 -m unittest discover tests`

## Uninstall

**AUR:** stop the kit and reset the display before removing the package:

```bash
systemctl --user disable --now z13-tablet-switch.service z13-touch-scroll.service
/usr/lib/z13-tablet-kit/dock laptop      # touchscreen on, on-screen keyboard off
z13ctl-plus display rotation none
sudo pacman -R z13-tablet-kit
```

Then re-check System Settings → Keyboard → Virtual Keyboard: the package can't restore the
mode you had before.

**From source:**

```bash
cd z13-tablet-kit
./uninstall.sh
```

This returns to laptop defaults (normal rotation, touchscreen on), re-enables the folio
touchpad, and restores the on-screen keyboard mode recorded by the first `install.sh` run.
Installs older than that record print a reminder to re-check it in System Settings. The OSK
package stays installed.
