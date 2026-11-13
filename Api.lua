-- Quest Triage: reads the game's quest log into plain tables for Core.lua.
-- Supports both the classic quest log API (GetQuestLogTitle) and the newer
-- C_QuestLog API, because WoW: Forever's client may expose either.
local _, QT = ...

local function parseCount(text)
  if not text then return nil, nil end
  local have, need = text:match("(%d+)%s*/%s*(%d+)")
  if have then return tonumber(have), tonumber(need) end
  return nil, nil
end

local function questTag(questID)
  local fn = C_QuestLog and C_QuestLog.GetQuestTagInfo or GetQuestTagInfo
  if not questID or not fn then return nil end
  local ok, a, b = pcall(fn, questID)
  if not ok then return nil end
  if type(a) == "table" then return a.tagName end -- newer API returns a table
  return b -- classic: tagID, tagName
end

local function readClassic()
  local quests, header = {}, nil
  local n = GetNumQuestLogEntries()
  for i = 1, n do
    local title, level, suggestedGroup, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
    if isHeader then
      header = title
    elseif title then
      local q = {
        title = title, level = level, questID = questID, zone = header,
        suggestedGroup = tonumber(suggestedGroup) or 0,
        isComplete = (isComplete == 1 or isComplete == true),
        isFailed = (isComplete == -1),
        tag = questTag(questID),
        objectives = {},
      }
      local numObj = GetNumQuestLeaderBoards(i) or 0
      for j = 1, numObj do
        local text, _, finished = GetQuestLogLeaderBoard(j, i)
        local have, need = parseCount(text)
        if not have then have, need = (finished and 1 or 0), 1 end
        table.insert(q.objectives, { text = text or "", have = have, need = need })
      end
      table.insert(quests, q)
    end
  end
  return quests
end

-- Equipment slots each item type competes for.
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  -- shortcut: 1h weapons are compared to the main hand only; ignores dual wield. 2h: see upgradeOver.
  INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local SLOT_NAMES = { "head", "neck", "shoulders", nil, "chest", "waist", "legs", "feet", "wrists", "hands",
  "ring", "ring", "trinket", "trinket", "back", "main hand", "off hand", "ranged" }

-- Is this item better for your class than what you wear? Returns { name, link, score, change, slot } or nil.
-- Uses the item's real stats and an armor-type check (QT.GearUpgrade in Core.lua), not item level.
local STAT_LABELS = setmetatable({}, { __index = function(_, key) return _G[key] end }) -- the game's own names
local function upgradeOver(link)
  local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
  local slots = SLOTS[equipLoc]
  if not slots then return nil end
  local worn = {}
  for i, s in ipairs(slots) do
    local l = GetInventoryItemLink("player", s)
    worn[i] = l and (C_Item.GetItemStats(l) or {}) or false
  end
  -- A two-hander takes the off hand too: it has to beat your weapon and shield (or off-hand) together.
  local off = equipLoc == "INVTYPE_2HWEAPON" and GetInventoryItemLink("player", 17)
  if off then worn[1] = QT.AddStats(worn[1], C_Item.GetItemStats(off)) end
  local _, class = UnitClass("player")
  local up = QT.GearUpgrade({ stats = C_Item.GetItemStats(link) or {}, classID = classID, subClassID = subClassID,
    equipLoc = equipLoc }, worn, class, UnitLevel("player"), STAT_LABELS)
  if not up then return nil end
  return { name = link, link = link, score = up.score, change = up.change, slot = SLOT_NAMES[slots[up.index]] }
end

local function better(a, b) return a and (not b or a.score > b.score) end

