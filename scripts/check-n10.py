#!/usr/bin/env python3
"""Final static resource/contracts audit. No SDK typecheck or native visual claim."""
from pathlib import Path
import plistlib
import struct
import subprocess
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
for text in ['＋ 添加事项','pinIndicator','便签标题（可选）','NSAccessibilityCustomAction','便签菜单','（当前）','remove.setAccessibilityLabel("删除事项")']:
    assert text in card, text
assert 'guard !invalidated, canMutate()' in card
assert 'canMutate() != false' in read('Sources/DeskNodesApp/WindowChrome.swift')
assert 'if docking && !canImport()' in read('Sources/DeskNodesApp/SettingsWindow.swift')
app = read('Sources/DeskNodesApp/Application.swift')
assert 'applicationShouldTerminate(_ sender:' in app and '.terminateCancel' in app
assert 'toast?.dismiss()' in app
assert 'toastDismissal' in read('Sources/DeskNodesApp/DeletionToast.swift')
assert 'canMutate(), controls.indices' in read('Sources/DeskNodesApp/DockController.swift')
# Review all five authoritative local artifacts; dimensions are PNG pixels (2× HTML canvas).
for name, width, height in [('01-desktop-overview',2880,1800),('02-fullscreen-edge-reveal',2880,1800),
                          ('03-note-states-menu',2880,1800),('04-history-window',2080,1400),('05-settings-window',1520,1240)]:
    html = read(f'docs/spec/macos-native/prototypes/html/{name}.html')
    data = (root/f'docs/spec/macos-native/prototypes/png/{name}.png').read_bytes()
    assert struct.unpack_from('>II',data,16) == (width,height)
    assert '<html lang="zh-CN">' in html and '<script' not in html
# Full authoritative inputs and milestone plan are immutable for N10.
subprocess.run(['git','diff','--exit-code','5e6443371a6181f63fe30cd41d8c6f023ea8410b','--',
                'docs/spec','docs/macos-native-plan.md',*[f'docs/native-n{i}.md' for i in range(1,10)]],cwd=root,check=True)
print('N10 resource/source/spec preservation checks passed; no Mac acceptance implied.')
