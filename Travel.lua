-- Character-specific travel availability. Recording and routing never take a taxi or cast a spell.
local _, QT = ...
local L = QT.L
local cache = {}
local function place(p)
  if not cache[p] then cache[p] = QT.TransportLocation(p) end
  return cache[p]
end

local slots, source = {}, nil
function QT.NoteTaxiMap()
  local db = QuestTriageCharDB.travel
  local map = GetTaxiMapID()
  slots, source = {}, nil
  local nodes = map and map > 0 and C_TaxiMap.GetAllTaxiNodes(map) or {}
  for _, n in ipairs(nodes) do
    if not n.isMapLayerTransition and n.slotIndex and QT.FlightPoints[n.nodeID] then
      slots[n.slotIndex] = n.nodeID
      if n.state == Enum.FlightPathState.Current then source = n.nodeID end
    end
  end
  if not source then
    -- The classic taxi frame exposes numbered slots; their current origin is the NPC in front of you.
    local origin = QT.PlayerLocation()
    local current, nearest = nil, 120
    for id,p in pairs(QT.FlightPoints) do
      local dist = QT.LegDistance(origin,place(p[2]))
      if dist < nearest then current,nearest=id,dist end
    end
    local byName = {}
    for id,p in pairs(QT.FlightPoints) do byName[p[2][4]] = id end
    for i=1,NumTaxiNodes() do
      local state,name = TaxiNodeGetType(i),TaxiNodeName(i)
      if state=="CURRENT" then source=current; slots[i]=current
      elseif state=="REACHABLE" then slots[i]=byName[name] end
    end
    if not source then return end
    nodes={}
    for slot,id in pairs(slots) do
      if id~=source then table.insert(nodes,{nodeID=id,slotIndex=slot,state=Enum.FlightPathState.Reachable}) end
    end
  end
  local routes = {}
  db.known[source] = true
  for _, n in ipairs(nodes) do
    if slots[n.slotIndex] == n.nodeID and n.state == Enum.FlightPathState.Reachable then
      db.known[n.nodeID] = true
      routes[n.nodeID] = TaxiNodeCost(n.slotIndex)
    end
  end
  db.routes[source] = routes
end

local taxiHooked
function QT.TrackTaxi()
  if taxiHooked or not TakeTaxiNode then return end
  taxiHooked = true
  hooksecurefunc("TakeTaxiNode", function(slot)
    local from, to = source, slots[slot]
    if not from or not to or not QT.FlightPoints[to] then return end
    local start, flying = GetTime(), false
    local timer
    timer = C_Timer.NewTicker(1, function()
      local elapsed = GetTime() - start
      if UnitOnTaxi("player") then flying = true
      elseif flying or elapsed > 8 then
        timer:Cancel()
        if flying and QT.LegDistance(QT.PlayerLocation(), place(QT.FlightPoints[to][2])) < 200 then
          QuestTriageCharDB.travel.times[from..":"..to] = elapsed
        end
      end
    end)
  end)
end

local distances = {}
for _, row in ipairs(QT.FlightDistances) do distances[row[1]..":"..row[2]] = row[3] end

local function spellReady(id)
  if not C_SpellBook.IsSpellKnown(id) or not C_Spell.IsSpellUsable(id) then return false end
  local cd = C_Spell.GetSpellCooldown(id)
  return cd and not issecretvalue(cd.duration) and cd.duration == 0
end