-- Best gear upgrade among a quest's rewards, or nil.
function QT.BestUpgrade(questID)
  if not (GetQuestLogItemLink and C_Item and C_Item.GetItemStats) then return nil end
  local best
  for _, kind in ipairs({ "choice", "reward" }) do
    local count = kind == "choice" and GetNumQuestLogChoices(questID) or GetNumQuestLogRewards(questID)
    for i = 1, count or 0 do
      local quality, usable
      if kind == "choice" then _, _, _, quality, usable = GetQuestLogChoiceInfo(i, questID)
      else _, _, _, quality, usable = GetQuestLogRewardInfo(i, questID) end
      local link = usable and GetQuestLogItemLink(kind, i, questID)
      local up = link and upgradeOver(link, quality)
      if better(up, best) then best = up end
    end
  end
  return best
end

-- Things outside the quest log that make you stronger or faster right now. See QT.BestActions.
function QT.ReadPower(level)
  local p = { freeSlots = 0, junk = 0 }
  for bag = 0, NUM_BAG_SLOTS do
    p.freeSlots = p.freeSlots + (C_Container.GetContainerNumFreeSlots(bag) or 0)
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info then
        -- An item that starts a quest you don't have yet: opening it is a free pick-up.
        local qi = C_Container.GetContainerItemQuestInfo(bag, slot)
        if qi and qi.questID and not qi.isActive and not p.bagQuest and not QuestTriageCharDB.hidden[qi.questID]
            and not C_QuestLog.IsQuestFlaggedCompleted(qi.questID) then
          p.bagQuest = { questID = qi.questID, link = info.hyperlink, name = C_Item.GetItemNameByID(info.itemID) or "the quest item" }
        end
        if info.quality == 0 and not info.hasNoValue then
          p.junk = p.junk + 1
        elseif C_PlayerInfo.CanUseItem(info.itemID) and not QuestTriageCharDB.skipItems[info.itemID] then
          local up = upgradeOver(info.hyperlink, info.quality)
          if better(up, p.bagUpgrade) then p.bagUpgrade = up end
        end
      end
    end
  end
  for slot = 1, 18 do
    local cur, max = GetInventoryItemDurability(slot)
    if cur and max and max > 0 then
      local pct = math.floor(cur / max * 100)
      if not p.durability or pct < p.durability then p.durability = pct end
    end
  end
  if p.durability and p.durability < 25 and QT.NearestTownsfolk then p.repairAt = QT.NearestTownsfolk("Repair") end
  p.train, p.nextSpells = QT.TrainerAdvice(QT.ScanSpellbook(level), QuestTriageCharDB.trainer, level)
  p.autoSell = QuestTriageDB.opts and QuestTriageDB.opts.autoSellJunk
  return p
end

-- Spells your spellbook lists but you haven't learned yet ("future spells"), with the level each unlocks.
-- Returns { ready, nextLevel } or nil when the spellbook lists none (then we know nothing and say nothing).
function QT.ScanSpellbook(level)
  if not (C_SpellBook and C_SpellBook.GetSpellBookItemLevelLearned) then return nil end
  local bank, future = Enum.SpellBookSpellBank.Player, Enum.SpellBookItemType.FutureSpell
  local ready, nextLevel, seen = 0, nil, {}
  for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
    local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
    if info and not info.isGuild and not info.shouldHide and (info.offSpecID or 0) == 0 then
      for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
        local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
        if item and item.itemType == future then
          local lvl = C_SpellBook.GetSpellBookItemLevelLearned(slot, bank)
          table.insert(seen, item.name .. "@" .. lvl)
          if lvl <= level then ready = ready + 1
          elseif not nextLevel or lvl < nextLevel then nextLevel = lvl end
        end
      end
    end
  end
  -- Kept in SavedVariables so the advice can be checked against the real trainer later.
  QuestTriageCharDB.spellbook = { level = level, future = seen }
  if #seen == 0 then return nil end
  return { ready = ready, nextLevel = nextLevel }
end

