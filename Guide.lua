-- Quest Triage: where things are. The only file that talks to Questie.
-- Questie's stable API (Questie.API) has no "available quests" or location queries, so this
-- reads Questie modules directly.
-- shortcut: depends on Questie internals (AvailableQuests, DistanceUtils, ZoneDB, QuestieDB);
-- everything is pcall-guarded, so a Questie update that changes them turns the guide off, not the addon.
local _, QT = ...

local M -- Questie modules, once ready
local HBD
local locCache = {}  -- [key] = loc without yards/dir; cleared on zone change and quest log change

local function load()
  if M then return true end
  if not (Questie and Questie.API and Questie.API.isReady and QuestieLoader) then return false end
  local ok = pcall(function()
    M = {
      DB = QuestieLoader:ImportModule("QuestieDB"),
      DU = QuestieLoader:ImportModule("DistanceUtils"),
      Zone = QuestieLoader:ImportModule("ZoneDB"),
      AQ = QuestieLoader:ImportModule("AvailableQuests"),
    }
    HBD = LibStub("HereBeDragonsQuestie-2.0")
    assert(M.DB.GetQuest and M.DU.GetNearestSpawnForQuest and M.DU.GetNearestFinisherOrStarter
      and M.Zone.GetUiMapIdByAreaId and M.AQ.__availableQuests and HBD.GetWorldVector)
  end)
  if not ok then M = nil end
  return M ~= nil
end

function QT.GuideReady() return load() end
-- questsOnly: drop only quest-log locations (objectives move as you progress); givers stay cached.
function QT.ClearLocations(questsOnly)
  for k in pairs(locCache) do
    if not questsOnly or not k:find("^start:") then locCache[k] = nil end
  end
end

-- Questie result (spawn {x, y} in 0..100, areaId, name) -> loc, or nil.
local function toLoc(spawn, areaId, name)
  if not (spawn and areaId and spawn[1] and spawn[1] >= 0) then return nil end
  local uiMapId = M.Zone:GetUiMapIdByAreaId(areaId)
  if not uiMapId then return nil end
  local info = C_Map.GetMapInfo(uiMapId)
  local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(spawn[1] / 100, spawn[2] / 100, uiMapId)
  return { name = name, zone = info and info.name, uiMapId = uiMapId, x = spawn[1], y = spawn[2],
    wx = wx, wy = wy, inst = inst }
end

-- Fresh distance and direction from where you stand now.
local function withVector(loc)
  if not loc then return nil end
  local out = setmetatable({}, { __index = loc })
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  if px and loc.wx and pinst == loc.inst then
    local angle, yards = HBD:GetWorldVector(pinst, px, py, loc.wx, loc.wy)
    out.yards, out.dir = yards and math.floor(yards), angle and QT.Compass(angle)
  end
  return out
end

-- Angle (radians, 0 = north, counter-clockwise) from where you stand to loc, for the live arrow.
function QT.AngleTo(loc)
  if not (HBD and loc and loc.wx) then return nil end
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  if not px or pinst ~= loc.inst then return nil end
  return (HBD:GetWorldVector(pinst, px, py, loc.wx, loc.wy))
end

-- fn returns either a ready loc table (with uiMapId) or Questie's (spawn, areaId, name), then optionally a
-- source label. Every loc remembers where it came from (loc.source) so /qt debug can explain any pin.
local function cached(key, fn, source)
  local loc = locCache[key]
  if loc == nil then
    local ok, a, b, c, d = pcall(fn)
    if ok and type(a) == "table" and a.uiMapId then
      loc = a
      if type(b) == "string" then source = b end
    else
      loc = ok and toLoc(a, b, c) or false
      if type(d) == "string" then source = d end -- Questie's own 4th value is a distance, not a label
    end
    if loc then loc.source = loc.source or source end
    locCache[key] = loc
  end
  return withVector(loc or nil)
end

