-- Quest Triage: the panel, events, feedback tracking, options and slash commands.
local addonName, QT = ...
local L = QT.L

local WIDTH = 340
local CONTENT_W = WIDTH - 44
local RIGHT_W = 74   -- travel-time column
local BAR_W = 36     -- progress bar
local ICONS = QT.ICONS -- defined in Guide.lua

-- Secondary text: the game's small font in a light gray that stays readable (Blizzard's "disabled" gray
-- measured only 3.7:1 on the Next card). See QT.META_GRAY.
local metaFont = CreateFont("QuestTriageFontMeta")
metaFont:CopyFontObject(GameFontHighlightSmall)
metaFont:SetTextColor(QT.META_GRAY, QT.META_GRAY, QT.META_GRAY)
-- The panel's own copies of the game fonts, so the outline below never touches Blizzard's shared ones.
local function ownFont(name, from)
  local f = CreateFont(name)
  f:CopyFontObject(from)
  return f
end
local FONTS = { metaFont, ownFont("QuestTriageFontHero", GameFontNormalMed3),
  ownFont("QuestTriageFontHeader", GameFontNormal), ownFont("QuestTriageFontItem", GameFontHighlightSmall) }

local DEFAULTS = { style = "power", locked = false, scale = 1, fadeInCombat = true, autoSellJunk = true, hearthTips = true, openMap = true, timedFirst = 0, bgAlpha = QT.PANEL_BG[4], compact = true, stat = "eta" }

local frame = CreateFrame("Frame", "QuestTriageFrame", UIParent,
  BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(WIDTH, 300)
local function defaultPos()
  frame:ClearAllPoints()
  frame:SetPoint("TOPRIGHT", UIParent, "RIGHT", -260, 150)
end
defaultPos()
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
-- Held by its top-left corner, so the panel grows downward and the Next card stays where you put it.
local function anchorTop()
  local x, y = frame:GetLeft(), frame:GetTop()
  if not (x and y) then return end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  frame:SetUserPlaced(false) -- our saved position, not the game's layout cache (which would keep the old anchor)
  QuestTriageDB.pos = { "TOPLEFT", "BOTTOMLEFT", x, y }
end
frame:SetScript("OnDragStart", function(self) if not QuestTriageDB.opts.locked then self:StartMoving() end end)
frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  anchorTop()
end)
if frame.SetBackdrop then
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(unpack(QT.PANEL_BG))
end
frame:Hide()

-- Background opacity (a setting). See-through below QT.SOLID_ALPHA: outline every letter so it stays readable.
function QT.SetOpacity(alpha)
  local c = QT.PANEL_BG
  if frame.SetBackdropColor then frame:SetBackdropColor(c[1], c[2], c[3], alpha) end
  local flags = QT.NeedsOutline(alpha) and "OUTLINE" or ""
  for _, f in ipairs(FONTS) do
    local file, size = f:GetFont()
    f:SetFont(file, size, flags)
  end
end

local title = frame:CreateFontString(nil, "OVERLAY", "QuestTriageFontHeader")
title:SetPoint("TOPLEFT", 12, -11)
title:SetText("Quest Triage")

local sub = frame:CreateFontString(nil, "OVERLAY", "QuestTriageFontMeta")
sub:SetPoint("LEFT", title, "RIGHT", 8, 0)

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)
close:SetScript("OnClick", function()
  QT.SetShown(false)
  print("|cffffd100Quest Triage:|r " .. L["Hidden. Bring it back from the minimap's addon menu, or type /qt."])
end)

-- Options (gear) and help (?) sit next to the close button.
local gear = CreateFrame("Button", nil, frame)
gear:SetSize(16, 16)
gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
gear:SetNormalAtlas("QuestLog-icon-setting")
gear:SetHighlightAtlas("QuestLog-icon-setting", "ADD")
gear:SetScript("OnClick", function() QT.OpenOptions() end)
gear:SetScript("OnEnter", function(self)
  if InCombatLockdown() then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText(L["Options"], 1, 1, 1)
  GameTooltip:AddLine(L["Leveling style, timed quests, tips, size and more."], 0.8, 0.8, 0.8, true)
  GameTooltip:Show()
end)
gear:SetScript("OnLeave", GameTooltip_Hide)

local help = CreateFrame("Button", nil, frame)
help:SetSize(16, 16)
help:SetPoint("RIGHT", gear, "LEFT", -4, 0)
help:SetNormalFontObject("QuestTriageFontHeader")
help:SetHighlightFontObject("GameFontHighlight")
help:SetText("?")

-- Compact: only the Next step and its notes. "-" folds the lists away, "+" brings them back.
local compactBtn = CreateFrame("Button", nil, frame)
compactBtn:SetSize(16, 16)
compactBtn:SetPoint("RIGHT", help, "LEFT", -4, 0)
compactBtn:SetNormalFontObject("QuestTriageFontHeader")
compactBtn:SetHighlightFontObject("GameFontHighlight")
compactBtn:SetText("-")
local compactSetting -- the "Compact panel" setting (registerOptions): the button goes through it so both agree
compactBtn:SetScript("OnClick", function()
  if compactSetting then
    compactSetting:SetValue(not QuestTriageDB.opts.compact) -- its callback re-renders
  else
    QuestTriageDB.opts.compact = not QuestTriageDB.opts.compact
    QT.Render()
  end
end)
compactBtn:SetScript("OnEnter", function(self)
  if InCombatLockdown() then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText(QuestTriageDB.opts.compact and L["Show the route and quest lists"] or L["Compact: only the Next step"], 1, 1, 1)
  GameTooltip:Show()
end)
compactBtn:SetScript("OnLeave", GameTooltip_Hide)

-- This session's results, shown in the help tooltip. Resets on every login or /reload.
local session = { done = 0 }
local pace, levelStats = {}, {}