local labels = {
  boat=L["Take the boat to %s"], zeppelin=L["Take the zeppelin to %s"], tram=L["Take the tram to %s"],
  portal=L["Use the portal to %s"], airship=L["Take the airship to %s"],
}
local surveyedMap, surveyedAt
function QT.ReadTravel(origin)
  local db = QuestTriageCharDB.travel
  if origin and origin.uiMapId and (origin.uiMapId~=surveyedMap or GetTime()-(surveyedAt or 0)>60) then
    surveyedMap,surveyedAt=origin.uiMapId,GetTime()
    for _,n in ipairs(C_TaxiMap.GetTaxiNodesForMap(surveyedMap) or {}) do
      if QT.FlightPoints[n.nodeID] and not n.isUndiscovered then db.known[n.nodeID]=true end
    end
  end
  local faction = UnitFactionGroup("player") == "Horde" and 2 or 1
  local travel = { origin = origin, speed = 7, edges = {}, stations = {}, inns = {}, money = GetMoney() }
  local grouped = IsInGroup()
  if not InCombatLockdown() and IsMounted() and not UnitOnTaxi("player") then
    local _, run = GetUnitSpeed("player")
    if not issecretvalue(run) and run and run > 7 then travel.speed = run end
  end
  local function edge(a, b, seconds, text, once, fare)
    if b then table.insert(travel.edges, {from=a,to=b,seconds=seconds,text=text,once=once,fare=fare}) end
  end
  for _, t in ipairs(QT.TransitLinks) do
    if (t[2]==3 or t[2]==faction) and (t[7]==0 or C_Item.GetItemCount(t[7])>0) then
      local a,b = place(t[3]), place(t[4])
      if a and b then edge(a,b,t[5]+t[6]*0.5,labels[t[1]]:format(b.name)) end
    end
  end
  for id, p in pairs(QT.FlightPoints) do
    if p[1]==3 or p[1]==faction then
      local loc=place(p[2])
      if loc then
        table.insert(travel.stations,{id=id,loc=loc,known=db.known[id]})
        for dest, fare in pairs(db.routes[id] or {}) do
          if db.known[dest] and QT.FlightPoints[dest] and fare <= travel.money
              and (not grouped or QT.PartyCanFly(id, dest)) then
            local target=place(QT.FlightPoints[dest][2])
            if target then
              local key=id..":"..dest
              local yards=distances[key] or QT.LegDistance(loc,target)*1.35
              local duration = (db.times[key] or yards/30)+8
              if duration < math.huge then edge(loc,target,duration,L["Fly to %s"]:format(target.name),nil,fare) end
            end
          end
        end
      end
    end
  end
  if InCombatLockdown() then return travel end
  local dbind = QuestTriageCharDB.bind
  local home = dbind and dbind.wx and dbind
  local bindName = GetBindLocation()
  for _, inn in ipairs(QT.BindPlaces) do
    local loc = QT.MapLocation(inn[2],inn[3]/100,inn[4]/100,inn[1][1])
    if loc then
      for _, name in ipairs(inn[1]) do if name == bindName then home = loc end end
      local side = faction == 2 and "H" or "A"
      for _, npc in ipairs(QT.RouteInns) do
        if npc[2][5] == inn[6] and npc[1]:find(side,1,true) then
          table.insert(travel.inns,loc)
          break
        end
      end
    end
  end
  travel.home = home
  local start,duration,enabled=C_Container.GetItemCooldown(6948)
  if not grouped and home and enabled==1 and C_Item.GetItemCount(6948)>0 and start and start+duration <= GetTime() then
    edge(nil,home,12,L["Hearth to %s"]:format(bindName),"hearth")
  end
  if not grouped then
    if home and spellReady(556) then edge(nil,home,12,L["Use %s"]:format(C_Spell.GetSpellName(556)),"recall") end
    for _, t in ipairs(QT.RouteTeleports) do
      if spellReady(t[1]) and (t[2]==0 or C_Item.GetItemCount(t[2])>0) then
        edge(nil,place(t[3]),12,L["Use %s"]:format(C_Spell.GetSpellName(t[1])),"teleport")
      end
    end
  end
  return travel
end

-- A nearby unlock is worthwhile when a later trip leg connects this hub to another flight point.
-- The later flight remains conditional until the flight master's map confirms that connection.
function QT.PlanTravelUnlock(plan, origin, travel)
  if not plan or #plan.steps<2 then return end
  local first=plan.steps[1]
  if first.travel then return end
  local best, benefit
  for _, station in ipairs(travel.stations) do
    local toStation=QT.LegDistance(origin,station.loc)
    local detour=toStation+QT.LegDistance(station.loc,first.loc)-QT.LegDistance(origin,first.loc)
    if not station.known and toStation<1000 and detour<350 then
      for i=2,#plan.steps do
        local target=plan.steps[i].loc
        for _, other in ipairs(travel.stations) do
          local flown=distances[station.id..":"..other.id]
          if flown and QT.LegDistance(other.loc,target)<800 then
            local saved=QT.LegDistance(station.loc,target)/travel.speed-flown/30-detour/travel.speed-20
            -- With two undiscovered ends, the return trip is the first potential flight.
            if not other.known and QT.LegDistance(plan.steps[#plan.steps].loc,station.loc)>450 then saved=0 end
            if saved>25 and (not benefit or saved>benefit) then
              benefit=saved
              best={text=L["Learn the flight path at %s"]:format(station.loc.name),loc=station.loc,travel=true,
                key="learn:"..station.id, reason=L["Later stop: %s. Confirm the connection at the flight master."]:format(other.loc.name)}
            end
          end
        end
      end
    end
  end
  if best then table.insert(plan.steps,1,best); return end
  if IsInGroup() or (QuestTriageDB and QuestTriageDB.opts and not QuestTriageDB.opts.hearthTips) or C_Item.GetItemCount(6948)==0 then return end
  local _,cd,en=C_Container.GetItemCooldown(6948)
  if en~=1 or not cd or cd>0 then return end
  for _, inn in ipairs(travel.inns) do
    if QT.LegDistance(origin,inn)<80 and QT.LegDistance(travel.home,inn)>500 then
      local last=plan.steps[#plan.steps].loc
      if QT.LegDistance(last,inn)<250 then
        for _, s in ipairs(plan.steps) do
          if QT.LegDistance(s.loc,inn)>1000 and s.loc.inst==inn.inst then
            table.insert(plan.steps,1,{text=L["Bind your hearthstone at %s"]:format(inn.name),loc=inn,travel=true,
              reason=L["This trip returns to this hub."]})
            return
          end
        end
      end
    end
  end
end
