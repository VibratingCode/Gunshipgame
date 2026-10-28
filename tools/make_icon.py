"""Render the game icon (thermal reticle) to icon.ico without dependencies."""
import struct, sys, zlib, math

S = 256
px = bytearray(S * S * 4)

def put(x, y, v, a=255):
    if 0 <= x < S and 0 <= y < S:
        i = (y * S + x) * 4
        px[i:i + 4] = bytes((v, v, v, a))

for y in range(S):
    for x in range(S):
        # rounded dark tile with a warm blob (a hot target) in the middle
        dx, dy = x - S / 2, y - S / 2
        cx, cy = max(abs(dx) - 96, 0), max(abs(dy) - 96, 0)
        if math.hypot(cx, cy) > 32:
            continue
        r = math.hypot(dx, dy)
        v = 18 + int(150 * math.exp(-(r / 30) ** 2))
        put(x, y, v)

def rect(x0, y0, x1, y1, v=235):
    for y in range(y0, y1):
        for x in range(x0, x1):
            put(x, y, v)

w = 10
for sx in (-1, 1):
    for sy in (-1, 1):
        cx, cy = 128 + sx * 88, 128 + sy * 88
        rect(min(cx, cx - sx * 44), min(cy, cy - sy * w) if sy > 0 else cy, max(cx, cx - sx * 44), (cy + w) if sy < 0 else cy + 1)
        rect(min(cx, cx - sx * w) if sx > 0 else cx, min(cy, cy - sy * 44), (cx + w) if sx < 0 else cx + 1, max(cy, cy - sy * 44))
rect(123, 52, 133, 106); rect(123, 150, 133, 204)
rect(52, 123, 106, 133); rect(150, 123, 204, 133)
rect(122, 122, 134, 134, 255)

raw = b"".join(b"\x00" + bytes(px[y * S * 4:(y + 1) * S * 4]) for y in range(S))
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
ico = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", 0, 0, 0, 0, 1, 32, len(png), 22) + png
open(sys.argv[1] if len(sys.argv) > 1 else "icon.ico", "wb").write(ico)