help:SetScript("OnEnter", function(self)
  if InCombatLockdown() then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("Quest Triage", 1, 0.82, 0)
  GameTooltip:AddLine(L["Click a line: map pin and open the map"], 1, 1, 1)
  GameTooltip:AddLine(L["Shift-click: link the quest in chat"], 1, 1, 1)
  GameTooltip:AddLine(L["Right-click: more (hide, abandon, quest log)"], 1, 1, 1)
  GameTooltip:AddLine(" ")
  for _, line in ipairs(levelStats) do GameTooltip:AddLine(line, 1, 1, 1) end
  GameTooltip:AddDoubleLine("/qt", L["show or hide"], 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  GameTooltip:AddDoubleLine("/qt options", L["settings"], 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  GameTooltip:AddDoubleLine("/qt stats", L["how you're doing"], 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  GameTooltip:AddDoubleLine("/qt unhide", L["bring back hidden quests and items"], 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  GameTooltip:AddDoubleLine("/qt reset", L["move the panel back"], 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  GameTooltip:AddDoubleLine("/qt debug", L["details for a bug report"], 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  GameTooltip:AddLine(L["The - button folds the panel to just the Next step."], 0.8, 0.8, 0.8, true)
  GameTooltip:AddLine(L["Closed it? Bring it back from the minimap's addon menu, /qt, or a key (Options > Keybindings > AddOns)."], 0.8, 0.8, 0.8, true)
  if session.done > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["This session: %d quests, %s XP"]:format(session.done, QT.Commas(pace.total or 0)), 0.8, 0.8, 0.8)
  end
  GameTooltip:Show()
end)
help:SetScript("OnLeave", GameTooltip_Hide)

local scroll = CreateFrame("ScrollFrame", "QuestTriageScroll", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 10, -30)
scroll:SetPoint("BOTTOMRIGHT", -30, 10)
scroll.scrollBarHideable = true -- Blizzard's template hides the scrollbar while nothing scrolls
scroll.ScrollBar:Hide() -- the template's OnLoad ran before the flag was set

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(CONTENT_W, 10)
scroll:SetScrollChild(content)

-- Abandoning asks first.
StaticPopupDialogs.QUESTTRIAGE_ABANDON = {
  text = L['Abandon "%s"?'], button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
  OnAccept = function(_, questID)
    C_QuestLog.SetSelectedQuest(questID)
    C_QuestLog.SetAbandonQuest()
    C_QuestLog.AbandonQuest()
  end,
}

local function pinRow(row)
  local lines = {}
  if row.sub:IsShown() then table.insert(lines, row.sub:GetText()) end
  for _, l in ipairs(row.tip or {}) do table.insert(lines, l) end
  local after = row.thenLoc and { loc = row.thenLoc, title = row.thenTitle } or nil
  if not QT.SetWaypoint(row.loc, { icon = row.pin, title = row.text:GetText(), lines = lines,
      questID = row.questID or row.pinQuestID, after = after }) then
    print("|cffffd100Quest Triage:|r " .. L["Can't place a map pin there (dungeon or other continent)."])
  end
end

local function linkQuest(questID)
  local link = questID and GetQuestLink(questID)
  if not link then return end
  if ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(link)
  elseif ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
end

local function rowMenu(row)
  local questID = row.questID
  MenuUtil.CreateContextMenu(row, function(_, root)
    root:CreateTitle(row.text:GetText())
    if row.loc then root:CreateButton(L["Show on map"], function() pinRow(row) end) end
    if row.hearth then
      root:CreateButton(L["Don't suggest this inn"], function()
        QuestTriageCharDB.hearthSkip[row.hearth] = true
        QT.Render()
      end)
    end
    if row.kind == "equip" and row.data then
      root:CreateButton(L["Don't suggest this item"], function()
        QuestTriageCharDB.skipItems[C_Item.GetItemInfoInstant(row.data)] = true
        QT.Render()
      end)
    end
    if questID and C_QuestLog.GetLogIndexForQuestID(questID) then
      root:CreateButton(L["Open in quest log"], function() QuestMapFrame_OpenToQuestDetails(questID) end)
      -- Same check and call as Blizzard's objective tracker menu.
      if IsInGroup() and C_QuestLog.IsPushableQuest(questID) then
        root:CreateButton(L["Share with party"], function() QuestUtil.ShareQuest(questID) end)
      end
    end
    if row.retry and questID then
      root:CreateButton(L["Try it again now"], function()
        QuestTriageCharDB.deaths[questID] = nil
        QT.Render()
      end)
    end
    -- Your call: park a quest in Save for later until a level you pick, or until you bring it back.
    if row.saved and questID then
      root:CreateButton(L["Do it now"], function()
        QuestTriageCharDB.deferred[questID] = nil
        QT.Render()
      end)
    elseif questID and C_QuestLog.GetLogIndexForQuestID(questID) and not row.drop and row.pin ~= "turnin" then
      local back = math.max(UnitLevel("player") + 1, row.qlevel or 0)
      local function save(untilLevel)
        QuestTriageCharDB.deferred[questID] = { untilLevel = untilLevel }
        local h = QuestTriageCharDB.history[questID]
        if h then h.deferred = true end -- feedback: the player disagreed with the advice
        QT.Render()
      end
      root:CreateButton(L["Save for later: until level %d"]:format(back), function() save(back) end)
      root:CreateButton(L["Save for later: until I bring it back"], function() save(nil) end)
    end
    -- A pickup you don't want (your friends already did it): skip each quest at this giver on its own.
    for _, p in ipairs(row.skips or {}) do
      root:CreateButton(L["Skip %s"]:format(p.title or "?"), function()
        QuestTriageCharDB.hidden[p.questID] = true
        QT.Render()
      end)
    end
    if questID and not row.skips then
      root:CreateButton(L["Hide from list"], function()
        QuestTriageCharDB.hidden[questID] = true
        local h = QuestTriageCharDB.history[questID]
        if h then h.hidden = true end -- feedback: the player disagreed with the advice
        QT.Render()
      end)
    end
    if row.drop and questID and C_QuestLog.CanAbandonQuest(questID) then
      root:CreateButton("|cffff5050" .. L["Abandon quest"] .. "|r", function()
        StaticPopup_Show("QUESTTRIAGE_ABANDON", C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
          or L["this quest"], nil, questID)
      end)
    end
  end)
end

-- The route: folded to ROUTE_FOLDED stops (done, now, next) at every login, opened to a window of ROUTE_OPEN that
-- the mouse wheel scrolls (routeOffset; nil = start at the last stop done).
local routeOpen, routeOffset, routeWindow, onRouteWheel = false
local ROUTE_FOLDED, ROUTE_OPEN = 3, 10

local function onRowClick(row, button)
  if button == "RightButton" then
    if row.questID or row.loc or row.kind == "equip" then rowMenu(row) end
  elseif IsShiftKeyDown() and row.questID then
    linkQuest(row.questID)
  elseif row.kind == "goto" or (row.kind == "quest" and row.loc) then
    pinRow(row)
  elseif row.kind == "quest" and row.data and QuestMapFrame_OpenToQuestDetails then
    QuestMapFrame_OpenToQuestDetails(row.data)
  elseif row.kind == "equip" then
    if InCombatLockdown() then
      print("|cffffd100Quest Triage:|r " .. L["You can't change gear in combat. Click again after the fight."])
    else
      C_Item.EquipItemByName(row.data)
    end
  elseif row.kind == "bags" then
    OpenAllBags() -- using the item for you would need a secure button; you right-click it
  elseif row.kind == "routeToggle" then
    routeOpen, routeOffset = not routeOpen, nil
    QT.Render()
  elseif row.kind == "toggle" then
    QuestTriageDB.expanded[row.data] = not QuestTriageDB.expanded[row.data]
    QT.Render()
  end
end

local HINTS = {
  quest = L["Click: open in your quest log."],
  questLoc = L["Click: map pin and open the map."],
  ["goto"] = L["Click: map pin and open the map."],
  equip = L["Click: put it on. Right-click: don't suggest it."],
  bags = L["Click: open your bags."],
  toggle = L["Click: show or hide."],
  routeToggle = L["Click: show or hide."],
}

-- Details live here, not in the panel: objectives, reason, exact location, XP, then what clicks do.
local hoveredForecast
local function showForecast(row)
  local f = row.forecast
  local expanded = IsShiftKeyDown()
  row.forecastExpanded = expanded
  GameTooltip:SetText(L["Level %d"]:format(f.level), 1, 0.82, 0)
  GameTooltip:AddDoubleLine(L["XP needed"], QT.Commas(f.needed), 1, 1, 1, 1, 1, 1)
  for _, id in ipairs({ "turnin", "now" }) do
    local group = f[id]
    if #group > 0 then
      local label = id == "turnin" and L["Ready to hand in (%d)"] or L["Still to finish (%d)"]
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine(label:format(#group), L["%s XP"]:format(QT.Commas(group.xp)),
        0.8, 0.87, 1, 0.8, 0.87, 1)
      local visible = expanded and #group or (id == "now" and math.min(2, #group) or 0)
      for i = 1, visible do
        local q = group[i]
        GameTooltip:AddDoubleLine("  " .. q.title, QT.Commas(q.xp), 0.9, 0.9, 0.9, 0.8, 0.8, 0.8)
      end
    end
  end
  local shortfall = f.needed - f.turnin.xp - f.now.xp
  if shortfall > 0 and shortfall < f.needed then
    GameTooltip:AddDoubleLine(L["XP still needed"], QT.Commas(shortfall), 1, 0.82, 0.55, 1, 0.82, 0.55)
  end
  if not expanded and (#f.turnin > 0 or #f.now > 2) then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Hold Shift for quest names"], 0.75, 0.75, 0.75)
  end
  GameTooltip:Show()
end

local function onRowEnter(row)
  if InCombatLockdown() then return end
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  if row.forecast then
    hoveredForecast = row
    showForecast(row)
    return
  end
  if row.kind == "equip" or row.kind == "bags" then
    GameTooltip:SetHyperlink(row.data)
  else
    GameTooltip:SetText(row.text:GetText(), 1, 1, 1, 1, true)
    if row.sub:IsShown() then GameTooltip:AddLine(row.sub:GetText(), 0.8, 0.8, 0.8, true) end
    for _, line in ipairs(row.tip or {}) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
    if row.yards then GameTooltip:AddLine(L["%s yd away"]:format(QT.Commas(row.yards)), 0.78, 0.78, 0.78) end
  end
  if row.questID and row.kind == "quest" and IsInGroup() and GameTooltip.SetQuestPartyProgress then
    GameTooltip:SetQuestPartyProgress(row.questID, true, true)
  end
  local hint = HINTS[(row.kind == "quest" and row.loc) and "questLoc" or row.kind]
  if hint then GameTooltip:AddLine(hint, 0.4, 1, 0.4, true) end
  if row.skips then GameTooltip:AddLine(L["Right-click: skip a quest you don't want."], 0.4, 1, 0.4, true)
  elseif row.questID then GameTooltip:AddLine(L["Shift-click: link in chat.  Right-click: more."], 0.4, 1, 0.4, true) end
  GameTooltip:Show()
end

-- The route timeline. NODE_X lines its nodes up under the centre of the Next card's icon.
local NODE_X, GOLD, RAIL_DIM, CARD = 21, { 1, 0.82, 0 }, { 0.62, 0.58, 0.48 }, { 0.1, 0.08, 0.045 }
local nodeFont = CreateFont("QuestTriageFontNode") -- the step numbers inside the route's nodes
nodeFont:SetFont(STANDARD_TEXT_FONT, 9, "")
local function circle(r, sublevel)
  local t = r:CreateTexture(nil, "ARTWORK", nil, sublevel)
  local mask = r:CreateMaskTexture()
  mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(t)
  t:AddMaskTexture(mask)
  return t
end
local function nodeAt(t, size, h, color)
  t:SetShown(size and true or false)
  if not size then return end
  t:ClearAllPoints()
  t:SetSize(size, size)
  t:SetPoint("CENTER", t:GetParent(), "TOPLEFT", NODE_X, -h / 2)
  t:SetColorTexture(color[1], color[2], color[3], 1)
end
-- An atlas this client lacks would leave the row's previous picture in place: show nothing instead.
local function setAtlas(t, name)
  if not name or (C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(name)) then return false end
  t:SetAtlas(name)
  return true
end

local rows = {}
local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, content)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.accent = r:CreateTexture(nil, "BORDER")
  r.accent:SetWidth(2)
  r.accent:SetPoint("TOPLEFT")
  r.accent:SetPoint("BOTTOMLEFT")
  r.line = r:CreateTexture(nil, "BORDER")
  r.line:SetHeight(1)
  r.line:SetPoint("TOPLEFT", 0, 0)
  r.line:SetPoint("TOPRIGHT", 0, 0)
  r.line:SetColorTexture(0.72, 0.68, 0.57, 0.45)
  r.icon = r:CreateTexture(nil, "ARTWORK", nil, 3)
  -- Route timeline: the line, and a node of up to three circles (ring, socket, core) under the icon.
  r.rail = r:CreateTexture(nil, "BORDER")
  r.rail:SetWidth(2)
  r.rail:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
  r.ring, r.socket = circle(r, 0), circle(r, 1)
  r.num = r:CreateFontString(nil, "OVERLAY", "QuestTriageFontNode")
  r.arrow = r:CreateTexture(nil, "ARTWORK")
  r.arrow:SetAtlas("UI-HUD-Minimap-Arrow-Player")
  r.arrow:SetSize(28, 28)
  r.arrow:SetPoint("RIGHT", -8, 0)
  r.text = r:CreateFontString(nil, "OVERLAY", "QuestTriageFontItem")
  r.text:SetJustifyH("LEFT")
  r.sub = r:CreateFontString(nil, "OVERLAY", "QuestTriageFontMeta")
  r.sub:SetJustifyH("LEFT")
  r.list = r:CreateFontString(nil, "OVERLAY", "QuestTriageFontItem")
  r.list:SetJustifyH("LEFT")
  r.list:SetSpacing(2)
  r.right = r:CreateFontString(nil, "OVERLAY", "QuestTriageFontMeta")
  r.right:SetJustifyH("RIGHT")
  r.right:SetWidth(RIGHT_W)
  r.right:SetPoint("RIGHT", -2, 0)
  r.bar = CreateFrame("StatusBar", nil, r)
  r.bar:SetSize(BAR_W, 4)
  r.bar:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
  r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  r.bar:SetStatusBarColor(1, 0.82, 0)
  r.bar:SetMinMaxValues(0, 1)
  r.bar.bg = r.bar:CreateTexture(nil, "BACKGROUND")
  r.bar.bg:SetAllPoints()
  r.bar.bg:SetColorTexture(1, 1, 1, 0.12)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r:SetScript("OnClick", onRowClick)
  r:SetScript("OnMouseWheel", function(_, delta) onRouteWheel(delta) end)
  r:SetScript("OnEnter", onRowEnter)
  r:SetScript("OnLeave", function(self)
    if hoveredForecast == self then hoveredForecast = nil end
    GameTooltip_Hide()
  end)
  rows[i] = r
  return r
end

-- Per style: font, icon size, left inset, gap before the row. Rows are one line except the Next card and notes.
local STYLE = {
  hero   = { font = "QuestTriageFontHero", icon = 26, x = 8, gap = 0 },
  forecast = { font = "QuestTriageFontItem", x = 9, gap = 3 },
  note   = { font = "QuestTriageFontMeta", x = 8, gap = 3 },
  header = { font = "QuestTriageFontHeader", x = 7, gap = 5 },
  zone   = { font = "QuestTriageFontMeta", x = 6, gap = 2 },
  item   = { font = "QuestTriageFontItem", icon = 12, x = 6, gap = 1 },
  alert  = { font = "QuestTriageFontItem", icon = 12, x = 8, gap = 3 },
  more   = { font = "QuestTriageFontMeta", x = 24, gap = 0 },
  routeStop = { font = "QuestTriageFontItem", x = 37, gap = 0 },
  routeMore = { font = "QuestTriageFontMeta", x = 37, gap = 0 },
}

local heroRow -- the Next card, whose arrow follows your facing
local faded = false
-- One strip shared by the pooled rows. The unfilled track shows the gap to the next level.
local xpTrack = CreateFrame("Frame", nil, content)
xpTrack:SetHeight(3)
xpTrack:EnableMouse(false)
local trackBg = xpTrack:CreateTexture(nil, "BACKGROUND")
trackBg:SetAllPoints()
trackBg:SetColorTexture(0.18, 0.19, 0.21, 1)
local earnedXP = xpTrack:CreateTexture(nil, "ARTWORK")
earnedXP:SetPoint("BOTTOMLEFT")
earnedXP:SetHeight(3)
earnedXP:SetColorTexture(0.23, 0.55, 0.88, 1)
local readyXP = xpTrack:CreateTexture(nil, "ARTWORK")
readyXP:SetHeight(3)
readyXP:SetColorTexture(0.68, 0.88, 1, 1)

-- Above the rows, so their card ground doesn't cover it.
local routeBar = CreateFrame("Frame", nil, content)
routeBar:SetFrameLevel(content:GetFrameLevel() + 20)
local routeTrack = routeBar:CreateTexture(nil, "ARTWORK")
routeTrack:SetAllPoints()
routeTrack:SetColorTexture(1, 1, 1, 0.08)
local routeThumb = routeBar:CreateTexture(nil, "OVERLAY")
routeThumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)

local function layout(specs)
  local compact = QuestTriageDB.opts.compact
  local width = compact and 300 or WIDTH
  local contentWidth = width - (compact and 22 or 44)
  frame:SetWidth(width)
  content:SetWidth(contentWidth)
  scroll:SetPoint("BOTTOMRIGHT", compact and -10 or -30, 10)
  local y = 0
  xpTrack:Hide()
  heroRow = nil
  -- The route shows a window of its stops: folded, the last one done, the current and the next; open, ten
  -- that the wheel scrolls. Clicking the footer folds and opens it; it says what is out of view.
  local routeFirst, routeLast, routeMax, routeSize
  for _, s in ipairs(specs) do
    if s.style == "routeMore" then
      routeSize = routeOpen and ROUTE_OPEN or ROUTE_FOLDED
      routeFirst, routeLast, routeMax = QT.RouteWindow(s.total, s.doneCount, routeSize, routeOpen and routeOffset or nil)
      local hidden = s.total - (routeLast - routeFirst + 1)
      local label = routeOpen and s.total > ROUTE_FOLDED and ("[-]" .. (routeMax > 0 and (" " .. L["Stops %d–%d of %d"]:format(routeFirst, routeLast, s.total)) or ""))
        or hidden > 0 and L["+%d more"]:format(hidden)
      s.text = (label and (label .. "  ·  ") or "") .. s.title
      s.rail = routeLast < s.total
      s.kind = s.total > ROUTE_FOLDED and "routeToggle" or nil
    end
  end
  routeWindow = routeOpen and routeMax and routeMax > 0 and { first = routeFirst, max = routeMax } or nil
  local visible = {}
  for _, s in ipairs(specs) do
    if not (s.step and routeFirst and (s.step < routeFirst or s.step > routeLast)) then visible[#visible + 1] = s end
  end
  specs = visible
  local routeTop, routeBottom
  for i, s in ipairs(specs) do
    local st = STYLE[s.style] or STYLE.item
    local r = getRow(i)
    y = y + (i > 1 and st.gap or 0)
    r.kind, r.data, r.tip, r.loc, r.pin = s.kind, s.data, s.tip, s.loc, s.pin or s.icon
    r.forecast = s.forecast
    r.questID, r.drop, r.yards, r.retry = s.questID, s.drop, s.yards or (s.loc and s.loc.yards), s.retry
    r.pinQuestID, r.thenLoc, r.thenTitle = s.pinQuestID, s.thenLoc, s.thenTitle
    r.saved, r.qlevel, r.hearth, r.skips = s.saved, s.qlevel, s.hearth, s.skips

    local left = st.x
    if st.icon then
      r.icon:ClearAllPoints()
      r.icon:SetSize(st.icon, st.icon)
      r.icon:SetShown(s.icon and setAtlas(r.icon, ICONS[s.icon]) or false)
      left = st.x + st.icon + 6
    else
      r.icon:Hide()
    end

    local isHero = s.style == "hero"
    local isHeader, isForecast = s.style == "header", s.style == "forecast"
    local route = s.style == "routeStop"
    local inset = route and 10 or (isHeader or isForecast) and 4 or 2 -- route rows leave line between their nodes
    local rightW = (s.right and RIGHT_W + 4 or 0) + (s.progress and BAR_W + 6 or 0) + ((isHero and r.loc) and 40 or 0)
    r.text:SetFontObject(st.font)
    r.text:SetTextColor(_G[st.font]:GetTextColor())
    r.text:ClearAllPoints()
    r.text:SetPoint("TOPLEFT", left, isHero and -7 or -inset)
    r.text:SetWidth(contentWidth - left - rightW - 4)
    r.text:SetWordWrap(not compact and (isHero or isForecast or s.style == "note" or s.style == "alert"))
    r.text:SetText(s.text)
    local h = r.text:GetStringHeight() + 2 * inset
    if s.style == "routeMore" then h = h + 4 end -- the plan card's bottom edge

    if isHero and s.sub then
      r.sub:ClearAllPoints()
      r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
      r.sub:SetWidth(contentWidth - left - rightW - 4)
      r.sub:SetWordWrap(not compact)
      r.sub:SetText(s.sub)
      r.sub:Show()
      h = h + r.sub:GetStringHeight() + 3
    else
      r.sub:Hide()
    end
    -- The Next card's checklist: every objective, done ones checked.
    if isHero and s.checklist then
      r.list:ClearAllPoints()
      r.list:SetPoint("TOPLEFT", r.sub:IsShown() and r.sub or r.text, "BOTTOMLEFT", 0, -4)
      r.list:SetWidth(contentWidth - left - rightW - 4)
      r.list:SetText(table.concat(s.checklist, "\n"))
      r.list:Show()
      h = h + r.list:GetStringHeight() + 4
    else
      r.list:Hide()
    end
    if isHero then h = math.max(h + 10, 44) end

    if st.icon and r.icon:IsShown() then
      r.icon:SetPoint(isHero and "LEFT" or "TOPLEFT", st.x, isHero and 0 or -((h - st.icon) / 2))
    end
    -- Route stepper: a line drops from the Next card's icon through one round node per stop. Done stops are
    -- checked, the current one is solid gold, the rest are numbered; travel is a small hollow ring.
    local travel = route and not s.num and not s.done
    r.rail:ClearAllPoints()
    if route or s.rail then
      r.rail:SetPoint("TOP", r, "TOPLEFT", NODE_X, 0)
      r.rail:SetPoint("BOTTOM", r, "TOPLEFT", NODE_X, (route and not s.last) and -h or -h / 2)
      r.rail:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], s.done and 0.25 or 0.5)
    end
    r.rail:SetShown(route or s.rail == true)
    nodeAt(r.ring, route and (travel and 8 or 16), h, (travel or s.done) and RAIL_DIM or GOLD)
    nodeAt(r.socket, route and not s.current and (travel and 4 or 13), h, CARD)
    r.num:SetShown(route and s.num ~= nil and not s.done)
    if r.num:IsShown() then
      r.num:SetText(s.num)
      r.num:ClearAllPoints()
      r.num:SetPoint("CENTER", r, "TOPLEFT", NODE_X + 0.5, -h / 2)
      if s.current then r.num:SetTextColor(0.14, 0.1, 0.02) else r.num:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    end
    if s.done then
      r.icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      r.icon:SetTexCoord(0, 1, 0, 1)
      r.icon:ClearAllPoints()
      r.icon:SetSize(16, 16)
      r.icon:SetPoint("CENTER", r, "TOPLEFT", NODE_X, -h / 2)
      r.icon:Show()
    end
    if s.done then r.text:SetTextColor(0.55, 0.55, 0.55)
    elseif s.current then r.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    r.right:ClearAllPoints()
    r.right:SetPoint("RIGHT", (route and routeWindow) and -8 or -2, 0) -- clear of the route's scrollbar
    if s.right then r.right:SetText(s.right); r.right:Show() else r.right:Hide() end
    if s.progress then
      r.bar:ClearAllPoints()
      if s.right then r.bar:SetPoint("RIGHT", r.right, "LEFT", -6, 0) else r.bar:SetPoint("RIGHT", -2, 0) end
      r.bar:SetValue(s.progress)
      r.bar:Show()
    else
      r.bar:Hide()
    end
    r.line:SetShown(isHeader)
    -- The Next card and its route are one card: same gold edge, a slightly deeper ground under the stops.
    local plan = route or s.style == "routeMore"
    r.accent:SetShown(isHero or isForecast or plan)
    r.bg:SetShown(isHero or isForecast or isHeader or plan)
    if plan then
      r.accent:SetColorTexture(1, 0.79, 0.2, 0.95)
      r.bg:SetColorTexture(CARD[1], CARD[2], CARD[3], 0.88)
    elseif isHero then
      r.accent:SetColorTexture(1, 0.79, 0.2, 0.95)
      r.bg:SetColorTexture(0.14, 0.11, 0.06, 0.88)
      heroRow = r.loc and r or nil
    elseif isForecast then
      local f = s.forecast
      local width = contentWidth - 12
      local earned = width * f.earned / f.cap
      local ready = width * math.min(f.needed, f.turnin.xp) / f.cap
      xpTrack:SetParent(r)
      xpTrack:ClearAllPoints()
      xpTrack:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 8, 0)
      xpTrack:SetWidth(width)
      earnedXP:SetWidth(earned)
      earnedXP:SetShown(earned > 0)
      readyXP:SetPoint("BOTTOMLEFT", xpTrack, "BOTTOMLEFT", earned, 0)
      readyXP:SetWidth(ready)
      readyXP:SetShown(ready > 0)
      xpTrack:Show()
      r.accent:SetColorTexture(0.48, 0.74, 0.93, 0.95)
      r.bg:SetColorTexture(0.07, 0.12, 0.16, 0.88)
    elseif isHeader then
      r.bg:SetColorTexture(0.12, 0.12, 0.13, 0.9)
    end
    r.arrow:SetShown(isHero and r.loc ~= nil)

    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -y)
    r:SetSize(contentWidth, h)
    r.interactive = s.kind ~= nil or s.questID ~= nil
    local wheel = routeWindow ~= nil and (route or s.style == "routeMore")
    r:EnableMouse(r.interactive or wheel)
    r:EnableMouseWheel(wheel)
    r:SetMouseMotionEnabled(not faded and (r.interactive or r.tip ~= nil or r.forecast ~= nil))
    r:SetMouseClickEnabled(r.interactive and not faded)
    r:Show()
    if route then routeTop, routeBottom = routeTop or y, y + h end
    y = y + h
  end
  for i = #specs + 1, #rows do rows[i]:Hide() end
  -- The route's scrollbar: a hairline track down the card's right edge, the thumb where the window is.
  routeBar:SetShown(routeTop ~= nil and routeWindow ~= nil)
  if routeBar:IsShown() then
    local trackH, total = routeBottom - routeTop, routeMax + ROUTE_OPEN
    routeBar:ClearAllPoints()
    routeBar:SetPoint("TOPRIGHT", content, "TOPLEFT", contentWidth - 2, -routeTop)
    routeBar:SetSize(2, trackH)
    routeThumb:ClearAllPoints()
    routeThumb:SetPoint("TOP", routeBar, "TOP", 0, -trackH * (routeFirst - 1) / total)
    routeThumb:SetSize(2, trackH * ROUTE_OPEN / total)
  end
  content:SetHeight(compact and y or y + 10)
  -- Grow with the content, up to 60% of the screen; scroll after that.
  frame:SetHeight(compact and 90 or math.min(y + 50, UIParent:GetHeight() * 0.6))
end

-- The wheel over the route moves its window one stop; at either end it scrolls the panel as usual.
onRouteWheel = function(delta)
  if routeWindow then
    local offset = math.max(0, math.min(routeWindow.max, routeWindow.first - 1 - delta))
    if offset ~= routeWindow.first - 1 then
      routeOffset = offset
      GameTooltip_Hide()
      layout(QT.lastSpecs)
      return
    end
  end
  scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(), scroll:GetVerticalScroll() - delta * 20)))