-- Spawn areas for a quest's unfinished objectives, from Questie's spawn data, on your continent.
-- Spawn points are bucketed into SPOT_CELL-yard cells; an area's density counts its cell and the 8 around it,
-- so a lone stray spawn reads as 1 while a real hunting ground reads as 10+.
-- Returns { {loc, density, dist}, ... } or nil when Questie has no spawn points for it.
QT.SPOT_CELL = 150
local function spawnAreas(questID)
  local quest = M.DB.GetQuest(questID)
  if not quest then return nil end
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  if not px then return nil end
  local size, cells = QT.SPOT_CELL, {}
  for _, obj in pairs(quest.Objectives or {}) do
    if obj.spawnList and (not obj.Needed or obj.Needed ~= obj.Collected) then
      for _, data in pairs(obj.spawnList) do
        for areaId, spawns in pairs(data.Spawns or {}) do
          local uiMapId = M.Zone:GetUiMapIdByAreaId(areaId)
          for _, s in ipairs(uiMapId and spawns or {}) do
            if s[1] and s[1] >= 0 then
              local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(s[1] / 100, s[2] / 100, uiMapId)
              if wx and inst == pinst then
                local cx, cy = math.floor(wx / size), math.floor(wy / size)
                local key = cx .. ":" .. cy
                local cell = cells[key] or { cx = cx, cy = cy, pts = {} }
                cells[key] = cell
                table.insert(cell.pts, { wx = wx, wy = wy, inst = inst, uiMapId = uiMapId, x = s[1], y = s[2], name = data.Name })
              end
            end
          end
        end
      end
    end
  end
  local list = {}
  for _, cell in pairs(cells) do
    local n = 0
    for dx = -1, 1 do
      for dy = -1, 1 do
        local o = cells[(cell.cx + dx) .. ":" .. (cell.cy + dy)]
        if o then n = n + #o.pts end
      end
    end
    local ax, ay = 0, 0
    for _, p in ipairs(cell.pts) do ax, ay = ax + p.wx, ay + p.wy end
    ax, ay = ax / #cell.pts, ay / #cell.pts
    -- Pin the real spawn point closest to the middle of the cell.
    local rep, bestSq
    for _, p in ipairs(cell.pts) do
      local sq = (p.wx - ax) ^ 2 + (p.wy - ay) ^ 2
      if not bestSq or sq < bestSq then rep, bestSq = p, sq end
    end
    local info = C_Map.GetMapInfo(rep.uiMapId)
    table.insert(list, { density = n, dist = math.sqrt((ax - px) ^ 2 + (ay - py) ^ 2),
      loc = { name = rep.name, zone = info and info.name, uiMapId = rep.uiMapId, x = rep.x, y = rep.y,
        wx = rep.wx, wy = rep.wy, inst = rep.inst } })
  end
  return #list > 0 and list or nil
end

-- Where to hunt: the nearest area with real density, not the nearest single spawn point, which is
-- often a stray one at the edge of the map. Quests with only a few spawns (named mobs) use any of them.
local function huntingArea(questID)
  local best = QT.PickHuntingArea(spawnAreas(questID))
  if best then best.loc.density = best.density end
  return best and best.loc
end

-- Where to go for a quest in your log:
--   complete            -> the turn-in NPC
--   inside its area     -> the nearest spawn, which is inside the area you're standing in (never somewhere else)
--   otherwise           -> the nearest real hunting area, else Questie's nearest objective point
--                          (objects, items, quests without spawn lists)
function QT.QuestLocation(questID, isComplete, inArea)
  if not load() then return nil end
  local key = (isComplete and "end:" or inArea and "here:" or "obj:") .. questID
  return cached(key, function()
    local quest = M.DB.GetQuest(questID)
    if not quest then return nil end
    if isComplete then
      local spawn, areaId, name = M.DU.GetNearestFinisherOrStarter(quest.Finisher)
      return spawn, areaId, name, "turn-in NPC"
    end
    if not inArea then
      local area = huntingArea(questID)
      if area then return area, string.format("hunting area (%d spawn points)", area.density or 0) end
    end
    local spawn, areaId, name = M.DU.GetNearestSpawnForQuest(quest)
    return spawn, areaId, name, inArea and "nearest spawn, inside the quest area" or "nearest spawn (Questie)"
  end)
