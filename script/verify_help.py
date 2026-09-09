#!/usr/bin/env python3
"""Verify the actual app bundle's offline Help Book, not just its source files."""
import argparse
from pathlib import Path
import plistlib

from build_help import BOOK_ID, TOPICS, ILLUSTRATIONS, Page


def verify(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info.get("CFBundleHelpBookFolder") == "VidiStudio.help", "Missing app Help folder registration"
    assert info.get("CFBundleHelpBookName") == BOOK_ID, "Missing app Help book registration"
    book = app / "Contents/Resources" / info["CFBundleHelpBookFolder"]
    metadata = plistlib.loads((book / "Contents/Info.plist").read_bytes())
    assert metadata["CFBundleIdentifier"] == BOOK_ID
    assert metadata["HPDBookType"] == "3", "Book must be offline/local"
    locale = book / "Contents/Resources/en.lproj"
    assert metadata["HPDBookAccessPath"] == "index.html"
    assert (locale / metadata["HPDBookIndexPath"]).stat().st_size > 0, "Empty search index"
    assert (locale / "style.css").stat().st_size > 0
    for name, _ in ILLUSTRATIONS.values():
        for theme in ["light", "dark"]:
            assert (locale / "images" / f"{name}-{theme}.png").stat().st_size > 0
    pages = {}
    for slug in ["index"] + [key for key, _ in TOPICS]:
        name = f"{slug}.html"
        source = (locale / name).read_text()
        assert f'content="{BOOK_ID}"' in source, f"Missing AppleTitle in {name}"
        assert '<html lang="en">' in source and '<main id="topic">' in source
        assert 'aria-label="Table of contents"' in source
        pages[name] = Page(source)
        assert slug in pages[name].ids, f"Missing native Help anchor in {name}"
    for name, page in pages.items():
        for link in page.links:
            if ":" in link:
                continue
            target, _, anchor = link.partition("#")
            target = target or name
            assert target in pages, f"Missing topic {link} from {name}"
            assert not anchor or anchor in pages[target].ids, f"Missing anchor {link} from {name}"
    print(f"PASS: packaged registration, {len(pages)} pages, topic anchors, links, style, and nonempty search index")
    print("Native Help Viewer rendering and search still require a runtime check.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    verify(parser.parse_args().app)
