-- Run outside the game: sh run-tests.sh   (not listed in the .toc, so WoW never loads it)
local QT = dofile("Core.lua")
local player = { level = 12, greenRange = 6, xp = 1000, xpMax = 5000, zone = "Durotar" }

local function q(t) t.objectives = t.objectives or {}; return t end
local function has(rows, pat) for _, x in ipairs(rows) do if x.text:find(pat) then return x end end end
local function count(rows, pat) local n = 0; for _, x in ipairs(rows) do if x.text:find(pat) then n = n + 1 end end; return n end
-- A loc at world position (x, y) in yards, measured from a player standing at (0, 0).
local function at(x, y, name, zone)
  return { name = name, zone = zone or "Durotar", wx = x, wy = y, inst = 1, yards = math.floor(math.sqrt(x * x + y * y)) }
end

-- Buckets; "right level" says nothing.
assert(QT.Classify(q{ title = "A", level = 12, isComplete = true }, player) == "turnin")
assert(QT.Classify(q{ title = "B", level = 20 }, player) == "later")
assert(QT.Classify(q{ title = "C", level = 4 }, player) == "drop")
assert(select(2, QT.Classify(q{ title = "R", level = 12 }, player)) == "")
assert(QT.Classify(q{ title = "G", level = 12, isTrivial = true }, player) == "drop")
assert(QT.Classify(q{ title = "H", level = 4, isTrivial = false }, player) == "now")
local b, r = QT.Classify(q{ title = "D", level = 4, upgrade = { name = "Boots", change = "+3 Strength", slot = "feet" } }, player)
assert(b == "now" and r:find("Boots") and r:find("+3", 1, true), r)
assert(QT.Classify(q{ title = "E", level = 12, isFailed = true, upgrade = { name = "X", slot = "feet" } }, player) == "drop")

-- Trainer advice: never a guess, never a wasted trip.
local a, nx = QT.TrainerAdvice(nil, nil, 14)
assert(a == nil and nx == nil)
a, nx = QT.TrainerAdvice({ ready = 0, nextLevel = 16 }, nil, 14)
assert(a == nil and nx == 16)
assert(QT.TrainerAdvice({ ready = 2, nextLevel = 16 }, nil, 14) == "Learn 2 new spells at your class trainer.")
a, nx = QT.TrainerAdvice({ ready = 1, nextLevel = 18 }, { level = 14, left = 0, nextLevel = 16 }, 14)
assert(a == nil and nx == 16)
assert(QT.TrainerAdvice(nil, { level = 14, left = 0, nextLevel = 16 }, 16):find("unlocked"))

-- Directions and travel time (7 yd/s on foot).
assert(QT.Compass(0) == "N" and QT.Compass(math.pi / 2) == "W" and QT.Compass(3 * math.pi / 2) == "E")
assert(QT.Compass(2 * math.pi - 0.1) == "N" and QT.Compass(math.pi / 4) == "NW")
assert(QT.Travel(300) == "<1 min" and QT.Travel(840) == "~2 min" and QT.Travel(5000) == "~12 min")
assert(QT.Short({ yards = 770, dir = "NW", zone = "Durotar" }) == "~2 min NW")
assert(QT.Short({ yards = 10, zone = "Durotar" }) == "here")
assert(QT.Short({ zone = "Mulgore" }) == "Mulgore" and QT.Short(nil) == nil)
assert(QT.Where({ yards = 2520, dir = "W", zone = "The Barrens" }, player) == "The Barrens · ~6 min W")
assert(QT.Where({ yards = 200, dir = "E", zone = "Durotar" }, player) == "<1 min E")

-- Quick fixes come first; trainer, repairs and bags become a short reminder line.
local t = QT.Triage({
  q{ title = "Half done", level = 12, zone = "Durotar", objectives = { { text = "5/10", have = 5, need = 10 } } },
}, player)
local acts, rem = QT.BestActions(t, { bagUpgrade = { name = "Axe", link = "L", change = "+4.2 damage per second" }, durability = 0,
  train = "Learn 2 new spells at your class trainer.", freeSlots = 1, junk = 3 })
