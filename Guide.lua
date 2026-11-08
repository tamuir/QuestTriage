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

local function cached(key, fn)
  local loc = locCache[key]
  if loc == nil then
    local ok, spawn, areaId, name = pcall(fn)
    loc = ok and toLoc(spawn, areaId, name) or false
    locCache[key] = loc
  end
  return withVector(loc or nil)
end

-- Where to go for a quest in your log: the turn-in NPC when complete, else the nearest objective.
function QT.QuestLocation(questID, isComplete)
  if not load() then return nil end
  return cached((isComplete and "end:" or "obj:") .. questID, function()
    local quest = M.DB.GetQuest(questID)
    if not quest then return nil end
    if isComplete then return M.DU.GetNearestFinisherOrStarter(quest.Finisher) end
    local spawn, areaId, name = M.DU.GetNearestSpawnForQuest(quest)
    return spawn, areaId, name
  end)
end

-- Nearest place an item comes from: an object, a mob that drops it, or a vendor.
local function nearestItemSource(itemID)
  local best, bestDist
  local function try(spawns, name)
    if not spawns then return end
    local spawn, zone, dist = M.DU.GetNearestSpawn(spawns)
    if spawn and (not bestDist or dist < bestDist) then best, bestDist = { spawn, zone, name }, dist end
  end
  for _, id in ipairs(M.DB.QueryItemSingle(itemID, "objectDrops") or {}) do
    local o = M.DB:GetObject(id); if o then try(o.spawns, o.name) end
  end
  for i, id in ipairs(M.DB.QueryItemSingle(itemID, "npcDrops") or {}) do
    if i > 15 then break end -- shortcut: checks the first 15 droppers only; enough to find a nearby one.
    local n = M.DB:GetNPC(id); if n then try(n.spawns, n.name) end
  end
  for _, id in ipairs(M.DB.QueryItemSingle(itemID, "vendors") or {}) do
    local n = M.DB:GetNPC(id); if n then try(n.spawns, n.name) end
  end
  if best then return best[1], best[2], best[3] end
end

-- What's missing before you can finish a quest in your log, from Questie's data:
-- items the quest needs you to carry (requiredSourceItems) and helper quests it hands you (childQuests).
-- Carrying every required item means nothing is missing. Returns { {text, loc}, ... } or nil.
function QT.QuestBlockers(questID)
  if not load() then return nil end
  local ok, items = pcall(M.DB.QueryQuestSingle, questID, "requiredSourceItems")
  local ok2, children = pcall(M.DB.QueryQuestSingle, questID, "childQuests")
  items, children = ok and items or {}, ok2 and children or {}

  local missing = {}
  for _, item in ipairs(items) do
    if C_Item.GetItemCount(item) == 0 then table.insert(missing, item) end
  end
  if #items > 0 and #missing == 0 then return nil end

  local out = {}
  -- A helper quest not yet picked up is the usual way to get the item.
  for _, c in ipairs(children) do
    if not C_QuestLog.IsQuestFlaggedCompleted(c) and not C_QuestLog.GetLogIndexForQuestID(c) then
      local okq, child = pcall(M.DB.GetQuest, c)
      if okq and child then
        table.insert(out, { text = "Pick up " .. child.name,
          loc = cached("start:" .. c, function() return M.DU.GetNearestFinisherOrStarter(child.Starts) end) })
      end
    end
  end
  if #out == 0 then
    for _, item in ipairs(missing) do
      local name = C_Item.GetItemNameByID(item) or M.DB.QueryItemSingle(item, "name") or "the quest item"
      table.insert(out, { text = "Get " .. name, loc = cached("item:" .. item, function() return nearestItemSource(item) end) })
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
    if ok and quest and not quest.isHidden then
      local giver = cached("start:" .. questID, function() return M.DU.GetNearestFinisherOrStarter(quest.Starts) end)
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
  repair = "Repair", bags = "Banker", group = "communities-icon-chat", death = "DeathIcon",
}

-- Where your corpse is, when it's on the map you're on. Works without Questie (no arrow then).
function QT.CorpseLocation()
  local mapID = C_Map.GetBestMapForUnit("player")
  local pos = mapID and C_DeathInfo.GetCorpseMapPosition(mapID)
  if not pos then return nil end
  local x, y = pos:GetXY()
  local info = C_Map.GetMapInfo(mapID)
  local loc = { name = "Your corpse", zone = info and info.name, uiMapId = mapID, x = x * 100, y = y * 100 }
  load()
  if not HBD then return loc end
  loc.wx, loc.wy, loc.inst = HBD:GetWorldCoordinatesFromZone(x, y, mapID)
  return withVector(loc)