end

-- The Next card's arrow points where to walk, relative to the way you face.
local arrowElapsed = 0
frame:SetScript("OnUpdate", function(_, elapsed)
  arrowElapsed = arrowElapsed + elapsed
  if arrowElapsed < 0.05 then return end
  arrowElapsed = 0
  if hoveredForecast and hoveredForecast.forecast and GameTooltip:IsOwned(hoveredForecast)
      and not InCombatLockdown() and hoveredForecast.forecastExpanded ~= IsShiftKeyDown() then
    showForecast(hoveredForecast)
  end
  if not heroRow then return end
  local angle, facing = QT.AngleTo(heroRow.loc), GetPlayerFacing()
  if angle and facing then
    heroRow.arrow:SetRotation(angle - facing)
    heroRow.arrow:Show()
  else
    heroRow.arrow:Hide()
  end
end)

-- In combat: fade to 30% and let clicks pass through to the world.
local function setFaded(on)
  faded = on and QuestTriageDB.opts.fadeInCombat
  frame:SetAlpha(faded and 0.3 or 1)
  frame:SetMouseClickEnabled(not faded)
  for _, button in ipairs({ close, gear, help, compactBtn, scroll }) do
    button:SetMouseClickEnabled(not faded)
    button:SetMouseMotionEnabled(not faded)
  end
  for _, r in ipairs(rows) do
    r:SetMouseMotionEnabled(not faded and (r.interactive or r.tip ~= nil or r.forecast ~= nil))
    if r.interactive then
      r:SetMouseClickEnabled(not faded)
    end
  end
