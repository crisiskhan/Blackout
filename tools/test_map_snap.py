#!/usr/bin/env python3
"""MAP desk SNAPs cameras to date the same one-shot way as CCTV.

ACTIVATE, PACK switch, and MAP tab all pull tapUpdate — packed HTTPS
stills, hop stills, weather, quakes. Airplane keeps last SNAP.
Never a live stream.
"""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


class MapDeskSnapTests(unittest.TestCase):
    def test_map_desk_snaps_the_same_pipe_as_tap_update(self):
        app = read("Blackout", "AppRuntime.swift")
        root = read("Blackout", "RootChrome.swift")
        sock = read("Blackout", "UpdateSocket.swift")
        self.assertIn("func pullMapSnap(", app)
        pull = app.split("func pullMapSnap")[1].split("func tapUpdate")[0]
        self.assertIn("tapUpdate()", pull)
        arm = app.split("func arm()")[1].split("func listenNet")[0]
        self.assertIn("pullMapSnap()", arm)
        switch = app.split("func switchPack")[1].split("func applyMapKeepAwake")[0]
        self.assertIn("pullMapSnap()", switch)
        self.assertIn("func showTab(", app)
        show = app.split("func showTab")[1].split("func pullMapSnap")[0]
        self.assertIn("tab = next", show)
        self.assertIn("pullMapSnap()", show)
        self.assertIn(".map", show)
        self.assertIn("runtime.showTab(t)", root)
        self.assertNotIn("runtime.tab = t", root)
        tap = app.split("func tapUpdate")[1].split("func fitPack")[0]
        self.assertIn("extraCams", tap)
        self.assertIn("hopCamStills", tap)
        self.assertIn("var queued", sock)
        self.assertNotIn("AVPlayer", sock)
        self.assertNotIn("WKWebView", sock)
        self.assertNotIn("rtmp", sock)

    def test_device_script_scores_map_open_snap(self):
        qa = read("docs", "SOLO_QA.md")
        cctv = next(line for line in qa.splitlines() if "Packed CCTV" in line)
        hop = next(line for line in qa.splitlines() if "Hop cameras" in line)
        self.assertIn("Opening MAP", cctv)
        self.assertIn("PACKS", cctv)
        self.assertIn("TAP UPDATE", cctv)
        self.assertIn("latest", cctv.lower())
        self.assertIn("Opening MAP", hop)
        agents = read("AGENTS.md")
        self.assertIn("test_map_snap.py", agents)
        validate = read("tools", "validate_v3.py")
        self.assertIn("test_map_snap.py", validate)
        self.assertIn("map_snap()", validate)


if __name__ == "__main__":
    unittest.main()
