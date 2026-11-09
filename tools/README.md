# Developer tools (not part of the addon)

Nothing in this folder ships to players: `tools/release.sh` packs only the files the game loads.

## Screenshots for the README and CurseForge page

Same method as LeanPad: a developer-only addon records where the frame is on screen and takes the screenshot,
then a script crops it, so only the Quest Triage panel (or the map with its tooltip, or Settings) is kept and chat
and other players' names stay out.

1. `QuestTriageShots/` is junctioned into `_forever_\Interface\AddOns\QuestTriageShots`. Enable **Quest Triage Shots**
   in the AddOns list at the character screen.
2. Set up each moment in game, then type its command (table below).
3. `/reload` so WoW saves the records, then run `sh tools/screenshots.sh` from the repo root. It crops each shot into
   `docs/images/<name>.png`. The first run builds a small ImageMagick Docker image (`Dockerfile.shots`); later runs
   take seconds.
4. Check each image before using it.

| Set up in game | Then type |
| --- | --- |
| Stand inside a quest area: "Do … here" with the objective checklist | `/qtshots quest-area` |
| World map open, mouse over the pin so its tooltip shows | `/qtshots pin-tooltip` |
| An "Equip …" step on the Next card | `/qtshots gear` |
| Esc > Options > AddOns > Quest Triage | `/qtshots settings` |

A shot keeps one window plus the tooltip over it: Settings, else the world map, else the panel. Retaking a name
replaces its old record.

## Releases

`release.sh` builds `QuestTriage-v<version>.zip` (the `.toc`, the Lua files it lists, the icon and the license) and
uploads it to GitHub Releases and CurseForge for WoW: Forever. `.github/workflows/release.yml` runs it when a new
dated section such as `## [0.5.1] - 2026-11-10` is pushed in `CHANGELOG.md`. To see the zip without publishing:
`DRY_RUN=1 bash tools/release.sh 0.5.0`.

## CurseForge description

The CurseForge description is made from `README.md`: after changing the README, run
`sh tools/curseforge-description.sh --update` to refresh `CURSEFORGE-DESCRIPTION.md` (the Test workflow fails if you forget).