end

-- What the fight check may read about your target: out of combat only, and nothing the game keeps secret.
local function readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

function QT.ReadTarget()
  if InCombatLockdown() or not UnitExists("target") then return nil end
  local level = UnitLevel("target")
  if not readable(level) then return nil end
  local name = UnitName("target")
  return { name = readable(name) and name or L["Your target"], level = level,
    classification = UnitClassification("target"), canAttack = UnitCanAttack("player", "target"),
    dead = UnitIsDead("target") }
end

-- Mana as a whole percent, or nil when you don't use mana or the game hides it.
function QT.ReadManaPct()
  if UnitPowerType("player") ~= 0 then return nil end
  local cur, max = UnitPower("player", 0), UnitPowerMax("player", 0)
  if not (readable(cur) and readable(max)) or max == 0 then return nil end
  return math.floor(cur / max * 100)
end

-- At any vendor: sell gray (Poor) items with a sell value, using Blizzard's own "sell all junk" when available.
local function sellJunk()
  if not QuestTriageDB.opts.autoSellJunk or InCombatLockdown() then return end
  local count, value, slots = 0, 0, {}
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.quality == 0 and not info.hasNoValue and not info.isLocked then
        local price = select(11, C_Item.GetItemInfo(info.hyperlink)) or 0
        if price > 0 then
          count, value = count + 1, value + price * (info.stackCount or 1)
          table.insert(slots, { bag, slot })
        end
      end
    end
  end
  if count == 0 then return end
  if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
    C_MerchantFrame.SellAllJunkItems()
  else
    for _, s in ipairs(slots) do C_Container.UseContainerItem(s[1], s[2]) end
  end
  print("|cffffd100Quest Triage:|r " .. (count == 1 and L["Sold 1 gray item for %s. (Turn this off in /qt options.)"]:format(GetMoneyString(value, true))
    or L["Sold %d gray items for %s. (Turn this off in /qt options.)"]:format(count, GetMoneyString(value, true))))
