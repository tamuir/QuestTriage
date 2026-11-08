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
local b, r = QT.Classify(q{ title = "D", level = 4, upgrade = { name = "Boots", gain = 3, slot = "feet" } }, player)
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
local acts, rem = QT.BestActions(t, { bagUpgrade = { name = "Axe", link = "L", gain = 4 }, durability = 0,
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
assert(ba[1].text:find("^Go do Pack") and ba[1].sub:find("2 more quests nearby"), "batch: the cluster beats the closer lone quest")
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
local seed = q{ title = "The Demon Seed", level = 12, questID = 924, loc = at(-1100, 0, "Altar", "The Barrens"),
  blockers = { { text = "Pick up Flawed Power Stone", loc = at(-1000, 0, "Flawed Power Stone", "The Barrens") } } }
local bt = QT.Triage({ seed }, player)
assert(bt.now[1].reason:find("^First: Pick up Flawed Power Stone"))
local bb = QT.BestActions(bt, {}, player)
assert(bb[1].text == "Pick up Flawed Power Stone first" and bb[1].icon == "blocker" and bb[1].sub == "You need it for The Demon Seed")
local br = QT.BuildRows(bt, player, {}, {})
local seedRow = has(br, "The Demon Seed")
assert(seedRow and seedRow.style == "item" and seedRow.icon == "blocker" and seedRow.text:find("needs item"),
  "the blocked quest stays listed with its warning")
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

local s = QT.Stats({
  [1] = { result = "done", bucket = "now", accepted = 0, finished = 600 },
  [2] = { result = "done", bucket = "later", accepted = 0, finished = 1200 },
  [3] = { result = "dropped", bucket = "drop" },
  [4] = { bucket = "now" },
})
assert(s.done == 2 and s.dropped == 1 and s.judged == 3 and s.followed == 2 and s.avgMinutes == 15)
assert(#QT.FormatStats(s) == 3)

print("all tests passed")
