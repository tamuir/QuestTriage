-- Quest Triage: pure decision logic. No WoW API calls in this file,
-- so it can be tested outside the game.
local _, QT = ...
QT = QT or {}

-- Bucket ids, in the order they are shown. limit = rows shown before folding (nil = all).
QT.BUCKETS = {
  { id = "turnin", label = "Turn in",           color = "ff40ff40" },
  { id = "now",    label = "Do now",            color = "ffffd100", limit = 5 },
  { id = "group",  label = "Needs a group",     color = "ff66b3ff" },
  { id = "later",  label = "Save for later",    color = "ffff8040", limit = 0 },
  { id = "drop",   label = "Drop",              color = "ff9d9d9d", limit = 0 },
}

-- How far above you a quest can be before we call it "later".
QT.MAX_LEVELS_ABOVE = 2

local function lower(s) return string.lower(s or "") end
local function colored(hex, text) return "|c" .. hex .. text .. "|r" end

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
-- q: { title, level, questID, zone, isComplete, isFailed, suggestedGroup, tag, xp, upgrade, objectives = {{text, have, need}} }
-- player: { level, greenRange, zone }  greenRange = levels below you that still give decent XP
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
  if isGroupQuest(q) then
    if diff > QT.MAX_LEVELS_ABOVE + 2 then
      return "later", string.format("Group quest, level %d. Come back at %d with a group.", ql, ql - 2)
    end
    return "group", "Dungeon or elite. Look for a group in chat."
  end
  if diff > QT.MAX_LEVELS_ABOVE then
    return "later", string.format("Too hard now. Come back at level %d.", ql - QT.MAX_LEVELS_ABOVE)
  end
  if diff == QT.MAX_LEVELS_ABOVE then
    return "now", "Hard: pull one mob at a time."
  end
  return "now", ""
end

-- up: { name, gain, slot }  gain = item levels over what you wear there (nil = slot is empty).
function QT.UpgradeNote(up)
  if up.gain then return string.format("+%d item level, %s", up.gain, up.slot) end
  return string.format("fills your empty %s slot", up.slot)
end