end

-- A clearly denser spot within SPOT_RANGE yards than where you stand (for slow spawns).
-- Returns a loc with .spawns and .hereSpawns, or nil. Cached for a minute per quest.

local spotCache = {}

local function findSpot(questID)
  local best, here = QT.PickBetterSpot(spawnAreas(questID))
  if not best then return nil end
  local loc = best.loc
  loc.spawns, loc.hereSpawns, loc.source = best.density, here, "denser spot"
  return loc
end

function QT.BetterSpot(questID)
  if not load() then return nil end
  local c = spotCache[questID]
  if not c or GetTime() - c.at > 60 then
    local ok, result = pcall(findSpot, questID)
    c = { at = GetTime(), result = ok and result or false }
    spotCache[questID] = c
  end
  return c.result and withVector(c.result) or nil
end

-- Nearest place an item comes from: an object to loot, a mob that drops it, or a vendor.
-- Returns spawn, areaId, name, how ("Loot it from ...", "Drops from ...", "Sold by ...").
local function nearestItemSource(itemID)
  local best, bestDist
  local function try(spawns, name, how)
    if not spawns then return end
    local spawn, zone, dist = M.DU.GetNearestSpawn(spawns)
    if spawn and (not bestDist or dist < bestDist) then best, bestDist = { spawn, zone, name, how }, dist end
  end
  for _, id in ipairs(M.DB.QueryItemSingle(itemID, "objectDrops") or {}) do
    local o = M.DB:GetObject(id); if o then try(o.spawns, o.name, "Loot it from " .. (o.name or "an object")) end
  end
  for i, id in ipairs(M.DB.QueryItemSingle(itemID, "npcDrops") or {}) do
    if i > 15 then break end -- shortcut: checks the first 15 droppers only; enough to find a nearby one.
    local n = M.DB:GetNPC(id); if n then try(n.spawns, n.name, "Drops from " .. (n.name or "a mob")) end
  end
  for _, id in ipairs(M.DB.QueryItemSingle(itemID, "vendors") or {}) do
    local n = M.DB:GetNPC(id); if n then try(n.spawns, n.name, "Sold by " .. (n.name or "a vendor")) end
  end
  if best then return best[1], best[2], best[3], best[4] end
end

-- Where a helper quest starts, and how: talk to an NPC or click an object.
local function helperStart(child)
  local s = child.Starts or {}
  if s.NPC and #s.NPC > 0 then
    local spawn, zone, name = M.DU.GetNearestFinisherOrStarter({ NPC = s.NPC })
    if spawn then return spawn, zone, name, "Talk to " .. (name or "the quest giver") end
  end
  if s.GameObject and #s.GameObject > 0 then
    local spawn, zone, name = M.DU.GetNearestFinisherOrStarter({ GameObject = s.GameObject })
    if spawn then return spawn, zone, name, "Click the " .. (name or "object") end
  end
end

-- Helper quests whose parent quest already has its item ([questID] = true). Questie keeps offering them for as
-- long as the parent is in your log, even when you're carrying the item. Filled by QT.QuestBlockers, which
-- runs for every quest in your log before pickups are read.
local helperNotNeeded = {}

