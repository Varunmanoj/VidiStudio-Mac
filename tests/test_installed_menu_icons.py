"""Run with All Projects active on an unlocked Mac using the project venv:
VIDISTUDIO_TEST_INSTALLED_MENUS=1 .venv/bin/python -m unittest tests.test_installed_menu_icons
For the editor, open a local project's Transcript (view mode, paused, no search)
and set VIDISTUDIO_MENU_CONTEXT=transcript. The fixture uses a generated transcript,
default sorting, preview and timeline visible and inspector open. Override the expected
language title arrays for another library or project using VIDISTUDIO_MENU_LIBRARY_LANGUAGES
and VIDISTUDIO_MENU_PROJECT_LANGUAGES (JSON). VIDISTUDIO_MENU_TRANSCRIPT_VERSIONS gives
the expected displayed version numbers. Set VIDISTUDIO_TEST_MENU_LAUNCH=1 to also quit
and relaunch the app. Section checks return to Transcript after visiting every tab.
The installed app and
an English menu bar, Accessibility and Screen Recording access are required.
"""
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

GALLERY = {
    "VidiStudio": ["About VidiStudio", "Settings…", "Services", "Hide VidiStudio",
                   "Hide Others", "Show All", "Quit VidiStudio"],
    "File": ["New Project…", "Open Project Folder…", "Open in New Window", "My YouTube Videos…",
             "?Open in YouTube", "Export…", "Delete Project…", "Choose What to Delete…",
             "Remove from List", "Settings…", "Open Project Settings…", "Close"],
    "Edit": ["Search Projects…", "Clear Search", "Rename Project…"],
    "View": ["Filter Projects by Source", "Filter Projects by Language", "Sort Projects",
             "Reset Project Filters", "Project List View", "Project Grid View", "Enter Full Screen"],
    "Project": ["Open Selected Project", "Analysis", "Show Project in Finder",
                "?Open Project Configuration", "Rename Project…", "Move Project to Bin…"],
    "YouTube": ["My YouTube Videos…", "YouTube Accounts…", "?Open in YouTube"],
    "Help": ["VidiStudio Help", "VidiStudio Website"],
    "Project/Analysis": ["Analyze Video…", "Generate Video Details & Timeline Pictures", "Generate Transcript",
                         "Generate Summary", "Generate Audio Descriptions"],
    "View/Sort Projects": ["Last Opened", "Name (A–Z)", "Duration (Longest First)", "Type (Local, then YouTube)"],
    "View/Filter Projects by Source": ["All Projects", "Local Video Projects", "YouTube Projects"],
}
WINDOW_COMMANDS = ["VidiStudio", "My YouTube Videos", "YouTube Details"]


SECTIONS = ["Show Transcript", "Show Summary", "Show Descriptions", "Show AD Overview", "Show AD Transcript"]
TRANSCRIPT = {
    "VidiStudio": GALLERY["VidiStudio"],
    "File": [item for item in GALLERY["File"] if item not in {"Open in New Window", "My YouTube Videos…", "?Open in YouTube"}],
    "Edit": ["Search Project…", "Clear Search", "Copy and Translate…", "Edit Transcript Segments"],
    "View": ["Editor Sections", "Project Language", "Transcript Saved Results", "Hide Preview",
             "Full-Screen Video", "Hide Timeline", "Show Thumbnail Images", "Filter Transcript…", "Sort Transcripts…",
             "Show Project List", "Hide Inspector", "Project List View", "Project Grid View", "Enter Full Screen"],
    "View/Editor Sections": SECTIONS,
    "View/Sort Transcripts…": ["Sort Options…", "Start Time", "Duration — Shortest First", "Duration — Longest First", "Origin"],
    "Playback": ["Show or Hide Preview", "Full-Screen Video", "Play Video", "Rewind 5 Seconds", "Fast Forward 5 Seconds",
                 "Jump to Time…", "Transcript Overlay: Off"],
    "Playback/Transcript Overlay: Off": ["Cycle Transcript Overlay", "Turn Transcript Overlay Off", "Show Transcript Overlay"],
    "Project": ["Language and Saved Results…", "Editor Sections", "Segments", "Analysis", "Delete Transcript…",
                "Import", "Show Project in Finder", "?Open Project Configuration", "Rename Project…", "Move Project to Bin…"],
    "Project/Editor Sections": SECTIONS,
    "Project/Segments": ["Edit Transcript Segments", "Add Transcript Segment", "Toggle Transcript Follow"],
    "Project/Analysis": ["Generate Video Details & Timeline Pictures", "Generate Transcript"],
    "Project/Import": ["Import Transcript…", "Import Existing Assets…"],
    "Help": GALLERY["Help"],
}