end

-- A death counts against the quest you were doing, if you died near where it's done.
local function recordDeath()
  local key = QuestTriageCharDB.committed or ""
  local id = tonumber(key:match("^do:(%d+)") or key:match("^need:(%d+)") or "")
  if not id then return end
  local loc = QT.QuestLocation(id, false)
  local inArea = C_Minimap and C_Minimap.IsInsideQuestBlob and C_Minimap.IsInsideQuestBlob(id)
  if not inArea and not (loc and loc.yards and loc.yards <= QT.CLUSTER_RADIUS) then return end
  local level = UnitLevel("player")
  local d = QuestTriageCharDB.deaths[id]
  if not d or d.level ~= level then d = { count = 0, level = level } end
  d.count = d.count + 1
  QuestTriageCharDB.deaths[id] = d
  if d.count == QT.DEATHS_BEFORE_LATER then
    local title = C_QuestLog.GetTitleForQuestID(id) or L["this quest"]
    print("|cffffd100Quest Triage:|r " .. L["You died %d times on %s. Moved to Save for later; come back at level %d, or bring a friend. Right-click it to try again."]:format(
      d.count, title, level + 2))
  end
end

-- Slow spawns: when you arrived near a quest's objectives, and each time its progress went up (this session).
local tracks = {}
local function trackProgress(q, now)
  local t = tracks[q.questID] or { gains = {} }
  tracks[q.questID] = t
  local value, required = 0, 0
  for _, o in ipairs(q.objectives or {}) do
    value, required = value + (o.have or 0), required + (o.need or 0)
  end
  if t.value and value > t.value then table.insert(t.gains, now) end
  t.value = value
  while t.gains[1] and t.gains[1] < now - 900 do table.remove(t.gains, 1) end
  local there = q.inArea or (q.loc and q.loc.yards and q.loc.yards <= 300)
  if there then
    t.leftAt = nil
    if not t.enteredAt or value < (t.initial or 0) then t.initial, t.enteredAt = value, now end
    local elapsed, gained = now - t.enteredAt, value - t.initial
    if gained >= 2 and elapsed >= 60 and required > value then
      q.secondsLeft = (required - value) * elapsed / gained
      q.pace = L["%d/%d · ~%d min left"]:format(value, required, math.ceil(q.secondsLeft / 60))
      q.campRate = L["%d objective credits in %d min"]:format(gained, math.floor(elapsed / 60))
    end
  elseif t.enteredAt then
    -- Stepping out for a moment doesn't reset the clock; leaving for 90 seconds does.
    t.leftAt = t.leftAt or now
    if now - t.leftAt > 90 then t.enteredAt, t.gains = nil, {} end
  end
  q.slow = QT.SlowCheck(t, now)
  if q.slow then q.altLoc = QT.BetterSpot(q.questID) end
end

