# Changelog

## [Unreleased]

## [0.5.9] - 2026-11-19

- Closed the panel? Bring it back from the minimap's addon menu (right-click there opens the options), or set a key in Options > Keybindings > AddOns. Closing it now says how.
- The panel is held by its top edge: it grows downward and the Next card no longer jumps when the list changes.
- The scrollbar only shows when there's something to scroll.
- "Directions need Questie" no longer flashes at every login while Questie starts up, and an unsupported Questie version now says so.
- Map pin tooltips no longer say "Based on: Click the …".
- `/qt stats` judges a quest by the advice just before you finished it: one saved for later and done once your level caught up counts as following the advice.
- `/qt debug` shows how long each refresh takes.
- Deutsch: Quest Triage is now in German on a German client. Anything not translated yet shows in English.
- Group, dungeon and PvP quests are recognised in every language. Battleground quests (like Battle of Warsong Gulch) now sit in Needs a group instead of Do now.
- Directions without Questie: the arrow and map pins follow Blizzard's own quest markers, hand-ins included. Questie still adds quests to pick up, turn-in NPC names, missing items and hunting spots.
- Compact panel: the new - button folds the panel to just the Next step; + brings the lists back. Also a setting, "Compact panel".
- Pick up lists quest givers within about 3½ minutes' walk, plus always the nearest three, instead of every giver on the continent.
- New key binding "Go to the next step": does what clicking the Next card does.
- Skip a pickup: right-click any quest to pick up, the Next step included, and choose "Skip <quest>". A giver with several quests lists each one. `/qt unhide` brings them back, and a skipped quest you take anyway shows up again.
- At the quest reward window, Quest Triage names the choice that's a clear upgrade for you, in chat. It never picks for you.

## [0.5.8] - 2026-11-16

- Hearthstone tips skip a city your mage can already teleport to: no need to spend your hearthstone on it.

## [0.5.7] - 2026-11-13

- Timed quests (like Need for a Cure) come first: while the timer runs, the Next step is that quest or its hand-in, whatever else is nearby, and it shows the minutes left. New setting "Timed quests first": always (default), only under 30, 15 or 5 minutes left, or never.
- Event quests (Darkmoon Faire and other holidays) show in Pick up with the event's name, but never become the Next step: they're off your leveling route. Event hand-ins you don't carry the items for are left out.
- New setting "Background opacity" (20% to 100%): see more of the game through the panel. Below 95% every letter gets a dark outline, so the text stays readable over bright skies and snow.
- The setting "Suggest where to set your hearthstone" is now called "Hearthstone tips" (the old name was cut off in the options window).
- New setting "Open the map when pinning": turn it off and clicking a step just sets the pin (map, minimap and navigation arrow) without opening the map.

## [0.5.6] - 2026-11-13

- `/qt debug` opens a window with the details already selected: press Ctrl+C and paste them into a bug report. It includes your Quest Triage and Questie versions.

## [0.5.5] - 2026-11-13

- Fixed Questie errors ("iconData is nil") when hovering Questie's map icons while a Quest Triage pin was set. Quest Triage now ships its own copy of the HereBeDragons map library instead of sharing Questie's, so Questie never sees our pins.
- Map pins and distances no longer need Questie to be loaded.
- Quest tooltips no longer say "Go to ?" for spots from Blizzard's quest marker: they name the zone.

## [0.5.4] - 2026-11-13

- Fixed Lua errors that started around level 10 with class quests (and other quests not tied to a zone). The errors stopped the panel from refreshing, so clicking a quest no longer pinned it on the map.

## [0.5.3] - 2026-11-10

- Two-handed weapons are compared against your weapon and shield (or off-hand) together, so tanking with a shield no longer gets a two-hander pushed at you.
- Right-click an Equip step and choose "Don't suggest this item" to silence it. `/qt unhide` brings hidden items back.

## [0.5.2] - 2026-11-09

- Quest locations follow Blizzard's own quest marker (the spot inside the blue quest area on your map) instead of a spot worked out from Questie's spawn points. Questie's spawn points are only used for quests Blizzard doesn't mark.

## [0.5.1] - 2026-11-09

- Save any quest for later from the right-click menu: until a level you pick (it comes back on its own) or until you bring it back with "Do it now".
- Quest items in your bags: an item that starts a quest you don't have yet (like Chen's Empty Keg) becomes the Next step. Click to open your bags; right-click the step to hide it.
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
