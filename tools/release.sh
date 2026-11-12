#!/usr/bin/env bash
# Packages Quest Triage as QuestTriage-v<version>.zip and publishes it to GitHub Releases and CurseForge, for WoW: Forever.
# Adapted from LeanPad's tools/release.sh. Run it from the repository root, with the commit to release checked out:
#   tools/release.sh 0.5.0            publish (needs GH_TOKEN and CF_API_TOKEN; run by .github/workflows/release.yml)
#   DRY_RUN=1 tools/release.sh 0.5.0  build the zip and print what would be sent, publish nothing
# The release notes are that version's section of CHANGELOG.md; the game version comes from the TOC's Interface line.
set -euo pipefail

version="${1:?usage: tools/release.sh <version>}"
root="$PWD"
toc="$root/QuestTriage.toc"
out="$root/.release"
zip="QuestTriage-v$version.zip"

# The zip holds only what the game loads: the TOC, the Lua files it lists, the icon, the license and the bundled libraries' licenses.
rm -rf "$out"
mkdir -p "$out/QuestTriage/media"
cp "$toc" "$out/QuestTriage/"
# TOC paths use backslashes (Libs\...); copy each file into the same subfolder.
grep -vE '^[[:space:]]*(#|$)' "$toc" | tr -d '\r' | tr '\\' / | while read -r file; do
  mkdir -p "$out/QuestTriage/$(dirname "$file")"
  cp "$root/$file" "$out/QuestTriage/$file"
done
cp "$root/media/icon-64.png" "$out/QuestTriage/media/"
cp "$root/LICENSE.md" "$out/QuestTriage/"
cp "$root/Libs/LICENSES.md" "$out/QuestTriage/Libs/"
sed -i "s/@project-version@/$version/" "$out/QuestTriage/QuestTriage.toc"
(cd "$out" && zip -qr "$zip" QuestTriage)

notes="$(tr -d '\r' < "$root/CHANGELOG.md" | awk -v v="$version" 'index($0, "## [" v "]") == 1 { on = 1; next } on && /^## \[/ { exit } on')"
if [ -z "$notes" ]; then
	echo "CHANGELOG.md has no section for $version" >&2
	exit 1
fi
printf '%s\n' "$notes" > "$out/notes.md"

# Interface 16001 is Forever's game version 1.60.1.
game_version() { echo "$(($1 / 10000)).$(($1 / 100 % 100)).$(($1 % 100))"; }
forever="$(game_version "$(grep -m1 '^## Interface:' "$toc" | grep -oE '[0-9]+' | head -n 1)")"
project="$(grep -m1 '^## X-Curse-Project-ID:' "$toc" | tr -dc '0-9' || true)"

# A version with a suffix, such as 0.6.0-beta.1, is published as a beta.
release_type="release"
case "$version" in *-*) release_type="beta" ;; esac

echo "Quest Triage $version ($release_type) for WoW: Forever $forever: $out/$zip, CurseForge project ${project:-<none>}"
if [ -n "${DRY_RUN:-}" ]; then
	unzip -l "$out/$zip"
	cat "$out/notes.md"
	exit 0
fi
if [ -z "$project" ]; then
	echo "QuestTriage.toc has no ## X-Curse-Project-ID line. Nothing was published." >&2
	exit 1
fi

# CurseForge's versions come first, so a release it can't take stops before anything is published.
# Forever's game version type isn't known here, so it's matched by name; 1.60.x names no other client.
cf="https://wow.curseforge.com"
versions="$(curl -fsS -H "X-Api-Token: $CF_API_TOKEN" "$cf/api/game/versions")"
forever_id="$(jq -r --arg v "$forever" 'map(select(.name == $v)) | first | .id // empty' <<< "$versions")"
if [ -z "$forever_id" ]; then
	echo "CurseForge lists no game version $forever (WoW: Forever). Nothing was published." >&2
	exit 1
fi

# GitHub: create the release for the tag, or replace its zip when re-releasing.
if gh release view "v$version" > /dev/null 2>&1; then
	gh release upload "v$version" "$out/$zip" --clobber
elif [ "$release_type" = "beta" ]; then
	gh release create "v$version" "$out/$zip" --title "Quest Triage $version" --notes-file "$out/notes.md" --prerelease
else
	gh release create "v$version" "$out/$zip" --title "Quest Triage $version" --notes-file "$out/notes.md"
fi

jq -n --rawfile notes "$out/notes.md" --arg name "Quest Triage $version" --arg type "$release_type" --argjson games "[$forever_id]" \
	'{changelog: $notes, changelogType: "markdown", displayName: $name, releaseType: $type, gameVersions: $games}' \
	> "$out/metadata.json"
curl -fsS -H "X-Api-Token: $CF_API_TOKEN" -F "metadata=<$out/metadata.json" -F "file=@$out/$zip" \
	"$cf/api/projects/$project/upload-file"
echo
echo "Uploaded $release_type to CurseForge project $project (game version $forever, id $forever_id)"
