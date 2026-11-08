# Publishing Quest Triage on CurseForge

Everything needed for the CurseForge project page, in the order the form asks for it.

## 1. Project fields

| Field | Value |
| --- | --- |
| Name | Quest Triage |
| Summary | Your leveling co-pilot: the best next step, an arrow to it, and what to pick up, skip or equip. |
| Main category | Quests & Leveling |
| Extra category | Map & Minimap |
| License | GNU General Public License version 3 (GPLv3) |
| Logo | `media/logo-400.png` (400 x 400) |
| Source | https://github.com/tamuir/QuestTriage |
| Issues | https://github.com/tamuir/QuestTriage/issues |
| Game version for files | WoW Forever (the `.toc` says `## Interface: 16001`) |
| Relations | Questie: **Optional dependency** |

## 2. Description (paste into the description editor, Markdown mode)

```markdown
**Your leveling co-pilot for WoW: Forever.** Quest Triage reads your quest log, bags, gear and position, and shows the single best thing to do next, with a live arrow pointing the way. No guide to read.

### One clear next step
The Next card picks the best move right now: hand in, pick up, go do, or fix something first. The arrow turns with you, and travel time is shown ("~2 min NW"). Every objective is listed with a check when done.

### Your quest log, sorted
Turn in · Do now · Pick up · Needs a group · Save for later (with the level to come back at) · Drop. Hover any line for the reason, objectives and exact location.

### Smarter than a list
- **Batch or one at a time.** Grab every quest in a hub before you leave, and do quests whose objectives are close together in one trip. Or finish, hand in, then pick up the next.
- **Knows the game's quest areas.** Inside the white boundary on your minimap, it says "do it here".
- **Catches blockers.** Needs an item first? It tells you where and how, with two map markers: get the item, then complete the quest.
- **Real hunting grounds,** not a stray spawn at the edge of the map. Slow kills? It suggests a denser spot.
- **Learns from your deaths.** Die twice on the same quest and it moves to "Save for later: come back at 16".
- **Death handling.** Release, run back with the arrow, resurrect, carry on.

### Get stronger as you level
- Gear upgrades from quest rewards and your bags, judged on real stats for your class. Click to equip.
- New trainer spells read from your spellbook, so no wasted trips.
- Fight check on your target: level, elite, rare.
- Gray items sell automatically at any vendor.

### Requirements
WoW: Forever. **Questie is recommended**: directions, pick-ups and spawn areas come from your Questie install. Without it, Quest Triage still sorts your log and checks gear, trainers, deaths and quest areas.

### Commands
`/qt` show or hide · `/qt options` settings · `/qt stats` your progress · `/qt unhide` · `/qt reset` · `/qt debug`

### Credits
Directions and quest data come from Questie and QuestieDB, read at runtime from your own install. Quest Triage contains none of their code or data. Thank you to the Questie team.
```

## 3. Screenshots

CurseForge shows these in a gallery. Take them in-game at 1920 x 1080 or larger, with the panel at 100 % size. Crop out chat (other players' names).

1. **The Next card in a quest hub.** Batch mode, "Pick up N quests from …", arrow visible. Caption: *One clear next step, with an arrow.*
2. **Inside a quest area.** "Do The Disruption Ends here" with the objective checklist. Caption: *Knows when you're in the right place.*
3. **A blocked quest.** "Pick up Flawed Power Stone first" plus the world map with both markers. Caption: *Tells you what you need first, and where.*
4. **The world map pin tooltip.** Hover the pin. Caption: *Every pin explains itself.*
5. **A gear upgrade.** "Equip [item] · +3 Strength, +2 Stamina, +12 Armor". Caption: *Upgrades judged on real stats for your class.*
6. **Options.** Esc > Options > AddOns > Quest Triage. Caption: *Batch or one at a time, auto-sell, size, combat fade.*

## 4. Automatic uploads (one-time setup)

1. Create the project on CurseForge with the fields above and note its **Project ID** (shown on the project page).
2. In `QuestTriage.toc`, replace the commented line with `## X-Curse-Project-ID: <your id>`.
3. On CurseForge, create an **API token** (your account settings, API tokens).
4. On GitHub, repo Settings > Secrets and variables > Actions, add a secret named `CF_API_KEY` with that token.
5. Release: update `## Version` in the `.toc` and the top of `CHANGELOG.md`, commit, then tag and push:
   `git tag v0.5.0 && git push origin v0.5.0`
   GitHub Actions runs the tests, builds the zip (without dev files) and uploads it to CurseForge and GitHub Releases.

The first upload can also be done by hand: zip the `QuestTriage` folder without `tests.lua`, `run-tests.sh`, `pics`, `media/logo.svg`, `media/logo-400.png` and `.github`, and upload it on the project's Files tab.

## 5. Before you publish

- [ ] Play a session on the release build; run `/qt debug` once to check pins.
- [ ] Screenshots taken (section 3).
- [ ] Project ID in the `.toc`, `CF_API_KEY` secret set.
- [ ] Questie listed as an optional dependency on the project page.