local lastOrigin, lastRefresh, lastGuide
function QT.Render()
  local player = QT.ReadPlayer()
  local hidden = QuestTriageCharDB.hidden
  local quests = {}
  local now = time()
  for _, q in ipairs(QT.ReadQuestLog()) do
    if not (q.questID and hidden[q.questID]) then
      q.deaths = q.questID and QuestTriageCharDB.deaths[q.questID]
      local df = q.questID and QuestTriageCharDB.deferred[q.questID]
      if df and df.untilLevel and player.level >= df.untilLevel then
        QuestTriageCharDB.deferred[q.questID], df = nil, nil -- reached the level: it comes back on its own
      end
      q.deferred = df
      if q.questID and not q.isComplete then trackProgress(q, now) end
      table.insert(quests, q)
    end
  end
  local buckets = QT.Triage(quests, player)
  QT.UpdatePace(pace, player.level, player.xp, player.xpMax, now)
  local forecast, ready = QT.QuestForecast(buckets, player)
  local rate, average, eta = QT.LevelPace(pace, now)
  local speed = rate and L["%s XP/hr"]:format(QT.Commas(rate))
  local arrival = eta and L["Level %d in ~%d min"]:format(player.level + 1, eta)
  levelStats = {}
  local canLevel = not GameRulesUtil.IsPlayerAtEffectiveMaxLevel() and not IsXPUserDisabled()
  if canLevel then
    if forecast then table.insert(levelStats, forecast) end
    if arrival then table.insert(levelStats, arrival) end
    if speed then table.insert(levelStats, speed) end
    if average then table.insert(levelStats, L["Session: %s XP/hr"]:format(QT.Commas(average))) end
    for _, q in ipairs(quests) do
      if q.pace then table.insert(levelStats, q.title .. " · " .. q.campRate .. " · " .. q.pace) end
    end
  end

  -- Remember the first advice given for each quest, to score it later.
  local history = QuestTriageCharDB.history
  for _, b in ipairs(QT.BUCKETS) do
    for _, e in ipairs(buckets[b.id]) do
      local id = e.quest.questID
      if id then
        local h = history[id] or {}
        history[id] = h
        h.title, h.level = e.quest.title, e.quest.level
        h.bucket = h.bucket or b.id
        if b.id ~= "turnin" then h.last = b.id end
      end
    end
  end

  QT.CheckArrival()
  -- A pin for a step that's already done is a wrong pin: clear it.
  local pin = QT.PinInfo and QT.PinInfo()
  if pin and pin.questID then
    local inLog
    for _, q in ipairs(quests) do if q.questID == pin.questID then inLog = q end end
    local done = (pin.icon == "pickup" and inLog) or (pin.icon == "turnin" and not inLog)
      or ((pin.icon == "objective" or pin.icon == nil) and (not inLog or inLog.isComplete))
      or (pin.icon == "blocker" and not inLog)
    if done then
      QT.ClearWaypoint()
    elseif pin.icon == "blocker" and not (inLog.blockers and inLog.blockers[1]) then
      -- Got the item: the second stop becomes the pin, with navigation, without popping the map open.
      local after = pin.after
      QT.ClearWaypoint()
      if after then
        QT.SetWaypoint(after.loc, { icon = "objective", title = after.title, questID = pin.questID, quiet = true })
        print("|cffffd100Quest Triage:|r " .. L["Got it. Pin moved to %s."]:format(inLog.title or L["the quest"]))
      end
    end
  end
  QT.lastQuests = quests
  if not frame:IsShown() then return end
  lastOrigin, lastRefresh = QT.PlayerLocation(), GetTime()
  local power = QT.ReadPower(player.level)
  local pct = player.xpMax and player.xpMax > 0 and math.floor(player.xp / player.xpMax * 100)
  compactBtn:SetText(QuestTriageDB.opts.compact and "+" or "-")
  sub:SetText(L["Level %d"]:format(player.level) .. (pct and string.format(" · %d%%", pct) or "")
    .. (power.nextSpells and (" · " .. L["spells at %d"]:format(power.nextSpells)) or ""))
  title:SetShown(not QuestTriageDB.opts.compact)
  sub:ClearAllPoints()
  if QuestTriageDB.opts.compact then
    local stat = QuestTriageDB.opts.stat
    local display = ready and forecast or (stat == "quests" and forecast) or (stat == "speed" and speed) or arrival
    sub:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -11)
    sub:SetText(canLevel and display or (L["Level %d"]:format(player.level) .. (pct and (" · " .. pct .. "%") or "")))
  else
    sub:SetPoint("LEFT", title, "RIGHT", 8, 0)
  end
  sub:SetPoint("RIGHT", compactBtn, "LEFT", -4, 0)
  sub:SetWordWrap(false)
  sub:SetJustifyH("LEFT")
  local powerMode = QuestTriageDB.opts.style == "power"
  local pickups = QT.ReadPickups(powerMode)
  -- A quest you can start from your bags is shown as "Open <item>", not as a trip to where it drops.
  if pickups and power.bagQuest then
    for i = #pickups, 1, -1 do
      if pickups[i].questID == power.bagQuest.questID then table.remove(pickups, i) end
    end
  end
  local death = UnitIsDeadOrGhost("player") and { ghost = UnitIsGhost("player") } or nil
  if death and death.ghost then death.corpse = QT.CorpseLocation() end
  -- Where your hearthstone is set; its position is learned once you stand at that inn.
  local bindName, hearth = GetBindLocation()
  local bind = QuestTriageCharDB.bind
  if bindName and (not bind or bind.name ~= bindName) then
    bind = { name = bindName }
    QuestTriageCharDB.bind = bind
  end
  if not death and QuestTriageDB.opts.hearthTips then
    hearth = QT.HearthTip(bind, QT.NearestTownsfolk("Innkeeper"), GetMinimapZoneText(), C_SpellBook.IsSpellKnown)
    if hearth and QuestTriageCharDB.hearthSkip[hearth.hearth] then hearth = nil end
  end
  local plan
  local closeToLevel=player.xpMax and player.xpMax>0 and player.xp>=player.xpMax*0.75
  if (powerMode or ready or closeToLevel) and canLevel and not death and not InCombatLockdown() and not UnitOnTaxi("player") then
    local origin = lastOrigin
    if origin then
      local travel = QT.ReadTravel(origin)
      plan = QT.BuildPowerPlan(player, buckets, pickups, origin, travel, not powerMode)
      if plan and not plan.gap then QT.PlanTravelUnlock(plan, origin, travel) end
      if powerMode then QT.UpdatePartyPlan(plan, quests, travel) end
    end
  elseif (powerMode or ready or closeToLevel) and canLevel and not death then
    local previous=QT.activePlan
    if previous and (not previous.gap or (previous.targetLevel==player.level+1 and previous.gap==player.xpMax-player.xp)) then
      plan=previous
    end
  end
  -- Check off the stops of the last route that game data now shows done; a new level starts a fresh list.
  local routeDone = QuestTriageCharDB.routeDone
  if not routeDone or routeDone.level ~= player.level then
    routeDone = { level = player.level }
    QuestTriageCharDB.routeDone = routeDone
  elseif plan and plan ~= QT.activePlan then
    QT.RecordRouteDone(QT.activePlan, quests, routeDone)
  end
  if #routeDone ~= (QT.routeDoneCount or 0) then routeOffset = nil end -- a stop done: back to the current one
  QT.routeDoneCount = #routeDone
  QT.activePlan = plan
  if plan and plan.gap then
    forecast,ready=QT.QuestForecast(buckets,player,false,plan)
    levelStats[1]=forecast
  end
  local specs = QT.BuildRows(buckets, player, power,
    { expanded = QuestTriageDB.expanded, style = QuestTriageDB.opts.style, timedFirst = QuestTriageDB.opts.timedFirst,
      committed = QuestTriageCharDB.committed, death = death, hearth = hearth, fight = QT.ReadTarget(), manaPct = QT.ReadManaPct(),
      compact = QuestTriageDB.opts.compact, canLevel = canLevel, plan = plan, routeDone = routeDone },
    pickups and QT.PickupGroups(pickups, player, hidden))
  if QuestTriageDB.opts.compact and specs[1] and specs[1].planned and plan.gap then
    sub:SetText(L["Level %d in ~%d min"]:format(plan.targetLevel or player.level+1,math.ceil(plan.seconds/60)))
  end
  -- Remember the Next step so it stays Next until done (survives death and /reload).
  if specs[1] and specs[1].key then QuestTriageCharDB.committed = specs[1].key end
  -- Nothing while Questie is still starting up at login.
  local guide = QT.GuideState()
  lastGuide = guide
  if not powerMode and guide == "missing" and not QuestTriageDB.opts.compact then
    table.insert(specs, { style = "note", text = L["Quests to pick up need Questie (installed and enabled)."] })
  elseif not powerMode and guide == "incompatible" and not QuestTriageDB.opts.compact then
    table.insert(specs, { style = "note", text = L["This Questie version isn't supported: no quests to pick up."] })
  end
  QT.lastSpecs = specs
  layout(specs)
end

-- Time full refreshes for /qt debug.
local perf = { runs = 0, last = 0, max = 0, total = 0 }
local render = QT.Render
function QT.Render()
  local t = debugprofilestop()
  render()
  t = debugprofilestop() - t
  perf.runs, perf.last, perf.total, perf.max = perf.runs + 1, t, perf.total + t, math.max(perf.max, t)
end

-- /qt debug: everything behind the arrows and pins, in a copy window and in SavedVariables (QuestTriageCharDB.debug)
-- so a session can be checked afterwards. Includes Blizzard's own quest marker for comparison.
local function fmtLoc(loc)
  if not loc then return "no location" end
  return string.format("%s | %s (map %s) %.1f, %.1f | %s | %s", loc.source or "?", loc.zone or "?",
    tostring(loc.uiMapId), loc.x or -1, loc.y or -1, loc.name or "?",
    loc.yards and (QT.Commas(loc.yards) .. " yd " .. (loc.dir or "")) or "distance unknown")
end

