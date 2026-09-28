#!/bin/sh
# Filter tests: render the test page with the PPD, run the filter with
# different options and check the decoded printer stream.
# Usage: tests/run.sh path/to/rastertoxmdy
# SPDX-License-Identifier: MIT
set -e
FILTER="${1:-build/rastertoxmdy}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PPD="$ROOT/ppd/xmdy-a4rj.ppd"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

python3 "$ROOT/tools/make_testpage.py" "$TMP/page.pdf"
cupsfilter -p "$PPD" -m application/vnd.cups-raster "$TMP/page.pdf" > "$TMP/page.ras" 2>/dev/null
(cat "$TMP/page.ras"; tail -c +5 "$TMP/page.ras") > "$TMP/two.ras"   # 2 pages

fail=0
check() {  # check <name> <raster> <options> <python assertion on list c>
  PPD="$PPD" "$FILTER" 1 test test 1 "$3" "$2" > "$TMP/out.bin" 2>/dev/null
  if python3 - "$TMP/out.bin" "$4" "$ROOT/tools" <<'PY'
import sys; sys.path.insert(0, sys.argv[3])
from xmdy_dump import decode, summarize
c = summarize(decode(open(sys.argv[1], "rb").read()))
names = [x["cmd"] for x in c]
raster = [x for x in c if x["cmd"] == "raster"]
assert "unknown" not in names, names
assert names[:4] == ["job start (1)", "job start (2)", "job start (3)", "density"], names
assert "vendor job end" not in names, names
ok = eval(sys.argv[2])
sys.exit(0 if ok else 1)
PY
  then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}

check "defaults: density 1, A4 width, 12 mm feed" "$TMP/page.ras" "" \
  'c[3]["value"] == 1 and raster[0]["width_dots"] == 1680 and raster[0]["rows"] % 24 == 0 and c[-1] == {"cmd": "feed", "dots": 96}'
check "density 3"          "$TMP/page.ras" "XmdyDensity=3"  'c[3]["value"] == 3'
check "density 0"          "$TMP/page.ras" "XmdyDensity=0"  'c[3]["value"] == 0'
check "two pages"          "$TMP/two.ras"  ""               'sum(r["bands"] for r in raster) == 198'
check "trim blank rows"    "$TMP/page.ras" "XmdyTrim=True"  'sum(r["bands"] for r in raster) < 99'
check "feeds"              "$TMP/page.ras" "XmdyFeedBefore=10 XmdyPageFeed=5 XmdyFeedAfter=0" \
  'c[4] == {"cmd": "feed", "dots": 80} and c[-1] == {"cmd": "feed", "dots": 40}'
check "marked paper"       "$TMP/page.ras" "XmdyMediaType=Marks" \
  'names[4] == "marked paper: find mark" and names[-2:] == ["form feed to mark", "marked paper: end"]'
check "tattoo: no feed"    "$TMP/page.ras" "XmdyMediaType=Tattoo" 'names[-1] == "raster"'
check "photo dithering"    "$TMP/page.ras" "XmdyDither=Diffusion" 'len(raster) == 1'
check "mirror + negative + offset" "$TMP/page.ras" "XmdyMirror=True XmdyNegative=True XmdyOffsetX=-5" 'len(raster) == 1'

# mirror must actually change the image
PPD="$PPD" "$FILTER" 1 t t 1 "" "$TMP/page.ras" > "$TMP/a.bin" 2>/dev/null
PPD="$PPD" "$FILTER" 1 t t 1 "XmdyMirror=True" "$TMP/page.ras" > "$TMP/b.bin" 2>/dev/null
if cmp -s "$TMP/a.bin" "$TMP/b.bin"; then echo "FAIL mirror changes output"; fail=1; else echo "ok   mirror changes output"; fi

exit $fail
