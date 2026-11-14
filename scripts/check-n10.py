#!/usr/bin/env python3
"""Final static resource/contracts audit. No SDK typecheck or native visual claim."""
from pathlib import Path
import plistlib
import re
import struct
from urllib.parse import unquote, urlsplit
import zlib

root = Path(__file__).resolve().parents[1]
def read(path): return (root / path).read_text()

def png(data, expected):
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    offset, packed, kinds = 8, b'', []
    while offset < len(data):
        size = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset+4:offset+8]
        payload = data[offset+8:offset+8+size]
        assert zlib.crc32(kind+payload) == struct.unpack_from('>I', data, offset+8+size)[0]
        if kind == b'IHDR':
            assert struct.unpack('>IIBBBBB', payload) == (expected, expected, 8, 6, 0, 0, 0)
        if kind == b'IDAT': packed += payload
        kinds.append(kind)
        offset += size+12
    assert offset == len(data) and kinds[0] == b'IHDR' and kinds[-1] == b'IEND'
    pixels = zlib.decompress(packed)
    assert len(pixels) == expected*(1+expected*4)
    assert all(pixels[row*(1+expected*4)] == 0 for row in range(expected))
    assert pixels[4] == 0  # outer corner remains transparent
    assert any(pixels[4::4])

plist = plistlib.loads((root/'Resources/Info.plist').read_bytes())
assert plist['CFBundleIconFile'] == 'DeskNodes.icns'
assert plist['LSUIElement'] and plist['LSMinimumSystemVersion'] == '14.0'
icon = (root/'Resources/DeskNodes.icns').read_bytes()
assert icon[:4] == b'icns' and struct.unpack_from('>I', icon, 4)[0] == len(icon)
slots = {b'icp4':16,b'icp5':32,b'icp6':64,b'ic07':128,b'ic08':256,b'ic09':512,b'ic10':1024,
         b'ic11':32,b'ic12':64,b'ic13':256,b'ic14':512}
offset, found = 8, set()
while offset < len(icon):
    kind, size = icon[offset:offset+4], struct.unpack_from('>I', icon, offset+4)[0]
    assert kind in slots and kind not in found and size > 8
    png(icon[offset+8:offset+size], slots[kind])
    offset += size; found.add(kind)
assert offset == len(icon) and found == set(slots)
png((root/'Resources/DeskNodes-icon.png').read_bytes(),512)
assert 'cp Resources/DeskNodes.icns "$app_path/Contents/Resources/DeskNodes.icns"' in read('scripts/build-macos.sh')
card = read('Sources/DeskNodesApp/NotePanel.swift')
for text in ['＋ 添加事项','pinIndicator','便签标题（可选）','NSAccessibilityCustomAction','便签菜单','（当前）','RowActionButton(symbol: "xmark", label: "删除事项"']:
    assert text in card, text
assert 'guard !invalidated, canMutate()' in card
assert 'canMutate() != false' in read('Sources/DeskNodesApp/WindowChrome.swift')
app = read('Sources/DeskNodesApp/Application.swift')
assert 'applicationShouldTerminate(_ sender:' in app and '.terminateCancel' in app
assert 'toast?.dismiss()' in app
assert 'toastDismissal' in read('Sources/DeskNodesApp/DeletionToast.swift')
assert 'guard canMutate() else { return }' in read('Sources/DeskNodesApp/DockController.swift')
# The maintained documentation replaces the retired milestone/spec snapshots.
for name in ['README.md', 'REQUIREMENTS.md', 'TECHNICAL_DESIGN.md', 'UI_SPEC.md',
             'ACCEPTANCE.md', 'native-build.md']:
    document = read(f'docs/{name}')
    assert document.startswith('# '), name
prototype = read('docs/UI_PROTOTYPE.html')
assert '<html lang="zh-CN">' in prototype
for element in ['stage', 'notes', 'menu', 'selbar', 'win', 'toast']:
    assert f'id="{element}"' in prototype, element
assert '<script src=' not in prototype
assert 'data-ver=' not in prototype  # one current demo, no competing old/new specification
# Relative links and explicit section anchors must survive document consolidation.
documents = [root / 'README.md', *sorted((root / 'docs').rglob('*.md')),
             *sorted((root / 'docs').rglob('*.html'))]
for document in documents:
    source = document.read_text()
    links = (re.findall(r'\[[^\]]*\]\(([^)]+)\)', source) if document.suffix == '.md'
             else re.findall(r'href=[\"\x27]([^\"\x27]+)', source))
    for link in links:
        url = urlsplit(link)
        if url.scheme or url.netloc:
            continue
        target = (document.parent / unquote(url.path)).resolve() if url.path else document
        assert target.exists(), f'{document.relative_to(root)}: missing {link}'
        if url.fragment:
            ids = re.findall(r'\bid=[\"\x27]([^\"\x27]+)', target.read_text())
            assert unquote(url.fragment) in ids, f'{document.relative_to(root)}: missing anchor {link}'
print('N10 resource/source/current documentation checks passed; no Mac acceptance implied.')