function QT.Debug()
  QT.Render()
  local lines = { "Quest Triage debug " .. date("%Y-%m-%d %H:%M:%S") }
  local mapID = C_Map.GetBestMapForUnit("player")
  local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
  local info = mapID and C_Map.GetMapInfo(mapID)
  table.insert(lines, string.format("You: %s (map %s) %s", info and info.name or "?", tostring(mapID),
    pos and string.format("%.1f, %.1f", pos.x * 100, pos.y * 100) or "position unknown"))
  local blizz = {}
  for _, p in ipairs(mapID and C_QuestLog.GetQuestsOnMap(mapID) or {}) do blizz[p.questID] = p end
  local h = QT.lastSpecs and QT.lastSpecs[1]
  if h then table.insert(lines, "Next: " .. (h.text or "?") .. " | key " .. tostring(h.key) .. " | " .. fmtLoc(h.loc)) end
  for _, q in ipairs(QT.lastQuests or {}) do
    local b = blizz[q.questID]
    local any = QT.BlizzardMarker(q.questID, q.zone)
    table.insert(lines, string.format("[%s] %s%s%s | %s | Blizzard marker: %s | your or quest's zone map: %s", tostring(q.questID),
      q.title or "?", q.isComplete and " (complete)" or "", q.inArea and " (you're in its area)" or "", fmtLoc(q.loc),
      b and string.format("%.1f, %.1f", b.x * 100, b.y * 100) or "none on this map",
      any and string.format("%s (map %s) %.1f, %.1f", any.zone or "?", tostring(any.uiMapId), any.x, any.y) or "none"))
  end
  local pin = QT.PinInfo()
  table.insert(lines, "Pin: " .. (pin and ((pin.title or "?") .. " | " .. fmtLoc(pin.loc)) or "none"))
  -- What the game itself provides, without Questie (for building our own data). The quest-line request is
  -- asynchronous: run /qt debug twice.
  if mapID then
    C_QuestLine.RequestQuestLinesForMap(mapID)
    local qls = C_QuestLine.GetAvailableQuestLines(mapID) or {}
    table.insert(lines, string.format("Blizzard available quests (quest lines) on this map: %d", #qls))
    for i = 1, math.min(5, #qls) do
      local l = qls[i]
      table.insert(lines, string.format("  [%s] %s at %.1f, %.1f", tostring(l.questID), l.questName or "?", (l.x or 0) * 100, (l.y or 0) * 100))
    end
    table.insert(lines, string.format("Blizzard quest hubs on this map: %d", #(C_AreaPoiInfo.GetQuestHubsForMap(mapID) or {})))
    local onMap = C_QuestLog.GetQuestsOnMap(mapID) or {}
    table.insert(lines, string.format("Blizzard quest markers on this map: %d", #onMap))
  end
  for _, q in ipairs(QT.lastQuests or {}) do
    local wMap, wx, wy = C_QuestLog.GetNextWaypoint(q.questID)
    if wMap then
      table.insert(lines, string.format("Blizzard waypoint [%s] %s: map %s %.1f, %.1f", tostring(q.questID), q.title or "?",
        tostring(wMap), (wx or 0) * 100, (wy or 0) * 100))
    end
  end
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  table.insert(lines, 2, "Quest Triage " .. (meta("QuestTriage", "Version") or "?")
    .. ", Questie " .. (meta("Questie", "Version") or "not loaded") .. " (" .. QT.GuideState() .. ")")
  table.insert(lines, 3, string.format("Refresh: last %.1f ms, average %.1f ms, slowest %.1f ms (%d runs)",
    perf.last, perf.total / math.max(1, perf.runs), perf.max, perf.runs))
  QuestTriageCharDB.debug = lines -- also kept in SavedVariables (written on /reload)
  QT.ShowCopyWindow("Quest Triage debug", table.concat(lines, "\n"))
end

-- A window with text selected and ready to copy (Ctrl+C), for bug reports. Native templates only.
local copyWindow
function QT.ShowCopyWindow(title, text)
  if not copyWindow then
    local f = CreateFrame("Frame", "QuestTriageCopyWindow", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(620, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "QuestTriageCopyWindow") -- Esc closes it
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOPLEFT", 14, -30)
    f.hint:SetText(L["Press Ctrl+C to copy, then paste it into your bug report. It holds your quest log and position, nothing else."])
    local s = CreateFrame("ScrollFrame", nil, f, "InputScrollFrameTemplate")
    s:SetPoint("TOPLEFT", 14, -50)
    s:SetPoint("BOTTOMRIGHT", -14, 14)
    s.CharCount:Hide()
    s.EditBox:SetWidth(620 - 28 - 18)
    s.EditBox:SetFontObject(GameFontHighlightSmall)
    s.EditBox:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Read-only: typing puts the original text back, still selected.
    s.EditBox:HookScript("OnTextChanged", function(eb, userInput)
      if userInput then eb:SetText(f.text); eb:HighlightText() end
    end)
    f.edit = s.EditBox
    copyWindow = f
  end
  copyWindow.TitleText:SetText(title)
  copyWindow.text = text
  copyWindow.edit:SetText(text)
  copyWindow:Show()
  copyWindow.edit:SetFocus()
  copyWindow.edit:HighlightText()
end

-- Events refresh the quest log and route. Between events, check pins promptly and
-- replan after 100 yards. A slower refresh keeps timers, cooldowns and party data current.
local pending = false
local function panelTick()
  if pending then return end
  QT.CheckArrival()
  local age = GetTime() - lastRefresh
  local sharing = QuestTriageCharDB.sharePlan and IsInGroup() and not IsInRaid()
  if age >= (sharing and 10 or 30) or (lastGuide == "loading" and QT.GuideState() ~= lastGuide) then
    QT.Render()
    return
  end
  local here = QT.PlayerLocation()
  if here and (not lastOrigin or here.uiMapId ~= lastOrigin.uiMapId
      or (age >= 6 and QT.LegDistance(here, lastOrigin) >= 100)) then
    QT.Render()
  end
end

local ticker
function QT.SetShown(shown)
  QuestTriageDB.shown = shown
  if ticker then ticker:Cancel(); ticker = nil end
  if shown then
    frame:Show()
    -- A position saved by an older version is held by its centre: re-anchor it by the top once.
    if QuestTriageDB.pos and QuestTriageDB.pos[1] ~= "TOPLEFT" then anchorTop() end
    QT.Render()
    ticker = C_Timer.NewTicker(2, panelTick)
  else
    frame:Hide()
  end
end

-- Options live in the game's own Settings panel (Esc > Options > AddOns > Quest Triage).
local category
local function registerOptions()
  if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local opts = QuestTriageDB.opts
  category = Settings.RegisterVerticalLayoutCategory("Quest Triage")

  local style = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_STYLE", "style", opts, Settings.VarType.String,
    L["Leveling style"], DEFAULTS.style)
  style:SetValueChangedCallback(function() QT.Render() end)
  Settings.CreateDropdown(category, style, function()
    local c = Settings.CreateControlTextContainer()
    c:Add("power", L["Power Leveling"], L["Automatically plan quests and travel as you play. Expand the panel for every stop."])
    c:Add("batch", L["Batch by hub"], L["Pick up every quest near you before leaving a town, and do quests whose objectives are close together in one trip."])
    c:Add("single", L["One at a time"], L["Finish one quest, hand it in, then pick up the next."])
    return c:GetData()
  end, L["How Quest Triage plans your route."])

  local timedFirst = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_TIMED", "timedFirst", opts, Settings.VarType.Number,
    L["Timed quests first"], DEFAULTS.timedFirst)
  timedFirst:SetValueChangedCallback(function() QT.Render() end)
  Settings.CreateDropdown(category, timedFirst, function()
    local c = Settings.CreateControlTextContainer()
    c:Add(0, L["Always"], L["A timed quest (or its hand-in) is always the next step while its timer runs."])
    c:Add(30, L["Under %d minutes left"]:format(30))
    c:Add(15, L["Under %d minutes left"]:format(15))
    c:Add(5, L["Under %d minutes left"]:format(5))
    c:Add(-1, L["Never"], L["Timed quests are ranked like any other quest. The time left is still shown."])
    return c:GetData()
  end, L["When a quest with a timer jumps ahead of everything else."])

  compactSetting = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_COMPACT", "compact", opts, Settings.VarType.Boolean,
    L["Compact panel"], DEFAULTS.compact)
  compactSetting:SetValueChangedCallback(function() QT.Render() end)
  local stat = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_STAT", "stat", opts, Settings.VarType.String,
    L["Compact leveling stat"], DEFAULTS.stat)
  stat:SetValueChangedCallback(function() QT.Render() end)
  Settings.CreateDropdown(category, stat, function()
    local c = Settings.CreateControlTextContainer()
    c:Add("eta", L["Time to level"])
    c:Add("speed", L["XP per hour"])
    c:Add("quests", L["Quests to level"])
    return c:GetData()
  end)
  Settings.CreateCheckbox(category, compactSetting, L["Show only the Next step and its notes, without the quest lists. The - and + buttons on the panel do the same."])

  local lock = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_LOCKED", "locked", opts, Settings.VarType.Boolean,
    L["Lock panel position"], DEFAULTS.locked)
  Settings.CreateCheckbox(category, lock, L["Stop the panel from being dragged."])

  local junk = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_AUTOSELL", "autoSellJunk", opts, Settings.VarType.Boolean,
    L["Sell gray items automatically"], DEFAULTS.autoSellJunk)
  Settings.CreateCheckbox(category, junk, L["When you open any vendor, sell all gray (Poor) items and show what they made."])

  local hearthTips = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_HEARTH", "hearthTips", opts, Settings.VarType.Boolean,
    L["Hearthstone tips"], DEFAULTS.hearthTips)
  hearthTips:SetValueChangedCallback(function() QT.Render() end)
  Settings.CreateCheckbox(category, hearthTips, L["When you're in a town far from where your hearthstone is set, suggest setting it at the inn there."])

  local openMap = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_OPENMAP", "openMap", opts, Settings.VarType.Boolean,
    L["Open the map when pinning"], DEFAULTS.openMap)
  Settings.CreateCheckbox(category, openMap, L["Clicking a step opens the world map at its pin. Off: the pin is set quietly (map, minimap and navigation arrow)."])

  local fade = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_FADE", "fadeInCombat", opts, Settings.VarType.Boolean,
    L["Fade in combat"], DEFAULTS.fadeInCombat)
  Settings.CreateCheckbox(category, fade, L["Fade the panel to 30% in combat and let clicks pass through it."])

  local scale = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_SCALE", "scale", opts, Settings.VarType.Number,
    L["Panel size"], DEFAULTS.scale)
  scale:SetValueChangedCallback(function(_, value) frame:SetScale(value) end)
  local sliderOpts = Settings.CreateSliderOptions(0.7, 1.4, 0.05)
  sliderOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%d%%", v * 100 + 0.5) end)
  Settings.CreateSlider(category, scale, sliderOpts, L["Make the panel bigger or smaller."])

  local bgAlpha = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_BGALPHA", "bgAlpha", opts, Settings.VarType.Number,
    L["Background opacity"], DEFAULTS.bgAlpha)
  bgAlpha:SetValueChangedCallback(function(_, value) QT.SetOpacity(value) end)
  local alphaOpts = Settings.CreateSliderOptions(0.2, 1, 0.05)
  alphaOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%d%%", v * 100 + 0.5) end)
  Settings.CreateSlider(category, bgAlpha, alphaOpts,
    L["How much of the game shows through the panel. Below 95% every letter gets a dark outline, so the text stays readable over anything."])

  Settings.RegisterAddOnCategory(category)
end

function QT.OpenOptions()
  if category then Settings.OpenToCategory(category:GetID()) end
end

-- Re-render at most twice a second; QUEST_LOG_UPDATE and BAG_UPDATE_DELAYED fire a lot.
-- Runs even while hidden so the advice history stays complete.
local function requestRender()
  if pending or not QuestTriageCharDB then return end
  pending = true
  C_Timer.After(0.5, function() pending = false; QT.Render() end)
