-- Quest Triage: the panel, events, feedback tracking, options and slash commands.
local addonName, QT = ...

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

local DEFAULTS = { style = "batch", locked = false, scale = 1, fadeInCombat = true, autoSellJunk = true }

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
  frame:SetBackdropColor(unpack(QT.PANEL_BG))
end
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 12, -11)
title:SetText("Quest Triage")

local sub = frame:CreateFontString(nil, "OVERLAY", "QuestTriageFontMeta")
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
  GameTooltip:AddDoubleLine("/qt debug", "explain every pin and arrow", 0.4, 1, 0.4, 0.8, 0.8, 0.8)
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
  local after = row.thenLoc and { loc = row.thenLoc, title = row.thenTitle } or nil
  if not QT.SetWaypoint(row.loc, { icon = row.pin, title = row.text:GetText(), lines = lines,
      questID = row.questID or row.pinQuestID, after = after }) then
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
    if row.retry and questID then
      root:CreateButton("Try it again now", function()
        QuestTriageCharDB.deaths[questID] = nil
        QT.Render()
      end)
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
    if row.yards then GameTooltip:AddLine(QT.Commas(row.yards) .. " yd away", 0.78, 0.78, 0.78) end
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
  r.sub = r:CreateFontString(nil, "OVERLAY", "QuestTriageFontMeta")
  r.sub:SetJustifyH("LEFT")
  r.list = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
  r:SetScript("OnEnter", onRowEnter)
  r:SetScript("OnLeave", GameTooltip_Hide)
  rows[i] = r
  return r
end

-- Per style: font, icon size, left inset, gap before the row. Rows are one line except the Next card and notes.
local STYLE = {
  hero   = { font = "GameFontNormalMed3", icon = 26, x = 8, gap = 0 },
  note   = { font = "QuestTriageFontMeta", x = 8, gap = 3 },
  header = { font = "GameFontNormal", x = 2, gap = 8 },
  zone   = { font = "QuestTriageFontMeta", x = 6, gap = 2 },
  item   = { font = "GameFontHighlightSmall", icon = 12, x = 6, gap = 1 },
  alert  = { font = "GameFontHighlightSmall", icon = 12, x = 8, gap = 3 },
  more   = { font = "QuestTriageFontMeta", x = 24, gap = 0 },
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
    r.questID, r.drop, r.yards, r.retry = s.questID, s.drop, s.yards or (s.loc and s.loc.yards), s.retry
    r.pinQuestID, r.thenLoc, r.thenTitle = s.pinQuestID, s.thenLoc, s.thenTitle

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
    r.text:SetWordWrap(isHero or s.style == "note" or s.style == "alert")
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
    -- The Next card's checklist: every objective, done ones checked.
    if isHero and s.checklist then
      r.list:ClearAllPoints()
      r.list:SetPoint("TOPLEFT", r.sub:IsShown() and r.sub or r.text, "BOTTOMLEFT", 0, -4)
      r.list:SetWidth(CONTENT_W - left - rightW - 4)
      r.list:SetText(table.concat(s.checklist, "\n"))
      r.list:Show()
      h = h + r.list:GetStringHeight() + 4
    else
      r.list:Hide()
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
      r.bg:SetColorTexture(1, 0.82, 0, 0.06)
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

-- What the fight check may read about your target: out of combat only, and nothing the game keeps secret.
local function readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

function QT.ReadTarget()
  if InCombatLockdown() or not UnitExists("target") then return nil end
  local level = UnitLevel("target")
  if not readable(level) then return nil end
  local name = UnitName("target")
  return { name = readable(name) and name or "Your target", level = level,
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
  print(string.format("|cffffd100Quest Triage:|r Sold %d gray item%s for %s. (Turn this off in /qt options.)",
    count, count > 1 and "s" or "", GetMoneyString(value, true)))
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
    local title = C_QuestLog.GetTitleForQuestID(id) or "this quest"
    print(string.format("|cffffd100Quest Triage:|r You died %d times on %s. Moved to Save for later; come back at level %d, or bring a friend. Right-click it to try again.",
      d.count, title, level + 2))
  end
end

-- Slow spawns: when you arrived near a quest's objectives, and each time its progress went up (this session).
local tracks = {}
local function trackProgress(q, now)
  local t = tracks[q.questID] or { gains = {} }
  tracks[q.questID] = t
  local value = 0
  for _, o in ipairs(q.objectives or {}) do value = value + (o.have or 0) end
  if t.value and value > t.value then table.insert(t.gains, now) end
  t.value = value
  while t.gains[1] and t.gains[1] < now - 900 do table.remove(t.gains, 1) end
  local there = q.inArea or (q.loc and q.loc.yards and q.loc.yards <= 300)
  if there then
    t.leftAt = nil
    t.enteredAt = t.enteredAt or now
  elseif t.enteredAt then
    -- Stepping out for a moment doesn't reset the clock; leaving for 90 seconds does.
    t.leftAt = t.leftAt or now
    if now - t.leftAt > 90 then t.enteredAt, t.gains = nil, {} end
  end
  q.slow = QT.SlowCheck(t, now)
  if q.slow then q.altLoc = QT.BetterSpot(q.questID) end
end

function QT.Render()
  local player = QT.ReadPlayer()
  local hidden = QuestTriageCharDB.hidden
  local quests = {}
  local now = time()
  for _, q in ipairs(QT.ReadQuestLog()) do
    if not (q.questID and hidden[q.questID]) then
      q.deaths = q.questID and QuestTriageCharDB.deaths[q.questID]
      if q.questID and not q.isComplete then trackProgress(q, now) end
      table.insert(quests, q)
    end
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
        print("|cffffd100Quest Triage:|r Got it. Pin moved to " .. (inLog.title or "the quest") .. ".")
      end
    end
  end
  QT.lastQuests = quests
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
      committed = QuestTriageCharDB.committed, death = death, fight = QT.ReadTarget(), manaPct = QT.ReadManaPct() },
    pickups and QT.PickupGroups(pickups, player, hidden))
  -- Remember the Next step so it stays Next until done (survives death and /reload).
  if specs[1] and specs[1].key then QuestTriageCharDB.committed = specs[1].key end
  if not pickups then
    table.insert(specs, { style = "note", text = "Directions and pick-ups need Questie (installed and loaded)." })
  end
  QT.lastSpecs = specs
  layout(specs)
