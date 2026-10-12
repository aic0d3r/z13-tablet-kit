#!/usr/bin/env python3
"""Offline checks for the kit's daemons. Run: python3 -m unittest discover tests"""
import importlib.machinery
import importlib.util
import json
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


if __name__ == "__main__":
    unittest.main()