-- Called while a class trainer window is open: record what it offers, so trainer advice is real, not guessed.
-- Reads only what the trainer's filters show; a hidden category is recorded as unknown.
function QT.ScanTrainer()
  if IsTradeskillTrainer() then return end
  local level = UnitLevel("player")
  local showAvail, showUnavail = GetTrainerServiceTypeFilter("available"), GetTrainerServiceTypeFilter("unavailable")
  local left, nextLevel = 0, nil
  for i = 1, GetNumTrainerServices() do
    local _, kind, _, reqLevel = GetTrainerServiceInfo(i)
    if kind == "available" then
      left = left + 1
    elseif kind == "unavailable" and reqLevel and reqLevel > level and (not nextLevel or reqLevel < nextLevel) then
      nextLevel = reqLevel
    end
  end
  QuestTriageCharDB.trainer = { level = level, left = showAvail and left or nil, nextLevel = showUnavail and nextLevel or nil }
end

local function readModern()
  local quests, header = {}, nil
  local n = C_QuestLog.GetNumQuestLogEntries()
  for i = 1, n do
    local info = C_QuestLog.GetInfo(i)
    if info then
      if info.isHeader then
        header = info.title
      elseif not info.isHidden then
        local id = info.questID
        local q = {
          title = info.title, level = info.level, questID = id, zone = header,
          suggestedGroup = info.suggestedGroup or 0,
          isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false,
          isFailed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) or false,
          tag = questTag(id),
          isTrivial = C_QuestLog.IsQuestTrivial and (C_QuestLog.IsQuestTrivial(id) == true),
          xp = GetQuestLogRewardXP and GetQuestLogRewardXP(id) or nil,
          upgrade = QT.BestUpgrade(id),
          objectives = {},
        }
        -- Timed quests (Need for a Cure): seconds left, the same call Blizzard's tracker uses for its timer bar.
        local total, elapsed = C_QuestLog.GetTimeAllowed(id)
        if not q.isFailed and total and elapsed and elapsed < total then q.timeLeft = total - elapsed end
        if not q.isComplete then
          q.blockers = QT.QuestBlockers(id)
          -- The game's own quest area (white boundary on the minimap): are you standing in it?
          q.inArea = C_Minimap and C_Minimap.IsInsideQuestBlob and C_Minimap.IsInsideQuestBlob(id) or nil
        end
        -- Decided after inArea: inside the area, the location is the nearest spawn there, never elsewhere.
        q.loc = QT.QuestLocation(id, q.isComplete, q.inArea)
        local c = GetQuestDifficultyColor and GetQuestDifficultyColor(q.level or 0)
        if c then q.color = string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
        local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) or {}
        for _, o in ipairs(objs) do
          table.insert(q.objectives, {
            text = o.text or "",
            have = o.numFulfilled or (o.finished and 1 or 0),
            need = o.numRequired or 1,
          })
        end
        table.insert(quests, q)
      end
    end
  end
  return quests
end

function QT.ReadQuestLog()
  if GetQuestLogTitle and GetNumQuestLogEntries then
    return readClassic()
  elseif C_QuestLog and C_QuestLog.GetInfo then
    return readModern()
  end
  return {}
end

-- Levels below you that still count as "green" (worth XP).
local function fallbackGreenRange(level)
  -- Approximation of the Classic rule, used only if the game doesn't tell us.
  if level < 10 then return 4 end
  if level < 40 then return 5 + math.floor(level / 10) end
  return 8
end

function QT.ReadPlayer()
  local level = UnitLevel("player") or 1
  local green
  if GetQuestGreenRange then
    local ok, v = pcall(GetQuestGreenRange)
    if ok and type(v) == "number" then green = v end
  end
  return { level = level, greenRange = green or fallbackGreenRange(level),
    xp = UnitXP("player"), xpMax = UnitXPMax("player"), zone = GetZoneText() }
end

-- How many quests this character has ever completed (used to show history).
function QT.CompletedCount()
  local list
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    list = C_QuestLog.GetAllCompletedQuestIDs()
  elseif GetQuestsCompleted then
    list = GetQuestsCompleted()
  end
  if not list then return nil end
  local count = 0
  for _ in pairs(list) do count = count + 1 end
  return count
end