end

-- /qt debug: everything behind the arrows and pins, to chat and to SavedVariables (QuestTriageCharDB.debug)
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
    table.insert(lines, string.format("[%s] %s%s%s | %s | Blizzard marker: %s", tostring(q.questID), q.title or "?",
      q.isComplete and " (complete)" or "", q.inArea and " (you're in its area)" or "", fmtLoc(q.loc),
      b and string.format("%.1f, %.1f", b.x * 100, b.y * 100) or "none on this map"))
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
  QuestTriageCharDB.debug = lines
  for _, l in ipairs(lines) do print("|cffffd100QT|r " .. l) end
  print("|cffffd100Quest Triage:|r Saved. /reload once to write it to disk, then tell Claude.")
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

  local junk = Settings.RegisterAddOnSetting(category, "QUESTTRIAGE_AUTOSELL", "autoSellJunk", opts, Settings.VarType.Boolean,
    "Sell gray items automatically", DEFAULTS.autoSellJunk)
  Settings.CreateCheckbox(category, junk, "When you open any vendor, sell all gray (Poor) items and show what they made.")

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
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
  "PLAYER_TARGET_CHANGED", "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED", "MERCHANT_SHOW" }) do
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
    QuestTriageCharDB.deaths = QuestTriageCharDB.deaths or {}
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
  elseif event == "MERCHANT_SHOW" then
    sellJunk()
  elseif event == "PLAYER_DEAD" then
    recordDeath()
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
  elseif msg == "debug" then
    QT.Debug()
  elseif msg == "unhide" then
    wipe(QuestTriageCharDB.hidden)
    print("|cffffd100Quest Triage:|r Hidden quests are back.")
    QT.Render()
  else
    QT.SetShown(not frame:IsShown())
  end
end
