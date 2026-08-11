#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Deterministic mechanism test. Runs the SHIPPED binary (the one inside
# KuromiCleans.app) against a fully controlled folder and asserts its own
# diagnostic output: plan, moved files, collision renames, skip reasons,
# and post-state health codes. No unit tests, no mocks, no test frameworks.

BIN="dist/KuromiCleans.app/Contents/MacOS/KuromiCleans"
if [ ! -x "$BIN" ]; then
    echo "App not built yet; building now."
    bash Scripts/build_app.sh
fi

STAGE=".build/mechanism-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Projects" "$STAGE/Images"

put() { printf 'x' > "$STAGE/$1"; }
put "photo.jpg"
put "DOCS.PDF"
put "clip.mp4"
put "song.mp3"
put "bundle.zip"
put "script.py"
put "blob.xyz"
put "README"
put "vacation photo 2026.jpg"
put "café menu.pdf"
put "real.txt"
put ".DS_Store"
put ".hidden"
put "Images/photo.jpg"
printf 'x' > "$STAGE/Projects/inner.txt"
ln -s real.txt "$STAGE/link.txt"

echo "== Dry-run plan (must not move anything) =="
"$BIN" --dry-run --dump --path "$STAGE" > .build/mechanism-dry.json
if [ -f "$STAGE/photo.jpg" ]; then
    echo "PASS  dry run moved nothing"
else
    echo "FAIL  dry run moved files"
    exit 1
fi

echo "== Real sort (shipped binary, no alert) =="
"$BIN" --dump --no-alert --path "$STAGE" > .build/mechanism-real.json
if [ -f "$STAGE/Images/photo.jpg" ]; then
    echo "PASS  pre-existing folder content untouched"
else
    echo "FAIL  pre-existing folder content moved"
    exit 1
fi

echo "== Post-state health check =="
"$BIN" --check --path "$STAGE" > .build/mechanism-check.txt
cat .build/mechanism-check.txt

echo "== Assertions on diagnostic output =="
python3 - <<'PY'
import json, os, sys

STAGE = ".build/mechanism-stage"
dry = json.load(open(".build/mechanism-dry.json"))
real = json.load(open(".build/mechanism-real.json"))
check_txt = open(".build/mechanism-check.txt").read()

EXPECTED_CATS = {"Images": 2, "Documents": 3, "Video": 1, "Audio": 1,
                 "Archives": 1, "Code": 1, "Other": 2}

total = 0
fails = []
def ok(name, cond, detail=""):
    global total
    total += 1
    if cond:
        print("PASS  " + name)
    else:
        print("FAIL  " + name + "  " + detail)
        fails.append(name)

ok("dry summary moved == 11", dry["summary"]["moved"] == 11, str(dry["summary"]))
ok("dry summary skipped == 5", dry["summary"]["skipped"] == 5, str(dry["summary"]))
ok("dry per-category counts", dry["byCategory"] == EXPECTED_CATS, str(dry["byCategory"]))
ok("dry collision rename to photo 2.jpg",
   any(m["renamed"] and m["to"].endswith("Images/photo 2.jpg") for m in dry["moved"]))
ok("dry skip reason dotfile",
   any(s["reason"] == "dotfile" and s["path"].endswith(".DS_Store") for s in dry["skipped"]))
ok("dry skip reason symlink",
   any(s["reason"] == "symlink" for s in dry["skipped"]))
ok("dry skip reason directory",
   any(s["reason"] == "directory" and s["path"].endswith("Projects") for s in dry["skipped"]))
ok("real summary moved == 11", real["summary"]["moved"] == 11, str(real["summary"]))
ok("real errors == 0", real["summary"]["errors"] == 0, str(real["summary"]["errors"]))
ok("real bytesMoved > 0", real["summary"]["bytesMoved"] > 0, str(real["summary"]["bytesMoved"]))
ok("real per-category counts match dry plan", real["byCategory"] == dry["byCategory"], str(real["byCategory"]))
ok("health root_clean", "HEALTH OK root_clean" in check_txt, check_txt)
ok("health category_match", "HEALTH OK category_match" in check_txt, check_txt)

print("Result: %d passed, %d failed" % (total - len(fails), len(fails)))
sys.exit(1 if fails else 0)
PY
