-- Developer tool, never packaged: takes the screenshots for Quest Triage's README and CurseForge page, so they
-- need no hand cropping. Set up the moment in game (stand in a quest area, open the map, hover a pin), then
-- /qtshots <name>. It records the screen rectangle of what's showing (the Quest Triage panel, plus the world map,
-- a tooltip or the Settings window when open) and takes the screenshot. /reload to save, then run
-- tools/screenshots.sh, which crops each screenshot to its rectangle into docs/images/<name>.png.
-- Only what's inside the rectangle is kept, so chat and other players' names stay out.

local function say(text) print("|cffffd100Quest Triage Shots:|r " .. text) end

-- A frame's rectangle in screen pixels from the top left: left, top, right, bottom.
local function rect(frame)
  local scale, uiHeight = frame:GetEffectiveScale(), UIParent:GetHeight() * UIParent:GetEffectiveScale()
  local px = select(2, GetPhysicalScreenSize()) / uiHeight
  local left, right = frame:GetLeft() * scale * px, frame:GetRight() * scale * px
  local top, bottom = (uiHeight - frame:GetTop() * scale) * px, (uiHeight - frame:GetBottom() * scale) * px
  return left, top, right, bottom
end

local waiting
local shooter = CreateFrame("Frame")
shooter:RegisterEvent("SCREENSHOT_SUCCEEDED")
shooter:RegisterEvent("SCREENSHOT_FAILED")
shooter:SetScript("OnEvent", function(_, event)
  if not waiting then return end
  if event == "SCREENSHOT_SUCCEEDED" then
    say(string.format("Took \"%s\". /reload when done, then run tools/screenshots.sh.", waiting))
  else
    QuestTriageShotsDB[waiting] = nil
    say(string.format("The game couldn't take \"%s\". Try again.", waiting))
  end
  waiting = nil
end)

SLASH_QUESTTRIAGESHOTS1 = "/qtshots"
SlashCmdList.QUESTTRIAGESHOTS = function(msg)
  local name = (msg or ""):match("^%s*([%w%-]+)")
  if not name then
    say("Name the shot, e.g. /qtshots quest-area. It keeps the Quest Triage panel, plus the map, a tooltip or Settings when open.")
    return
  end
  -- One window per shot, plus the tooltip over it: Settings, else the world map, else the panel. Never the map and
  -- the panel together: they sit on opposite sides of the screen, and the crop between them would catch the world,
  -- with other players' names in it.
  local main = (SettingsPanel and SettingsPanel:IsShown() and SettingsPanel)
    or (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame) or QuestTriageFrame
  local frames = {}
  if main and main:IsShown() then table.insert(frames, main) end
  if main ~= SettingsPanel and GameTooltip:IsShown() then table.insert(frames, GameTooltip) end
  if #frames == 0 then
    say("Nothing to photograph: open the Quest Triage panel (/qt) first.")
    return
  end
  local l, t, r, b
  for _, f in ipairs(frames) do
    local fl, ft, fr, fb = rect(f)
    l, t = math.min(l or fl, fl), math.min(t or ft, ft)
    r, b = math.max(r or fr, fr), math.max(b or fb, fb)
  end
  QuestTriageShotsDB = QuestTriageShotsDB or {}
  QuestTriageShotsDB[name] = table.concat({ name, time(), math.floor(l), math.floor(t), math.ceil(r), math.ceil(b) }, "|")
  waiting = name
  Screenshot()
end