-- What's missing before you can finish a quest in your log, from Questie's data:
-- items the quest needs you to carry (requiredSourceItems) and helper quests it hands you (childQuests).
-- Carrying every required item means nothing is missing.
-- Returns { {text, how, loc}, ... } or nil. how says what to do there ("Click the Flawed Power Stone").
function QT.QuestBlockers(questID)
  if not load() then return nil end
  local ok, items = pcall(M.DB.QueryQuestSingle, questID, "requiredSourceItems")
  local ok2, children = pcall(M.DB.QueryQuestSingle, questID, "childQuests")
  items, children = ok and items or {}, ok2 and children or {}

  local missing = {}
  for _, item in ipairs(items) do
    if C_Item.GetItemCount(item) == 0 then table.insert(missing, item) end
  end
  -- Helper quests are only worth picking up while this quest still needs what they give.
  local satisfied = #items > 0 and #missing == 0
  for _, c in ipairs(children) do helperNotNeeded[c] = satisfied or nil end
  if satisfied then return nil end

  local out = {}
  -- A helper quest not yet picked up is the usual way to get the item.
  for _, c in ipairs(children) do
    if not C_QuestLog.IsQuestFlaggedCompleted(c) and not C_QuestLog.GetLogIndexForQuestID(c) then
      local okq, child = pcall(M.DB.GetQuest, c)
      if okq and child then
        local loc = cached("help:" .. c, function() return helperStart(child) end, "helper quest giver")
        table.insert(out, { text = "Pick up " .. child.name, how = loc and loc.source, loc = loc })
      end
    end
  end
  if #out == 0 then
    for _, item in ipairs(missing) do
      local name = C_Item.GetItemNameByID(item) or M.DB.QueryItemSingle(item, "name") or "the quest item"
      local loc = cached("item:" .. item, function() return nearestItemSource(item) end, "item source")
      table.insert(out, { text = "Get " .. name, how = loc and loc.source or "Questie doesn't know where it comes from",
        loc = loc })
    end
  end
  return out[1] and out or nil
end

-- Quests you can pick up right now (Questie checks level, race, class, prerequisites, professions),
-- each with where its giver is. Returns a list or nil when the guide is unavailable.
function QT.ReadPickups()
  if not load() then return nil end
  local list = {}
  for questID in pairs(M.AQ.__availableQuests) do
    local ok, quest = pcall(M.DB.GetQuest, questID)
    if ok and quest and not quest.isHidden and not helperNotNeeded[questID] then
      local giver = cached("start:" .. questID, function() return M.DU.GetNearestFinisherOrStarter(quest.Starts) end, "quest giver")
      table.insert(list, {
        questID = questID, title = quest.name, level = quest.level, requiredLevel = quest.requiredLevel,
        isGroup = M.DB.IsGroupQuest and M.DB.IsGroupQuest(questID) or M.DB.IsDungeonQuest(questID) or false,
        giver = giver,
      })
    end
  end
  return list
end

-- Native icons for each kind of step (all verified in the Forever atlas list). Shared with UI.lua.
QT.ICONS = {
  pickup = "QuestNormal", turnin = "QuestTurnin", objective = "Crosshair_Quest_48",
  blocker = "services-icon-warning", equip = "bags-greenarrow", train = "Class",
  repair = "Repair", bags = "Banker", group = "communities-icon-chat", death = "DeathIcon", hearth = "Innkeeper",
}

-- Where your corpse is, when it's on the map you're on. Works without Questie (no arrow then).
function QT.CorpseLocation()
  local mapID = C_Map.GetBestMapForUnit("player")
  local pos = mapID and C_DeathInfo.GetCorpseMapPosition(mapID)
  if not pos then return nil end
  local x, y = pos:GetXY()
  local info = C_Map.GetMapInfo(mapID)
  local loc = { name = "Your corpse", zone = info and info.name, uiMapId = mapID, x = x * 100, y = y * 100, source = "corpse" }
  load()
  if not HBD then return loc end
  loc.wx, loc.wy, loc.inst = HBD:GetWorldCoordinatesFromZone(x, y, mapID)
  return withVector(loc)