# Menus that only exist outside the Transcript tab.
SECTION_MENUS = {
    "Summary": {"Playback/Summary Reading": [
        "Play or Resume Summary Reading", "Pause Summary Reading", "Stop Summary Reading",
        "Previous Summary Sentence", "Next Summary Sentence", "Previous Summary Paragraph",
        "Next Summary Paragraph", "Read Summary from Start", "Read Summary from Selection", "Read Selected Summary Text"]},
    "Descriptions": {
        "Project/Narration": ["AD Segment Generation", "Narration Audio"],
        "Project/Narration/AD Segment Generation": ["Generate Audio Descriptions", "Delete Descriptions…"],
        "Project/Narration/Narration Audio": ["Generate All AD Audio", "Generate Missing or Changed AD Audio",
            "Review Narration Issues…", "Review Narration Voices…", "Delete All Narration Audio…"],
    },
    "AD Overview": {"Project/Narration": ["Narration Audio"]},
    "AD Transcript": {"Project/Narration": ["Narration Audio"]},
}


# AppKit reserves a separate checkmark column for submenu toggles and version rows.
TOGGLE_MENUS = {"View/Project Language", "View/Transcript Saved Results", "View/Filter Projects by Language"}


def normalized(text):
    return "".join(c for c in text.casefold() if c.isalnum())


