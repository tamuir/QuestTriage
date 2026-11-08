-- Quest Triage: the panel, events, feedback tracking, options and slash commands.
local addonName, QT = ...

local WIDTH = 340
local CONTENT_W = WIDTH - 44
local RIGHT_W = 74   -- travel-time column
local BAR_W = 36     -- progress bar
local ICONS = QT.ICONS -- defined in Guide.lua

local DEFAULTS = { style = "batch", locked = false, scale = 1, fadeInCombat = true }

local frame = CreateFrame("Frame", "QuestTriageFrame", UIParent,
  BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(WIDTH, 300)
frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 0)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self) if not QuestTriageDB.opts.locked then self:StartMoving() end end)
frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relPoint, x, y = self:GetPoint()
  QuestTriageDB.pos = { point, relPoint, x, y }
end)
if frame.SetBackdrop then
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0.03, 0.03, 0.05, 0.92)
end
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 12, -11)
title:SetText("Quest Triage")

local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
sub:SetPoint("LEFT", title, "RIGHT", 8, 0)

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)
close:SetScript("OnClick", function() QT.SetShown(false) end)

-- Options (gear) and help (?) sit next to the close button.
local gear = CreateFrame("Button", nil, frame)
gear:SetSize(16, 16)
gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
gear:SetNormalAtlas("QuestLog-icon-setting")
gear:SetHighlightAtlas("QuestLog-icon-setting", "ADD")
gear:SetScript("OnClick", function() QT.OpenOptions() end)
gear:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("Options", 1, 1, 1)
  GameTooltip:AddLine("Leveling style, lock, scale, combat fade.", 0.8, 0.8, 0.8, true)
  GameTooltip:Show()
end)
gear:SetScript("OnLeave", GameTooltip_Hide)

local help = CreateFrame("Button", nil, frame)
help:SetSize(16, 16)
help:SetPoint("RIGHT", gear, "LEFT", -4, 0)
help:SetNormalFontObject("GameFontNormal")
help:SetHighlightFontObject("GameFontHighlight")
help:SetText("?")

-- This session's results, shown in the help tooltip. Resets on every login or /reload.
local session = { start = time(), done = 0, xp = 0 }

help:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("Quest Triage", 1, 0.82, 0)
  GameTooltip:AddLine("Click a line: map pin and open the map", 1, 1, 1)
  GameTooltip:AddLine("Shift-click: link the quest in chat", 1, 1, 1)
  GameTooltip:AddLine("Right-click: more (hide, abandon, quest log)", 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("/qt", "show or hide", 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  GameTooltip:AddDoubleLine("/qt options", "settings", 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  GameTooltip:AddDoubleLine("/qt stats", "how you're doing", 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  GameTooltip:AddDoubleLine("/qt unhide", "bring back hidden quests", 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  GameTooltip:AddDoubleLine("/qt reset", "move the panel back", 0.4, 1, 0.4, 0.8, 0.8, 0.8)
  if session.done > 0 then
    local hours = (time() - session.start) / 3600
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format("This session: %d quests, %s XP%s", session.done, QT.Commas(session.xp),
      hours > 0.08 and string.format(" (%s/hour)", QT.Commas(session.xp / hours)) or ""), 0.8, 0.8, 0.8)
  end
  GameTooltip:Show()
end)
help:SetScript("OnLeave", GameTooltip_Hide)

local scroll = CreateFrame("ScrollFrame", "QuestTriageScroll", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 10, -30)
scroll:SetPoint("BOTTOMRIGHT", -30, 10)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(CONTENT_W, 10)
scroll:SetScrollChild(content)

-- Abandoning asks first.
StaticPopupDialogs.QUESTTRIAGE_ABANDON = {
  text = "Abandon \"%s\"?", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
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
  if not QT.SetWaypoint(row.loc, { icon = row.pin, title = row.text:GetText(), lines = lines }) then
    print("|cffffd100Quest Triage:|r Can't place a map pin there (dungeon or other continent).")
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
    if row.loc then root:CreateButton("Show on map", function() pinRow(row) end) end
    if questID and C_QuestLog.GetLogIndexForQuestID(questID) then
      root:CreateButton("Open in quest log", function() QuestMapFrame_OpenToQuestDetails(questID) end)
    end
    if questID then
      root:CreateButton("Hide from list", function()
        QuestTriageCharDB.hidden[questID] = true
        local h = QuestTriageCharDB.history[questID]
        if h then h.hidden = true end -- feedback: the player disagreed with the advice
        QT.Render()
      end)
    end
    if row.drop and questID and C_QuestLog.CanAbandonQuest(questID) then
      root:CreateButton("|cffff5050Abandon quest|r", function()
        StaticPopup_Show("QUESTTRIAGE_ABANDON", C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
          or "this quest", nil, questID)
      end)
    end
  end)
end

local function onRowClick(row, button)
  if button == "RightButton" then
    if row.questID or row.loc then rowMenu(row) end
  elseif IsShiftKeyDown() and row.questID then
    linkQuest(row.questID)
  elseif row.kind == "goto" or (row.kind == "quest" and row.loc) then
    pinRow(row)
  elseif row.kind == "quest" and row.data and QuestMapFrame_OpenToQuestDetails then
    QuestMapFrame_OpenToQuestDetails(row.data)
  elseif row.kind == "equip" then
    if InCombatLockdown() then
      print("|cffffd100Quest Triage:|r You can't change gear in combat. Click again after the fight.")
    else
      C_Item.EquipItemByName(row.data)
    end
  elseif row.kind == "toggle" then
    QuestTriageDB.expanded[row.data] = not QuestTriageDB.expanded[row.data]
    QT.Render()
  end
end

local HINTS = {
  quest = "Click: open in your quest log.",
  questLoc = "Click: map pin and open the map.",
  ["goto"] = "Click: map pin and open the map.",
  equip = "Click: put it on.",
  toggle = "Click: show or hide.",
}

-- Details live here, not in the panel: objectives, reason, exact location, XP, then what clicks do.
local function onRowEnter(row)
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  if row.kind == "equip" then
    GameTooltip:SetHyperlink(row.data)
  else
    GameTooltip:SetText(row.text:GetText(), 1, 1, 1, 1, true)
    if row.sub:IsShown() then GameTooltip:AddLine(row.sub:GetText(), 0.8, 0.8, 0.8, true) end
    for _, line in ipairs(row.tip or {}) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
    if row.yards then GameTooltip:AddLine(QT.Commas(row.yards) .. " yd away", 0.6, 0.6, 0.6) end
  end
  local hint = HINTS[(row.kind == "quest" and row.loc) and "questLoc" or row.kind]
  if hint then GameTooltip:AddLine(hint, 0.4, 1, 0.4, true) end
  if row.questID then GameTooltip:AddLine("Shift-click: link in chat.  Right-click: more.", 0.4, 1, 0.4, true) end
  GameTooltip:Show()
end

local rows = {}
local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, content)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.line = r:CreateTexture(nil, "BORDER")
  r.line:SetHeight(1)
  r.line:SetPoint("TOPLEFT", 0, 0)
  r.line:SetPoint("TOPRIGHT", 0, 0)
  r.line:SetColorTexture(1, 1, 1, 0.12)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.arrow = r:CreateTexture(nil, "ARTWORK")
  r.arrow:SetAtlas("UI-HUD-Minimap-Arrow-Player")
  r.arrow:SetSize(28, 28)
  r.arrow:SetPoint("RIGHT", -8, 0)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetJustifyH("LEFT")
  r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.sub:SetJustifyH("LEFT")
  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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
  r:SetScript("OnEnter", onRowEnter)
  r:SetScript("OnLeave", GameTooltip_Hide)
  rows[i] = r
  return r
end

-- Per style: font, icon size, left inset, gap before the row. Rows are one line except the Next card and notes.
local STYLE = {
  hero   = { font = "GameFontNormalMed3", icon = 26, x = 8, gap = 0 },
  note   = { font = "GameFontDisableSmall", x = 8, gap = 3 },
  header = { font = "GameFontNormal", x = 2, gap = 8 },
  zone   = { font = "GameFontDisableSmall", x = 6, gap = 2 },
  item   = { font = "GameFontHighlightSmall", icon = 12, x = 6, gap = 1 },
  more   = { font = "GameFontDisableSmall", x = 24, gap = 0 },
}

local heroRow -- the Next card, whose arrow follows your facing
local faded = false

local function layout(specs)
  local y = 0
  heroRow = nil
  for i, s in ipairs(specs) do
    local st = STYLE[s.style] or STYLE.item
    local r = getRow(i)
    y = y + (i > 1 and st.gap or 0)
    r.kind, r.data, r.tip, r.loc, r.pin = s.kind, s.data, s.tip, s.loc, s.pin or s.icon
    r.questID, r.drop, r.yards = s.questID, s.drop, s.yards or (s.loc and s.loc.yards)

    local left = st.x
    if st.icon then
      r.icon:ClearAllPoints()
      r.icon:SetSize(st.icon, st.icon)
      if s.icon and ICONS[s.icon] then r.icon:SetAtlas(ICONS[s.icon]); r.icon:Show() else r.icon:Hide() end
      left = st.x + st.icon + 6
    else
      r.icon:Hide()
    end

    local isHero = s.style == "hero"
    local rightW = (s.right and RIGHT_W + 4 or 0) + (s.progress and BAR_W + 6 or 0) + ((isHero and r.loc) and 40 or 0)
    r.text:SetFontObject(st.font)
    r.text:ClearAllPoints()
    r.text:SetPoint("TOPLEFT", left, isHero and -7 or -2)
    r.text:SetWidth(CONTENT_W - left - rightW - 4)
    r.text:SetWordWrap(isHero or s.style == "note")
    r.text:SetText(s.text)
    local h = r.text:GetStringHeight() + 4

    if isHero and s.sub then
      r.sub:ClearAllPoints()
      r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
      r.sub:SetWidth(CONTENT_W - left - rightW - 4)
      r.sub:SetText(s.sub)
      r.sub:Show()
      h = h + r.sub:GetStringHeight() + 3
    else
      r.sub:Hide()
    end
    if isHero then h = math.max(h + 10, 44) end
    if s.style == "header" then h = h + 2 end

    if st.icon and r.icon:IsShown() then
      r.icon:SetPoint(isHero and "LEFT" or "TOPLEFT", st.x, isHero and 0 or -((h - st.icon) / 2))
    end
    if s.right then r.right:SetText(s.right); r.right:Show() else r.right:Hide() end
    if s.progress then
      r.bar:ClearAllPoints()
      if s.right then r.bar:SetPoint("RIGHT", r.right, "LEFT", -6, 0) else r.bar:SetPoint("RIGHT", -2, 0) end
      r.bar:SetValue(s.progress)
      r.bar:Show()
    else
      r.bar:Hide()
    end
    r.line:SetShown(s.style == "header")
    if isHero then
      r.bg:SetAllPoints()
      r.bg:SetColorTexture(1, 0.82, 0, 0.10)
      r.bg:Show()
      heroRow = r.loc and r or nil
    else
      r.bg:Hide()
    end
    r.arrow:SetShown(isHero and r.loc ~= nil)

    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -y)
    r:SetSize(CONTENT_W, h)
    r.interactive = s.kind ~= nil or s.questID ~= nil
    r:EnableMouse(r.interactive)
    if r.interactive then r:SetMouseClickEnabled(not faded) end
    r:Show()
    y = y + h
  end
  for i = #specs + 1, #rows do rows[i]:Hide() end
  content:SetHeight(y + 10)
  -- Grow with the content, up to 60% of the screen; scroll after that.
  frame:SetHeight(math.min(y + 50, UIParent:GetHeight() * 0.6))
end

-- The Next card's arrow points where to walk, relative to the way you face.
local arrowElapsed = 0
frame:SetScript("OnUpdate", function(_, elapsed)
  arrowElapsed = arrowElapsed + elapsed
  if arrowElapsed < 0.05 or not heroRow then return end
  arrowElapsed = 0
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
  for _, r in ipairs(rows) do
    if r.interactive then r:SetMouseClickEnabled(not faded) end
  end
end

function QT.Render()
  local player = QT.ReadPlayer()
  local hidden = QuestTriageCharDB.hidden
  local quests = {}
  for _, q in ipairs(QT.ReadQuestLog()) do
    if not (q.questID and hidden[q.questID]) then table.insert(quests, q) end
  end
  local buckets = QT.Triage(quests, player)

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
      end
    end
  end

  QT.CheckArrival()
  if not frame:IsShown() then return end
  local power = QT.ReadPower(player.level)
  local pct = player.xpMax and player.xpMax > 0 and math.floor(player.xp / player.xpMax * 100)
  sub:SetText(string.format("Level %d%s%s", player.level, pct and string.format(" · %d%%", pct) or "",
    power.nextSpells and string.format(" · spells at %d", power.nextSpells) or ""))
  local pickups = QT.ReadPickups()
  local death = UnitIsDeadOrGhost("player") and { ghost = UnitIsGhost("player") } or nil
  if death and death.ghost then death.corpse = QT.CorpseLocation() end
  local specs = QT.BuildRows(buckets, player, power,
    { expanded = QuestTriageDB.expanded, style = QuestTriageDB.opts.style,
      committed = QuestTriageCharDB.committed, death = death },
    pickups and QT.PickupGroups(pickups, player, hidden))
  -- Remember the Next step so it stays Next until done (survives death and /reload).
  if specs[1] and specs[1].key then QuestTriageCharDB.committed = specs[1].key end
  if not pickups then
    table.insert(specs, { style = "note", text = "Directions and pick-ups need Questie (installed and loaded)." })
  end
  layout(specs)
end

-- Distances change as you move: refresh every 2 seconds while the panel is open.
local ticker
function QT.SetShown(shown)
  QuestTriageDB.shown = shown
  if ticker then ticker:Cancel(); ticker = nil end
  if shown then
    frame:Show(); QT.Render()
    ticker = C_Timer.NewTicker(2, function() QT.Render() end)
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
    "Leveling style", DEFAULTS.style)
  style:SetValueChangedCallback(function() QT.Render() end)
  Settings.CreateDropdown(category, style, function()
    local c = Settings.CreateControlTextContainer()
    c:Add("batch", "Batch (fastest)", "Pick up every quest near you before leaving a town, and do quests whose objectives are close together in one trip.")
    c:Add("single", "One at a time", "Finish one quest, hand it in, then pick up the next.")
    return c:GetData()
  end, "How Quest Triage plans your route.")

  local lock = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_LOCKED", "locked", opts, Settings.VarType.Boolean,
    "Lock panel position", DEFAULTS.locked)
  Settings.CreateCheckbox(category, lock, "Stop the panel from being dragged.")

  local fade = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_FADE", "fadeInCombat", opts, Settings.VarType.Boolean,
    "Fade in combat", DEFAULTS.fadeInCombat)
  Settings.CreateCheckbox(category, fade, "Fade the panel to 30% in combat and let clicks pass through it.")

  local scale = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_SCALE", "scale", opts, Settings.VarType.Number,
    "Panel size", DEFAULTS.scale)
  scale:SetValueChangedCallback(function(_, value) frame:SetScale(value) end)
  local sliderOpts = Settings.CreateSliderOptions(0.7, 1.4, 0.05)
  sliderOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%d%%", v * 100 + 0.5) end)
  Settings.CreateSlider(category, scale, sliderOpts, "Make the panel bigger or smaller.")

  Settings.RegisterAddOnCategory(category)
