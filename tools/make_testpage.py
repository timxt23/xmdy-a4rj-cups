#!/usr/bin/env python3
"""Generate an A4 test page PDF (frame, 100 mm bar, 170 mm ruler, text). No dependencies.

Usage: make_testpage.py [output.pdf]
SPDX-License-Identifier: MIT
"""
import sys

mm = lambda v: v * 72 / 25.4
W, H = 595, 842
c = []
c.append("0 g 2 w")
c.append(f"{mm(5):.2f} {mm(5):.2f} {W-2*mm(5):.2f} {H-2*mm(5):.2f} re S")          # 5 mm frame
c.append(f"{mm(20):.2f} {H-mm(40):.2f} {mm(100):.2f} {mm(8):.2f} re f")            # 100 mm bar
for i in range(0, 171):                                                             # 170 mm ruler
    L = mm(8) if i % 10 == 0 else (mm(5) if i % 5 == 0 else mm(2.5))
    x = mm(20) + mm(i)
    c.append(f"0.6 w {x:.2f} {H-mm(45):.2f} m {x:.2f} {H-mm(45)-L:.2f} l S")
def text(x, y, s, size):
    c.append(f"BT /F1 {size} Tf {x:.2f} {y:.2f} Td ({s}) Tj ET")
text(mm(20), H-mm(25), "XMDY A4RJ - CUPS test page", 22)
text(mm(20), H-mm(65), "Black bar above = 100 mm. Ruler = 170 mm, ticks 1 mm.", 12)
text(mm(20), H-mm(72), "Frame = 5 mm from page edges.", 12)
for k in range(1, 6):
    text(mm(20), H-mm(90+k*12), f"Line {k}: The quick brown fox jumps over the lazy dog 0123456789", 11)
text(mm(20), mm(15), "Bottom of page (5 mm frame below)", 12)
stream = "\n".join(c).encode()
objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {W} {H}] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>".encode(),
        b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
out = bytearray(b"%PDF-1.4\n"); offs = []
for i, o in enumerate(objs, 1):
    offs.append(len(out)); out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
x = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs)+1) + b"".join(b"%010d 00000 n \n" % o for o in offs)
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs)+1, x)
open(sys.argv[1] if len(sys.argv) > 1 else "testpage_a4.pdf", "wb").write(out)