@unittest.skipUnless(os.getenv("VIDISTUDIO_TEST_INSTALLED_MENUS") == "1", "Requires interactive installed Mac app")
class InstalledMenuTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.folder.cleanup)
        cls.probe = Path(cls.folder.name) / "menu-probe"
        subprocess.run(["xcrun", "swiftc", str(Path(__file__).with_name("installed_menu_probe.swift")),
                        "-o", str(cls.probe)], check=True)

    def capture(self, path):
        picture = Path(self.folder.name) / "menu.png"
        for attempt in range(2):
            result = subprocess.run([str(self.probe), str(picture), *path.split("/")],
                                    capture_output=True, text=True, timeout=40)
            if attempt == 0 and result.returncode and "Menu capture failed" in result.stderr:
                continue
            self.assertEqual(result.returncode, 0, result.stderr)
            menu = json.loads(result.stdout)
            # A disappearing native popup can leave AX geometry from the last
            # frame. Only repeat an empty/background capture, never a bad icon.
            if any(normalized(row["title"]) in normalized(label["text"])
                   for row in menu["rows"] for label in menu["labels"]):
                break
        # Native alternate commands share the same visible row (e.g. Close All
        # with Option held). Only the first title is displayed without modifiers.
        rows = {}
        for row in menu["rows"]:
            rows.setdefault(row["y"], row)
        self.assertTrue(rows, f"{path} has no visible command rows")
        return menu, rows, picture

    def check_icons(self, path, menu, rows, picture):
        from PIL import Image
        with Image.open(picture) as png:
            image = png.convert("L")
        scale = image.width / menu["width"]
        for y, row in rows.items():
            with self.subTest(menu=path, command=row["title"]):
                labels = [label for label in menu["labels"] if abs(label["y"]-y) < row["height"]/2]
                matches = [label for label in labels if normalized(row["title"]) in normalized(label["text"])]
                self.assertTrue(matches, f'Title absent in the rendered row: {labels}')
                # An empty icon column and text shifted left are independent
                # regressions. Checking both avoids mistaking text for an icon.
                label = matches[0]
                window_has_checkmarks = path == "Window" and any(r["title"] not in WINDOW_COMMANDS for r in rows.values())
                left, right = (30, 44) if path in TOGGLE_MENUS or window_has_checkmarks else (15, 30)
                self.assertGreater(label["x"], 23, "Command title occupied the icon column")
                box = tuple(round(v*scale) for v in (left, y-7, right, y+7))
                low, high = image.crop(box).getextrema()
                self.assertGreater(high-low, 18, "No visible icon beside command")

    @unittest.skipUnless(os.getenv("VIDISTUDIO_TEST_MENU_LAUNCH") == "1", "Opt in to quit and reopen the app")
    def test_cold_launch_menu_bar(self):
        result = subprocess.run([str(self.probe), "--sample-launch"], check=True, capture_output=True, timeout=30)
        sample = json.loads(result.stdout)
        self.assertGreater(sample["samples"], 0, "Did not observe a menu bar")
        for titles in sample["states"]:
            with self.subTest(menu_bar=titles):
                self.assertEqual(titles[:5], ["Apple", "VidiStudio", "File", "Edit", "View"])
                self.assertEqual([t for t in titles if t not in {"Playback", "YouTube"}],
                                 ["Apple", "VidiStudio", "File", "Edit", "View", "Project", "Window", "Help"])
                self.assertEqual(len(titles), len(set(titles)))

    @unittest.skipUnless(os.getenv("VIDISTUDIO_MENU_CONTEXT") == "transcript", "Requires the local editor fixture")
    def test_edit_when_switching_sections(self):
        def select(section):
            subprocess.run([str(self.probe), "--section", "Show " + section], check=True, timeout=15)

        self.addCleanup(select, "Transcript")
        for section, edit in [("Summary", "Edit Summary"), ("Descriptions", "Edit Audio Description Segments"),
                              ("AD Overview", None), ("AD Transcript", "Edit AD Transcript Segments"),
                              ("Transcript", "Edit Transcript Segments")]:
            with self.subTest(section=section):
                select(section)
                menu, rows, picture = self.capture("Edit")
                expected = ["Search Project…", "Clear Search"]
                if edit:
                    expected += ["Copy and Translate…", edit]
                self.assertEqual([row["title"] for row in rows.values()], expected)
                self.assertEqual(menu["menus"], ["Apple", "VidiStudio", "File", "Edit", "View", "Playback", "Project", "Window", "Help"])
                self.check_icons("Edit", menu, rows, picture)
                for path, commands in SECTION_MENUS.get(section, {}).items():
                    with self.subTest(menu=path):
                        menu, rows, picture = self.capture(path)
                        # Existing generated audio or descriptions rename the same actions.
                        aliases = {"Regenerate All AD Audio…": "Generate All AD Audio",
                                   "Regenerate Audio Descriptions…": "Generate Audio Descriptions"}
                        self.assertEqual([aliases.get(r["title"], r["title"]) for r in rows.values()], commands)
                        self.check_icons(path, menu, rows, picture)

    def test_open_menus(self):
        context = os.getenv("VIDISTUDIO_MENU_CONTEXT", "gallery")
        self.assertIn(context, ["gallery", "transcript"])
        gallery = context == "gallery"
        if gallery:
            subprocess.run([str(self.probe), "--gallery", "VidiStudio"], check=True, timeout=15)
        contract = GALLERY if gallery else TRANSCRIPT
        expected_bar = (["Apple", "VidiStudio", "File", "Edit", "View", "Project", "YouTube", "Window", "Help"] if gallery
                        else ["Apple", "VidiStudio", "File", "Edit", "View", "Playback", "Project", "Window", "Help"])
        dynamic_paths = ["View/Filter Projects by Language"] if gallery else ["View/Project Language", "View/Transcript Saved Results"]
        for path in [*contract, *dynamic_paths, "Window"]:
            with self.subTest(context=context, menu=path):
                menu, rows, picture = self.capture(path)
                self.assertEqual(menu["menus"], expected_bar)
                titles = [r["title"] for r in rows.values()]
                if path == "Window":
                    system = {"Minimize", "Zoom", "Fill", "Center", "Move & Resize", "Full Screen Tile",
                              "Bring All to Front", "Remove Window from Set", "Add Window to Set",
                              "Merge All Windows", "Show Previous Tab", "Show Next Tab", "Move Tab to New Window"}
                    app_rows = [t for t in titles if t not in system and not t.startswith("Move to ")]
                    for title in app_rows:
                        self.assertIn(title, WINDOW_COMMANDS + menu["windows"], "Unexpected Window menu command")
                    self.assertEqual([t for t in app_rows if t in WINDOW_COMMANDS], WINDOW_COMMANDS)
                    rows = {y:r for y,r in rows.items() if r["title"] in app_rows}
                elif path in dynamic_paths:
                    self.assertEqual(len(titles), len(set(titles)), "Duplicate dynamic menu row")
                    if path == "View/Filter Projects by Language":
                        self.assertEqual(titles[0], "All Languages")
                        expected_options = json.loads(os.getenv("VIDISTUDIO_MENU_LIBRARY_LANGUAGES", '["Auto", "English", "Hindi"]'))
                        self.assertEqual(titles[1:], expected_options)
                    elif path == "View/Project Language":
                        expected_options = json.loads(os.getenv("VIDISTUDIO_MENU_PROJECT_LANGUAGES", '["Auto (Transcript, Summary, Descriptions)"]'))
                        self.assertEqual(titles, expected_options)
                    else:
                        versions = json.loads(os.getenv("VIDISTUDIO_MENU_TRANSCRIPT_VERSIONS", "[1]"))
                        numbers = [re.fullmatch(r"Version (\d+) · .+ · .+", t) for t in titles]
                        self.assertTrue(all(numbers), f"Unexpected saved-result command in {titles}")
                        self.assertEqual([int(match.group(1)) for match in numbers], versions)
                else:
                    if path == "Project/Analysis":
                        titles = [re.sub(r"^Regenerate ", "Generate ", t).rstrip("…")
                                  if t.startswith(("Generate ", "Regenerate ")) else t for t in titles]
                    expected = [t.lstrip("?") for t in contract[path] if not t.startswith("?") or t[1:] in titles]
                    self.assertEqual(titles, expected, "Unexpected, missing or misplaced command")
                self.check_icons(path, menu, rows, picture)
