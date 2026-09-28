#!/usr/bin/env python3
"""Decode an XMDY A4RJ printer byte stream into a readable command list.

Usage: xmdy_dump.py job.bin [--json]
SPDX-License-Identifier: MIT
"""
import json
import sys

KNOWN = {
    bytes.fromhex("10FFF102"): "job start (1)",
    bytes.fromhex("1040"): "job start (2)",
    bytes.fromhex("1F800110"): "job start (3)",
    bytes.fromhex("1F1151"): "marked paper: find mark",
    bytes.fromhex("1D0C"): "form feed to mark",
    bytes.fromhex("1F1150"): "marked paper: end",
    bytes.fromhex("10FFF145"): "vendor job end",
}


def decode(data):
    i, cmds = 0, []
    while i < len(data):
        if data[i:i + 3] == b"\x1dv0":
            wb = data[i + 4] | data[i + 5] << 8
            h = data[i + 6] | data[i + 7] << 8
            cmds.append({"cmd": "raster", "width_dots": wb * 8, "rows": h})
            i += 8 + wb * h
        elif data[i:i + 4] == b"\x10\xff\x10\x00":
            cmds.append({"cmd": "density", "value": data[i + 4]})
            i += 5
        elif data[i:i + 2] == b"\x1bJ":
            cmds.append({"cmd": "feed", "dots": data[i + 2]})
            i += 3
        else:
            for k, name in KNOWN.items():
                if data.startswith(k, i):
                    cmds.append({"cmd": name})
                    i += len(k)
                    break
            else:
                cmds.append({"cmd": "unknown", "byte": data[i]})
                i += 1
    return cmds


def summarize(cmds):
    """Collapse consecutive raster bands."""
    out = []
    for c in cmds:
        if c["cmd"] == "raster" and out and out[-1]["cmd"] == "raster" \
                and out[-1]["width_dots"] == c["width_dots"]:
            out[-1]["rows"] += c["rows"]
            out[-1]["bands"] += 1
        else:
            out.append(dict(c, bands=1) if c["cmd"] == "raster" else c)
    return out


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmds = summarize(decode(open(sys.argv[1], "rb").read()))
    if "--json" in sys.argv:
        print(json.dumps(cmds))
    else:
        for c in cmds:
            print(" ".join(f"{k}={v}" for k, v in c.items()))
