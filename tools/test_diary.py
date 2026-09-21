#!/usr/bin/env python3
"""DIARY is the party day feed. Current time, same group, newest first.

TRIP due-clock is gone. Members log TODAY; only the joined party can open
those lines. Attendance is HERE or SILENT for the local day.
"""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


def diary_feed(lines: list[dict]) -> list[dict]:
    """Most recent `at` first. Id breaks ties so the order is stable."""
    return sorted(lines, key=lambda line: (-line["at"], line["id"]))


def diary_attend(roster: list[dict], lines: list[dict], now_day: str) -> list[dict]:
    here = {line["from"] for line in lines if line["day"] == now_day}
    return [
        {
            "id": row["id"],
            "name": row["name"],
            "mark": "HERE" if row["id"] in here else "SILENT",
        }
        for row in roster
    ]


class DiaryFeedTests(unittest.TestCase):
    def test_feed_is_newest_first(self):
        lines = [
            {"id": "a", "from": "you", "at": 100, "text": "morning"},
            {"id": "b", "from": "rui", "at": 300, "text": "ridge"},
            {"id": "c", "from": "you", "at": 200, "text": "tank"},
        ]
        self.assertEqual(
            [line["text"] for line in diary_feed(lines)],
            ["ridge", "tank", "morning"],
        )

    def test_attendance_is_here_or_silent_for_the_local_day(self):
        roster = [
            {"id": "you", "name": "YOU"},
            {"id": "rui", "name": "RUI"},
            {"id": "sam", "name": "SAM"},
        ]
        lines = [
            {"from": "you", "day": "2026-09-18"},
            {"from": "rui", "day": "2026-09-17"},
        ]
        self.assertEqual(
            diary_attend(roster, lines, "2026-09-18"),
            [
                {"id": "you", "name": "YOU", "mark": "HERE"},
                {"id": "rui", "name": "RUI", "mark": "SILENT"},
                {"id": "sam", "name": "SAM", "mark": "SILENT"},
            ],
        )


class DiaryGlassTests(unittest.TestCase):
    def test_expedition_plate_is_diary_with_now_not_due(self):
        exped = read("Blackout", "ExpeditionTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        brief = read(
            "Packages", "TripBrief", "Sources", "TripBrief", "TripBrief.swift"
        )
        tests = read(
            "Packages",
            "TripBrief",
            "Tests",
            "TripBriefTests",
            "TripBriefTests.swift",
        )
        self.assertIn("case condition, roster, timers, inventory", exped)
        self.assertNotIn("case .diary", exped)
        self.assertNotIn('return "DIARY"', exped)
        roster = exped.split("private var rosterPlate")[1].split("private var timersPlate")[0]
        self.assertIn("runtime.liveRoster", roster)
        self.assertIn('sectionLabel("DIARY")', roster)
        self.assertGreater(
            roster.find("runtime.liveRoster"),
            -1,
        )
        self.assertGreater(
            roster.find('sectionLabel("DIARY")'),
            roster.find("runtime.liveRoster"),
            "DIARY sits under the members, not on its own plate",
        )
        self.assertNotIn('sectionLabel("TRIP")', exped)
        self.assertNotIn('return "TRIP"', exped)
        self.assertNotIn("dueBack", exped)
        self.assertNotIn("DUE ", exped)
        self.assertNotIn("overdue()", exped)
        self.assertIn('HUDField("TODAY"', roster)
        self.assertIn('submit: "LOG"', roster)
        self.assertIn("WRITE TODAY", roster)
        self.assertIn("HERE", exped)
        self.assertIn("SILENT", exped)
        self.assertIn("rosterAttend", exped)
        self.assertIn("runtime.diary.feed()", roster)
        self.assertIn("runtime.diaryAttend", exped)
        self.assertIn("logDiary", exped)
        self.assertIn("TimelineView", roster)
        self.assertIn("struct DiaryLine", brief)
        self.assertIn("struct DiaryLog", brief)
        self.assertIn("func feed(", brief)
        self.assertIn("func attend(", brief)
        self.assertIn('case here = "HERE"', brief)
        self.assertIn('case silent = "SILENT"', brief)
        self.assertIn("var diary", app)
        self.assertIn("func logDiary(", app)
        self.assertIn("func persistDiary(", app)
        self.assertNotIn("var trip", app)
        self.assertNotIn("TripFactory", app)
        self.assertIn("testFeedIsNewestFirst", tests)
        self.assertIn("testAttendanceIsHereOrSilentForTheLocalDay", tests)
        self.assertIn("testLineStampsTheGivenNow", tests)

    def test_paper_prints_diary_not_due(self):
        paper = read("Packages", "PaperGen", "Sources", "PaperGen", "PaperGen.swift")
        tests = read(
            "Packages", "PaperGen", "Tests", "PaperGenTests", "PaperGenTests.swift"
        )
        exped = read("Blackout", "ExpeditionTab.swift")
        self.assertIn("func export(", paper)
        self.assertIn("diary: DiaryLog", paper)
        self.assertIn("diary.attend(", paper)
        self.assertIn("diary.feed()", paper)
        self.assertNotIn("due ", paper)
        self.assertNotIn("dueBack", paper)
        self.assertNotIn("TripSheet", paper)
        self.assertNotIn("PaperGen.export(diary:", exped)
        self.assertNotIn('Button("EXPORT PAPER")', exped)
        self.assertIn("HERE", tests)
        self.assertIn("SILENT", tests)
        self.assertNotIn("TripFactory", tests)

    def test_mesh_diary_is_party_only(self):
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        tests = read(
            "Packages", "MeshDTN", "Tests", "MeshDTNTests", "MeshDTNTests.swift"
        )
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("enum MeshDiaryBody", mesh)
        self.assertIn("func sendDiary(", mesh)
        self.assertIn('kind: "diary"', mesh)
        self.assertIn('case "diary":', mesh)
        self.assertIn("inboundDiary", mesh)
        inbound = app.split("func applyInbound")[1].split("func raiseIncoming")[0]
        self.assertIn('case "diary":', inbound)
        self.assertIn("MeshDiaryBody.parse", inbound)
        self.assertIn("diary.upsert", inbound)
        self.assertIn("testDiaryBodyRoundtrip", tests)
        self.assertIn("testDiarySealsToPartyAndWrongCodeStaysClosed", tests)
        self.assertIn("testSendDiaryLogsWhenSolo", tests)

    def test_solo_qa_names_diary(self):
        qa = read("docs", "SOLO_QA.md")
        hud = next(line for line in qa.splitlines() if "HUD keyboard rises" in line)
        roster = next(line for line in qa.splitlines() if "Roster is the live party" in line)
        kit = next(line for line in qa.splitlines() if "INVENTORY names and counts" in line)
        self.assertIn("TODAY", hud)
        self.assertNotIn("BRIEF", hud)
        self.assertIn("DIARY", roster)
        self.assertIn("HERE", roster)
        self.assertIn("SILENT", roster)
        self.assertIn("not its own plate", roster)
        self.assertIn("under the members", roster)
        self.assertNotIn("TRIP brief", kit)
        self.assertNotIn("DIARY", kit)
        self.assertNotIn("due", kit.lower())
        self.assertNotIn("due", roster.lower())


if __name__ == "__main__":
    unittest.main()
