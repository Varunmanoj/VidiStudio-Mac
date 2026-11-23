#!/usr/bin/env python3
"""Check icon declarations for app-owned desktop menu actions."""
import argparse
import re
from pathlib import Path
from xml.etree import ElementTree

LITERALS = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"""[\s\S]*?"""|@?"(?:\\.|[^"\\\n])*"')
MENU_SCOPE = re.compile(
    r'(?<!\w)(?:contextMenu|commands|CommandMenu|CommandGroup|Menu|\w*ContextMenu|projectMenu\b|'
    r'fileViewMenu|choiceMenu)\s*(?:\([^;\n]*\)(?:\s*->\s*some View)?|:\s*some View)?\s*\{'
)
SWIFT_ACTION = re.compile(r'(?<![\w.])(?:Button|Link|Toggle|Menu)\s*\(')
WINDOWS_ROW = r'(?:ToggleMenuFlyoutItem|MenuFlyoutItem|MenuFlyoutSubItem)'
CS_ACTION = re.compile(r'\bnew\s+' + WINDOWS_ROW + r'\s*(?:\(\s*\))?\s*\{')


def masked(source):
    return LITERALS.sub(lambda match: ''.join('\n' if char == '\n' else ' ' for char in match[0]), source)


def end_of_block(code, start, pair):
    start_char, end_char = pair
    depth = 1
    for match in re.finditer(re.escape(start_char) + '|' + re.escape(end_char), code[start + 1:]):
        depth += 1 if match[0] == start_char else -1
        if depth == 0:
            return start + 1 + match.start()
    raise ValueError('Unbalanced menu declaration')


def mac_missing_icons(source, symbols):
    code = masked(source)
    scopes = [(match.start(), end_of_block(code, match.end() - 1, '{}')) for match in MENU_SCOPE.finditer(code)]
    for action in SWIFT_ACTION.finditer(code):
        if not any(start <= action.start() < end for start, end in scopes):
            continue
        start = action.end() - 1
        end = end_of_block(code, start, '()')
        args = source[start + 1:end].strip()
        if re.search(r'\b(?:systemImage|image):\s*(?!"")\S', args):
            continue
        label = re.match(r'"([^"\n]+)"\s*(?:,|$)', args)
        if label and label[1] in symbols:
            continue
        # Check a trailing custom label, including saved-result status artwork.
        trailing = re.match(r'\s*\{', code[end + 1:])
        if trailing:
            body_start = end + trailing.end()
            body = source[body_start + 1:end_of_block(code, body_start, '{}')].strip()
            if re.match(r'(?:Label|Image)\s*\(', body):
                continue
            if body == 'option' and 'let option = SavedResultOption(' in source[max(0, start - 700):start]:
                continue
        yield source.count('\n', 0, action.start()) + 1, args.splitlines()[0][:100]


    for action in re.finditer(r'(?<![\w.])Button\s*\{', code):
        if not any(start <= action.start() < end for start, end in scopes):
            continue
        end = end_of_block(code, action.end() - 1, '{}')
        label = re.match(r'\s*label:\s*\{', code[end + 1:])
        if label:
            body_start = end + label.end()
            body = code[body_start + 1:end_of_block(code, body_start, '{}')].strip()
            if re.match(r'(?:Label|Image)\s*\(', body):
                continue
        yield source.count('\n', 0, action.start()) + 1, 'Button label needs an icon'

    # Explicit AppKit items are built before insertion. Check their image at
    # that construction site, where it can be traced to the same item.
    for action in re.finditer(r'\blet\s+(\w+)\s*=\s*NSMenuItem\s*\(', code):
        name = action[1]
        end = end_of_block(code, action.end() - 1, '()')
        added = code.find(f'.addItem({name})', end)
        if added == -1:
            continue
        if re.search(r'\b' + re.escape(name) + r'\.image\s*=\s*NSImage\(', code[end:added]):
            continue
        yield source.count('\n', 0, action.start()) + 1, f'{name} NSMenuItem'


def windows_missing_icons(source):
    code = masked(source)
    for action in CS_ACTION.finditer(code):
        end = end_of_block(code, action.end() - 1, '{}')
        args = source[action.end():end]
        if re.search(r'\bIcon\s*=\s*(?:(?:\w+\.)*MenuIcons\.Create|DesktopCommandIcon|SavedResultOptions\.MenuIcon)\(', args):
            continue
        if re.search(r'\bIcon\s*=\s*new\s+(?:SymbolIcon|ImageIcon|BitmapIcon|PathIcon)\b', args):
            continue
        font = re.search(r'\bIcon\s*=\s*new\s+FontIcon\s*\{([^}]+)\}', args)
        if font and re.search(r'\bGlyph\s*=\s*(?!"\s*"|null\b)\S', font[1]):
            continue
        prefix = source[:action.start()].splitlines()[-2:]
        if any('Menu heading:' in line for line in prefix) and re.search(r'\bIsEnabled\s*=\s*false\b', args):
            continue
        yield source.count('\n', 0, action.start()) + 1, args.strip().splitlines()[0][:100]


def xaml_missing_icons(source):
    root = ElementTree.fromstring(source)
    for item in root.iter():
        name = item.tag.rsplit('}', 1)[-1]
        if not re.fullmatch(WINDOWS_ROW, name):
            continue
        icons = [icon for child in item if child.tag.endswith('.Icon') for icon in child]
        if item.get('Icon') or any(
            not icon.tag.endswith('}FontIcon') and icon.tag != 'FontIcon' or bool(icon.get('Glyph', '').strip())
            for icon in icons
        ):
            continue
        yield item.get('Text') or item.get('Tag') or name


def check(app_root):
    app_root = Path(app_root)
    failures = []
    if (app_root / 'VidiStudio').is_dir():
        source_root = app_root / 'VidiStudio'
        source = (source_root / 'NativeMenuIcons.swift').read_text(encoding='utf-8')
        symbols = set(re.findall(r'^\s*"([^"\n]+)"\s*:\s*"[^"\n]+"', source, re.M))
        symbols.update(
            title for case in re.findall(r'case\s+([^:\n]+):\s*return\s+"[^"\n]+"', source)
            for title in re.findall(r'"([^"\n]+)"', case)
        )
        for path in sorted(source_root.rglob('*.swift')):
            failures.extend(f'{path.relative_to(app_root)}:{line} {action}'
                            for line, action in mac_missing_icons(path.read_text(encoding='utf-8'), symbols))
    elif (app_root / 'Vidi Studio Windows').is_dir():
        source_root = app_root / 'Vidi Studio Windows'
        for path in sorted(source_root.rglob('*')):
            if path.suffix not in ('.cs', '.xaml') or {'bin', 'obj'}.intersection(path.parts):
                continue
            source = path.read_text(encoding='utf-8-sig')
            if path.suffix == '.cs' and not path.name.endswith(('SmokeTest.cs', 'Smoke.cs', 'Accessibility.cs')):
                failures.extend(f'{path.relative_to(app_root)}:{line} {action}'
                                for line, action in windows_missing_icons(source))
            if path.suffix == '.xaml':
                failures.extend(f'{path.relative_to(app_root)} {action}' for action in xaml_missing_icons(source))
    else:
        raise ValueError(f"No desktop source tree found in {app_root}")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path, nargs='?', default=Path(__file__).resolve().parents[1])
    failures = check(parser.parse_args().root)
    if failures:
        parser.exit(1, 'Menu actions missing icon declarations:\n' + '\n'.join(failures) + '\n')
    print('PASS: desktop menu and context menu icon declarations.')


if __name__ == '__main__':
    main()