end

function QT.OpenOptions()
  if category then Settings.OpenToCategory(category:GetID()) end
end

-- Re-render at most twice a second; QUEST_LOG_UPDATE and BAG_UPDATE_DELAYED fire a lot.
-- Runs even while hidden so the advice history stays complete.
local pending = false
local function requestRender()
  if pending or not QuestTriageCharDB then return end
  pending = true
  C_Timer.After(0.5, function() pending = false; QT.Render() end)
end

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP",
  "PLAYER_EQUIPMENT_CHANGED", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "BAG_UPDATE_DELAYED",
  "UPDATE_INVENTORY_DURABILITY", "ZONE_CHANGED_NEW_AREA", "TRAINER_SHOW", "TRAINER_UPDATE",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
  frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function(self, event, arg1, arg2)
  if event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    QuestTriageDB = QuestTriageDB or { shown = true }
    QuestTriageDB.expanded = QuestTriageDB.expanded or {}
    QuestTriageDB.opts = QuestTriageDB.opts or {}
    for k, v in pairs(DEFAULTS) do
      if QuestTriageDB.opts[k] == nil then QuestTriageDB.opts[k] = v end
    end
    QuestTriageCharDB = QuestTriageCharDB or {}
    QuestTriageCharDB.history = QuestTriageCharDB.history or {}
    QuestTriageCharDB.levels = QuestTriageCharDB.levels or {}
    QuestTriageCharDB.hidden = QuestTriageCharDB.hidden or {}
    if QuestTriageDB.pos then
      local p = QuestTriageDB.pos
      self:ClearAllPoints()
      self:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    frame:SetScale(QuestTriageDB.opts.scale)
    registerOptions()
    return
  end
  if not QuestTriageCharDB then return end
  local history = QuestTriageCharDB.history
  if event == "PLAYER_ENTERING_WORLD" then
    if QuestTriageDB.shown ~= false then QT.SetShown(true) end
    requestRender()
  elseif event == "PLAYER_REGEN_DISABLED" then
    setFaded(true)
  elseif event == "PLAYER_REGEN_ENABLED" then
    setFaded(false)
  elseif event == "QUEST_ACCEPTED" then
    history[arg1] = { accepted = time(), acceptedLevel = UnitLevel("player") }
    requestRender()
  elseif event == "QUEST_TURNED_IN" then
    local h = history[arg1] or {}
    history[arg1] = h
    h.result, h.finished, h.xp = "done", time(), arg2
    session.done, session.xp = session.done + 1, session.xp + (arg2 or 0)
    requestRender()
  elseif event == "QUEST_REMOVED" then
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
    -- UnitLevel is not updated yet when this fires; wait a moment.
    C_Timer.After(1, requestRender)
  else
    requestRender()
  end
end)

SLASH_QUESTTRIAGE1 = "/qt"
SLASH_QUESTTRIAGE2 = "/questtriage"
SlashCmdList.QUESTTRIAGE = function(msg)
  msg = string.lower(msg or "")
  if msg == "reset" then
    QuestTriageDB.pos = nil
    frame:ClearAllPoints()
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 0)
    QT.SetShown(true)
  elseif msg == "stats" then
    for _, line in ipairs(QT.FormatStats(QT.Stats(QuestTriageCharDB.history))) do
      print("|cffffd100Quest Triage:|r " .. line)
    end
  elseif msg == "options" or msg == "config" then
    QT.OpenOptions()
  elseif msg == "unhide" then
    wipe(QuestTriageCharDB.hidden)
    print("|cffffd100Quest Triage:|r Hidden quests are back.")
    QT.Render()
  else
    QT.SetShown(not frame:IsShown())
  end
end
