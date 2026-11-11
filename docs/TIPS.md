# Tips

Back to the [README](../README.md).

- **Touch scrolling:** a two-finger vertical swipe scrolls any focused app (terminal,
  browser, TUI). In `z13gui-plus`, **Scroll sensitivity** sets how readily a drag starts
  scrolling and **Scroll speed** how far content moves (1–5, defaults 3 and 2; **Reset
  Scroll Defaults** restores them).
- **Touch context menus:** a stationary two-finger hold (~650 ms) moves the pointer to the
  touch point and sends a real right-click; moving either finger cancels it and scrolls.
  Known limit: with touch enabled in desktop posture and a monitor placed left of or above
  the built-in panel, the click lands offset onto that monitor.
- **Page Up/Down without dedicated keys:** the Z13 folio keyboard has no Page Up/Down
  keycaps, but **Fn+Up / Fn+Down** are mapped in firmware and work everywhere.
- **Three-finger gestures** are reserved by KWin (overview, virtual desktop switching), so
  touch scroll deliberately uses two fingers.
- **Auto-rotate:** driven by Plasma + `iio-sensor-proxy`, gated by the virtual tablet-mode
  switch. If a portrait orientation comes out mirrored on your unit, that's a sensor-mount
  quirk to fix in `iio-sensor-proxy`, not in this kit.
- Configure optional edge gestures in **System Settings → Workspace → Touchscreen Gestures**.
