#!/usr/bin/env python3
"""Build the offline Apple Help book and validate its internal navigation."""
import argparse
import html
from html.parser import HTMLParser
import pathlib
import plistlib
import re
import subprocess
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
BOOK_ID = "Varunmanojkumar.VidiStudio.help.v2"
TOPICS = [
    ("welcome", "Welcome to VidiStudio"),
    ("first-project", "Create your first described video"),
    ("projects", "Manage projects"),
    ("editor", "Explore the editor"),
    ("descriptions", "Write and edit descriptions"),
    ("analysis", "Analyze and replace content"),
    ("narration", "Choose voices and play narration"),
    ("exports", "Export your work"),
    ("settings", "Settings reference"),
    ("keyboard", "Keyboard shortcuts and accessibility"),
    ("troubleshooting", "Solve common problems"),
    ("privacy", "Privacy and glossary"),
]

class Page(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.ids, self.links = set(), []
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            if attrs["id"] in self.ids:
                raise ValueError("Duplicate anchor: " + attrs["id"])
            self.ids.add(attrs["id"])
        if tag == "a" and "href" in attrs:
            self.links.append(attrs["href"])

def keyboard():
    source = (ROOT / "VidiStudio/KeyboardShortcuts.swift").read_text()
    commands = re.findall(r'\.init\(id: "[^"]+", title: "([^"]+)".*?spoken: "([^"]+)"', source)
    if len(commands) < 20:
        raise ValueError("Editor shortcut extraction failed")
    general = [("New Project", "Command + N"), ("Open Selected Project", "Command + O"),
               ("Open Project Folder", "Command + Shift + O"), ("Rename selected project in All Projects", "Return"),
               ("Settings", "Command + Comma"), ("Show or Hide Inspector", "Command + Shift + B"),
               ("Project List View", "Command + Option + 1"), ("Project Grid View", "Command + Option + 2"),
               ("VidiStudio Help", "Command + Option + Slash")]
    rows = "".join(f"<tr><th scope='row'>{html.escape(title)}</th><td>{html.escape(keys)}</td></tr>" for title, keys in general + commands)
    return """<h1>Keyboard shortcuts and accessibility</h1>
<p>Use the menu bar to discover commands and their shortcuts. Project commands require an open project and may be unavailable during processing or while a sheet is open. View can show or hide the preview and the complete timeline, including thumbnails, seeking, Transcript segments, and Audio Description segments. Editor opening, preview, timeline, inspector, Settings and Export presentation, and Settings disclosure changes use short transitions; macOS Reduce Motion disables this added movement. Playback includes Transcript Overlay commands on the Transcript, Descriptions, and AD Transcript pages. Playback &gt; Summary Reading contains separate Play or Resume, Pause, and Stop commands that are available only on Summary. Project &gt; Segments contains Edit or Done, Add Segment, Select All, Deselect All, Edit Selected, Delete Selected, Follow, Undo, and Redo; their availability follows the selected section, edit mode, and selection. Media metadata, thumbnails, and transcription audio are prepared automatically.</p>
<table><caption>Application shortcuts</caption><thead><tr><th scope='col'>Action</th><th scope='col'>Shortcut</th></tr></thead><tbody>""" + rows + """</tbody></table>
<h2>Look more closely at a section</h2><p>In Add or Edit Audio Description, choose a start and end time and use Re-Analyze This Segment beside Read Frame Text. Project &gt; Segments &gt; Re-Analyze a Video Section (Command-Option-R) opens the range editor on Transcript or Descriptions. Audio Description analysis requires a transcript and summary. Gemini receives the video section, summary, transcript, existing descriptions, and your draft. It can rewrite and move nearby descriptions to fit around dialogue; unrelated descriptions remain unchanged. Invalid overlapping proposals are corrected or rejected before saving. Use Undo Segment Edit to restore the previous descriptions. Changed narration must be synthesized again.</p><p>For local videos, Video Analysis Availability shows a spinning progress indicator while checking, uploading, or preparing the video, including when another analysis action triggers a fresh upload. It changes to a green check mark as soon as Gemini reports the upload ready, and the remaining-availability timer starts then. At rest, an orange hourglass marks remote processing and a red information icon marks an availability issue. The timer uses consistent numeric values for days, hours, minutes, and seconds; at the full window it reads “2 days, 0 hours, 0 minutes, 0 seconds.” VoiceOver announces the progress or complete status and remaining time. Use the upload-arrow button to prepare the video and the circular-arrow button to refresh. YouTube videos use their public link and do not show upload availability controls.</p><h2>Generate transcript segments for a range</h2><p>In Transcript edit mode, open Add Segment, choose start and end times, and use Re-Analyze This Segment. You can also use this action in Edit Transcript Segment or open the range editor with Command-Option-R. Gemini can create multiple dialogue segments and reconcile immediate transcript neighbors. The optional Hint for Gemini is separate from manual Transcript text; Save Segment saves manual text. Shared multilingual system and user prompts preserve every spoken language, original scripts, and code-switching. Range analysis uses the Transcript video model, or the configured YouTube Transcript video model when Transcript uses an audio-only transcription model. No existing transcript or summary is required.</p><p>Existing AD segments, narration, and summary are preserved. Speech that conflicts with AD timing is rejected; review and adjust that description before retrying. Invalid or empty proposals keep existing content. Undo Segment Edit and Redo on Transcript restore saved transcript edits; history restoration also checks for conflicts with current descriptions. Deleting transcript rows clears transcript history so permanently deleted rows cannot return. Successful segment edits clear the current export listing; create fresh exports afterward. Regenerate Transcript replaces all transcript edits and clears transcript history, while retaining AD and narration. Its warning offers Add Segment and Re-Analyze This Segment for targeted changes. Review retained AD timing after full regeneration.</p><h2>Edit text and segments</h2><p>Command-Option-E enters or leaves segment edit mode. In Transcript edit mode, Command-Shift-N adds a new Transcript segment at the current video time; on Descriptions it adds a new Audio Description. Command-Option-A selects every visible segment, Command-Option-Shift-A deselects all, Command-Option-Return edits the selected rows, and Command-Control-Delete asks to delete selected rows. Command-Z and Command-Shift-Z undo and redo text editing. The separate segment-history commands above restore saved segment edits. Return activates Save Segment when the sheet's default action is available; Escape cancels a sheet or leaves full-screen video. Regeneration shortcuts still ask for confirmation before replacing existing content.</p>
<p>When you reopen a local-video project, the inspector resumes the saved availability countdown without contacting Gemini or asking you to refresh. The green check mark means the video was last confirmed ready, not that it has just been checked. Refresh Status or a new video-analysis action checks the remote file before use. A temporary connection or permission error does not replace the last confirmed upload state; an older unverified state appears with a neutral question mark and its remaining countdown. A confirmed missing file or elapsed expiry still needs a new preparation upload.</p>
<h2>Read the Summary from the keyboard</h2><p>While Summary is selected, Command-Shift-P plays or resumes summary reading, Command-Option-P pauses it, and Command-Shift-S stops it. The corresponding Playback &gt; Summary Reading commands show the same shortcuts and update their availability as reading starts, pauses, resumes, and stops.</p>
<h2>Navigate without a mouse</h2><p>Enable Keyboard navigation in macOS System Settings &gt; Keyboard to reach all controls using Tab and Shift-Tab. Use Space to activate a focused button or toggle, and arrow keys within lists and pickers. Select a project and press Command-O to open it. Focus the video timeline slider to seek without dragging. Description rows expose edit and other actions in their contextual menu.</p>
<h2>Use VoiceOver</h2><p>Use standard Control-Option navigation and interaction commands. VidiStudio does not assign those combinations to app shortcuts. The player, timeline, sections, segment times, generation status, and voice choices expose accessible labels. In this Help Book, use headings, links, and the table of contents to navigate; the Skip to topic link bypasses repeated navigation. Tables have column headings and prose instructions do not depend on screenshots or color.</p>
<h2>Make reading comfortable</h2><p>VidiStudio supports System, Light, and Dark appearance in Settings. This Help Book follows the system appearance independently. Follow synchronized transcript can keep the active text visible during playback; turn it off when you want to read without automatic scrolling.</p>"""

CSS = """html{color-scheme:light dark;font:17px/1.6 -apple-system,BlinkMacSystemFont,sans-serif}body{margin:0;color:light-dark(#202124,#ededf0);background:light-dark(#fff,#1c1c1e)}a{color:light-dark(#005bbb,#80baff)}a:focus-visible,input:focus-visible{outline:3px solid #e89c23;outline-offset:4px}header{padding:1rem 2rem;border-bottom:1px solid #8885}header a{font-weight:700;text-decoration:none}.layout{display:grid;grid-template-columns:260px minmax(0,800px);max-width:1120px;margin:auto}nav{padding:1.5rem}nav ol{padding-left:1.2rem}nav li{margin:.5rem 0}nav a[aria-current=page]{font-weight:700}main{padding:2rem;min-width:0}h1{font-size:2.3rem;line-height:1.15;letter-spacing:-.04em}h2{font-size:1.35rem;margin-top:2rem}h3{font-size:1.1rem}dt{font-weight:650;margin-top:1rem}dd{margin-left:0}li{margin:.6rem 0}table{border-collapse:collapse;width:100%;font-size:.93rem}td,th{text-align:left;vertical-align:top;padding:.7rem;border-bottom:1px solid #8885}caption{text-align:left;font-weight:700;margin:1rem 0}.pager{display:flex;justify-content:space-between;gap:2rem;border-top:1px solid #8885;margin-top:3rem;padding-top:1rem}.skip{position:absolute;left:-9999px}.skip:focus{left:1rem;background:Canvas;padding:1rem;z-index:1}.collection{padding:1rem;border:1px solid #8885;border-radius:12px;margin:1rem 0}.collection a{font-size:1.15rem;font-weight:600}footer{font-size:.8rem;color:light-dark(#54545a,#bbb);margin-top:2rem}@media(max-width:760px){.layout{display:block}nav{border-bottom:1px solid #8885}main{padding:1.25rem}h1{font-size:2rem}}"""

CSS += """a,a:visited{color:inherit;text-decoration:none}a:hover{background:light-dark(#ececee,#333336);border-radius:4px}a:focus-visible{outline:2px solid currentColor;outline-offset:4px}nav a{display:block;padding:3px 6px}nav a[aria-current=page]{background:light-dark(#ececee,#333336);border-radius:6px}.collection:hover{background:light-dark(#f3f3f5,#29292c)}figure{margin:1.75rem 0}figure img{display:block;width:100%;height:auto;border:1px solid #8885;border-radius:10px}figcaption{font-size:.85rem;color:light-dark(#54545a,#bbb);margin-top:.65rem}.screenshot-light{display:block}.screenshot-dark{display:none}@media(prefers-color-scheme:dark){.screenshot-light{display:none}.screenshot-dark{display:block}}"""

ILLUSTRATIONS = {
    "index": ("editor", "The VidiStudio editor: video and a labeled Thumbnails, Transcript, and Audio Description timeline above the transcript, with processing actions in the right inspector."),
    "welcome": ("editor", "The editor brings video, timed text, and processing tools into one window."),
    "first-project": ("projects", "Start in All Projects. Choose New Project to import a video, or Open Project Folder to reopen existing work."),
    "projects": ("projects", "All Projects in Grid View, with search, project tiles, layout controls, and the icon-size slider."),
    "editor": ("editor", "Video preview and the labeled Thumbnails, Transcript, and Audio Description timeline occupy the top; the section picker and Transcript are below. Hide or show the complete timeline from View. Project Inspector is on the right."),
    "analysis": ("editor", "Find Analyze Video and page-specific generation actions in the Project Inspector on the right."),
    "narration": ("narration", "Narration settings separate the speech engine from playback mode, followed by indication sounds and Apple voice controls."),
    "settings": ("narration", "Use the Settings sidebar to choose a section. Narration includes playback, sound, and voice controls."),
}

def illustration(slug):
    if slug not in ILLUSTRATIONS:
        return ""
    name, caption = ILLUSTRATIONS[slug]
    return '<figure>' + ''.join(
        f'<img class="screenshot-{theme}" src="images/{name}-{theme}.png" alt="{html.escape(caption)}" loading="lazy">'
        for theme in ["light", "dark"]
    ) + f'<figcaption>{html.escape(caption)}</figcaption></figure>'

def build(output, index=True):
    resources = output / "Contents/Resources"
    locale = resources / "en.lproj"
    locale.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "docs/help/images", locale / "images", dirs_exist_ok=True)
    for name, _ in ILLUSTRATIONS.values():
        for theme in ["light", "dark"]:
            if not (locale / "images" / f"{name}-{theme}.png").is_file():
                raise ValueError(f"Missing screenshot: {name}-{theme}")
    info = dict(CFBundleDevelopmentRegion="en", CFBundleIdentifier=BOOK_ID,
                CFBundleInfoDictionaryVersion="6.0", CFBundleName="VidiStudio Help",
                CFBundlePackageType="BNDL", CFBundleSignature="hbwr",
                CFBundleVersion="2", CFBundleShortVersionString="1.1",
                HPDBookAccessPath="index.html", HPDBookIndexPath="search.helpindex",
                HPDBookTitle="VidiStudio Help", HPDBookType="3")
    (output / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    (locale / "style.css").write_text(CSS)
    (locale / "InfoPlist.strings").write_text('"HPDBookTitle" = "VidiStudio Help";\n')
    pages = [("index", "VidiStudio Help")] + TOPICS
    for position, (slug, title) in enumerate(pages):
        if slug == "index":
            body = '<h1>VidiStudio Help</h1><p>Create accessible video, one clear description at a time. Start with the guided workflow or choose a topic below.</p>'
            body += ''.join(f'<section class="collection"><a href="{key}.html">{html.escape(label)}</a></section>' for key, label in TOPICS)
        elif slug == "keyboard":
            body = keyboard()
        else:
            body = (ROOT / "docs/help" / f"{slug}.html").read_text()
        if illustration(slug):
            before, separator, after = body.partition('</p>')
            body = before + separator + illustration(slug) + after
        toc = ''.join(f'<li><a href="{key}.html"' + (' aria-current="page"' if key == slug else '') + f'>{html.escape(label)}</a></li>' for key, label in TOPICS)
        pager = '<div class="pager">'
        if position:
            key, label = pages[position - 1]
            pager += f'<a rel="prev" href="{key}.html">Previous: {html.escape(label)}</a>'
        if position + 1 < len(pages):
            key, label = pages[position + 1]
            pager += f'<a rel="next" href="{key}.html">Next: {html.escape(label)}</a>'
        pager += '</div>'
        document = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(title)}</title><meta name="AppleTitle" content="{BOOK_ID}"><meta name="description" content="{html.escape(title)} — VidiStudio user guide"><link rel="stylesheet" href="style.css"></head><body><a class="skip" href="#topic">Skip to topic</a><header><a href="index.html">VidiStudio Help · Home</a></header><div class="layout"><nav aria-label="Table of contents"><h2>Contents</h2><ol>{toc}</ol><p>Use Help Viewer’s search field to find words across this guide.</p></nav><main id="topic"><a name="{slug}" id="{slug}"></a>{body}{pager}<footer>VidiStudio for macOS · Offline user guide</footer></main></div></body></html>'''
        (locale / f"{slug}.html").write_text(document)
    parsed = {path.name: Page(path.read_text()) for path in locale.glob("*.html")}
    for name, page in parsed.items():
        for link in page.links:
            if ":" in link:
                continue
            target, _, anchor = link.partition("#")
            target = target or name
            if target not in parsed or (anchor and anchor not in parsed[target].ids):
                raise ValueError(f"Broken link in {name}: {link}")
    if index:
        subprocess.run(["/usr/bin/hiutil", "-I", "lsm", "-C", "-a", "-s", "en", "-f", str(locale / "search.helpindex"), str(locale)], check=True)
    print(f"Validated {len(parsed)} Help pages and all internal links: {output}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "build/help/VidiStudio.help")
    parser.add_argument("--no-index", action="store_true")
    args = parser.parse_args()
    build(args.output, not args.no_index)