end
-- Nearest friendly townsfolk of one kind ("Innkeeper", "Repair"), from Questie's townsfolk list (built at Questie boot).
local folks = {} -- [kind] = { loc, ... }, built once per kind
function QT.NearestTownsfolk(kind)
  if not load() then return nil end
  if not folks[kind] then
    local list = {}
    pcall(function()
      local T = QuestieLoader:ImportModule("Townsfolk")
      for _, id in ipairs(T.townsfolk and T.townsfolk[kind] or {}) do
        local n = M.DB:GetNPC(id)
        for areaId, spawns in pairs(n and n.friendly and n.spawns or {}) do
          for _, s in ipairs(spawns) do
            local loc = toLoc(s, areaId, n.name)
            if loc and loc.wx then loc.source = kind; table.insert(list, loc) end
          end
        end
      end
    end)
    if #list == 0 then return nil end -- Questie not booted yet: try again next time
    folks[kind] = list
  end
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  local best, bestSq
  for _, loc in ipairs(px and folks[kind] or {}) do
    local sq = loc.inst == pinst and (loc.wx - px) ^ 2 + (loc.wy - py) ^ 2
    if sq and (not bestSq or sq < bestSq) then best, bestSq = loc, sq end
  end
  return withVector(best)
end

local LABELS = { pickup = "Pick up", turnin = "Hand in", objective = "Objective", blocker = "Do this first",
  group = "Group quest" }

-- Map pins. Blizzard's own map pin (with the game's on-screen navigation marker) marks the spot, and its
-- tooltip gets a Quest Triage block added below Blizzard's lines. Our gold ring and pulse sit around it as
-- branding, and our own pin shows on the minimap. Pins you place yourself are never touched.
local pinInfo   -- what we point at: { loc, icon, title, lines, questID, after = { loc, title } }
local nativeSet -- the Blizzard pin we placed: { m = uiMapId, x, y } (0..1), to tell it apart from yours
local mapPin, miniPin
local thenMap, thenMini -- the second stop (where to complete a quest once you have its item)

-- Is the current Blizzard map pin the one we placed?
local function nativeIsOurs()
  if not (nativeSet and C_Map.HasUserWaypoint()) then return false end
  local wp = C_Map.GetUserWaypoint()
  return wp and wp.uiMapID == nativeSet.m and math.abs(wp.position.x - nativeSet.x) < 0.0005
    and math.abs(wp.position.y - nativeSet.y) < 0.0005
end

-- Everything you need at the spot: what to do, what's left, who or what is there, exactly where, how far.
local function addPinInfo(tip)
  local i = pinInfo
  tip:AddDoubleLine("Quest Triage", LABELS[i.icon] or "Waypoint", 1, 0.82, 0, 0.75, 0.75, 0.75)
  tip:AddLine(i.title, 1, 1, 1, true)
  for _, line in ipairs(i.lines or {}) do tip:AddLine(line, 0.85, 0.85, 0.85, true) end
  local loc = withVector(i.loc)
  if loc.name then tip:AddLine("At: " .. loc.name, 1, 1, 1, true) end
  tip:AddDoubleLine(string.format("%s  %.1f, %.1f", loc.zone or "", loc.x, loc.y),
    loc.yards and (QT.Where(loc) .. string.format(" (%s yd)", QT.Commas(loc.yards))) or "", 1, 0.82, 0, 0.75, 0.75, 0.75)
  if loc.source then tip:AddLine("Based on: " .. loc.source, 0.78, 0.78, 0.78, true) end
end

-- The second stop's tooltip: what you'll do there once the first stop is done.
local function thenTooltip(self)
  local a = pinInfo and pinInfo.after
  if not a then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddDoubleLine("Quest Triage", "Then", 1, 0.82, 0, 0.75, 0.75, 0.75)
  GameTooltip:AddLine(a.title, 1, 1, 1, true)
  GameTooltip:AddLine("After: " .. (pinInfo.title or "the first stop"), 0.85, 0.85, 0.85, true)
  local loc = withVector(a.loc)
  if loc.name then GameTooltip:AddLine("At: " .. loc.name, 1, 1, 1, true) end
  GameTooltip:AddDoubleLine(string.format("%s  %.1f, %.1f", loc.zone or "", loc.x, loc.y),
    loc.yards and (QT.Where(loc) .. string.format(" (%s yd)", QT.Commas(loc.yards))) or "", 1, 0.82, 0, 0.75, 0.75, 0.75)
  GameTooltip:AddLine("Right-click: remove pins.", 0.4, 1, 0.4, true)
  GameTooltip:Show()
