#!/usr/bin/env python3
"""Static consistency only. Does not parse/typecheck Swift or execute Swift tests."""
import pathlib
import plistlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
def read(path):
    return (ROOT / path).read_text()

def check(label, condition):
    if not condition:
        raise AssertionError(label)
    print('PASS:', label)

spec = read('docs/spec/macos-native/requirements.md')
tokens = read('Sources/DeskNodesCore/DesignTokens.swift')
pairs = re.findall(r'\|\s*(宣纸|柠黄|杏|樱|薰衣草|雾蓝|薄荷|石墨)\s*\|\s*#([A-F0-9]{6})\s*\|\s*#([A-F0-9]{6})', spec)
check('eight authoritative palette rows', len(pairs) == 8)
# 石墨 was retired by docs/design/desknodes-color-and-topmost.md; the other seven stay exact.
check('石墨 is the retired last row', pairs[-1][0] == '石墨' and 'case paper, lemon, apricot, cherry, lavender, mist, mint\n' in tokens)
pairs = pairs[:7]
case_names = ['paper', 'lemon', 'apricot', 'cherry', 'lavender', 'mist', 'mint']
sections = [tokens.split('public var ' + field + ': String {', 1)[1].split('\n    }', 1)[0]
            for field in ('name', 'lightHex', 'darkHex')]
for case_name, (name, light, dark) in zip(case_names, pairs):
    check(f'{name}: exact light/dark tokens', all(
        f'case .{case_name}: return "{value}"' in section
        for value, section in zip((name, light, dark), sections)))
check('exactly fourteen palette hex literals', len(re.findall(r'return "[A-F0-9]{6}"', tokens)) == 14)
proto = read('docs/spec/macos-native/prototypes/html/03-note-states-menu.html')
for hex_value in ('1F1F1F', 'EDEBE6', '5F5A52', 'B3ADA2', '6F6A61', 'A39D92'):
    check(f'prototype 03 ink {hex_value}', f'#{hex_value}' in proto and f'"{hex_value}"' in tokens)
# Card metrics follow docs/design/desknodes-desktop-redesign-prompt.md §9, which supersedes N1's.
for key, value in [('width', 288), ('padding', 18), ('cornerRadius', 13), ('titleSize', 16),
                   ('itemSize', 14), ('rowHeight', 32), ('collapsedHeight', 32)]:
    check(f'metric {key}', f'let {key} = {value}.0' in tokens)

with (ROOT / 'Resources/Info.plist').open('rb') as stream:
    plist = plistlib.load(stream)
check('plist accessory / minimum OS / executable / type', plist['LSUIElement'] is True and
      plist['LSMinimumSystemVersion'] == '14.0' and plist['CFBundleExecutable'] == 'DeskNodes' and
      plist['CFBundlePackageType'] == 'APPL')
check('no sandbox entitlement files', not list(ROOT.glob('**/*.entitlements')))
manifest = read('Package.swift')
check('manifest tools version and macOS 14 declaration (text only)',
      manifest.startswith('// swift-tools-version: 5.9\n') and '.macOS(.v14)' in manifest)
check('manifest Mac app conditional and no third-party package declarations',
      '#if os(macOS)' in manifest and '.package(' not in manifest)
for target in ('DeskNodesCore', 'DeskNodesApp'):
    check(f'{target} source layout', bool(list((ROOT / 'Sources' / target).glob('*.swift'))))
    check(f'{target} test layout', bool(list((ROOT / 'Tests' / (target + 'Tests')).glob('*.swift'))))
core = '\n'.join(p.read_text() for p in (ROOT / 'Sources/DeskNodesCore').glob('*.swift'))
check('portable core has no platform imports', not re.search(r'import (AppKit|SwiftUI|QuartzCore|Carbon|SQLite)', core))
check('source/test separation', not list((ROOT / 'Sources').glob('**/*Tests.swift')))
subprocess.run(['bash', '-n', str(ROOT / 'scripts/build-macos.sh')], check=True)
print('PASS: bash -n scripts/build-macos.sh')
print('Static checks complete. Swift manifest evaluation, compilation, tests, signing and AppKit runtime NOT checked.')
