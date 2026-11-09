#!/bin/sh
# Prints the CurseForge project description, made from README.md so the two never drift apart:
# drops the logo (CurseForge shows its own) and the Development section, and turns relative links and image paths
# into full addresses on GitHub, which is where CurseForge loads the images from.
#   sh tools/curseforge-description.sh            print it
#   sh tools/curseforge-description.sh --update   write it to CURSEFORGE-DESCRIPTION.md, ready to paste
set -e
cd "$(dirname "$0")/.."
RAW="https://raw.githubusercontent.com/tamuir/QuestTriage/main"
REPO="https://github.com/tamuir/QuestTriage/blob/main"

desc=$(tr -d '\r' < README.md | awk '
  NR == 1 && /^<p align="center">/ { skip_blank = 1; next }
  skip_blank && /^$/ { skip_blank = 0; next }
  /^# Quest Triage$/ { skip_blank = 1; next } # CurseForge shows the project name itself
  /^## Development/ { dev = 1; next }
  dev && /^## / { dev = 0 }
  !dev' |
  sed -e "s#](docs/images/#]($RAW/docs/images/#g" -e "s#](media/#]($RAW/media/#g" -e "s#](LICENSE.md)#]($REPO/LICENSE.md)#g")

if [ "$1" = "--update" ]; then
  printf '%s\n' "$desc" > CURSEFORGE-DESCRIPTION.md
  echo "CURSEFORGE-DESCRIPTION.md updated from README.md"
else
  printf '%s\n' "$desc"
fi