end

local function pinTooltip(self)
  if not pinInfo then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  addPinInfo(GameTooltip)
  if pinInfo.after then GameTooltip:AddLine("Then: " .. pinInfo.after.title, 0.4, 0.8, 1, true) end
  if pinInfo.questID and C_QuestLog.GetLogIndexForQuestID(pinInfo.questID) then
    GameTooltip:AddLine("Click: open the quest.  Right-click: remove pin.", 0.4, 1, 0.4, true)
  else
    GameTooltip:AddLine("Right-click: remove pin.", 0.4, 1, 0.4, true)
  end
  GameTooltip:Show()
end

-- Added to Blizzard's map pin tooltip, after its own lines, only when that pin is ours.
local lastAdd = 0
local function addToNativeTooltip()
  if not (pinInfo and nativeIsOurs()) then return end
  if lastAdd == GetTime() then return end -- hooked twice (shared function and the pin itself): add once
  lastAdd = GetTime()
  GameTooltip:AddLine(" ")
  addPinInfo(GameTooltip)
  if pinInfo.after then GameTooltip:AddLine("Then: " .. pinInfo.after.title, 0.4, 0.8, 1, true) end
  GameTooltip:Show()
end

-- Blizzard's pin code loads on demand: hook it whenever it's there. The shared function covers pins made
-- later; pins that already exist are hooked one by one.
local mixinHooked
local function hookNativePins()
  if WaypointLocationPinMixin and not mixinHooked then
    hooksecurefunc(WaypointLocationPinMixin, "OnMouseEnter", addToNativeTooltip)
    mixinHooked = true
  end
  if WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate then
    for pin in WorldMapFrame:EnumeratePinsByTemplate("WaypointLocationPinTemplate") do
      if not pin.questTriageHooked then
        hooksecurefunc(pin, "OnMouseEnter", addToNativeTooltip)
        pin.questTriageHooked = true
      end
    end
  end
end
local hookWatcher = CreateFrame("Frame")
hookWatcher:RegisterEvent("ADDON_LOADED")
hookWatcher:SetScript("OnEvent", hookNativePins)

local function pinClick(_, button)
  if button == "RightButton" then
    QT.ClearWaypoint()
  elseif pinInfo and pinInfo.questID and C_QuestLog.GetLogIndexForQuestID(pinInfo.questID)
      and QuestMapFrame_OpenToQuestDetails then
    QuestMapFrame_OpenToQuestDetails(pinInfo.questID)
  end
end