assert(acts[1].icon == "repair" and acts[2].kind == "equip" and acts[3].text == "Go do Half done")
assert(#rem == 2 and rem[1]:find("trainer") and rem[2] == "Sell 3 grey items")

-- Batch mode: grab what's near you before leaving; do quests whose objectives sit together.
local hub = QT.Triage({
  q{ title = "Lone", level = 12, questID = 1, loc = at(0, 500, "Far camp") },          -- 500 yd, alone
  q{ title = "Pack A", level = 12, questID = 2, loc = at(700, 0, "Raptors") },        -- 700 yd, clustered
  q{ title = "Pack B", level = 12, questID = 3, loc = at(750, 50, "Raptors") },
  q{ title = "Pack C", level = 12, questID = 4, loc = at(720, -60, "Raptors") },
}, player)
local groups = QT.PickupGroups({
  { questID = 10, title = "Nearby", level = 12, giver = at(100, 0, "Gornek") },
  { questID = 11, title = "Faraway", level = 12, giver = at(0, 2000, "Hermit") },
}, player)
local ba = QT.BestActions(hub, {}, player, groups, { style = "batch" })
assert(ba[1].text == "Pick up Nearby from Gornek", "batch: grab the quest next to you first: " .. ba[1].text)
groups = QT.PickupGroups({}, player)
ba = QT.BestActions(hub, {}, player, groups, { style = "batch" })
assert(ba[1].text:find("^Go do Pack") and ba[1].sub:find("same trip: Pack ., Pack ."), "batch: the cluster beats the closer lone quest")
local sa = QT.BestActions(hub, {}, player, groups, { style = "single" })
assert(sa[1].text == "Go do Lone", "single: just the nearest quest")
-- Single mode: finish what you have before picking up more.
groups = QT.PickupGroups({ { questID = 10, title = "Nearby", level = 12, giver = at(100, 0, "Gornek") } }, player)
assert(QT.BestActions(hub, {}, player, groups, { style = "single" })[1].text == "Go do Lone")
assert(QT.BestActions(QT.Triage({}, player), {}, player, groups, { style = "single" })[1].text == "Pick up Nearby from Gornek")
-- Batch mode says how much is left to grab here.
groups = QT.PickupGroups({
  { questID = 10, title = "One", level = 12, giver = at(100, 0, "Gornek") },
  { questID = 12, title = "Two", level = 12, giver = at(0, 150, "Margoz") },
}, player)
ba = QT.BestActions(hub, {}, player, groups, { style = "batch" })
assert(ba[1].sub and ba[1].sub:find("1 more to do here"), ba[1].sub)

-- Hand-ins: a near one wins; a far one waits until you pass by (batch).
local r2 = QT.Triage({ q{ title = "Close", level = 12, questID = 5, loc = at(300, 0, "Raptor") } }, player)
r2.turnin = { { quest = { title = "Far", questID = 6, loc = at(0, 2000, "Gornek") } } }
assert(QT.BestActions(r2, {}, player, nil, { style = "batch" })[1].text == "Go do Close")
r2.turnin[1].quest.loc = at(0, 200, "Gornek")
local ha = QT.BestActions(r2, {}, player, nil, { style = "batch" })
assert(ha[1].text == "Hand in Far" and ha[1].sub == "to Gornek")

-- Blockers: a quest missing its item sends you to get it first, and says why.
local stone = at(-1000, 0, "Flawed Power Stone", "The Barrens")
stone.x, stone.y = 47.1, 12.4
local seed = q{ title = "The Demon Seed", level = 12, questID = 924, loc = at(-1100, 0, "Altar", "The Barrens"),
  blockers = { { text = "Pick up Flawed Power Stone", how = "Click the Flawed Power Stone", loc = stone } } }
local bt = QT.Triage({ seed }, player)
assert(bt.now[1].reason:find("^First: Pick up Flawed Power Stone%. Click the Flawed Power Stone%."), bt.now[1].reason)
local bb = QT.BestActions(bt, {}, player)
assert(bb[1].text == "Pick up Flawed Power Stone first" and bb[1].icon == "blocker"
  and bb[1].sub == "Click the Flawed Power Stone · needed for The Demon Seed", bb[1].sub)
local br = QT.BuildRows(bt, player, {}, {})
local seedRow = has(br, "The Demon Seed")
assert(seedRow and seedRow.style == "item" and seedRow.icon == "blocker" and seedRow.text:find("needs item"),
  "the blocked quest stays listed with its warning")
assert(seedRow.loc == stone and seedRow.pin == "blocker", "the row points where to get the item, not at the altar")
assert(seedRow.tip[1]:find("^First: Pick up Flawed Power Stone%. Click the Flawed Power Stone at Flawed Power Stone, The Barrens 47%.1, 12%.4"),
  seedRow.tip[1])
local firsts = 0
for _, line in ipairs(seedRow.tip) do if line:find("^First:") then firsts = firsts + 1 end end
assert(firsts == 1, "the blocker is explained once, not twice")
-- An item with no known source still says so, instead of pointing somewhere wrong.
local lost = QT.Triage({ q{ title = "Odd", level = 12, questID = 9, loc = at(10, 0),
  blockers = { { text = "Get Strange Key", how = "Questie doesn't know where it comes from" } } } }, player)
local la = QT.BestActions(lost, {}, player)
assert(la[1].text == "Get Strange Key first" and la[1].loc == nil and la[1].sub:find("doesn't know"))
-- The blocker's own pickup isn't listed twice.
local dup = QT.PickupGroups({ { questID = 926, title = "Flawed Power Stone", level = 12,
  giver = at(-1000, 0, "Flawed Power Stone", "The Barrens") } }, player)
assert(not has(QT.BuildRows(bt, player, {}, {}, dup), "^%[12%] Flawed Power Stone"))

-- Pickups: worth doing at your level only; nearest first, then closest to your level; hidden ones gone.
local pg = QT.PickupGroups({
  { questID = 1, title = "A", level = 12, giver = at(100, 0, "Gornek") },
  { questID = 2, title = "B", level = 13, giver = at(100, 0, "Gornek") },
  { questID = 3, title = "C", level = 20, giver = at(10, 0, "Far") },
  { questID = 4, title = "D", level = 12, giver = at(50, 0, "Margoz") },
  { questID = 5, title = "E", level = 12, requiredLevel = 14, giver = at(5, 0, "Early") },
  { questID = 6, title = "F", level = 3, giver = at(5, 0, "Grey") },
  { questID = 7, title = "Stone", level = 12, giver = at(500, 0, "Stone") },
  { questID = 8, title = "Hidden", level = 12, giver = at(1, 0, "Hidden") },
}, player, { [8] = true })
assert(#pg == 3 and pg[1].giver.name == "Margoz" and #pg[2].quests == 2)
local pa = QT.BestActions(QT.Triage({}, player), {}, player, pg, { style = "single" })
assert(pa[1].text == "Pick up D from Margoz" and pa[3].text == "Pick up Stone")

-- Rows: one Next card, its giver not repeated; "Pick up" folds to 3 with a "+N more".
local many = {}
for i = 1, 6 do table.insert(many, { questID = 100 + i, title = "P" .. i, level = 12, giver = at(i * 100, 0, "G" .. i) }) end
local rows = QT.BuildRows(QT.Triage({}, player), player, {}, {}, QT.PickupGroups(many, player))
assert(rows[1].style == "hero" and rows[1].text == "Pick up P1 from G1" and rows[1].sub:find("<1 min"))
assert(not has(rows, "^%[12%] P1"), "the Next step isn't listed again")
assert(count(rows, "^%[12%] P") == 3 and has(rows, "%+2 more") and has(rows, "%[%+%] Pick up").right == "5")

-- "Do now": top 5, grouped by the objective's zone, "(you are here)" on yours, nearest first.
local log = {}
for i = 1, 4 do table.insert(log, q{ title = "Here" .. i, level = 12, questID = i, loc = at(i * 100, 0, "x", "Durotar") }) end
for i = 1, 3 do table.insert(log, q{ title = "There" .. i, level = 12, questID = 10 + i, loc = at(0, 2000 + i * 100, "y", "The Barrens") }) end
table.insert(log, q{ title = "Later", level = 20, questID = 99 })
table.insert(log, q{ title = "Old", level = 3, questID = 98 })
local tb = QT.Triage(log, player)
rows = QT.BuildRows(tb, player, {}, { style = "single" })
assert(rows[1].text == "Go do Here1")
assert(has(rows, "Durotar  %(you are here%)").style == "zone" and has(rows, "^The Barrens").style == "zone")
assert(count(rows, "^%[12%]") == 5 and has(rows, "%+1 more"), "5 shown, Next excluded, 1 more")
assert(has(rows, "Save for later").text:find("%[%+%]") and not has(rows, "^%[20%]"), "Later starts folded")
assert(has(rows, "Drop").text:find("%[%+%]") and not has(rows, "^%[3%]"), "Drop starts folded")
rows = QT.BuildRows(tb, player, {}, { style = "single", expanded = { now = true, later = true, drop = true } })
assert(count(rows, "^%[12%]") == 6 and has(rows, "at level 18") and has(rows, "^%[3%] Old  .*grey"))
for _, x in ipairs(rows) do assert(not x.text:find("\n"), "one line per row") end
-- Progress shows as a bar value, not text.
local prog = QT.BuildRows(QT.Triage({ q{ title = "X", level = 12, questID = 1, loc = at(10, 0) },
  q{ title = "Y", level = 12, questID = 2, loc = at(900, 0), objectives = { { text = "3/12 Head", have = 3, need = 12 } } } }, player),
  player, {}, { style = "single" })
local yRow = has(prog, "^%[12%] Y")
assert(yRow.progress == 0.25 and not yRow.text:find("3/12"))

-- Next card shows what the step is worth.
local xpRows = QT.BuildRows(QT.Triage({ q{ title = "Big", level = 12, questID = 1, xp = 400, loc = at(10, 0) } }, player), player, {}, {})
assert(xpRows[1].sub:find("%+10%% of level"), xpRows[1].sub)

-- XP summary and stats.
assert(QT.XPSummary(QT.Triage({ q{ title = "Z", level = 12, xp = 2000 } }, player), player) == "Your quests cover 50% of this level.")
assert(QT.XPSummary(QT.Triage({}, player), player) == nil)
assert(QT.Commas(1234567) == "1,234,567" and QT.Commas(999) == "999")

-- Death: everything waits until you're back at your corpse.
local quest = QT.Triage({ q{ title = "Raptors", level = 12, questID = 1, loc = at(50, 0) } }, player)
local dead = QT.BestActions(quest, {}, player, nil, { death = { ghost = false } })
assert(dead[1].text == "Release your spirit" and dead[1].icon == "death")
local ghost = QT.BestActions(quest, {}, player, nil, { death = { ghost = true, corpse = at(0, 600, "Your corpse") } })
assert(ghost[1].text == "Run back to your corpse" and ghost[1].loc.yards == 600 and ghost[1].kind == "goto")
assert(ghost[2].text == "Go do Raptors", "the quest is still next once you're back")
local close2 = QT.BestActions(quest, {}, player, nil, { death = { ghost = true, corpse = at(0, 30) } })
assert(close2[1].text == "Resurrect at your corpse")
local deadRows = QT.BuildRows(quest, player, {}, { death = { ghost = true, corpse = at(0, 600) } })
assert(deadRows[1].text == "Run back to your corpse" and deadRows[1].key == nil, "death step never becomes the commitment")
assert(has(deadRows, "^%[12%] Raptors"), "the quest stays listed while you run back")

-- Staying on track: the current step keeps going unless another is less than half the effort.
local two = QT.Triage({
  q{ title = "Started", level = 12, questID = 1, loc = at(600, 0) },
  q{ title = "Fresh", level = 12, questID = 2, loc = at(0, 450) },
}, player)
local free = QT.BestActions(two, {}, player, nil, { style = "single" })
assert(free[1].text == "Go do Fresh" and free[1].key == "do:2")
local kept = QT.BestActions(two, {}, player, nil, { style = "single", committed = "do:1" })
assert(kept[1].text == "Go do Started" and kept[1].committed, "commitment beats a slightly closer quest")
for _, e in ipairs(two.now) do -- Fresh is now less than half the effort: switch
  if e.quest.title == "Fresh" then e.quest.loc = at(0, 200) end
end
assert(QT.BestActions(two, {}, player, nil, { style = "single", committed = "do:1" })[1].text == "Go do Fresh")
-- Momentum: a half-done quest beats a slightly closer fresh one, in batch mode too.
local mo = QT.Triage({
  q{ title = "Half", level = 12, questID = 1, loc = at(600, 0), objectives = { { text = "6/12", have = 6, need = 12 } } },
  q{ title = "New", level = 12, questID = 2, loc = at(0, 500) },
}, player)
assert(QT.BestActions(mo, {}, player, nil, { style = "batch" })[1].text == "Go do Half")
-- The Next card carries its key so the panel can remember it.
assert(QT.BuildRows(mo, player, {}, { style = "batch" })[1].key == "do:1")

-- Quest areas: standing inside the game's own boundary means "do it here", never "go somewhere else".
local area = QT.Triage({
  q{ title = "Raptor Thieves", level = 12, questID = 1, loc = at(300, 0), inArea = true,
    objectives = { { text = "5/12 Raptor Head", have = 5, need = 12 } } },
  q{ title = "Closer", level = 12, questID = 2, loc = at(50, 0) },
}, player)
local ar = QT.BuildRows(area, player, {}, { style = "single", committed = "do:2" })
assert(ar[1].text == "Do Raptor Thieves here" and ar[1].here, "inside the area wins, even over the current step")
assert(ar[1].sub:find("^You're in the area") and ar[1].sub:find("nearest <1 min"), ar[1].sub)
assert(ar[1].checklist and ar[1].checklist[1] == "- 5/12 Raptor Head", "objectives show as a checklist on the card")
assert(not has(ar, "^%[12%] Raptor Thieves"), "not listed twice")
-- Two areas overlapping: one step for both, both left out of the list.
local two2 = QT.Triage({
  q{ title = "Raptor Thieves", level = 12, questID = 1, loc = at(300, 0), inArea = true,
    objectives = { { text = "5/12 Raptor Head", have = 5, need = 12 } } },
  q{ title = "Prowlers", level = 12, questID = 3, loc = at(200, 0), inArea = true,
    objectives = { { text = "0/7 Prowler Claws", have = 0, need = 7 } } },
  q{ title = "Elsewhere", level = 12, questID = 4, loc = at(900, 0) },
}, player)
local tr = QT.BuildRows(two2, player, {}, { style = "batch" })
assert(tr[1].text == "Do 2 quests here" and tr[1].key == "area:1,3", tr[1].text)
assert(tr[1].sub:find("Raptor Thieves %(5/12 Raptor Head%)") and tr[1].sub:find("Prowlers %(0/7 Prowler Claws%)"), tr[1].sub)
assert(#tr[1].tip == 2 and not has(tr, "^%[12%] Raptor") and not has(tr, "^%[12%] Prowlers") and has(tr, "^%[12%] Elsewhere"))
-- A quest you're in the area of, but missing its item, still sends you for the item first.
local blockedHere = QT.Triage({ q{ title = "Seed", level = 12, questID = 5, loc = at(10, 0), inArea = true,
  blockers = { { text = "Pick up Stone", loc = at(400, 0, "Stone") } } } }, player)
assert(QT.BestActions(blockedHere, {}, player)[1].text == "Pick up Stone first")

-- Hunting areas: go to the nearest real hunting ground, not the nearest stray spawn (your Barrens raptors).
local stray = { density = 1, dist = 80, loc = { name = "stray" } }
local ground = { density = 14, dist = 900, loc = { name = "ground" } }
local smaller = { density = 5, dist = 600, loc = { name = "smaller" } }
assert(QT.PickHuntingArea({ stray, ground }).loc.name == "ground", "a lone spawn is skipped")
assert(QT.PickHuntingArea({ stray, ground, smaller }).loc.name == "smaller", "nearest area with real density wins")
assert(QT.PickHuntingArea({ { density = 1, dist = 700, loc = { name = "Kreenig" } } }).loc.name == "Kreenig",
  "a named mob with one spawn still has a location")
assert(QT.PickHuntingArea(nil) == nil and QT.PickHuntingArea({}) == nil)
-- Better spot: only when clearly denser than where you stand, and within reach.
local hereA = { density = 4, dist = 100, loc = {} }
local better, hd = QT.PickBetterSpot({ hereA, ground })
assert(better == ground and hd == 4)
assert(QT.PickBetterSpot({ hereA, { density = 5, dist = 500, loc = {} } }) == nil, "5 vs 4 isn't worth the walk")
assert(QT.PickBetterSpot({ hereA, { density = 30, dist = 5000, loc = {} } }) == nil, "too far away")

-- Slow spawns: measured from your own progress, never guessed.
assert(QT.SlowCheck(nil, 1000) == nil and QT.SlowCheck({ gains = {} }, 1000) == nil, "not in the area: nothing to judge")
assert(QT.SlowCheck({ enteredAt = 1000, gains = {} }, 1200) == nil, "under 5 minutes: too early to call")
local slow = QT.SlowCheck({ enteredAt = 1000, gains = { 1100, 1400 } }, 1600) -- 2 in 10 min
assert(slow and slow.gains == 2 and slow.minutes == 10)
assert(QT.SlowCheck({ enteredAt = 1000, gains = { 1050, 1150, 1250, 1350 } }, 1600) == nil, "4 in 10 min is fine")
assert(QT.SlowCheck({ enteredAt = 0, gains = { 10, 20, 30, 40, 50, 60 } }, 2000).gains == 0, "only the last 15 min count")
-- A slow quest with a denser spot elsewhere: go there. Without one: do nearby work first.
local slowQ = q{ title = "Raptor Thieves", level = 12, questID = 1, loc = at(20, 0), inArea = true,
  slow = { minutes = 10, gains = 2 }, objectives = { { text = "7/12 Raptor Head", have = 7, need = 12 } } }
slowQ.altLoc = at(0, -900, "Bloodtalon Raptor")
slowQ.altLoc.spawns, slowQ.altLoc.hereSpawns = 18, 6
local sr = QT.BuildRows(QT.Triage({ slowQ }, player), player, {}, {})
assert(sr[1].text == "Try another spot for Raptor Thieves" and sr[1].loc.yards == 900, sr[1].text)
assert(sr[1].sub:find("Slow here: only 2 in 10 min · 18 spawn points there vs 6 here"), sr[1].sub)
slowQ.altLoc = nil
local other = q{ title = "Nearby", level = 12, questID = 2, loc = at(300, 0) }
local sa2 = QT.BestActions(QT.Triage({ slowQ, other }, player), {}, player, nil, { style = "single" })
assert(sa2[1].text == "Go do Nearby" and sa2[2].sub:find("do something nearby and come back"))
local slowRows = QT.BuildRows(QT.Triage({ slowQ, other }, player), player, {}, { style = "single" })
assert(has(slowRows, "Raptor Thieves.*slow"), "the list tags it slow")

-- Saved for later by the player: stays there until the chosen level, or until brought back.
local kolkar = q{ title = "Kolkar Leaders", level = 13, questID = 850, deferred = { untilLevel = 13 } }
local kb, kr, kback = QT.Classify(kolkar, player)
assert(kb == "later" and kback == 13 and kr:find("comes back at level 13"), kr)
assert(QT.Classify(q{ title = "K2", level = 13, deferred = { untilLevel = 12 } }, player) == "now", "back once you reach the level")
local kb2, kr2 = QT.Classify(q{ title = "K3", level = 12, deferred = {} }, player)
assert(kb2 == "later" and kr2:find("Right%-click it to bring it back"), "saved with no level stays until brought back")
assert(QT.Classify(q{ title = "K4", level = 12, isComplete = true, deferred = {} }, player) == "turnin", "a finished quest is still handed in")
local kRows = QT.BuildRows(QT.Triage({ kolkar, q{ title = "K3", level = 12, questID = 851, deferred = {} } }, player),
  player, {}, { expanded = { later = true } })
local kRow, k3Row = has(kRows, "Kolkar Leaders"), has(kRows, "K3")
assert(kRow.saved and kRow.qlevel == 13 and kRow.text:find("at level 13"), "saved row: offers Do it now, shows the level")
assert(k3Row.saved and k3Row.text:find("saved"), "no level: tagged saved")

-- Deaths: dying twice on a quest at your level moves it to Save for later, with the level to come back at.
local died = q{ title = "Kreenig", level = 14, questID = 7, deaths = { count = 2, level = 12 } }
local db, dr, dback = QT.Classify(died, player)
assert(db == "later" and dback == 14 and dr:find("died 2 times") and dr:find("Come back at 14"), dr)
assert(QT.Classify(q{ title = "Once", level = 12, deaths = { count = 1, level = 12 } }, player) == "now", "one death isn't enough")
assert(QT.Classify(q{ title = "Old", level = 12, deaths = { count = 3, level = 10 } }, player) == "now",
  "deaths at a lower level don't count once you've levelled")
assert(select(3, QT.Classify(q{ title = "Easy", level = 11, deaths = { count = 2, level = 12 } }, player)) == 14,
  "come back at least 2 levels higher")
local dRows = QT.BuildRows(QT.Triage({ died }, player), player, {}, { expanded = { later = true } })
local dRow = has(dRows, "Kreenig")
assert(dRow and dRow.text:find("at level 14") and dRow.retry, "later row shows its level and offers a retry")
assert(has(QT.BuildRows(QT.Triage({ q{ title = "Hi", level = 20 } }, player), player, {}, { expanded = { later = true } }),
  "at level 18"), "level-based later still shows its own level")

-- Fight check: honest about what it knows.
local me = { level = 14 }
assert(QT.FightCheck({ name = "Kreenig", level = 16, classification = "normal", canAttack = true }, me)
  :find("level 16 %(%+2%), risky.*Pull it alone and start at full health"))
assert(QT.FightCheck({ name = "Boar", level = 13, classification = "normal", canAttack = true }, me) == nil, "easy: say nothing")
assert(QT.FightCheck({ name = "Boar", level = 14, classification = "normal", canAttack = true }, { level = 14, manaPct = 30 })
  :find("Drink first %(mana 30%%%)"))
assert(QT.FightCheck({ name = "Ogre", level = 15, classification = "elite", canAttack = true }, me):find("needs a group"))
assert(QT.FightCheck({ name = "Boss", level = -1, classification = "normal", canAttack = true }, me):find("Leave it"))
assert(QT.FightCheck({ name = "Guard", level = 30, canAttack = false }, me) == nil, "friendly: nothing")
assert(QT.FightCheck({ name = "Corpse", level = 16, canAttack = true, dead = true }, me) == nil)
local fRows = QT.BuildRows(QT.Triage({}, player), player, {}, { fight = { name = "Kreenig", level = 15, canAttack = true } })
assert(fRows[2].style == "alert" and fRows[2].text:find("Kreenig"), "fight check sits right under the Next card")

-- Prep: heading to a quest above your level says how to get ready, from real data only.
local hard = QT.Triage({ q{ title = "Tough", level = 14, questID = 1, loc = at(50, 0) } }, player)
local hRows = QT.BuildRows(hard, player, { train = "Learn 1 new spell at your class trainer.", durability = 40 }, {})
assert(hRows[1].sub:find("^Hard %(%+2%): train and repair first, start at full health"), hRows[1].sub)
assert(QT.BuildRows(hard, player, {}, {})[1].sub:find("^Hard %(%+2%): start at full health"))
assert(not (QT.BuildRows(QT.Triage({ q{ title = "Fine", level = 12, questID = 1, loc = at(50, 0) } }, player), player, {}, {})[1].sub or "")
  :find("Hard"), "no prep line for quests at your level")

local s = QT.Stats({
  [1] = { result = "done", bucket = "now", accepted = 0, finished = 600 },
  [2] = { result = "done", bucket = "later", accepted = 0, finished = 1200 },
  [3] = { result = "dropped", bucket = "drop" },
  [4] = { bucket = "now" },
})
assert(s.done == 2 and s.dropped == 1 and s.judged == 3 and s.followed == 2 and s.avgMinutes == 15)
assert(#QT.FormatStats(s) == 3)

-- Checklist: every objective, done ones checked, so you see what's finished and what's left.
local multi = q{ title = "The Disruption Ends", level = 12, questID = 30, loc = at(100, 0), objectives = {
  { text = "8/8 Razormane Geomancer slain", have = 8, need = 8 },
  { text = "2/8 Razormane Defender slain", have = 2, need = 8 },
  { text = "0/1 Kreenig Snarlsnout's Tusk", have = 0, need = 1 } } }
local cl = QT.Checklist(multi)
assert(#cl == 3 and cl[1]:find("ReadyCheck%-Ready") and cl[1]:find("8/8 Razormane Geomancer slain"))
assert(cl[2] == "- 2/8 Razormane Defender slain" and cl[3] == "- 0/1 Kreenig Snarlsnout's Tusk")
assert(QT.Checklist(q{ title = "None" }) == nil)
local mr = QT.BuildRows(QT.Triage({ multi }, player), player, {}, {})
assert(mr[1].text == "Go do The Disruption Ends" and #mr[1].checklist == 3, "the Next card lists all three")
assert(not (mr[1].sub or ""):find("Geomancer"), "objectives aren't repeated in the subtext")

-- Gear: your exact case. Cloth gloves (+1 Str, +1 Sta, +2 Spi, 17 armor) vs worn mail gloves (68 armor), Warrior 14.
local mailGloves = { RESISTANCE0_NAME = 68 }
local clothGloves = { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_STAMINA_SHORT = 1, ITEM_MOD_SPIRIT_SHORT = 2, RESISTANCE0_NAME = 17 }
assert(QT.GearUpgrade({ stats = clothGloves, classID = 4, subClassID = 1, equipLoc = "INVTYPE_HAND" },
  { mailGloves }, "WARRIOR", 14) == nil, "cloth is never suggested to a Warrior")
assert(QT.GearUpgrade({ stats = clothGloves, classID = 4, subClassID = 3, equipLoc = "INVTYPE_HAND" },
  { mailGloves }, "WARRIOR", 14) == nil, "even as mail, losing 51 armor for 1 Str + 1 Sta isn't worth it")
local betterMail = { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 2, RESISTANCE0_NAME = 80 }
local gu = QT.GearUpgrade({ stats = betterMail, classID = 4, subClassID = 3, equipLoc = "INVTYPE_HAND" },
  { mailGloves }, "WARRIOR", 14)
assert(gu and gu.change == "+3 Strength, +2 Stamina, +12 Armor", gu and gu.change)
-- Casters can wear cloth; the same gloves are an upgrade for a mage wearing nothing better.
assert(QT.GearUpgrade({ stats = clothGloves, classID = 4, subClassID = 1, equipLoc = "INVTYPE_HAND" },
  { { RESISTANCE0_NAME = 10 } }, "MAGE", 14).change == "+1 Strength, +1 Stamina, +2 Spirit, +7 Armor",
  "the same cloth gloves are a real upgrade for a mage")
assert(QT.GearUpgrade({ stats = { ITEM_MOD_INTELLECT_SHORT = 4, RESISTANCE0_NAME = 15 }, classID = 4, subClassID = 1,
  equipLoc = "INVTYPE_HAND" }, { { RESISTANCE0_NAME = 10 } }, "MAGE", 14).change == "+4 Intellect, +5 Armor")
-- Empty slots, cloaks, rings and weapons.
assert(QT.GearUpgrade({ stats = clothGloves, classID = 4, subClassID = 3, equipLoc = "INVTYPE_HAND" }, { false },
  "WARRIOR", 14).change == nil, "fills an empty slot")
assert(QT.ArmorOK("WARRIOR", 14, 4, 1, "INVTYPE_CLOAK"), "cloaks are cloth for everyone")
assert(not QT.ArmorOK("WARRIOR", 40, 4, 3, "INVTYPE_CHEST") and QT.ArmorOK("WARRIOR", 40, 4, 4, "INVTYPE_CHEST"), "plate at 40")
assert(QT.GearUpgrade({ stats = { ITEM_MOD_STRENGTH_SHORT = 3 }, classID = 4, subClassID = 0, equipLoc = "INVTYPE_FINGER" },
  { { ITEM_MOD_STRENGTH_SHORT = 5 }, { ITEM_MOD_STAMINA_SHORT = 1 } }, "WARRIOR", 14).index == 2, "replaces the weaker ring")
assert(QT.GearUpgrade({ stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 9.5 }, classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPON" },
  { { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 7.2 } }, "WARRIOR", 14).change == "+2.3 damage per second")

-- Hearthstone tip: at an inn far from your bind, suggest it; learn the bind position when you stand at it.
do
  local function inn(yards, wx) return { name = "Innkeeper Boorand", zone = "The Barrens", yards = yards, wx = wx, wy = 0, inst = 1 } end
  local b = { name = "Razor Hill" }
  assert(not QT.HearthTip(b, inn(500, 0), "The Crossroads"), "too far from the inn to be in its town")
  assert(not QT.HearthTip(b, inn(200, 0), "The Crossroads"), "unknown bind position: only speaks at the inn")
  local t = QT.HearthTip(b, inn(30, 0), "The Crossroads")
  assert(t and t.text == "Set your hearthstone here (now Razor Hill)" and t.hearth == "Innkeeper Boorand|The Barrens", "at a different inn")
  assert(not b.wx, "doesn't learn a position from someone else's inn")
  assert(not QT.HearthTip(b, inn(30, 5000), "Razor Hill") and b.wx == 5000, "bound here: silent, and learns the position")
  assert(not QT.HearthTip(b, inn(250, 5500), "Razor Hill Outskirts"), "known bind 500 yd away: fine")
  assert(QT.HearthTip(b, inn(250, 0), "The Crossroads"), "known bind far away: suggests from anywhere in town")
  b.inst = 2
  assert(QT.HearthTip(b, inn(250, 5000), "Somewhere"), "bound on another continent")
  local rows = QT.BuildRows({ turnin = {}, now = {}, group = {}, later = {}, drop = {} }, { level = 10 }, {},
    { hearth = t })
  assert(has(rows, "^Set your hearthstone"), "shown in the panel")
end

-- Repairs: with a known vendor, low gear becomes a clickable row (and broken gear a Next step) pointing at it.
do
  local empty = { turnin = {}, now = {}, group = {}, later = {}, drop = {} }
  local vendor = { name = "Gruk", zone = "The Barrens", yards = 300, dir = "SE" }
  local rows = QT.BuildRows(empty, { level = 10 }, { durability = 18, repairAt = vendor }, {})
  local r = has(rows, "^Repair soon")
  assert(r and r.text == "Repair soon (gear at 18%): Gruk" and r.loc == vendor and r.kind == "goto", "repair row")
  assert(not has(rows, "^Also: Repair"), "not also a reminder")
  assert(has(QT.BuildRows(empty, { level = 10 }, { durability = 18 }, {}), "^Also: Repair soon %(gear at 18%%%)"),
    "no vendor known: reminder only")
  local acts = QT.BestActions(empty, { durability = 0, repairAt = vendor }, { level = 10 })
  assert(acts[1].loc == vendor and acts[1].sub == "Broken gear gives you no stats · at Gruk", "broken gear: go to the vendor")
end

-- A quest-starting item in your bags is a free pick-up: it's the Next step.
do
  local empty = { turnin = {}, now = {}, group = {}, later = {}, drop = {} }
  local acts = QT.BestActions(empty, { bagQuest = { questID = 7, name = "Chen's Empty Keg", link = "L" } }, { level = 17 })
  assert(acts[1].text == "Open Chen's Empty Keg" and acts[1].kind == "bags" and acts[1].questID == 7, "open the item")
end

-- The giver's own offer list beats Questie: not offered by them -> marked; offered later -> cleared.
do
  local no = {}
  local starters = { [1] = { 50 }, [2] = { 50, 60 }, [3] = { 70 } }
  QT.MarkOffered(starters, 50, { [2] = true }, no)
  assert(no[1] and not no[2] and not no[3], "only this NPC's quests that it didn't offer")
  QT.MarkOffered(starters, 50, { [1] = true, [2] = true }, no)
  assert(not no[1], "offered now (prerequisite done): back in the list")
end

-- Readability: every text color in Core.lua, and the secondary-text gray, reach 7:1 (WCAG AAA) against the panel,
-- even with a white sky showing through it.
do
  local function lin(c) return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
  local function lum(t) return 0.2126 * lin(t[1]) + 0.7152 * lin(t[2]) + 0.0722 * lin(t[3]) end
  local function ratio(a, b) local l1, l2 = lum(a), lum(b); if l1 < l2 then l1, l2 = l2, l1 end; return (l1 + 0.05) / (l2 + 0.05) end
  local bgc = QT.PANEL_BG
  local bg = { bgc[1] * bgc[4] + (1 - bgc[4]), bgc[2] * bgc[4] + (1 - bgc[4]), bgc[3] * bgc[4] + (1 - bgc[4]) }
  local src = io.open("Core.lua"):read("*a")
  local seen = 0
  for h in src:gmatch('"ff(%x%x%x%x%x%x)"') do
    local c = { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
    assert(ratio(c, bg) >= 7, string.format("color %s is only %.1f:1", h, ratio(c, bg)))
    seen = seen + 1
  end
  assert(seen >= 8, "found the palette")
  local g = QT.META_GRAY
  assert(ratio({ g, g, g }, bg) >= 7, "secondary text gray")
end

print("all tests passed")
