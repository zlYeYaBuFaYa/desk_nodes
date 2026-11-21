"""Generate the application ICO offline using only Python 3's standard library."""
from pathlib import Path
import math
import struct
import zlib

SIZES = (16, 20, 24, 32, 48, 64, 256)


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


def distance(x, y):
    # Rounded paper rectangle in a 32-unit design space.
    return math.hypot(max(abs(x - 16) - 8, 0), max(abs(y - 16) - 9, 0)) - 3


def segment_distance(x, y, ax, ay, bx, by):
    t = max(0, min(1, ((x-ax)*(bx-ax)+(y-ay)*(by-ay))/((bx-ax)**2+(by-ay)**2)))
    return math.hypot(x-ax-t*(bx-ax), y-ay-t*(by-ay))


def rgba(size):
    rows = bytearray()
    for py in range(size):
        for px in range(size):
            samples = []
            for sy in range(4):
                for sx in range(4):
                    x, y = (px+(sx+.5)/4)*32/size, (py+(sy+.5)/4)*32/size
                    d = distance(x, y)
                    color = (0, 0, 0, 0)
                    if d <= 0:
                        color = (185, 175, 154, 255) if d > -.8 else (246, 241, 231, 255)
                        if min(segment_distance(x,y,10,16,14,20), segment_distance(x,y,14,20,22,11)) < 1.05:
                            color = (104, 119, 96, 255)
                    samples.append(color)
            alpha = sum(c[3] for c in samples)
            rows.extend([round(sum(c[i]*c[3] for c in samples)/alpha) if alpha else 0 for i in range(3)])
            rows.append(round(alpha/16))
    return rows


def png(size):
    pixels = rgba(size)
    stride = size * 4
    rows = b''.join(b'\0' + pixels[y:y + stride] for y in range(0, len(pixels), stride))
    header = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')


def dib(size):
    pixels = rgba(size)
    mask_stride = ((size + 31) // 32) * 4
    color = bytearray()
    mask = bytearray()
    for y in reversed(range(size)):
        row_mask = bytearray(mask_stride)
        for x in range(size):
            r, g, b, a = pixels[(y * size + x) * 4:(y * size + x + 1) * 4]
            color.extend((b, g, r, a))
            if a == 0:
                row_mask[x // 8] |= 0x80 >> (x % 8)
        mask.extend(row_mask)
    header = struct.pack('<IiiHHIIiiII', 40, size, size * 2, 1, 32, 0, len(color), 0, 0, 0, 0)
    return header + color + mask


def main():
    images = [png(size) if size == 256 else dib(size) for size in SIZES]
    offset = 6 + 16*len(SIZES)
    entries = bytearray()
    for size, data in zip(SIZES, images):
        entries.extend(struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(data), offset))
        offset += len(data)
    target = Path(__file__).resolve().parents[1] / 'src/DeskNodes.App/Assets/DeskNodes.ico'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(struct.pack('<HHH', 0, 1, len(SIZES)) + entries + b''.join(images))
    print(f'{target}: {target.stat().st_size} bytes')


if __name__ == '__main__':
    main()
