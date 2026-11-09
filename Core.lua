-- Quest Triage: pure decision logic. No WoW API calls in this file,
-- so it can be tested outside the game.
local _, QT = ...
QT = QT or {}

-- Bucket ids, in the order they are shown. limit = rows shown before folding (nil = all).
QT.BUCKETS = {
  { id = "turnin", label = "Turn in",           color = "ff40ff40" },
  { id = "now",    label = "Do now",            color = "ffffd100", limit = 5 },
  { id = "group",  label = "Needs a group",     color = "ff7ec4ff" },
  { id = "later",  label = "Save for later",    color = "ffffa060", limit = 0 },
  { id = "drop",   label = "Drop",              color = "ffb8b8b8", limit = 0 },
}

-- How far above you a quest can be before we call it "later".
QT.MAX_LEVELS_ABOVE = 2

local function lower(s) return string.lower(s or "") end
local function colored(hex, text) return "|c" .. hex .. text .. "|r" end

-- Readability: the panel background and the gray used for secondary text. Every text color in this file is
-- checked in tests.lua to reach 7:1 contrast (WCAG AAA) against this background, even with a white sky behind it.
QT.PANEL_BG = { 0.04, 0.04, 0.05, 0.97 } -- r, g, b, alpha
QT.META_GRAY = 0.784                      -- secondary text (#c8c8c8)

local function isGroupQuest(q)
  local t = lower(q.title)
  if t:find("%(dungeon%)") or t:find("%(raid%)") or t:find("%(elite%)") then return true end
  if q.tag and (q.tag == "Dungeon" or q.tag == "Raid" or q.tag == "Elite" or q.tag == "Group") then return true end
  if q.suggestedGroup and q.suggestedGroup > 1 then return true end
  return false
end

-- Fraction of objectives done, 0..1. Quests with no countable objectives count as 0.
function QT.Progress(q)
  local have, need = 0, 0
  for _, o in ipairs(q.objectives or {}) do
    local h, n = o.have or 0, o.need or 0
    if n > 0 then
      have = have + math.min(h, n)
      need = need + n
    end
  end
  if need == 0 then return 0 end
  return have / need
end

-- Decide the bucket and a one-line reason for one quest. An empty reason means "nothing worth saying".
-- q: { title, level, questID, zone, isComplete, isFailed, suggestedGroup, tag, xp, upgrade, deaths, objectives = {{text, have, need}} }
-- q.deaths (optional, recorded by UI.lua): { count, level } = how often you died doing it, at which level.
-- q.deferred (optional, set by the player): { untilLevel = level it comes back at, or nil = until brought back }.
-- player: { level, greenRange, zone }  greenRange = levels below you that still give decent XP
-- Returns bucket, reason, and for "later" the level to come back at.
QT.DEATHS_BEFORE_LATER = 2
local function classifyBase(q, player)
  local pl = player.level
  local ql = q.level or pl
  local diff = ql - pl
  local greyBelow = pl - (player.greenRange or 5)

  if q.isFailed then
    return "drop", "Failed. Abandon it, and pick it up again if you pass the quest giver."
  end
  if q.isComplete then
    return "turnin", ""
  end
  -- Trust the game's own grey flag; level math is only the fallback.
  if q.isTrivial or (q.isTrivial == nil and ql < greyBelow) then
    return "drop", string.format("Grey for you (level %d). Almost no XP left.", ql)
  end
  -- You chose to save it for later: respect that until the level you picked (or until you bring it back).
  local df = q.deferred
  if df and (not df.untilLevel or pl < df.untilLevel) then
    return "later", df.untilLevel and string.format("You saved this for later. It comes back at level %d.", df.untilLevel)
      or "You saved this for later. Right-click it to bring it back.", df.untilLevel
  end
  -- Your own deaths are the best evidence: dying twice on it at this level means it's too hard right now.
  local dd = q.deaths
  if dd and dd.level == pl and dd.count >= QT.DEATHS_BEFORE_LATER then
    local back = math.max(pl + 2, ql)
    return "later", string.format("You died %d times on this at level %d. Come back at %d, or bring a friend.",
      dd.count, pl, back), back
  end
  if isGroupQuest(q) then
    if diff > QT.MAX_LEVELS_ABOVE + 2 then
      return "later", string.format("Group quest, level %d. Come back at %d with a group.", ql, ql - 2), ql - 2
    end
    return "group", "Dungeon or elite. Look for a group in chat."
  end
  if diff > QT.MAX_LEVELS_ABOVE then
    local back = ql - QT.MAX_LEVELS_ABOVE
    return "later", string.format("Too hard now. Come back at level %d.", back), back
  end
  if diff == QT.MAX_LEVELS_ABOVE then
    return "now", "Hard: pull one mob at a time."
  end
  return "now", ""
end

-- Gear: is an item better for YOUR class than what you wear? Judged on the item's real stats (the same numbers
-- the game's comparison tooltip shows), weighted per class, after an armor-type check.
-- Stat keys are the game's own (C_Item.GetItemStats).
local STAT = { STR = "ITEM_MOD_STRENGTH_SHORT", AGI = "ITEM_MOD_AGILITY_SHORT", STA = "ITEM_MOD_STAMINA_SHORT",
  INT = "ITEM_MOD_INTELLECT_SHORT", SPI = "ITEM_MOD_SPIRIT_SHORT", ARMOR = "RESISTANCE0_NAME",
  DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" }
local STAT_ORDER = { "STR", "AGI", "STA", "INT", "SPI", "ARMOR", "DPS" }
local STAT_NAMES = { STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit",
  ARMOR = "Armor", DPS = "damage per second" }
-- shortcut: simple leveling weights, not min-maxed sim values; good enough to rank quest and drop gear 1-60.
QT.STAT_WEIGHTS = {
  WARRIOR = { STR = 1, AGI = 0.6, STA = 0.6, ARMOR = 0.05, DPS = 3 },
  PALADIN = { STR = 1, STA = 0.6, INT = 0.4, AGI = 0.3, SPI = 0.2, ARMOR = 0.05, DPS = 3 },
  HUNTER  = { AGI = 1, STA = 0.5, INT = 0.3, STR = 0.1, ARMOR = 0.03, DPS = 2 },
  ROGUE   = { AGI = 1, STR = 0.5, STA = 0.5, ARMOR = 0.03, DPS = 3 },
  SHAMAN  = { STR = 0.7, INT = 0.7, AGI = 0.4, STA = 0.6, SPI = 0.3, ARMOR = 0.04, DPS = 2.5 },
  DRUID   = { STR = 0.6, AGI = 0.6, INT = 0.6, STA = 0.6, SPI = 0.4, ARMOR = 0.03, DPS = 1.5 },
  PRIEST  = { INT = 1, SPI = 0.8, STA = 0.6, ARMOR = 0.01, DPS = 0.5 },
  MAGE    = { INT = 1, SPI = 0.6, STA = 0.6, ARMOR = 0.01, DPS = 0.5 },
  WARLOCK = { INT = 1, STA = 0.8, SPI = 0.5, ARMOR = 0.01, DPS = 0.5 },
}

function QT.ItemScore(stats, class)
  local w = QT.STAT_WEIGHTS[class] or QT.STAT_WEIGHTS.WARRIOR
  local score = 0
  for short, key in pairs(STAT) do score = score + (w[short] or 0) * ((stats and stats[key]) or 0) end
  return score
end

-- Never suggest armor below the best type your class wears (cloth for a Warrior). Cloaks are cloth for all.
-- Armor = item class 4; subclasses 1 cloth, 2 leather, 3 mail, 4 plate.
function QT.BestArmor(class, level)
  if class == "WARRIOR" or class == "PALADIN" then return level >= 40 and 4 or 3 end
  if class == "HUNTER" or class == "SHAMAN" then return level >= 40 and 3 or 2 end
  if class == "ROGUE" or class == "DRUID" then return 2 end
  return 1
end
function QT.ArmorOK(class, level, classID, subClassID, equipLoc)
  if classID ~= 4 or not subClassID or subClassID < 1 or subClassID > 4 or equipLoc == "INVTYPE_CLOAK" then return true end
  return subClassID >= QT.BestArmor(class, level)
end

-- "+1 Strength, +1 Stamina, -51 Armor": what changes if you swap. labels = localized stat names (optional).
function QT.StatChanges(new, old, labels)
  local parts = {}
  for _, short in ipairs(STAT_ORDER) do
    local key = STAT[short]
    local d = ((new and new[key]) or 0) - ((old and old[key]) or 0)
    if math.abs(d) >= 0.05 then
      local n = short == "DPS" and string.format("%+.1f", d) or string.format("%+d", d)
      table.insert(parts, n .. " " .. ((labels and labels[key]) or STAT_NAMES[short]))
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

-- Is this item an upgrade over what you wear in the slots it fits?
-- cand = { stats, classID, subClassID, equipLoc }; worn = { [i] = stats of the item in slot i, or false if empty }.
-- Compares against the weaker slot (rings, trinkets). Must be clearly better: 5% and half a point of score.
-- Returns { index = which slot, change = stat changes text (nil for an empty slot), score = gain } or nil.
function QT.GearUpgrade(cand, worn, class, level, labels)
  if not QT.ArmorOK(class, level, cand.classID, cand.subClassID, cand.equipLoc) then return nil end
  local new = QT.ItemScore(cand.stats, class)
  local worstI, worstScore
  for i, stats in ipairs(worn) do
    local s = stats and QT.ItemScore(stats, class) or -1
    if not worstScore or s < worstScore then worstI, worstScore = i, s end
  end
  if not worstI then return nil end
  if worstScore < 0 then return { index = worstI, score = new + 1 } end -- empty slot
  if new <= worstScore * 1.05 + 0.5 then return nil end
  return { index = worstI, score = new - worstScore, change = QT.StatChanges(cand.stats, worn[worstI], labels) }
end

-- up: { name, change = "+3 Strength, ...", slot }  change is nil when the slot is empty.
function QT.UpgradeNote(up)
  if up.change then return up.change .. ", " .. up.slot end
  return string.format("fills your empty %s slot", up.slot)
end

-- q.blockers (optional, from Guide.lua): { {text = "Pick up Flawed Power Stone", loc}, ... } = what's missing to finish it.
function QT.Classify(q, player)
  local bucket, reason, backAt = classifyBase(q, player)
  if bucket == "now" and q.blockers and q.blockers[1] then
    local b = q.blockers[1]
    reason = "First: " .. b.text .. "." .. (b.how and (" " .. b.how .. ".") or "") .. (reason ~= "" and (" " .. reason) or "")
  end
  local up = q.upgrade
  if not up or q.isFailed then return bucket, reason, backAt end
  local note = "Gear upgrade: " .. up.name .. " (" .. QT.UpgradeNote(up) .. ")."
  if bucket == "drop" then
    return "now", "Grey, but worth it. " .. note
  end
  return bucket, reason == "" and note or (reason .. " " .. note), backAt
end

-- Sort helper inside a bucket.
local function sortKey(bucket, q, player)
  if bucket == "now" then
    -- Where you are first, then closest to done, then gear, then lower level.
    local here = (player.zone and q.zone == player.zone) and -5000 or 0
    return here - QT.Progress(q) * 1000 - (q.upgrade and 300 or 0) + (q.level or 0)
  elseif bucket == "later" or bucket == "group" then
    return q.level or 0
  end
  return 0
end

-- Main entry: returns { [bucketId] = { {quest=q, reason=...}, ... } }
function QT.Triage(quests, player)
  local out = {}
  for _, b in ipairs(QT.BUCKETS) do out[b.id] = {} end
  for _, q in ipairs(quests) do
    local bucket, reason, backAt = QT.Classify(q, player)
    table.insert(out[bucket], { quest = q, reason = reason, backAt = backAt, key = sortKey(bucket, q, player) })
  end
  for _, list in pairs(out) do
    table.sort(list, function(a, b)
      if a.key ~= b.key then return a.key < b.key end
      return (a.quest.title or "") < (b.quest.title or "")
    end)
  end
  return out
end

-- Short objective summary like "5/12 Raptor Head".
function QT.ObjectiveSummary(q)
  local parts = {}
  for _, o in ipairs(q.objectives or {}) do
    if o.need and o.need > 0 and (o.have or 0) < o.need then
      table.insert(parts, o.text)
    end
  end
  return table.concat(parts, ", ")
end

local function commas(n)
  local s = tostring(math.floor(n))
  while true do
    local r, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    s = r
    if k == 0 then return s end
  end
end
QT.Commas = commas

-- Trainer advice, never a guess. Returns actionText (or nil), nextLevel (or nil).
-- book: from your spellbook, { ready = spells learnable now, nextLevel }, nil if it lists no future spells.
-- trainer: what your class trainer offered on your last visit, { level, left, nextLevel }.
function QT.TrainerAdvice(book, trainer, level)
  local nextLevel
  for _, l in ipairs({ book and book.nextLevel or false, trainer and trainer.nextLevel or false }) do
    if l and l > level and (not nextLevel or l < nextLevel) then nextLevel = l end
  end
  local count
  if trainer and trainer.level == level and trainer.left then
    count = trainer.left -- seen at the trainer this level: the most exact source
  elseif book then
    count = book.ready
  elseif trainer and trainer.nextLevel and level >= trainer.nextLevel then
    return "New spells unlocked: visit your class trainer.", nextLevel
  end
  if count and count > 0 then
    return string.format("Learn %d new spell%s at your class trainer.", count, count > 1 and "s" or ""), nextLevel
  end
  return nil, nextLevel
end

-- Unfinished objectives, one per line, for tooltips.
local function objectiveLines(q)
  local lines = {}
  for _, o in ipairs(q.objectives or {}) do
    if o.need and o.need > 0 and (o.have or 0) < o.need and o.text ~= "" then table.insert(lines, o.text) end
  end
  return lines
end

-- Every objective with its status, done ones first marked with a check: what's finished and what's left.
-- Returns formatted lines, or nil when the quest has no objectives.
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
function QT.Checklist(q)
  local lines = {}
  for _, o in ipairs(q.objectives or {}) do
    if o.text and o.text ~= "" then
      local done = o.need and o.need > 0 and (o.have or 0) >= o.need
      table.insert(lines, done and (CHECK .. colored("ffc8c8c8", o.text)) or ("- " .. o.text))
    end
  end
  return #lines > 0 and lines or nil
end

-- Angle from Questie's map library (radians, 0 = north, counter-clockwise) -> compass word.
local COMPASS = { "N", "NW", "W", "SW", "S", "SE", "E", "NE" }
function QT.Compass(angle)
  return COMPASS[math.floor((angle % (2 * math.pi)) / (math.pi / 4) + 0.5) % 8 + 1]
end

-- Running speed on foot. shortcut: straight-line time; real paths around hills and rivers take longer.
QT.RUN_SPEED = 7
function QT.Travel(yards)
  local s = yards / QT.RUN_SPEED
  if s < 60 then return "<1 min" end
  return string.format("~%d min", math.floor(s / 60 + 0.5))
end

local function elsewhere(loc, player)
  return loc.zone and player and player.zone and loc.zone ~= player.zone
end

-- Right-hand column: "~2 min NW", "<1 min", "here", or the zone name when the distance is unknown.
function QT.Short(loc)
  if not loc then return nil end
  if not loc.yards then return loc.zone end
  if loc.yards <= 25 then return "here" end
  return QT.Travel(loc.yards) .. (loc.dir and (" " .. loc.dir) or "")
end

-- Full form for the Next card: "Rezlak · ~2 min NW" or "The Barrens · ~6 min W".
function QT.Where(loc, player)
  if not loc then return nil end
  local parts = {}
  if elsewhere(loc, player) then table.insert(parts, loc.zone) end
  local short = loc.yards and QT.Short(loc)
  if short then table.insert(parts, short) end
  return #parts > 0 and table.concat(parts, " · ") or nil
end

-- Straight-line yards between two locs, when both have world coordinates on the same continent.
local function between(a, b)
  if a and b and a.wx and b.wx and a.inst == b.inst then
    return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2)
  end
end

-- Hearthstone: worth setting at the inn you're near when it's set somewhere far away.
-- bind = { name = GetBindLocation(), wx, wy, inst }: the position is learned (written into bind) the first time
-- you stand at that inn. Until then it only speaks at an inn, where the zone name settles it (the game's own check).
-- inn = nearest friendly innkeeper loc with yards; zoneText = GetMinimapZoneText(). Returns a row or nil.
QT.INN_NEAR = 300    -- yards: you're in this inn's town
QT.INN_AT = 60       -- yards: you're at the inn
QT.HEARTH_FAR = 1000 -- yards: a bind closer than this is fine
function QT.HearthTip(bind, inn, zoneText)
  if not (bind and bind.name and inn and inn.yards and inn.yards <= QT.INN_NEAR) then return nil end
  if not bind.wx and inn.yards <= QT.INN_AT and bind.name == zoneText then
    bind.wx, bind.wy, bind.inst = inn.wx, inn.wy, inn.inst
  end
  if bind.wx then
    local d = between(bind, inn)
    if d and d <= QT.HEARTH_FAR then return nil end
  elseif inn.yards > QT.INN_AT or bind.name == zoneText then
    return nil
  end
  return { style = "item", icon = "hearth", kind = "goto", loc = inn,
    hearth = (inn.name or "?") .. "|" .. (inn.zone or ""),
    text = "Set your hearthstone here (now " .. bind.name .. ")",
    tip = { "Talk to " .. (inn.name or "the innkeeper") .. " and choose \"Make this inn your home\".",
      "Your hearthstone then brings you back to this town." } }
end

-- What a quest giver actually offers beats Questie's guess. starters = { [questID] = { npcID, ... } } for the
-- quests Questie says you can pick up; offered = { [questID] = true } from the NPC you're talking to.
-- Quests this NPC gives but didn't offer are marked in notOffered; ones it does offer are cleared.
function QT.MarkOffered(starters, npcID, offered, notOffered)
  for questID, npcs in pairs(starters) do
    for _, id in ipairs(npcs) do
      if id == npcID then notOffered[questID] = (not offered[questID]) or nil end
    end
  end
end

-- Quests you can pick up, grouped by giver: nearest first, then closest to your level.
-- Only ones worth doing now: required level met, not grey, at most MAX_LEVELS_ABOVE over you.
-- pickups (from Guide.lua): { questID, title, level, requiredLevel, isGroup, giver = loc }; hidden = { [questID] = true }
function QT.PickupGroups(pickups, player, hidden)
  local groups, byKey = {}, {}
  local low = player.level - (player.greenRange or 5)
  for _, p in ipairs(pickups or {}) do
    local lvl = p.level or player.level
    local ok = (p.requiredLevel or 0) <= player.level and lvl >= low and lvl <= player.level + QT.MAX_LEVELS_ABOVE
      and not (hidden and hidden[p.questID])
    if ok and p.giver then
      local key = (p.giver.name or "?") .. "|" .. (p.giver.zone or "")
      local g = byKey[key]
      if not g then g = { key = key, giver = p.giver, quests = {} }; byKey[key] = g; table.insert(groups, g) end
      table.insert(g.quests, p)
    end
  end
  local function fit(g)
    local best = 99
    for _, p in ipairs(g.quests) do best = math.min(best, math.abs((p.level or player.level) - player.level)) end
    return best
  end
  for _, g in ipairs(groups) do
    table.sort(g.quests, function(a, b) return (a.level or 0) < (b.level or 0) end)
    g.fit = fit(g)
  end
  table.sort(groups, function(a, b)
    local da, db = a.giver.yards or 1e9, b.giver.yards or 1e9
    if da ~= db then return da < db end
    return a.fit < b.fit
  end)
  return groups
end

local function pickupText(g)
  local q = g.quests
  if #q == 1 then
    -- Objects often share the quest's name ("Flawed Power Stone"): don't say it twice.
    return "Pick up " .. q[1].title .. ((g.giver.name and g.giver.name ~= q[1].title) and (" from " .. g.giver.name) or "")
  end
  return string.format("Pick up %d quests from %s", #q, g.giver.name or "?")
end

local function pickupTip(g)
  local tip = {}
  for _, p in ipairs(g.quests) do
    table.insert(tip, string.format("[%d] %s%s", p.level or 0, p.title or "?", p.isGroup and "  (group)" or ""))
  end
  return tip
end

-- Leveling styles (Options): "batch" grabs every quest near you before leaving a hub and does quests whose
-- objectives sit together in one trip; "single" finishes one quest, hands it in, then picks up the next.
QT.HUB_RADIUS = 250   -- yards: "here" for pickups and hand-ins
QT.CLUSTER_RADIUS = 400 -- yards: objectives this close count as one trip

-- While you're dead nothing else matters: release, run back, resurrect. Then the route resumes.
-- death = { ghost = bool, corpse = loc or nil }
local function deathStep(death)
  if not death.ghost then
    return { icon = "death", text = "Release your spirit", sub = "Then run back to your corpse" }
  end
  local c = death.corpse
  if c and c.yards and c.yards <= 40 then
    return { icon = "death", text = "Resurrect at your corpse", sub = "Accept the prompt on screen" }
  end
  return { icon = "death", text = "Run back to your corpse", kind = c and "goto" or nil, loc = c,
    sub = "Your quests wait until you're back" }
end

-- Once a step is the Next one it stays, unless another becomes much better (costs less than half).
QT.STICKY = 0.5

-- Slow spawns, measured from your own progress: after SLOW_AFTER seconds in a quest's area, fewer than one
-- objective tick per SLOW_RATE seconds counts as slow. Looks back at most 15 minutes.
QT.SLOW_AFTER = 300
QT.SLOW_RATE = 240
QT.SLOW_PENALTY = 800 -- a slow spot costs as much as walking 800 yd, so nearby work goes first
-- Spawn areas (from Guide.lua): { {loc, density = spawn points in and around it, dist = yards from you}, ... }

-- Where to hunt: the nearest area with real density. A lone stray spawn at the edge of a zone is ignored;
-- quests with only a few spawns (named mobs) can use any of them. Returns an area or nil.
function QT.PickHuntingArea(list)
  if not list or #list == 0 then return nil end
  local top = 0
  for _, a in ipairs(list) do top = math.max(top, a.density) end
  local floor = top >= 3 and math.max(3, top * 0.3) or top
  local best
  for _, a in ipairs(list) do
    if a.density >= floor and (not best or a.dist < best.dist) then best = a end
  end
  return best
end

-- For slow spawns: the densest area within SPOT_RANGE yards, if it's clearly better than where you stand
-- (at least 1.5x and 3 more spawn points). Returns area, densityHere; or nil, densityHere.
QT.SPOT_RANGE = 2000
function QT.PickBetterSpot(list)
  local here, best = 0, nil
  for _, a in ipairs(list or {}) do
    if a.dist <= 250 then
      here = math.max(here, a.density)
    elseif a.dist <= QT.SPOT_RANGE and (not best or a.density > best.density
        or (a.density == best.density and a.dist < best.dist)) then
      best = a
    end
  end
  if not best or best.density < math.max(here * 1.5, here + 3) then return nil, here end
  return best, here
end

-- track = { enteredAt = when you arrived in the area, gains = { times objective progress went up } }
-- Returns { minutes, gains } when progress is slow, else nil.
function QT.SlowCheck(track, now)
  if not (track and track.enteredAt) then return nil end
  local window = math.min(now - track.enteredAt, 900)
  if window < QT.SLOW_AFTER then return nil end
  local n = 0
  for _, t in ipairs(track.gains or {}) do
    if t >= now - window then n = n + 1 end
  end
  if n * QT.SLOW_RATE >= window then return nil end
  return { minutes = math.floor(window / 60 + 0.5), gains = n }
end

-- The best things to do right now. Returns the ranked list of actions and a list of short reminders:
-- action = { icon, text, sub, loc, kind = "equip"|"quest"|"goto"|nil, data, tip, questID, giverKey, xp, key }
-- Quick fixes (repair, equip) first, then route steps ranked by cost (distance, weighted by style).
-- A quest you can't finish yet is replaced by the step that unblocks it.
-- power: { bagUpgrade, train = text, durability, freeSlots, junk }; groups = QT.PickupGroups.
-- opts: { style = "batch"|"single", committed = key of the current Next step, death = see deathStep }
function QT.BestActions(buckets, power, player, groups, opts)
  opts = opts or {}
  local batch = opts.style ~= "single"
  local acts, reminders = {}, {}
  local function add(a) table.insert(acts, a) end
  if opts.death then add(deathStep(opts.death)) end
  local d = power.durability
  local r = power.repairAt -- nearest repair vendor, when gear is low
  if d and d == 0 then
    add({ icon = "repair", text = "Repair your gear", kind = r and "goto" or nil, loc = r,
      sub = "Broken gear gives you no stats" .. (r and r.name and (" · at " .. r.name) or "") })
  end
  local up = power.bagUpgrade
  if up then
    add({ icon = "equip", text = "Equip " .. up.name, kind = "equip", data = up.link,
      sub = up.change and (up.change .. " · already in your bags") or "Fills an empty slot" })
  end
  local bq = power.bagQuest
  if bq then
    add({ icon = "pickup", text = "Open " .. bq.name, kind = "bags", data = bq.link, questID = bq.questID,
      sub = "In your bags: right-click it to start its quest" })
  end
  if power.train then table.insert(reminders, power.train) end
  if d and d > 0 and d < 25 and not r then table.insert(reminders, string.format("Repair soon (gear at %d%%)", d)) end
  if power.freeSlots and power.freeSlots <= 2 then
    table.insert(reminders, power.junk and power.junk > 0 and string.format(power.autoSell and "%d grey items sell automatically at any vendor" or "Sell %d grey items", power.junk)
      or "Make room in your bags")
  end

  local function yards(loc) return loc and loc.yards or 1e6 end
  local near = function(loc) return loc and loc.yards and loc.yards <= QT.HUB_RADIUS end
  local hereCount = 0

  -- Where each unfinished quest sends you, for cluster counting.
  local targets = {}
  for _, e in ipairs(buckets.now) do
    local q = e.quest
    local b = q.blockers and q.blockers[1]
    table.insert(targets, (b and b.loc) or q.loc or false)
  end
  -- Other unfinished quests whose objectives are within one trip of loc: count and names.
  local function neighbours(loc, self)
    local n, names = 0, {}
    for i, other in ipairs(targets) do
      local dist = i ~= self and other and between(loc, other)
      if dist and dist <= QT.CLUSTER_RADIUS then
        n = n + 1
        table.insert(names, buckets.now[i].quest.title)
      end
    end
    return n, names
  end
  local inside = {} -- quests whose game-drawn area you're standing in

  local route = {}
  local function step(cost, a)
    if a.key and a.key == opts.committed then
      a.cost = cost * QT.STICKY
      a.committed = true
    else
      a.cost = cost
    end
    table.insert(route, a)
  end
  -- "+ i" keeps ties in list order, so the advice doesn't flicker between equal steps.
  for i, e in ipairs(buckets.turnin) do
    local q = e.quest
    local w = batch and (near(q.loc) and 0.3 or 1.0) or 0.6
    if near(q.loc) then hereCount = hereCount + 1 end
    step(yards(q.loc) * w + i, { icon = "turnin", text = "Hand in " .. q.title, kind = "quest", data = q.questID,
      questID = q.questID, key = "end:" .. tostring(q.questID), loc = q.loc, xp = q.xp, sub = q.loc and q.loc.name and ("to " .. q.loc.name) or nil })
  end
  -- One at a time: no new quests while you still have one to finish.
  local wait = (not batch and #buckets.now > 0) and 5e6 or 0
  for i, g in ipairs(groups or {}) do
    local w = batch and (near(g.giver) and 0.3 or 1.2) or 0.7
    if near(g.giver) then hereCount = hereCount + 1 end
    step(yards(g.giver) * w + wait + i, { icon = "pickup", text = pickupText(g), kind = "goto", loc = g.giver, tip = pickupTip(g),
      giverKey = g.key, key = "pick:" .. g.key, sub = #g.quests > 1 and "Quests at your level" or nil })
  end
  for i, e in ipairs(buckets.now) do
    local q = e.quest
    local b = q.blockers and q.blockers[1]
    local p = QT.Progress(q)
    if b then
      step(yards(b.loc) + i, { icon = "blocker", text = b.text .. " first",
        sub = (b.how and (b.how .. " · ") or "") .. "needed for " .. q.title,
        key = "need:" .. tostring(q.questID), pinQuestID = q.questID,
        thenLoc = q.loc, thenTitle = "Complete " .. q.title .. " here",
        kind = b.loc and "goto" or "quest", data = q.questID, loc = b.loc, giverKey = b.loc and b.loc.name and
        (b.loc.name .. "|" .. (b.loc.zone or "")), tip = { "You can't finish " .. q.title .. " without this." } })
    elseif q.slow then
      -- You've been here a while with little to show: a denser spot, or do something else and come back.
      local s = q.slow
      local slowText = string.format("Slow here: only %d in %d min", s.gains, s.minutes)
      local alt = q.altLoc
      if alt then
        step(yards(alt) + i, { icon = "objective", text = "Try another spot for " .. q.title, kind = "goto",
          questID = q.questID, key = "alt:" .. tostring(q.questID), loc = alt, qlevel = q.level, xp = q.xp,
          sub = string.format("%s · %d spawn points there vs %d here", slowText, alt.spawns or 0, alt.hereSpawns or 0),
          tip = objectiveLines(q) })
      else
        step(QT.SLOW_PENALTY + yards(q.loc) + i, { icon = "objective", text = "Go do " .. q.title, kind = "quest",
          data = q.questID, questID = q.questID, key = "do:" .. tostring(q.questID), loc = q.loc, xp = q.xp,
          qlevel = q.level, sub = slowText .. " · do something nearby and come back", tip = objectiveLines(q) })
      end
    elseif q.inArea then
      table.insert(inside, e) -- handled together below
    else
      local obj = objectiveLines(q)
      local n, names = 0, {}
      if batch then n, names = neighbours(q.loc, i) end
      -- Momentum: a quest you've started costs less, so you finish it before starting fresh ones.
      local cost = (batch and yards(q.loc) / (1 + n) or yards(q.loc)) * (1 - (batch and 0.6 or 0.7) * p)
      local sub = (not q.loc and q.zone) or nil -- objectives show as a checklist on the card
      if n > 0 then
        sub = (sub and (sub .. " · ") or "") .. (n <= 2 and ("same trip: " .. table.concat(names, ", "))
          or string.format("%d more quests nearby", n))
      end
      step(cost + i, { icon = "objective", text = "Go do " .. q.title, kind = "quest", data = q.questID,
        questID = q.questID, key = "do:" .. tostring(q.questID), loc = q.loc, xp = q.xp, sub = sub, tip = obj, checklist = QT.Checklist(q),
        qlevel = q.level })
    end
  end
  -- Standing inside the game's own quest area (the white boundary on the minimap): do it right here.
  -- Nothing beats that, so it costs nothing and never points you somewhere else. Several areas overlapping
  -- become one step listing everything you can do on the spot.
  if #inside > 0 then
    local first, ids, idList, parts, tip, xp, lvl = inside[1].quest, {}, {}, {}, {}, 0, 0
    for _, e in ipairs(inside) do
      local q = e.quest
      local obj = objectiveLines(q)
      ids[q.questID or false] = true
      table.insert(idList, tostring(q.questID))
      table.insert(parts, #inside == 1 and "" or (q.title .. (obj[1] and (" (" .. obj[1] .. ")") or "")))
      table.insert(tip, q.title .. ((#obj > 0) and (": " .. table.concat(obj, ", ")) or ""))
      xp, lvl = xp + (q.xp or 0), math.max(lvl, q.level or 0)
    end
    table.sort(idList)
    local detail = table.concat(parts, " · ")
    step(0.01, { icon = "objective", here = true, loc = first.loc, xp = xp, qlevel = lvl, tip = tip,
      text = #inside == 1 and ("Do " .. first.title .. " here") or string.format("Do %d quests here", #inside),
      sub = "You're in the area" .. (detail ~= "" and (" · " .. detail) or ""),
      kind = "quest", data = first.questID, questID = first.questID, questIDs = ids, checklist = #inside == 1 and QT.Checklist(first) or nil,
      key = #inside == 1 and ("do:" .. tostring(first.questID)) or ("area:" .. table.concat(idList, ",")) })
  end
  table.sort(route, function(a, b) return a.cost < b.cost end)

  -- In batch mode, say how much is left to grab here before moving on.
  local first = route[1]
  if batch and first and near(first.loc) and hereCount > 1 then
    first.sub = (first.sub and (first.sub .. " · ") or "") .. string.format("%d more to do here", hereCount - 1)
  end
  for _, a in ipairs(route) do add(a) end
  if #acts == 0 then
    if #buckets.group > 0 then
      local q = buckets.group[1].quest
      add({ icon = "group", text = "Find a group for " .. q.title, sub = "Ask in chat", kind = "quest", data = q.questID,
        questID = q.questID })
    else
      add({ icon = "pickup", text = "Pick up new quests", sub = "Look for a yellow ! on your map" })
    end
  end
  return acts, reminders
end

-- How far your current quests take you. player: { xp, xpMax }. Returns nil when the game gave no XP data.
function QT.XPSummary(buckets, player)
  local total = 0
  for _, id in ipairs({ "turnin", "now" }) do
    for _, e in ipairs(buckets[id]) do total = total + (e.quest.xp or 0) end
  end
  if total == 0 or not player.xpMax or player.xpMax == 0 then return nil end
  local need = player.xpMax - (player.xp or 0)
  if total >= need then return "Your quests are enough to level up." end
  return string.format("Your quests cover %d%% of this level.", math.floor(total / need * 100))
end

-- Short tag after a quest name, only when it matters.
local function questTag(bucket, q, backAt)
  if bucket == "drop" then
    return q.isFailed and colored("ffff7a7a", "failed") or colored("ffb8b8b8", "grey")
  end
  if bucket == "later" then
    return colored("ffffa060", (backAt and ("at level " .. backAt)) or (q.deferred and "saved") or ("at level " .. (q.level or 0)))
  end
  local tags = {}
  if q.blockers and q.blockers[1] then table.insert(tags, colored("ffff7a7a", "needs item")) end
  if q.slow then table.insert(tags, colored("ffffa060", "slow")) end
  if q.upgrade then table.insert(tags, colored("ff40ff40", "gear")) end
  return table.concat(tags, " ")
end

-- Before you attack: is this target safe for you? Uses only what the game lets addons read.
-- Your health is hidden from addons on Forever, so risky fights always say "start at full health" rather than
-- guessing how full you are. Mana is readable out of combat.
-- t = { name, level (-1 = skull), classification, canAttack, dead }; me = { level, manaPct (nil = unknown) }
function QT.FightCheck(t, me)
  if not t or not t.canAttack or t.dead or not t.level then return nil end
  local cls = t.classification or "normal"
  local name = t.name or "Your target"
  if t.level == -1 or cls == "worldboss" then
    return colored("ffff7a7a", name .. ": far too strong. Leave it.")
  end
  local diff = t.level - me.level
  local elite = cls == "elite" or cls == "rareelite"
  local verdict, color
  if elite then
    verdict, color = string.format("elite (level %d), needs a group", t.level), "ffff7a7a"
  elseif diff >= 3 then
    verdict, color = string.format("level %d (+%d), very risky alone", t.level, diff), "ffff7a7a"
  elseif diff == 2 then
    verdict, color = string.format("level %d (+2), risky: you'll miss more and it hits harder", t.level), "ffffa060"
  elseif diff == 1 then
    verdict, color = string.format("level %d (+1), a bit tougher", t.level), "ffffd100"
  elseif cls == "rare" then
    verdict, color = "rare, tougher than a normal mob", "ffffd100"
  end
  local tips = {}
  if verdict and not elite and diff >= 1 then table.insert(tips, "pull it alone and start at full health") end
  if me.manaPct and me.manaPct < 60 and (verdict or diff >= 0) then
    table.insert(tips, string.format("drink first (mana %d%%)", me.manaPct))
  end
  if not verdict and #tips == 0 then return nil end
  local text = name .. ": " .. (verdict or string.format("level %d", t.level))
  if #tips > 0 then
    local t1 = table.concat(tips, ", ")
    text = text .. ". " .. t1:sub(1, 1):upper() .. t1:sub(2) .. "."
  end
  return colored(color or "ffffd100", text)
end

-- Everything the panel shows, as rows:
-- { style = "hero"|"alert"|"note"|"header"|"zone"|"item"|"more", icon, text, sub, right, progress, kind, data, loc, tip, pin, questID }
-- kind: "quest" (data = questID), "goto", "equip" (data = item link), "toggle" (data = section id), nil = not clickable.
-- Nothing is listed twice: the Next step's quest or giver is left out of the lists below.
-- opts = { expanded = { [sectionId] = bool }, style, committed, death } (see BestActions). groups = QT.PickupGroups (optional).
function QT.BuildRows(buckets, player, power, opts, groups)
  opts = opts or {}
  local expanded = opts.expanded or {}
  local rows = {}
  local function add(r) table.insert(rows, r) end

  local acts, reminders = QT.BestActions(buckets, power, player, groups, opts)
  local nextStep = acts[1]
  do
    local a = nextStep
    local meta = {}
    -- Heading to a quest above your level: say how to prepare, from what we actually know.
    local over = a.qlevel and (a.qlevel - player.level) or 0
    if over >= QT.MAX_LEVELS_ABOVE then
      local prep = {}
      if power.train then table.insert(prep, "train") end
      if power.durability and power.durability < 50 then table.insert(prep, "repair") end
      table.insert(meta, string.format("Hard (+%d): %sstart at full health", over,
        #prep > 0 and (table.concat(prep, " and ") .. " first, ") or ""))
    end
    if a.sub then table.insert(meta, a.sub) end
    -- Inside a quest area the location is the nearest spawn of what you need, so point at it.
    local where = a.here and a.loc and a.loc.yards and (a.loc.yards <= 25 and "one right next to you" or ("nearest " .. QT.Short(a.loc))) or (not a.here and QT.Where(a.loc, player)) or nil
    if where then table.insert(meta, where) end
    local need = player.xpMax and player.xpMax > 0 and (player.xpMax - (player.xp or 0))
    if a.xp and a.xp > 0 and need and need > 0 then
      table.insert(meta, string.format("+%d%% of level", math.max(1, math.floor(a.xp / need * 100 + 0.5))))
    end
    add({ style = "hero", icon = a.icon, text = a.text, sub = #meta > 0 and table.concat(meta, "  ·  ") or nil,
      kind = a.kind, data = a.data, loc = a.loc, tip = a.tip, questID = a.questID, key = a.key, pinQuestID = a.pinQuestID, thenLoc = a.thenLoc, thenTitle = a.thenTitle, checklist = a.checklist,
      yards = a.loc and a.loc.yards, here = a.here, qlevel = a.qlevel })
  end
  local fight = opts.fight and QT.FightCheck(opts.fight, { level = player.level, manaPct = opts.manaPct })
  if fight then add({ style = "alert", icon = "blocker", text = fight }) end
  local dur, rep = power.durability, power.repairAt
  if dur and dur > 0 and dur < 25 and rep then
    add({ style = "item", icon = "repair", kind = "goto", loc = rep, right = QT.Short(rep),
      text = string.format("Repair soon (gear at %d%%): %s", dur, rep.name or "nearest vendor"),
      tip = { "Nearest repair vendor: " .. (rep.name or "?") .. (rep.zone and (", " .. rep.zone) or "") } })
  end
  if opts.hearth then add(opts.hearth) end
  if #reminders > 0 then add({ style = "note", text = "Also: " .. table.concat(reminders, " · ") }) end
  local xp = QT.XPSummary(buckets, player)
  if xp then add({ style = "note", text = xp }) end

  local function section(id, label, color, items, limit)
    if #items == 0 then return end
    local foldable = limit ~= nil and #items > limit
    local open = foldable and expanded[id] or not foldable
    local shown = open and #items or limit
    local mark = foldable and (open and "[-] " or "[+] ") or ""
    add({ style = "header", text = colored(color, mark .. label), right = tostring(#items),
      kind = foldable and "toggle" or nil, data = id })
    -- A zone heading is only shown together with its first visible quest.
    local count, zone = 0, nil
    for _, it in ipairs(items) do
      if it.style == "zone" then
        zone = it
      else
        count = count + 1
        if count > shown then break end
        if zone then add(zone); zone = nil end
        add(it)
      end
    end
    if shown < #items and shown > 0 then
      local quests = 0
      for _, it in ipairs(items) do if it.style ~= "zone" then quests = quests + 1 end end
      if quests > shown then
        add({ style = "more", text = string.format("+%d more", quests - shown), kind = "toggle", data = id })
      end
    end
  end

  local function questRow(b, e)
    local q = e.quest
    local tag = questTag(b.id, q, e.backAt)
    local tip = QT.Checklist(q) or {}
    -- A blocked quest's reason is "First: …", which the blocker line below already says (with where and how).
    if e.reason ~= "" and not (b.id == "now" and q.blockers and q.blockers[1]) then table.insert(tip, e.reason) end
    if q.xp and q.xp > 0 then table.insert(tip, commas(q.xp) .. " XP") end
    local loc = (b.id ~= "later" and b.id ~= "drop") and q.loc or nil
    local function place(l)
      return (l.name or "?") .. (l.zone and (", " .. l.zone) or "") .. (l.x and string.format(" %.1f, %.1f", l.x, l.y) or "")
        .. (l.yards and string.format(" (%s yd)", commas(l.yards)) or "")
    end
    if loc then table.insert(tip, 1, (b.id == "turnin" and "Hand in to " or "Go to ") .. place(loc)) end
    -- Blocked: the row points where to get what's missing, not at the quest area you can't finish yet.
    local blocker = b.id == "now" and q.blockers and q.blockers[1]
    local thenLoc, thenTitle -- blocked: the second stop, where the quest is completed once you have the item
    if blocker then
      table.insert(tip, 1, "First: " .. blocker.text .. (blocker.how and (". " .. blocker.how) or "")
        .. (blocker.loc and (" at " .. place(blocker.loc)) or ""))
      local questLoc = loc
      if blocker.loc then loc = blocker.loc end
      thenLoc, thenTitle = blocker.loc and questLoc, "Complete " .. (q.title or "the quest") .. " here"
    end
    local lvl = string.format("[%d]", q.level or 0)
    local p = QT.Progress(q)
    return { style = "item", icon = (q.blockers and q.blockers[1]) and "blocker" or nil,
      text = (q.color and colored(q.color, lvl) or lvl) .. " " .. (q.title or "?") .. (tag ~= "" and ("  " .. tag) or ""),
      right = (q.inArea and not blocker and loc) and "here" or QT.Short(loc), progress = (b.id == "now" or b.id == "group") and p > 0 and p or nil,
      kind = "quest", data = q.questID, questID = q.questID, loc = loc, tip = tip, drop = b.id == "drop",
      pin = b.id == "turnin" and "turnin" or blocker and "blocker" or "objective", thenLoc = thenLoc, thenTitle = thenTitle,
      retry = b.id == "later" and q.deaths and q.deaths.count >= QT.DEATHS_BEFORE_LATER or nil,
      saved = (b.id == "later" and q.deferred) and true or nil, qlevel = q.level }
  end

  local total = 0
  for _, b in ipairs(QT.BUCKETS) do
    local list = {}
    for _, e in ipairs(buckets[b.id]) do
      total = total + 1
      local id = e.quest.questID
      local shown = id ~= nil and (id == nextStep.questID or (nextStep.questIDs and nextStep.questIDs[id]))
      if not shown then table.insert(list, e) end
    end
    local items = {}
    if b.id == "now" then
      -- Grouped by where the objective is; zones in order of their nearest quest, nearest first inside.
      local rank = {}
      for i, e in ipairs(list) do rank[e] = i end
      table.sort(list, function(x, y)
        local function d(e) return e.quest.inArea and 0 or (e.quest.loc and e.quest.loc.yards) or 1e9 end
        local dx, dy = d(x), d(y)
        if dx ~= dy then return dx < dy end
        return rank[x] < rank[y]
      end)
      local byZone, order = {}, {}
      for _, e in ipairs(list) do
        local z = (e.quest.loc and e.quest.loc.zone) or e.quest.zone or "Other"
        if not byZone[z] then byZone[z] = {}; table.insert(order, z) end
        table.insert(byZone[z], e)
      end
      for _, z in ipairs(order) do
        if #order > 1 then -- zone headings only help when there is more than one
          table.insert(items, { style = "zone", text = z .. ((player.zone == z) and "  (you are here)" or "") })
        end
        for _, e in ipairs(byZone[z]) do table.insert(items, questRow(b, e)) end
      end
    else
      for _, e in ipairs(list) do table.insert(items, questRow(b, e)) end
    end
    section(b.id, b.label, b.color, items, b.limit)

    -- Quests you haven't picked up yet sit right after "Do now": nearest givers first.
    if b.id == "now" and groups and #groups > 0 then
      local pick = {}
      for _, g in ipairs(groups) do
        if g.key ~= nextStep.giverKey then
          local single = #g.quests == 1 and g.quests[1]
          table.insert(pick, { style = "item", icon = "pickup", kind = "goto", loc = g.giver, tip = pickupTip(g),
            text = single and string.format("[%d] %s", single.level or 0, single.title or "?")
              or string.format("%s  %s", g.giver.name or "?", colored("ffc8c8c8", #g.quests .. " quests")),
            right = QT.Short(g.giver), questID = single and single.questID or nil })
        end
      end
      section("pickup", "Pick up", "ffffffff", pick, 3)
    end
  end
  if total == 0 then
    add({ style = "note", text = "Your quest log is empty. Pick up quests at your level (yellow ! on the map)." })
  end
  return rows
end

-- Feedback: did following the advice work? history = { [questID] = { bucket, accepted, finished, result = "done"|"dropped" } }
function QT.Stats(history)
  local s = { done = 0, dropped = 0, minutes = 0, timed = 0, followed = 0, judged = 0 }
  for _, h in pairs(history) do
    if h.result == "done" then
      s.done = s.done + 1
      if h.accepted and h.finished then
        s.timed = s.timed + 1
        s.minutes = s.minutes + (h.finished - h.accepted) / 60
      end
    elseif h.result == "dropped" then
      s.dropped = s.dropped + 1
    end
    if h.result and h.bucket then
      s.judged = s.judged + 1
      -- Advice matched if you finished something we didn't call drop/later, or dropped what we called drop.
      local good = (h.result == "done" and h.bucket ~= "drop" and h.bucket ~= "later")
        or (h.result == "dropped" and h.bucket == "drop")
      if good then s.followed = s.followed + 1 end
    end
  end
  s.avgMinutes = s.timed > 0 and s.minutes / s.timed or nil
  return s
end

function QT.FormatStats(s)
  local lines = { string.format("Finished %d quests, dropped %d.", s.done, s.dropped) }
  if s.avgMinutes then
    table.insert(lines, string.format("Average time from pick-up to hand-in: %d min.", math.floor(s.avgMinutes + 0.5)))
  end
  if s.judged > 0 then
    table.insert(lines, string.format("Matched Quest Triage's advice: %d of %d (%d%%).",
      s.followed, s.judged, math.floor(s.followed / s.judged * 100)))
  end
  return lines
end

_G.QuestTriage = QT
return QT