end
local LABELS = { pickup = "Pick up", turnin = "Hand in", objective = "Objective", blocker = "Do this first",
  group = "Group quest" }

-- The Quest Triage map pin: our step icon in a gold ring, with a soft pulse, on the world map and minimap.
local pinInfo  -- what the pin points at: { loc, icon, title, lines }
local mapPin, miniPin

local function pinTooltip(self)
  local i = pinInfo
  if not i then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddDoubleLine("Quest Triage", LABELS[i.icon] or "Waypoint", 1, 0.82, 0, 0.75, 0.75, 0.75)
  GameTooltip:AddLine(i.title, 1, 1, 1, true)
  for _, line in ipairs(i.lines or {}) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
  local loc = withVector(i.loc)
  if loc.name then GameTooltip:AddLine("At: " .. loc.name, 0.8, 0.8, 0.8, true) end
  GameTooltip:AddDoubleLine(string.format("%s  %.1f, %.1f", loc.zone or "", loc.x, loc.y),
    loc.yards and QT.Where(loc) or "", 1, 0.82, 0, 0.75, 0.75, 0.75)
  GameTooltip:AddLine("Right-click: remove pin", 0.4, 1, 0.4)
  GameTooltip:Show()
end

local function makePin(size)
  local f = CreateFrame("Button", nil, UIParent)
  f:SetSize(size, size)
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
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetPoint("CENTER")
  f.bg:SetSize(size * 0.78, size * 0.78)
  f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
  local mask = f:CreateMaskTexture()
  mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(f.bg)
  f.bg:AddMaskTexture(mask)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("CENTER")
  f.icon:SetSize(size * 0.52, size * 0.52)
  f.ring = f:CreateTexture(nil, "OVERLAY")
  f.ring:SetAtlas("Adventures-Ring-Gold")
  f.ring:SetAllPoints()
  f:RegisterForClicks("RightButtonUp")
  f:SetScript("OnClick", function() QT.ClearWaypoint() end)
  f:SetScript("OnEnter", pinTooltip)
  f:SetScript("OnLeave", GameTooltip_Hide)
  return f
end

function QT.ClearWaypoint()
  local pins = LibStub("HereBeDragonsQuestie-Pins-2.0", true)
  if pins then
    pins:RemoveAllWorldMapIcons("QuestTriage")
    pins:RemoveAllMinimapIcons("QuestTriage")
  end
  if C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then C_Map.ClearUserWaypoint() end
  pinInfo = nil
end

-- Pin loc on the world map and minimap, open the map there, and point the game's own navigation at it.
-- info: { icon = step kind, title, lines = {extra tooltip lines} }
function QT.SetWaypoint(loc, info)
  if not (load() and loc and loc.uiMapId and loc.x) then return false end
  local pins = LibStub("HereBeDragonsQuestie-Pins-2.0", true)
  if not pins then return false end
  QT.ClearWaypoint()
  pinInfo = { loc = loc, icon = info and info.icon, title = info and info.title or loc.name or "Waypoint",
    lines = info and info.lines }
  mapPin = mapPin or makePin(30)
  miniPin = miniPin or makePin(20)
  local atlas = QT.ICONS[pinInfo.icon] or QT.ICONS.objective
  mapPin.icon:SetAtlas(atlas)
  miniPin.icon:SetAtlas(atlas)
  pins:AddWorldMapIconMap("QuestTriage", mapPin, loc.uiMapId, loc.x / 100, loc.y / 100, HBD_PINS_WORLDMAP_SHOW_CONTINENT)
  pins:AddMinimapIconMap("QuestTriage", miniPin, loc.uiMapId, loc.x / 100, loc.y / 100, true, true)
  if C_Map.CanSetUserWaypointOnMap(loc.uiMapId) then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(loc.uiMapId, loc.x / 100, loc.y / 100))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
  end
  if OpenWorldMap then OpenWorldMap(loc.uiMapId) end
  return true
end

-- Remove the pin once you get there.
function QT.CheckArrival()
  if not pinInfo then return end
  local here = withVector(pinInfo.loc)
  if here.yards and here.yards <= 15 then QT.ClearWaypoint() end
end
