# Changelog

## [Unreleased]

- Save any quest for later from the right-click menu: until a level you pick (it comes back on its own) or until you bring it back with "Do it now".
- Pick-ups trust the quest giver over Questie: when you talk to an NPC, quests Questie lists for them that they don't offer yet (follow-ups whose earlier quest you haven't done) leave the list until they're offered or you level up.
- Nearest repair vendor: when your gear drops below 25% (or breaks), it names the closest repair vendor with distance; click to pin it.
- Hearthstone tip: in a town far from where your hearthstone is set, it suggests setting it at the inn there. Right-click to skip that inn, or turn tips off in settings.
- Share a quest with your party from the right-click menu (shown when you're in a group and the quest can be shared).

## [0.5.0] - 2026-11-08

- Death handling: release, run back to your corpse with the arrow, resurrect; the route resumes where you left off.
- Two deaths on a quest at the same level move it to Save for later with a come-back level ("Try it again now" brings it back).
- The route stays on track: it sticks with the current step and favours quests you've started.
- Honours the game's quest areas: inside the white boundary the card says "do it here"; overlapping areas become one step.
- Points to real hunting grounds instead of stray spawns; detects slow spawns from your own kills and suggests a denser spot.
- Quests that need an item first say where and how to get it, with two map markers; helper quests stop being offered once you have the item.
- Map pins keep Blizzard's navigation and add a Quest Triage block to its tooltip; stale pins clear themselves; `/qt debug` explains every pin.
- Next card shows a checklist of all objectives.
- Fight check when you target a monster; prep line for quests above your level.
- Gear is judged on real stats per class with an armor-type check (no more cloth for Warriors).
- Auto-sell gray items at vendors (option).
- Better contrast: every text color reaches 7:1.

## [0.4.0] - 2026-11-08

- Next card with a live arrow and travel time; route by distance with Batch and One-at-a-time styles.
- Pick-ups from Questie, quest blockers, branded map pins, right-click menu, combat fade, options panel.

## [0.3.0] - 2026-11-08

- Directions from Questie: nearby quest givers, objective and turn-in locations, map pins.

## [0.2.0] - 2026-11-08

- Next step line, gear upgrades from quest rewards and bags, trainer reminders, automatic progress tracking (`/qt stats`).

## [0.1.0] - 2026-11-08

- First version: sorts the quest log into Turn in, Do now, Needs a group, Save for later and Drop.
