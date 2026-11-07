#!/usr/bin/env python3
"""Deterministic original DeskNodes icon. Python standard library only.
PNG-backed ICNS representations cover 16–1024 pixels, including Retina slots.
Run --check to compare committed bytes without modifying resources.
"""
from pathlib import Path
import math
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]

def rounded(x, y, left, top, right, bottom, radius):
    dx = max(left + radius - x, 0, x - right + radius)
    dy = max(top + radius - y, 0, y - bottom + radius)
    return left <= x <= right and top <= y <= bottom and dx * dx + dy * dy <= radius * radius

def segment(x, y, ax, ay, bx, by, radius):
    t = max(0, min(1, ((x-ax)*(bx-ax)+(y-ay)*(by-ay))/((bx-ax)**2+(by-ay)**2)))
    return (x-ax-t*(bx-ax))**2+(y-ay-t*(by-ay))**2 <= radius**2

def pixel(x, y):
    # Calm sage tile, offset blue sheet, paper checklist. Transparent outer margin.
    color = (0, 0, 0, 0)
    if rounded(x, y, .07, .07, .93, .93, .19):
        color = (127, 143, 134, 255)
    if rounded(x, y, .26, .20, .80, .82, .07):
        color = (227, 236, 245, 255)
    if rounded(x, y, .19, .16, .73, .78, .07):
        color = (246, 241, 231, 255)
    ink = (69, 84, 74, 255)
    if rounded(x, y, .27, .255, .61, .28, .012):
        color = ink
    for row in range(3):
        cy = .385 + row * .125
        distance = math.hypot(x-.295, y-cy)
        if distance < .034 and (row == 0 or distance > .024):
            color = ink
        if row == 0 and (segment(x,y,.278,cy,.291,cy+.012,.005) or segment(x,y,.291,cy+.012,.314,cy-.014,.005)):
            color = (246, 241, 231, 255)
        if rounded(x, y, .365, cy-.011, .63 if row != 2 else .55, cy+.011, .011):
            color = (111, 106, 97, 255) if row == 0 else ink
    return color

def png(size):
    # Four samples per pixel; average premultiplied channels to keep clean alpha edges.
    raw = bytearray()
    for row in range(size):
        raw.append(0)
        for col in range(size):
            samples = [pixel((col+dx)/size, (row+dy)/size) for dx,dy in ((.25,.25),(.75,.25),(.25,.75),(.75,.75))]
            alpha = sum(c[3] for c in samples)
            raw.extend([round(sum(c[k]*c[3] for c in samples)/alpha) if alpha else 0 for k in range(3)])
            raw.append(round(alpha/4))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind+data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',size,size,8,6,0,0,0)) + chunk(b'IDAT',zlib.compress(raw,9)) + chunk(b'IEND',b'')

def artifacts():
    sizes = {size: png(size) for size in (16,32,64,128,256,512,1024)}
    slots = [(b'icp4',16),(b'icp5',32),(b'icp6',64),(b'ic07',128),(b'ic08',256),(b'ic09',512),(b'ic10',1024),
             (b'ic11',32),(b'ic12',64),(b'ic13',256),(b'ic14',512)]
    body = b''.join(kind + struct.pack('>I',len(sizes[size])+8) + sizes[size] for kind,size in slots)
    return {'DeskNodes.icns': b'icns'+struct.pack('>I',len(body)+8)+body, 'DeskNodes-icon.png': sizes[512]}

if __name__ == '__main__':
    if sys.argv[1:] not in ([], ['--check']):
        raise SystemExit('usage: generate-icon.py [--check]')
    for name, data in artifacts().items():
        path = ROOT / 'Resources' / name
        if '--check' in sys.argv:
            if path.read_bytes() != data:
                raise SystemExit(f'Icon differs: {path}')
        else:
            path.write_bytes(data)
    print('Icon resources reproducible (standard library; not macOS IconServices acceptance).')