-- q.blockers (optional, from Guide.lua): { {text = "Pick up Flawed Power Stone", loc}, ... } = what's missing to finish it.
function QT.Classify(q, player)
  local bucket, reason = classifyBase(q, player)
  if bucket == "now" and q.blockers and q.blockers[1] then
    reason = "First: " .. q.blockers[1].text .. "." .. (reason ~= "" and (" " .. reason) or "")
  end
  local up = q.upgrade
  if not up or q.isFailed then return bucket, reason end
  local note = "Gear upgrade: " .. up.name .. " (" .. QT.UpgradeNote(up) .. ")."
  if bucket == "drop" then
    return "now", "Grey, but worth it. " .. note
  end
  return bucket, reason == "" and note or (reason .. " " .. note)
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
    local bucket, reason = QT.Classify(q, player)
    table.insert(out[bucket], { quest = q, reason = reason, key = sortKey(bucket, q, player) })
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
  if d and d == 0 then add({ icon = "repair", text = "Repair your gear", sub = "Broken gear gives you no stats." }) end
  local up = power.bagUpgrade
  if up then
    add({ icon = "equip", text = "Equip " .. up.name, kind = "equip", data = up.link,
      sub = up.gain and string.format("+%d item level, already in your bags", up.gain) or "Fills an empty slot" })
  end
  if power.train then table.insert(reminders, power.train) end
  if d and d > 0 and d < 25 then table.insert(reminders, string.format("Repair soon (gear at %d%%)", d)) end
  if power.freeSlots and power.freeSlots <= 2 then
    table.insert(reminders, power.junk and power.junk > 0 and string.format("Sell %d grey items", power.junk)
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
  local function neighbours(loc, self)
    local n = 0
    for i, other in ipairs(targets) do
      local dist = i ~= self and other and between(loc, other)
      if dist and dist <= QT.CLUSTER_RADIUS then n = n + 1 end
    end
    return n
  end

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
      step(yards(b.loc) + i, { icon = "blocker", text = b.text .. " first", sub = "You need it for " .. q.title,
        key = "need:" .. tostring(q.questID),
        kind = b.loc and "goto" or "quest", data = q.questID, loc = b.loc, giverKey = b.loc and b.loc.name and
        (b.loc.name .. "|" .. (b.loc.zone or "")), tip = { "You can't finish " .. q.title .. " without this." } })
    else
      local obj = objectiveLines(q)
      local n = batch and neighbours(q.loc, i) or 0
      -- Momentum: a quest you've started costs less, so you finish it before starting fresh ones.
      local cost = (batch and yards(q.loc) / (1 + n) or yards(q.loc)) * (1 - (batch and 0.6 or 0.7) * p)
      local sub = obj[1] or (not q.loc and q.zone) or nil
      if n > 0 then sub = (sub and (sub .. " · ") or "") .. string.format("%d more quest%s nearby", n, n > 1 and "s" or "") end
      step(cost + i, { icon = "objective", text = "Go do " .. q.title, kind = "quest", data = q.questID,
        questID = q.questID, key = "do:" .. tostring(q.questID), loc = q.loc, xp = q.xp, sub = sub, tip = obj })
    end
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
local function questTag(bucket, q)
  if bucket == "drop" then
    return q.isFailed and colored("ffff5050", "failed") or colored("ff888888", "grey")
  end
  if bucket == "later" then
    local back = (q.level or 0) - (isGroupQuest(q) and 2 or QT.MAX_LEVELS_ABOVE)
    return colored("ffff8040", "at level " .. back)
  end
  local tags = {}
  if q.blockers and q.blockers[1] then table.insert(tags, colored("ffff5050", "needs item")) end
  if q.upgrade then table.insert(tags, colored("ff40ff40", "gear")) end
  return table.concat(tags, " ")
end

-- Everything the panel shows, as rows:
-- { style = "hero"|"note"|"header"|"zone"|"item"|"more", icon, text, sub, right, progress, kind, data, loc, tip, pin, questID }
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
    if a.sub then table.insert(meta, a.sub) end
    local where = QT.Where(a.loc, player)
    if where then table.insert(meta, where) end
    local need = player.xpMax and player.xpMax > 0 and (player.xpMax - (player.xp or 0))
    if a.xp and a.xp > 0 and need and need > 0 then
      table.insert(meta, string.format("+%d%% of level", math.max(1, math.floor(a.xp / need * 100 + 0.5))))
    end
    add({ style = "hero", icon = a.icon, text = a.text, sub = #meta > 0 and table.concat(meta, "  ·  ") or nil,
      kind = a.kind, data = a.data, loc = a.loc, tip = a.tip, questID = a.questID, key = a.key,
      yards = a.loc and a.loc.yards })
  end
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
    local tag = questTag(b.id, q)
    local tip = objectiveLines(q)
    if e.reason ~= "" then table.insert(tip, e.reason) end
    if q.xp and q.xp > 0 then table.insert(tip, commas(q.xp) .. " XP") end
    local loc = (b.id ~= "later" and b.id ~= "drop") and q.loc or nil
    if loc then
      table.insert(tip, 1, ((b.id == "turnin" and "Hand in to " or "Go to ") .. (loc.name or "?"))
        .. (loc.zone and (", " .. loc.zone) or "") .. (loc.yards and string.format(" (%s yd)", commas(loc.yards)) or ""))
    end
    local lvl = string.format("[%d]", q.level or 0)
    local p = QT.Progress(q)
    return { style = "item", icon = (q.blockers and q.blockers[1]) and "blocker" or nil,
      text = (q.color and colored(q.color, lvl) or lvl) .. " " .. (q.title or "?") .. (tag ~= "" and ("  " .. tag) or ""),
      right = QT.Short(loc), progress = (b.id == "now" or b.id == "group") and p > 0 and p or nil,
      kind = "quest", data = q.questID, questID = q.questID, loc = loc, tip = tip, drop = b.id == "drop",
      pin = b.id == "turnin" and "turnin" or "objective" }
  end

  local total = 0
  for _, b in ipairs(QT.BUCKETS) do
    local list = {}
    for _, e in ipairs(buckets[b.id]) do
      total = total + 1
      if e.quest.questID == nil or e.quest.questID ~= nextStep.questID then table.insert(list, e) end
    end
    local items = {}
    if b.id == "now" then
      -- Grouped by where the objective is; zones in order of their nearest quest, nearest first inside.
      local rank = {}
      for i, e in ipairs(list) do rank[e] = i end
      table.sort(list, function(x, y)
        local dx, dy = x.quest.loc and x.quest.loc.yards or 1e9, y.quest.loc and y.quest.loc.yards or 1e9
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
              or string.format("%s  %s", g.giver.name or "?", colored("ffaaaaaa", #g.quests .. " quests")),
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
