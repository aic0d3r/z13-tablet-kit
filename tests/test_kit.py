#!/usr/bin/env python3
"""Offline checks for the kit's daemons. Run: python3 -m unittest discover tests"""
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
BIN = Path(__file__).resolve().parent.parent / "bin"


def load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), str(BIN / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


ts = load("z13-touch-scroll")
sw = load("z13-tablet-switch")
E = ts.evdev.ecodes
real_touch_action_settings = ts.touch_action_settings  # TouchScroll.setUp stubs the module one


class FakeUI:
    def __init__(self):
        self.wheel = []

    def write(self, _type, code, value):
        if code == E.REL_WHEEL:
            self.wheel.append(value)

    def syn(self):
        pass


class TouchScroll(unittest.TestCase):
    def setUp(self):
        self.state, self.ui = ts.new_state(), FakeUI()
        patcher = mock.patch.object(ts, "touch_action_settings", lambda: (90, 2, False))
        patcher.start()
        self.addCleanup(patcher.stop)

    def send(self, *events):
        for type_, code, value in events:
            event = types.SimpleNamespace(type=type_, code=code, value=value)
            if ts.handle_event(self.state, event):
                ts.emit_scrolls(self.state, self.ui)

    def down(self, slot, x, y):
        self.send((E.EV_ABS, E.ABS_MT_SLOT, slot), (E.EV_ABS, E.ABS_MT_TRACKING_ID, slot + 1),
                  (E.EV_ABS, E.ABS_MT_POSITION_X, x), (E.EV_ABS, E.ABS_MT_POSITION_Y, y),
                  (E.EV_SYN, E.SYN_REPORT, 0))

    def move_y(self, y):
        for slot in (0, 1):
            self.send((E.EV_ABS, E.ABS_MT_SLOT, slot), (E.EV_ABS, E.ABS_MT_POSITION_Y, y))
        self.send((E.EV_SYN, E.SYN_REPORT, 0))

    def test_two_finger_swipe_down_scrolls_up(self):
        self.down(0, 1000, 500)
        self.down(1, 1200, 500)
        self.move_y(700)  # 200 units down, step 90 -> 2 notches-of-2
        self.assertEqual(self.ui.wheel, [-2, -2])

    def test_third_finger_does_not_scroll(self):
        self.down(0, 1000, 500)
        self.down(1, 1200, 500)
        self.down(2, 1100, 1600)
        self.assertEqual(self.ui.wheel, [])
        for slot in (0, 1, 2):  # moving all three must not scroll either
            self.send((E.EV_ABS, E.ABS_MT_SLOT, slot), (E.EV_ABS, E.ABS_MT_POSITION_Y, 100))
        self.send((E.EV_SYN, E.SYN_REPORT, 0))
        self.assertEqual(self.ui.wheel, [])

    def test_dropped_events_forget_fingers(self):
        self.down(0, 1000, 500)
        self.send((E.EV_SYN, E.SYN_DROPPED, 0))
        self.assertEqual(self.state["positions"], {})

    def arm_hold(self):
        with mock.patch.object(ts, "touch_action_settings", lambda: (90, 2, True)):
            self.down(0, 1000, 500)
            self.down(1, 1200, 500)
        self.state["hold_started"] -= ts.HOLD_SECONDS + 1
        fired = []
        with mock.patch.object(ts, "emit_context_menu", lambda *_: fired.append(1)):
            ts.check_hold(self.state, self.ui)
            ts.check_hold(self.state, self.ui)  # once per hold
        return fired

    def test_still_two_finger_hold_right_clicks_once(self):
        self.assertEqual(self.arm_hold(), [1])

    def test_moving_finger_cancels_hold(self):
        with mock.patch.object(ts, "touch_action_settings", lambda: (90, 2, True)):
            self.down(0, 1000, 500)
            self.down(1, 1200, 500)
        self.send((E.EV_ABS, E.ABS_MT_SLOT, 0), (E.EV_ABS, E.ABS_MT_POSITION_Y, 500 + 2 * ts.HOLD_MOVE))
        self.state["hold_started"] -= ts.HOLD_SECONDS + 1
        with mock.patch.object(ts, "emit_context_menu", lambda *_: self.fail("fired")):
            ts.check_hold(self.state, self.ui)

    def test_touch_off_in_desktop_posture_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            posture = Path(tmp) / "posture"
            settings = Path(tmp) / "missing.json"  # defaults: disable touch on desktop
            with mock.patch.object(ts, "POSTURE_FILE", str(posture)), mock.patch.object(
                    ts, "SETTINGS_FILE", str(settings)):
                posture.write_text("desktop\n")
                self.assertIsNone(real_touch_action_settings())
                posture.write_text("laptop\n")
                self.assertIsNotNone(real_touch_action_settings())

    def test_to_logical_rotations(self):
        w, h = ts.PANEL_W / 2, ts.PANEL_H / 2  # scale 2
        top_left = (0, 0)
        self.assertEqual(ts.to_logical(*top_left, 1, 2), (0, 0))
        self.assertEqual(ts.to_logical(*top_left, 2, 2), (h, 0))      # left: native top-left -> top-right
        self.assertEqual(ts.to_logical(*top_left, 4, 2), (w, h))      # inverted
        self.assertEqual(ts.to_logical(*top_left, 8, 2), (0, w))      # right: -> bottom-left
        self.assertEqual(ts.to_logical(ts.TOUCH_MAX_X, ts.TOUCH_MAX_Y, 1, 2), (w, h))


class TabletSwitch(unittest.TestCase):
    def test_scroll_settings_do_not_trigger_reapply(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "s.json"
            with mock.patch.object(sw, "SETTINGS_FILE", path):
                path.write_text(json.dumps({"scroll_speed": 2}))
                before = sw.tablet_settings()
                path.write_text(json.dumps({"scroll_speed": 4, "two_finger_hold_context_menu": True}))
                self.assertEqual(before, sw.tablet_settings())

    def test_report_failure_does_not_block_posture(self):
        def run(cmd, **_):
            failed = cmd[1:3] == ["tablet", "report"]  # dock succeeds, report fails
            return types.SimpleNamespace(returncode=int(failed), stdout="", stderr="no socket")

        with mock.patch.object(sw.subprocess, "run", run):
            self.assertTrue(sw.apply_posture("tablet", False, (True, False)))

    def test_touchpad_applied_even_when_dock_fails(self):
        # GNOME: no KWin, so dock exits 1; the sysfs touchpad opt-in must still apply.
        run = lambda cmd, **_: types.SimpleNamespace(
            returncode=int(cmd[0] == sw.DOCK_HELPER), stdout="", stderr="dock: touchscreen unavailable")
        with tempfile.TemporaryDirectory() as tmp:
            dev = Path(tmp, "event9", "device")
            dev.mkdir(parents=True)
            (dev / "name").write_text(sw.TOUCHPAD_NAME + "\n")
            (dev / "inhibited").write_text("1\n")
            with mock.patch.object(sw.subprocess, "run", run), mock.patch.object(
                    sw.glob, "glob", lambda _: [str(dev)]):
                self.assertFalse(sw.apply_posture("laptop", True, (True, True)))
            self.assertEqual((dev / "inhibited").read_text(), "0")

    def test_repeated_failure_is_logged_once(self):
        run = lambda cmd, **_: types.SimpleNamespace(
            returncode=int(cmd[0] == sw.DOCK_HELPER), stdout="", stderr="dock: down")
        sw._last_error = ""
        with mock.patch.object(sw.subprocess, "run", run), mock.patch.object(
                sw.glob, "glob", lambda _: []), mock.patch("builtins.print") as out:
            for _ in range(3):
                sw.apply_posture("laptop", False, (True, False))
        self.assertEqual([c.args[0] for c in out.call_args_list].count("dock: down"), 1)

    def test_dock_is_next_to_switch(self):
        self.assertEqual(sw.DOCK_HELPER, BIN / "dock")
        self.assertEqual(sw.DOCK, (0x0B05, 0x1AC1))  # USB id, not shadowed by the helper path

    def test_heartbeat_resends_last_report_with_fresh_timestamp(self):
        calls = []
        run = lambda cmd, **_: calls.append(cmd) or types.SimpleNamespace(
            returncode=0, stdout="", stderr="")
        with mock.patch.object(sw.subprocess, "run", run):
            sw.report_integration("desktop", True, True, "", False, False, False)
            with mock.patch.object(sw.time, "time", lambda: 12345):
                sw.heartbeat()
        self.assertEqual(len(calls), 2)
        self.assertIn("--last-seen=12345", calls[1])
        self.assertEqual(calls[0][2:5], calls[1][2:5])

    def test_event_sources_open_and_filter(self):
        sock = sw.uevent_socket()
        self.assertTrue(sock is None or sock.fileno() >= 0)  # None only without netlink
        if sock:
            sock.close()
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(
                sw, "SETTINGS_FILE", Path(tmp) / "s.json"):
            fd = sw.settings_watch()
            self.assertIsNotNone(fd)
            (Path(tmp) / "s.json").write_text("{}")
            import select
            self.assertTrue(select.select([fd], [], [], 1)[0])
            sw.drain(fd)
            os.close(fd)

    def test_missing_binaries_fail_softly(self):
        def run(cmd, **_):
            raise FileNotFoundError(cmd[0])

        with mock.patch.object(sw.subprocess, "run", run):
            self.assertFalse(sw.apply_posture("tablet", False, (True, False)))


STUBS = {
    "qdbus6": 'echo /org/kde/KWin/InputDevice/event5',
    "gdbus": 'echo "$*" >> "$LOG"\ncase "$*" in\n'
             '  *" name") echo "(<\'ELAN9008:00 04F3:43C7\'>,)" ;;\n'
             '  *Get*enabled) echo "(<$TOUCH>,)" ;;\nesac',
    "z13ctl-plus": 'echo "$*" >> "$LOG"; exit "${PUBLISH_RC:-0}"',
    "dbus-send": 'echo "dbus-send $*" >> "$LOG"',
    "pgrep": 'exit 1',
    "kreadconfig6": 'echo "${SAVED:-}"',
    "kwriteconfig6": 'echo "kwriteconfig6 $*" >> "$LOG"',
}


class Dock(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        stubs = self.tmp / "stubs"
        stubs.mkdir()
        for name, body in STUBS.items():
            (stubs / name).write_text(f"#!/bin/sh\n{body}\n")
            (stubs / name).chmod(0o755)
        self.log = self.tmp / "log"
        self.posture = self.tmp / "z13-tablet-kit/posture"
        self.env = {**os.environ, "PATH": f"{stubs}:{os.environ['PATH']}",
                    "HOME": str(self.tmp), "XDG_RUNTIME_DIR": str(self.tmp),
                    "LOG": str(self.log)}

    def dock(self, *args, touch="true", publish_rc=0, saved=""):
        env = {**self.env, "TOUCH": touch, "PUBLISH_RC": str(publish_rc),
               "SAVED": saved}
        return subprocess.run([str(BIN / "dock"), *args], env=env,
                              capture_output=True, text=True)

    def calls(self):
        return self.log.read_text() if self.log.exists() else ""

    def test_desktop_disables_touch_and_publishes(self):
        result = self.dock("desktop", "true", touch="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("enabled <false>", self.calls())
        self.assertIn("display posture desktop", self.calls())
        self.assertIn("int32:0", self.calls())  # OSK off
        self.assertEqual(self.posture.read_text(), "desktop\n")

    def test_desktop_keeps_touch_when_policy_allows(self):
        self.assertEqual(self.dock("desktop", "false", touch="true").returncode, 0)
        self.assertNotIn("InputDevice enabled <", self.calls())  # no touch write

    def test_tablet_enables_touch_and_osk(self):
        self.assertEqual(self.dock("tablet", touch="false").returncode, 0)
        self.assertIn("enabled <true>", self.calls())
        self.assertIn("int32:1", self.calls())  # OSK touch-only

    def test_failed_publish_keeps_old_posture(self):
        result = self.dock("tablet", publish_rc=1)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.posture.exists())
        self.assertIn("int32:1", self.calls())  # OSK mode set even though publish failed

    def test_rejects_bad_arguments(self):
        self.assertEqual(self.dock("sideways").returncode, 2)
        self.assertEqual(self.dock("tablet", "maybe").returncode, 2)

    def test_saved_touch_off_is_dropped(self):
        # KWin persists enabled=false; it must not survive to the next boot.
        self.assertEqual(self.dock("desktop", saved="false").returncode, 0)
        self.assertIn("--key Enabled --delete", self.calls())

    def test_saved_touch_absent_is_left_alone(self):
        self.assertEqual(self.dock("tablet").returncode, 0)
        self.assertNotIn("kwriteconfig6", self.calls())

    def test_unchanged_rerun_is_silent(self):
        self.assertIn("dock: laptop", self.dock("laptop").stdout)
        self.assertEqual(self.dock("laptop").stdout, "")


if __name__ == "__main__":
    unittest.main()