-- second = the "then" stop: silver ring, no pulse, so the first stop is clearly the one to go to now.
local function makePin(size, second)
  local f = CreateFrame("Button", nil, UIParent)
  f:SetSize(size, size)
  if not second then
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.glow:SetAtlas("ArtifactsFX-YellowRing")
    f.glow:SetPoint("CENTER")
    f.glow:SetSize(size * 1.7, size * 1.7)
    local pulse = f.glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.9)
    fade:SetToAlpha(0.2)
    fade:SetDuration(0.8)
    pulse:Play()
  end
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetPoint("CENTER")
  f.bg:SetSize(size * 0.78, size * 0.78)
  f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
  local mask = f:CreateMaskTexture()
  mask:SetTexture("Interface\CharacterFrame\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(f.bg)
  f.bg:AddMaskTexture(mask)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("CENTER")
  f.icon:SetSize(size * 0.52, size * 0.52)
  f.ring = f:CreateTexture(nil, "OVERLAY")
  f.ring:SetAtlas("Adventures-Ring-Gold")
  f.ring:SetAllPoints()
  if second then f.ring:SetDesaturated(true) end
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f:SetScript("OnClick", pinClick)
  f:SetScript("OnEnter", second and thenTooltip or pinTooltip)
  f:SetScript("OnLeave", GameTooltip_Hide)
  return f
end

function QT.ClearWaypoint()
  local pins = LibStub("HereBeDragonsQuestie-Pins-2.0", true)
  if pins then
    pins:RemoveAllWorldMapIcons("QuestTriage")
    pins:RemoveAllMinimapIcons("QuestTriage")
  end
  if nativeIsOurs() then C_Map.ClearUserWaypoint() end
  nativeSet, pinInfo = nil, nil
end

-- Pin loc: Blizzard's map pin with navigation, our ring around it on the world map, our pin on the minimap,
-- and open the map there (unless info.quiet). info: { icon = step kind, title, lines = {extra tooltip lines},
-- questID, after = { loc, title } = a second stop, e.g. where to complete a quest once you have its item }
function QT.SetWaypoint(loc, info)
  if not (load() and loc and loc.uiMapId and loc.x) then return false end
  local pins = LibStub("HereBeDragonsQuestie-Pins-2.0", true)
  if not pins then return false end
  QT.ClearWaypoint()
  local after = info and info.after
  if after and not (after.loc and after.loc.uiMapId and after.loc.x) then after = nil end
  pinInfo = { loc = loc, icon = info and info.icon, title = info and info.title or loc.name or "Waypoint",
    lines = info and info.lines, questID = info and info.questID, after = after }
  if after then
    thenMap = thenMap or makePin(26, true)
    thenMini = thenMini or makePin(16, true)
    thenMap.icon:SetAtlas(QT.ICONS.objective)
    thenMini.icon:SetAtlas(QT.ICONS.objective)
    pins:AddWorldMapIconMap("QuestTriage", thenMap, after.loc.uiMapId, after.loc.x / 100, after.loc.y / 100,
      HBD_PINS_WORLDMAP_SHOW_CONTINENT)
    pins:AddMinimapIconMap("QuestTriage", thenMini, after.loc.uiMapId, after.loc.x / 100, after.loc.y / 100, true, false)
  end
  mapPin = mapPin or makePin(44) -- bigger than Blizzard's 30px pin, so the gold ring shows around it
  miniPin = miniPin or makePin(20)
  local atlas = QT.ICONS[pinInfo.icon] or QT.ICONS.objective
  mapPin.icon:SetAtlas(atlas)
  miniPin.icon:SetAtlas(atlas)
  pins:AddWorldMapIconMap("QuestTriage", mapPin, loc.uiMapId, loc.x / 100, loc.y / 100, HBD_PINS_WORLDMAP_SHOW_CONTINENT)
  pins:AddMinimapIconMap("QuestTriage", miniPin, loc.uiMapId, loc.x / 100, loc.y / 100, true, true)
  if C_Map.CanSetUserWaypointOnMap(loc.uiMapId) then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(loc.uiMapId, loc.x / 100, loc.y / 100))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    nativeSet = { m = loc.uiMapId, x = loc.x / 100, y = loc.y / 100 }
  end
  if OpenWorldMap and not (info and info.quiet) then OpenWorldMap(loc.uiMapId) end
  hookNativePins()
  C_Timer.After(0.2, hookNativePins) -- the map makes its pin when it shows
  return true
end

-- Remove the pin once you get there.
-- What the pin points at, for clearing stale pins and /qt debug.
function QT.PinInfo() return pinInfo end

function QT.CheckArrival()
  if not pinInfo then return end
  local here = withVector(pinInfo.loc)
  if here.yards and here.yards <= 15 then QT.ClearWaypoint() end
end