end

-- Talking to a quest giver: the quests they really offer you right now (gossip or quest greeting window).
local function noteOffered(event)
  local guid = UnitGUID("npc")
  if not guid or (issecretvalue and issecretvalue(guid)) then return end
  local kind, _, _, _, _, id = strsplit("-", guid)
  local npcID = kind == "Creature" and tonumber(id)
  if not npcID then return end
  local offered = {}
  if event == "GOSSIP_SHOW" then
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests()) do offered[q.questID] = true end
  else
    for i = 1, GetNumAvailableQuests() do
      local questID = select(5, GetAvailableQuestInfo(i))
      if questID then offered[questID] = true end
    end
  end
  QT.NoteOffered(npcID, offered)
  requestRender()
end

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "GROUP_ROSTER_UPDATE", "TAXIMAP_OPENED", "CHAT_MSG_ADDON",
  "PLAYER_EQUIPMENT_CHANGED", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "BAG_UPDATE_DELAYED",
  "UPDATE_INVENTORY_DURABILITY", "ZONE_CHANGED_NEW_AREA", "TRAINER_SHOW", "TRAINER_UPDATE",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
  "PLAYER_TARGET_CHANGED", "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED", "MERCHANT_SHOW", "HEARTHSTONE_BOUND", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_COMPLETE" }) do
  frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
  if event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    QuestTriageDB = QuestTriageDB or { shown = true }
    QuestTriageDB.expanded = QuestTriageDB.expanded or {}
    QuestTriageDB.opts = QuestTriageDB.opts or {}
    QT.InitializeOptions(QuestTriageDB.opts,DEFAULTS)
    QuestTriageCharDB = QuestTriageCharDB or {}
    QuestTriageCharDB.travel = QuestTriageCharDB.travel or { known={}, routes={}, times={} }
    QT.TrackTaxi()
    C_ChatInfo.RegisterAddonMessagePrefix("QTLevel1")
    QuestTriageCharDB.history = QuestTriageCharDB.history or {}
    QuestTriageCharDB.levels = QuestTriageCharDB.levels or {}
    QuestTriageCharDB.hidden = QuestTriageCharDB.hidden or {}
    QuestTriageCharDB.skipItems = QuestTriageCharDB.skipItems or {}
    QuestTriageCharDB.deaths = QuestTriageCharDB.deaths or {}
    QuestTriageCharDB.deferred = QuestTriageCharDB.deferred or {}
    QuestTriageCharDB.hearthSkip = QuestTriageCharDB.hearthSkip or {}
    QuestTriageCharDB.notOffered = QuestTriageCharDB.notOffered or {}
    if QuestTriageDB.pos then
      local p = QuestTriageDB.pos
      self:ClearAllPoints()
      self:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    frame:SetScale(QuestTriageDB.opts.scale)
    QT.SetOpacity(QuestTriageDB.opts.bgAlpha)
    registerOptions()
    return
  end
  if not QuestTriageCharDB then return end
  local history = QuestTriageCharDB.history
  if event == "CHAT_MSG_ADDON" then
    QT.ReceivePartyPlan(arg1,arg2,arg3,arg4)
  elseif event == "TAXIMAP_OPENED" then
    QT.NoteTaxiMap()
    requestRender()
  elseif event == "PLAYER_ENTERING_WORLD" then
    if QuestTriageDB.shown ~= false then QT.SetShown(true) else requestRender() end
    setFaded(InCombatLockdown())
  elseif event == "PLAYER_XP_UPDATE" then
    QT.UpdatePace(pace, UnitLevel("player"), UnitXP("player"), UnitXPMax("player"), time())
    requestRender()
  elseif event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
    noteOffered(event)
  elseif event == "QUEST_COMPLETE" then
    -- The reward window: name the choice that's a clear upgrade. A hint only; the pick stays yours.
    if (GetNumQuestChoices() or 0) > 1 then
      C_Timer.After(0.3, function() -- item stats can arrive a moment after the window opens
        local up = QT.BestRewardChoice()
        if up then print("|cffffd100Quest Triage:|r " .. L["Best reward for you: %s (%s)."]:format(up.link, QT.UpgradeNote(up))) end
      end)
    end
  elseif event == "MERCHANT_SHOW" then
    sellJunk()
  elseif event == "PLAYER_DEAD" then
    recordDeath()
    requestRender()
  elseif event == "PLAYER_REGEN_DISABLED" then
    setFaded(true)
  elseif event == "PLAYER_REGEN_ENABLED" then
    setFaded(false)
    requestRender()
  elseif event == "QUEST_ACCEPTED" then
    history[arg1] = { accepted = time(), acceptedLevel = UnitLevel("player") }
    QuestTriageCharDB.hidden[arg1] = nil -- skipped as a pickup but taken after all (shared by a friend): show it
    requestRender()
  elseif event == "QUEST_TURNED_IN" then
    -- A chain completion can make a quest available at a giver already visited this level.
    QuestTriageCharDB.notOffered = {}
    local h = history[arg1] or {}
    history[arg1] = h
    h.result, h.finished, h.xp = "done", time(), arg2
    session.done = session.done + 1
    requestRender()
  elseif event == "QUEST_REMOVED" then
    tracks[arg1] = nil
    -- Also fires on hand-in; if no hand-in was recorded within a second, it was abandoned.
    C_Timer.After(1, function()
      local h = history[arg1]
      if h and not h.result then h.result, h.finished = "dropped", time() end
    end)
    requestRender()
  elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
    QT.ScanTrainer()
    requestRender()
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    QT.ClearLocations()
    requestRender()
  elseif event == "QUEST_LOG_UPDATE" then
    QT.ClearLocations(true)
    requestRender()
  elseif event == "PLAYER_LEVEL_UP" then
    QuestTriageCharDB.levels[arg1] = time()
    QuestTriageCharDB.notOffered = {} -- a new level can unlock them: trust Questie again until the giver says no
    -- UnitLevel is not updated yet when this fires; wait a moment.
    C_Timer.After(1, requestRender)
  else
    requestRender()
  end
end)

-- Ways back after closing the panel: the key binding (Bindings.xml) and the game's minimap addon menu.
function QT.Toggle() QT.SetShown(not frame:IsShown()) end
BINDING_HEADER_QUESTTRIAGE = "Quest Triage"
BINDING_NAME_QUESTTRIAGE_TOGGLE = L["Show or hide the panel"]
BINDING_NAME_QUESTTRIAGE_NEXT = L["Go to the next step (same as clicking it)"]
function QT.DoNext()
  if not frame:IsShown() then QT.SetShown(true) end
  local r = rows[1]
  if r and r:IsShown() and r.interactive then onRowClick(r, "LeftButton") end
end
function QuestTriage_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then QT.OpenOptions() else QT.Toggle() end
end

SLASH_QUESTTRIAGE1 = "/qt"
SLASH_QUESTTRIAGE2 = "/questtriage"
SlashCmdList.QUESTTRIAGE = function(msg)
  msg = string.lower(msg or "")
  if msg == "power" then
    QuestTriageDB.opts.style = "power"
    QT.SetShown(true)
    QT.Render()
    print("|cffffd100Quest Triage:|r " .. L["Power Leveling"])
  elseif msg == "route" then
    QT.ShowCopyWindow(L["Power Leveling"], QT.RouteOverview(QT.activePlan))
  elseif msg == "route bands" then
    QT.ShowCopyWindow(L["Power Leveling"], QT.RouteBands())
  elseif msg:match("^route %d+$") then
    local level = tonumber(msg:match("%d+"))
    if level >= 1 and level <= 60 and not InCombatLockdown() then
      QT.ShowCopyWindow(L["Power Leveling"], QT.PreviewBand(level))
    end
  elseif msg == "party on" or msg == "party off" then
    QuestTriageCharDB.sharePlan = msg == "party on"
    QT.ResetPartyPlan()
    print("|cffffd100Quest Triage:|r " .. (QuestTriageCharDB.sharePlan and L["Party route sharing enabled."] or L["Party route sharing disabled."]))
  elseif msg == "reset" then
    QuestTriageDB.pos = nil
    defaultPos()
    QT.SetShown(true)
  elseif msg == "stats" then
    QT.Render()
    for _, line in ipairs(levelStats) do print("|cffffd100Quest Triage:|r " .. line) end
    for _, line in ipairs(QT.FormatStats(QT.Stats(QuestTriageCharDB.history))) do
      print("|cffffd100Quest Triage:|r " .. line)
    end
  elseif msg == "options" or msg == "config" then
    QT.OpenOptions()
  elseif msg == "debug" then
    QT.Debug()
  elseif msg == "unhide" then
    wipe(QuestTriageCharDB.hidden)
    wipe(QuestTriageCharDB.skipItems)
    print("|cffffd100Quest Triage:|r " .. L["Hidden quests and items are back."])
    QT.Render()
  else
    QT.Toggle()
  end
end
