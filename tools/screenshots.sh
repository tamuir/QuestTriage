#!/bin/sh
# Crops the shots Quest Triage Shots took in game into docs/images, where the README and CurseForge page point.
# Reads each shot's name, time and screen rectangle from the tool's saved variables, finds the screenshot WoW wrote
# within 10 seconds of that time, crops it to the rectangle with a 16-pixel margin and saves it as PNG.
# Runs ImageMagick in Docker. Set WOW_FOREVER if your _forever_ folder is somewhere else.
set -e
FOREVER="${WOW_FOREVER:-C:/Program Files (x86)/World of Warcraft/_forever_}"
UNIX=$(cygpath -u "$FOREVER" 2>/dev/null || echo "$FOREVER")
SV=$(ls -t "$UNIX"/WTF/Account/*/SavedVariables/QuestTriageShots.lua 2>/dev/null | head -n 1)
if [ -z "$SV" ]; then
  echo "No QuestTriageShots.lua yet: take shots with /qtshots <name>, then /reload so WoW saves them."
  exit 1
fi
REPO=$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))
mkdir -p "$REPO/docs/images"

# The ImageMagick image is built once (a few minutes), then reused.
if ! docker image inspect questtriage-shots >/dev/null 2>&1; then
  echo "First run: building the ImageMagick image (one time only)..."
  docker build -q -t questtriage-shots -f "$REPO/tools/Dockerfile.shots" "$REPO/tools" >/dev/null
fi

MSYS_NO_PATHCONV=1 docker run --rm -e "SVREL=${SV#$UNIX/}" \
  -v "$(cygpath -m "$UNIX" 2>/dev/null || echo "$UNIX"):/wow:ro" -v "$REPO/docs/images:/out" \
  questtriage-shots sh -c '
    M=16; NEAR=10
    grep -oE "\"[A-Za-z0-9-]+\|[0-9]+\|-?[0-9]+\|-?[0-9]+\|-?[0-9]+\|-?[0-9]+\"" "/wow/$SVREL" | tr -d "\"" |
    while IFS="|" read -r name t l top r b; do
      shot=""
      for f in /wow/Screenshots/*; do
        [ -f "$f" ] || continue
        d=$(( $(stat -c %Y "$f") - t )); [ $d -lt 0 ] && d=$(( -d ))
        [ $d -le $NEAR ] && shot=$f
      done
      if [ -z "$shot" ]; then echo "  $name: no screenshot within ${NEAR}s of the shot"; continue; fi
      x=$(( l - M )); y=$(( top - M )); [ $x -lt 0 ] && x=0; [ $y -lt 0 ] && y=0
      magick "$shot" -crop $(( r - l + 2*M ))x$(( b - top + 2*M ))+$x+$y +repage "/out/$name.png"
      echo "  docs/images/$name.png  (from $(basename "$shot"))"
    done'
