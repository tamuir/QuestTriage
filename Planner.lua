-- Power Leveling: score complete pickup/work/hand-in trips, then try bundling two trips.
local _, QT = ...
local L = QT.L
local huge = math.huge
local floor, sqrt = math.floor, math.sqrt

function QT.LevelBand(level)
  local first = level <= 10 and 1 or floor((level - 1) / 5) * 5 + 1
  return first, first == 1 and 10 or first + 4
end

function QT.LegDistance(a, b)
  if not (a and b and a.wx and b.wx and a.inst and a.inst == b.inst) then return huge end
  return sqrt((a.wx - b.wx)^2 + (a.wy - b.wy)^2)
end

-- Index nearby departures once per planning pass. A flight into Ratchet can connect to
-- the boat, for example, without repeatedly comparing every pair for every quest.
local function network(travel)
  local departures, connections = {}, {}
  for _, edge in ipairs(travel.edges) do
    if edge.from then
      local list = departures[edge.from] or {}
      departures[edge.from] = list
      table.insert(list, edge)
    end
  end
  for _, edge in ipairs(travel.edges) do
    if not connections[edge.to] then
      local links = {}
      for loc, rides in pairs(departures) do
        local walk = QT.LegDistance(edge.to, loc)
        if walk < 1500 then
          for _, nextRide in ipairs(rides) do
            table.insert(links, {ride = nextRide, seconds = walk / travel.speed})
          end
        end
      end
      connections[edge.to] = links
    end
  end
  return {edges = travel.edges, speed = travel.speed, connections = connections, money = travel.money or huge}
end

local function leg(a, b, travel, used)
  local seconds = QT.LegDistance(a, b) / travel.speed
  local best, transfer
  if seconds <= 8 then return seconds end
  for _, edge in ipairs(travel.edges) do
    if (not edge.once or not used[edge.once]) and (edge.fare or 0) <= used.money then
      local walk = edge.from and QT.LegDistance(a, edge.from) or 0
      local arrival = walk / travel.speed + edge.seconds
      if arrival < seconds - 8 then
        local t = arrival + QT.LegDistance(edge.to, b) / travel.speed
        if t < seconds - 8 then seconds, best, transfer = t, edge, nil end
        for _, link in ipairs(travel.connections[edge.to]) do
          local ride = link.ride
          local total = arrival + link.seconds + ride.seconds + QT.LegDistance(ride.to, b) / travel.speed
          if total < seconds - 8 and (edge.fare or 0) + (ride.fare or 0) <= used.money then
            seconds, best, transfer = total, edge, ride
          end
        end
      end
    end
  end
  return seconds, best, transfer
end

local function assess(jobs, origin, travel, keep, previous)
  local stages, cursor, used = {}, {}, {money = travel.money}
  for key,value in pairs(previous or {}) do used[key] = value end
  local at, secs, reward = origin, 0, 0
  for i, job in ipairs(jobs) do cursor[i] = 1; reward = reward + job.xp end
  while true do
    local best, idx, route, transfer, elapsed
    for i, job in ipairs(jobs) do
      local s = job.steps[cursor[i]]
      if s then
        local t, edge, nextRide = leg(at, s.loc, travel, used)
        if not elapsed or t < elapsed then best, idx, route, transfer, elapsed = s, i, edge, nextRide, t end
      end
    end
    if not best then break end
    if elapsed == huge then return end
    if route then
      used.money = used.money - (route.fare or 0) - (transfer and transfer.fare or 0)
      if route.once then used[route.once] = true end
      table.insert(stages, { text = route.text, loc = route.from or at, boarding = route.from, icon = "goto", travel = true, key = "ride:"..route.text })
      if transfer then
        table.insert(stages, { text = transfer.text, loc = transfer.from, boarding = transfer.from, icon = "goto", travel = true })
      end
    end
    table.insert(stages, best)
    secs = secs + elapsed + best.work + 5
    at, cursor[idx] = best.loc, cursor[idx] + 1
  end
  local score = reward / math.max(1, secs)
  if stages[1] and stages[1].key == keep then score = score * 1.15 end
  return { steps = stages, score = score, seconds = secs, xp = reward, jobs = jobs, at = at, used = used }
end

-- Near a ding the finish line is the missing XP. Count rewards only at the hand-in.
-- Try several first stops, plus ready-only and shared-objective alternatives. Each
-- continuation starts where the previous hand-in ended, with its remaining travel budget.
function QT.PlanToLevel(jobs, origin, travel, gap, committed)
  if not gap or gap <= 0 or #jobs == 0 then return end
  local search = network(travel)
  local ranked, ready, total = {}, {}, 0
  local available,children,chains={},{},{}
  local function value(trip, missing) return trip.seconds / math.min(trip.xp,missing) end
  local function cheaper(a,b)
    local av,bv=value(a,gap),value(b,gap)
    return av<bv or (av==bv and a.jobs[1].id<b.jobs[1].id)
  end
  for _,job in ipairs(jobs) do
    local p=assess({job},origin,search)
    if p and job.xp>0 then
      ranked[#ranked+1]=p
      available[job.id]=true
      total=total+job.xp
      if job.steps[1].icon=="turnin" then ready[#ready+1]=p end
    end
  end
  for _,p in ipairs(ranked) do
    local parent=p.jobs[1]
    for _,child in ipairs(parent.followups or {}) do
      if not available[child.id] and not children[child.id] then
        children[child.id]={job=child,parent=parent.id}
        total=total+child.xp
        local after=assess({child},p.at,search,nil,p.used)
        if after and p.xp<gap then
          local steps={}
          for _,trip in ipairs({p,after}) do for _,s in ipairs(trip.steps) do steps[#steps+1]=s end end
          chains[#chains+1]={jobs={parent,child},steps=steps,xp=p.xp+child.xp,seconds=p.seconds+after.seconds,at=after.at,used=after.used}
        end
      end
    end
  end
  if total<gap then return end
  table.sort(ranked,cheaper)
  table.sort(ready,cheaper)
  local candidates,added={},{}
  local function candidate(p)
    local job=p.jobs[1]
    if not added[job.id] then candidates[#candidates+1]=job; added[job.id]=true end
  end
  for _,p in ipairs(ready) do candidate(p) end
  for i=1,math.min(12,#ranked) do candidate(ranked[i]) end
  for _,child in pairs(children) do candidates[#candidates+1]=child.job end
  local best
  local function finish(first,readyOnly)
    local taken,trips={},{}
    local xp, seconds=0,0
    -- A few yards of movement should not reverse yesterday's equally good choice.
    local switchCost=committed and first.steps[1].key~=committed and 8 or 0
    local p=first
    while p do
      seconds=seconds+p.seconds
      if best and seconds+switchCost>=best.cost then return end
      for _,job in ipairs(p.jobs) do taken[job.id]=true end
      trips[#trips+1]=p
      xp=xp+p.xp
      if xp>=gap then
        best={steps={},jobs={},seconds=seconds,cost=seconds+switchCost,xp=xp,gap=gap,origin=origin}
        for _,trip in ipairs(trips) do
          for _,s in ipairs(trip.steps) do best.steps[#best.steps+1]=s end
          for _,job in ipairs(trip.jobs) do best.jobs[#best.jobs+1]=job end
        end
        return
      end
      local nextTrip,lowest=nil,math.huge
      for _,job in ipairs(candidates) do
        if not taken[job.id] and (not children[job.id] or taken[children[job.id].parent])
            and (not readyOnly or job.steps[1].icon=="turnin") then
          local next=assess({job},p.at,search,nil,p.used)
          local cost=next and value(next,gap-xp)
          if cost and (cost<lowest or (cost==lowest and job.id<nextTrip.jobs[1].id)) then
            nextTrip,lowest=next,cost
          end
        end
      end
      p=nextTrip
    end
  end
  for _,p in ipairs(ready) do finish(p,true) end
  local readySeconds=best and best.seconds
  for _,chain in ipairs(chains) do finish(chain) end
  for _,p in ipairs(ranked) do if p.xp>=gap then finish(p) end end
  for i=1,math.min(6,#ranked) do finish(ranked[i]) end
  for i=1,math.min(4,#ranked) do
    for j=i+1,math.min(4,#ranked) do
      local a,b=ranked[i].jobs[1],ranked[j].jobs[1]
      if a.xp<gap and b.xp<gap and not (travel.freeSlots==1 and a.steps[1].icon=="pickup" and b.steps[1].icon=="pickup") then
        local pair=assess({a,b},origin,search)
        if pair then finish(pair) end
      end
    end
  end
  if best then best.readySeconds=readySeconds end
  return best
end

function QT.PlanTrips(jobs, origin, travel, keep)
  local search = network(travel)
  local ranked = {}
  for _, job in ipairs(jobs) do
    local plan = assess({job}, origin, search, keep)
    if plan then table.insert(ranked, plan) end
  end
  table.sort(ranked, function(a,b)
    if a.score ~= b.score then return a.score > b.score end
    return a.jobs[1].id < b.jobs[1].id
  end)
  local best = ranked[1]
  -- Pair nearby work even when combining two independent singles would yield the same XP.
  for i = 1, math.min(8, #ranked) do
    local parent = ranked[i].jobs[1]
    -- Chain follow-ups become available only after their parent's hand-in.
    for _, child in ipairs(parent.followups or {}) do
      local steps={}
      for _,s in ipairs(parent.steps) do table.insert(steps,s) end
      for _,s in ipairs(child.steps) do table.insert(steps,s) end
      local chain=assess({{id=parent.id,xp=parent.xp+child.xp,steps=steps}},origin,search,keep)
      if chain and chain.score>best.score then chain.jobs={parent,child}; best=chain end
    end
    for j = i + 1, math.min(8, #ranked) do
      local plan = assess({ranked[i].jobs[1], ranked[j].jobs[1]}, origin, search, keep)
      if plan and plan.score > best.score and not (travel.freeSlots == 1 and
          ranked[i].jobs[1].steps[1].icon=="pickup" and ranked[j].jobs[1].steps[1].icon=="pickup") then best = plan end
    end
  end
  if best then best.origin = origin end
  return best
end

-- Display only: keep adding the best XP-per-minute trip from where the last one ends, so the
-- expanded panel shows the road to the next level. The first trip, and so the next step, is unchanged.
function QT.ExtendRoute(plan, jobs, travel, gap)
  if not plan.at then return end
  local search, taken, pool = network(travel), {}, {}
  local function take(job)
    taken[job.id] = true
    for _, child in ipairs(job.followups or {}) do pool[#pool+1] = child end
  end
  for _, job in ipairs(jobs) do pool[#pool+1] = job end
  for _, job in ipairs(plan.jobs) do take(job) end
  local more = {steps={}, jobs={}, seconds=0, xp=0, gap=gap}
  local at, used, xp = plan.at, plan.used, plan.xp
  -- Cap the greedy search at 12 trips to bound the work per refresh.
  for _ = 1, 12 do
    if xp >= gap then break end
    local best
    for _, job in ipairs(pool) do
      if not taken[job.id] then
        local trip = assess({job}, at, search, nil, used)
        if trip and (not best or trip.score > best.score or (trip.score == best.score and job.id < best.jobs[1].id)) then
          best = trip
        end
      end
    end
    if not best then break end
    for _, s in ipairs(best.steps) do more.steps[#more.steps+1] = s end
    for _, job in ipairs(best.jobs) do more.jobs[#more.jobs+1] = job; take(job) end
    more.seconds, more.xp, xp = more.seconds + best.seconds, more.xp + best.xp, xp + best.xp
    at, used = best.at, best.used
  end
  if more.steps[1] then plan.more = more end
end

local locCache = {}
local function location(p)
  local loc = locCache[p]
  if not loc then loc = QT.MapLocation(p[1], p[2]/100, p[3]/100, p[4]); locCache[p] = loc end
  return loc
end

local function stopLabel(loc)
  if not loc then return end
  local parts = {}
  if loc.name and loc.name ~= loc.zone then parts[#parts+1] = loc.name end
  if loc.zone then parts[#parts+1] = loc.zone end
  if loc.x and loc.y then parts[#parts+1] = ("%.1f, %.1f"):format(loc.x,loc.y) end
  if #parts > 0 then return table.concat(parts," · ") end
end

local function sameStop(a,b)
  if not (a and b) then return false end
  if a == b then return true end
  return a.uiMapId and a.uiMapId == b.uiMapId and a.name and a.name == b.name
    and a.x and b.x and a.y and b.y and math.abs(a.x-b.x)<0.05 and math.abs(a.y-b.y)<0.05
end

local DIM = "|cffaaaaaa"

local function handinReward(xp,remaining,target)
  local text=L["+%s XP"]:format(QT.Commas(xp))
  if remaining and remaining>0 then
    remaining=remaining-xp
    text=text.." · "..(remaining>0 and L["%s XP left"]:format(QT.Commas(remaining)) or L["Level %d"]:format(target))
  end
  return text,remaining
end

function QT.RouteRows(plan,level)
  local more = plan.more or {steps={},jobs={},seconds=0,xp=0}
  local xp, gap = plan.xp+more.xp, plan.gap or more.gap
  local minutes = math.ceil((plan.seconds+more.seconds)/60)
  local target = plan.targetLevel or (level or UnitLevel("player"))+1
  local title, note
  if gap and xp>=gap then
    title = L["Level %d in ~%d min"]:format(target,minutes)
    note = L["%s XP needed · %s XP on this trip"]:format(QT.Commas(gap),QT.Commas(xp))
  else
    title = L["~%d min · %s quest XP"]:format(minutes,QT.Commas(xp))
    local short = gap and gap-xp or plan.shortfall
    if short then note = L["After this trip: %s XP to level %d"]:format(QT.Commas(short),target) end
  end
  local jobs, steps = {}, {}
  for _,list in ipairs({plan.jobs,more.jobs}) do for _,job in ipairs(list) do jobs[job.id] = job end end
  for _,list in ipairs({plan.steps,more.steps}) do for _,s in ipairs(list) do steps[#steps+1] = s end end
  -- One row per stop: what to do there, XP on the right; the full label and every step go in the tooltip.
  local stops, cur, lastStop, remaining = {}, nil, nil, gap
  for _,s in ipairs(steps) do
    local job = jobs[s.questID]
    local interaction = s.icon=="pickup" or s.icon=="turnin" or s.icon=="objective"
    local place = interaction and stopLabel(s.loc)
    local text = s.text
    if place and s.icon=="pickup" and job and job.title and s.loc.name then
      text = L["Pick up %s"]:format(job.title)
    end
    if s.bagReady then text = text.." · "..L["quest item in bags"] end
    local action = text
    if s.icon=="turnin" and job then
      local reward
      reward,remaining=handinReward(job.xp,remaining,target)
      text=text.." · "..reward
    end
    if not place or not sameStop(lastStop,s.loc) then
      local n = #stops+1
      local boarding = s.travel and stopLabel(s.boarding)
      local label = n..". "..(place or text)..(boarding and (" · "..boarding) or "")
      -- Travel is the connective tissue between stops: dimmed, details in the tooltip.
      cur = {style="routeStop", label=label, text=DIM..text.."|r",
        loc=place and s.loc or s.boarding, steps={}, checks={}, xp=0, key=s.key or label}
      cur.kind = cur.loc and "goto" or nil
      stops[n] = cur
    end
    if place then cur.steps[#cur.steps+1] = text end
    if s.reason then cur.steps[#cur.steps+1] = s.reason end
    if s.icon=="turnin" and job then cur.xp = cur.xp+job.xp end
    if interaction and s.questID then cur.checks[#cur.checks+1] = {icon=s.icon, questID=s.questID} end
    -- The row says the stop's main action (a hand-in beats a pickup beats an objective); a camp names
    -- the quest and, dimmed, what to find there.
    if interaction and (not cur.icon or (s.icon=="turnin" and cur.icon~="turnin")) then
      local camp = s.icon=="objective" and s.loc.name ~= s.loc.zone and s.loc.name
      cur.icon = s.icon
      cur.text = camp and ((job and job.title or action)..DIM.." · "..camp.."|r") or action
    end
    lastStop = place and s.loc or nil
  end
  if stops[1] then stops[#stops].last = true end
  for _,stop in ipairs(stops) do
    stop.tip = {stop.label}
    for _,line in ipairs(stop.steps) do stop.tip[#stop.tip+1] = line end
    if stop.xp > 0 then stop.right = L["+%s XP"]:format(QT.Commas(stop.xp)) end
  end
  return stops, title, note, minutes
end

function QT.RouteOverview(plan)
  if not plan then return L["No route is available from your current position."] end
  local stops, title, note = QT.RouteRows(plan)
  local lines={title, note}
  for _,stop in ipairs(stops) do
    lines[#lines+1]=""
    lines[#lines+1]=stop.label
    for _,line in ipairs(stop.steps) do lines[#lines+1]="    "..line end
  end
  return table.concat(lines,"\n")
end

local function matchesCharacter(q,race,faction)
  return q.faction:find(faction,1,true) and (q.races==0 or (race and floor(q.races / 2^(race-1)) % 2 == 1))
end

function QT.RouteBands()
  local lines = {L["Catalog zones for your character"]}
  local faction = UnitFactionGroup("player")=="Horde" and "H" or "A"
  local _,_,race = UnitRace("player")
  local zones = {}
  for _, q in pairs(QT.RouteQuests) do
    if matchesCharacter(q,race,faction) then
      local lo = QT.LevelBand(q.level)
      zones[lo] = zones[lo] or {}
      zones[lo][q.giver[1]] = true
    end
  end
  for i, maps in ipairs(QT.RouteRegions) do
    local lo,hi=QT.LevelBand(i==1 and 1 or i*5+1)
    local names={}
    for _,map in ipairs(maps) do
      local info=zones[lo] and zones[lo][map] and C_Map.GetMapInfo(map)
      if info then table.insert(names,info.name) end
    end
    if #names>0 then table.insert(lines,lo.."–"..hi.."  "..table.concat(names,", ")) end
  end
  return table.concat(lines,"\n")
end

function QT.RouteEligible(q, level, race, faction, done)
  if q.min > level or q.level > level + 2 or q.level < level - 5 then return false end
  if not matchesCharacter(q,race,faction) then return false end
  if q.closedBy and done(q.closedBy) then return false end
  for _, id in ipairs(q.all or {}) do if not done(id) then return false end end
  if q.any then
    for _, id in ipairs(q.any) do if done(id) then return true end end
    return false
  end
  return true
end

local function makeJob(id, q, held, complete, origin)
  local steps = {}
  local title = held and held.title or q.title
  local function step(icon, loc, label, work, key)
    if not loc then return false end
    table.insert(steps, { icon = icon, loc = loc, text = label, work = work, questID = id, key = key..id })
    return true
  end
  if not held and not step("pickup", location(q.giver), L["Pick up %s from %s"]:format(title, q.giver[4]), 5, "pickq:") then return end
  local carrying=q.items and C_Item and C_Item.GetItemCount
  for _,item in ipairs(q.items or {}) do
    if not carrying or C_Item.GetItemCount(item[1])<item[2] then carrying=false; break end
  end
  if carrying and not held then steps[1].bagReady=true end
  if not complete and not carrying then
    local progress = held and QT.Progress(held) or 0
    local groupSpeed=1 + 0.25 * (held and held.shared or 0)
    local work = 75 * (1 - progress) / groupSpeed
    if held and held.loc and held.loc.wx and (#q.camps > 0 or #(held.objectives or {}) > 0) then
      local credits=0
      for _,obj in ipairs(held.objectives or {}) do credits=credits+math.max(0,(obj.need or 0)-(obj.have or 0)) end
      local estimate=math.max(work * math.max(1,#q.camps),credits * 20 / groupSpeed)
      step("objective", held.inArea and origin or held.loc, L["Go do %s"]:format(title), held.secondsLeft or estimate, "do:")
    else
      for _, camp in ipairs(q.camps) do
        if not step("objective", location(camp), L["%s · %s"]:format(title, camp[4]), work, "do:") then return end
      end
    end
  end
  local finish = complete and held.loc and held.loc.wx and held.loc or location(q.finish)
  if not step("turnin", finish, L["Hand in %s"]:format(title), 6, "end:") then return end
  local xp=held and held.xp or q.xp
  if xp<=0 then return end
  return { id = id, title = title, steps = steps, xp = xp }
end

function QT.PreviewBand(level)
  local origin = QT.PlayerLocation()
  if not origin then return L["No route is available from your current position."] end
  local lo,hi = QT.LevelBand(level)
  local lines={L["Levels %d–%d · preview from your position"]:format(lo,hi)}
  local _,_,race=UnitRace("player")
  local side=UnitFactionGroup("player")=="Horde" and "H" or "A"
  local simulated={}
  local function done(id) return simulated[id] or C_QuestLog.IsQuestFlaggedCompleted(id) end
  local travel=QT.ReadTravel(origin)
  for trip=1,3 do
    local jobs={}
    for id,q in pairs(QT.RouteQuests) do
      if q.level>=lo and q.level<=hi and not done(id) and not QuestTriageCharDB.hidden[id]
          and QT.RouteEligible(q,level,race,side,done) then
        local job=makeJob(id,q,nil,false,origin)
        if job then table.insert(jobs,job) end
      end
    end
    local plan=QT.PlanTrips(jobs,origin,travel)
    if not plan then break end
    table.insert(lines,"")
    for _,s in ipairs(plan.steps) do
      table.insert(lines,s.text.." · "..(s.loc.zone or "?"))
    end
    for _,job in ipairs(plan.jobs) do simulated[job.id]=true end
    origin=plan.steps[#plan.steps].loc
    -- Future cooldowns are unknown. Preview reusable scheduled travel on subsequent trips.
    for i=#travel.edges,1,-1 do if travel.edges[i].once then table.remove(travel.edges,i) end end
  end
  if #lines==1 then table.insert(lines,L["No eligible catalog trip at this level."]) end
  return table.concat(lines,"\n")
end

-- Compare currently eligible offers and accepted quests using the character's observed state.
function QT.BuildPowerPlan(player, buckets, offers, origin, travel, goalOnly)
  if not origin or player.level >= 60 then return end
  local db = QuestTriageCharDB
  local _, _, race = UnitRace("player")
  local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
  if not race then return end
  local held, eligible, completed, available, jobs = {}, {}, {}, {}, {}
  local questie = QT.GuideReady()
  for _, p in ipairs(offers or {}) do if not p.event and not p.isGroup then available[p.questID] = true end end
  for bucket, list in pairs(buckets) do
    for _, e in ipairs(list) do
      local id = e.quest.questID
      if id then held[id] = e.quest; eligible[id] = bucket end
    end
  end
  local function done(id)
    if completed[id] == nil then completed[id] = C_QuestLog.IsQuestFlaggedCompleted(id) or false end
    return completed[id]
  end
  local _, logCount = C_QuestLog.GetNumQuestLogEntries()
  travel.freeSlots = logCount and C_QuestLog.GetMaxNumQuestsCanAccept() - logCount
  local full = travel.freeSlots and travel.freeSlots <= 0
  for id, q in pairs(QT.RouteQuests) do
    local h, bucket = held[id], eligible[id]
    local ok = bucket == "turnin" or bucket == "now" and not h.slow and not (h.blockers and h.blockers[1])
    if not h and not full and not db.hidden[id] and not db.deferred[id] and not db.notOffered[id]
        and (not questie or available[id]) and QT.RouteEligible(q, player.level, race, faction, done)
        and not done(id) and not C_QuestLog.GetLogIndexForQuestID(id) then
      local tag = C_QuestLog.GetQuestTagInfo(id)
      ok = not tag or (not tag.isElite and not ({[1]=true,[41]=true,[62]=true,[81]=true,[85]=true,[88]=true,[89]=true})[tag.tagID])
    end
    if ok then
      local job = makeJob(id, q, h, bucket == "turnin", origin)
      if job then table.insert(jobs, job) end
    end
  end
  -- Live offers extend the bundled bands when Questie can identify every stop.
  if questie and not full then
    for _, p in ipairs(offers or {}) do
      if available[p.questID] and not QT.RouteQuests[p.questID] and not held[p.questID] and not db.hidden[p.questID]
          and not db.deferred[p.questID] and p.giver and p.giver.yards and p.giver.yards<2500
          and p.level and p.level>=player.level-4 and p.level<=player.level+2 then
        QT.PickupItinerary(p)
        if p.camps and p.finish and p.xp and p.xp>0 then
          local steps={{icon="pickup",loc=p.giver,questID=p.questID,key="pickq:"..p.questID,work=5,
            text=L["Pick up %s from %s"]:format(p.title,p.giver.name or p.title)}}
          for _,loc in ipairs(p.camps) do table.insert(steps,{icon="objective",loc=loc,questID=p.questID,
            key="do:"..p.questID,work=75,text=L["Go do %s"]:format(p.title)}) end
          table.insert(steps,{icon="turnin",loc=p.finish,questID=p.questID,key="end:"..p.questID,
            work=6,text=L["Hand in %s"]:format(p.title)})
          table.insert(jobs,{id=p.questID,title=p.title,steps=steps,xp=p.xp})
        end
      end
    end
  end
  -- Completed quests outside the catalog can still be the most profitable stop.
  for _, e in ipairs(buckets.turnin) do
    local q = e.quest
    if q.questID and not QT.RouteQuests[q.questID] and q.loc and q.loc.wx and (q.xp or 0)>0 then
      table.insert(jobs,{id=q.questID,title=q.title,xp=q.xp,steps={{icon="turnin",questID=q.questID,key="end:"..q.questID,
        text=L["Hand in %s"]:format(q.title),loc=q.loc,work=6}}})
    end
  end
  if questie then
    for _,e in ipairs(buckets.now) do
      local q=e.quest
      -- q.helpers: the marker shows one of several stops, so the trip can't be priced.
      if q.questID and not QT.RouteQuests[q.questID] and not q.slow and not q.helpers and not (q.blockers and q.blockers[1])
          and q.loc and q.loc.wx and (q.xp or 0)>0 then
        local finish=QT.QuestFinisher(q.questID)
        if finish then
          local remaining=math.max(1,75*(1-QT.Progress(q)))
          table.insert(jobs,{id=q.questID,title=q.title,xp=q.xp,steps={
            {icon="objective",questID=q.questID,key="do:"..q.questID,text=L["Go do %s"]:format(q.title),
              loc=q.inArea and origin or q.loc,work=q.secondsLeft or remaining},
            {icon="turnin",questID=q.questID,key="end:"..q.questID,text=L["Hand in %s"]:format(q.title),loc=finish,work=6}}})
        end
      end
    end
  end
  for _, job in ipairs(jobs) do
    local parent=QT.RouteQuests[job.id]
    local childId=parent and parent.closedBy
    local child=childId and QT.RouteQuests[childId]
    if child and not held[childId] and not done(childId) and not db.hidden[childId] and not db.deferred[childId]
        and QT.RouteEligible(child,player.level,race,faction,function(id) return id==job.id or done(id) end) then
      -- Only project an explicit prerequisite relationship in both records.
      for _, reqs in ipairs({child.any or {},child.all or {}}) do
        for _, required in ipairs(reqs) do
          if required==job.id then job.followups={makeJob(childId,child,nil,false,origin)} end
        end
      end
    end
  end
  local focus = QT.PartyFocus()
  if focus then
    for _,job in ipairs(jobs) do
      if job.id==focus then return QT.PlanTrips({job},origin,travel,db.committed) end
    end
  end
  local gap=(player.xpMax or 0)-(player.xp or 0)
  if gap>0 and (goalOnly or gap<=player.xpMax*0.25 or select(2,QT.QuestForecast(buckets,player))) then
    local goal=QT.PlanToLevel(jobs,origin,travel,gap,db.committed)
    if goal then goal.targetLevel=player.level+1; return goal end
    local partial=QT.PlanTrips(jobs,origin,travel,db.committed)
    if partial then partial.shortfall=math.max(0,gap-partial.xp); QT.ExtendRoute(partial,jobs,travel,gap) end
    return partial
  end
  if goalOnly then return end
  local plan=QT.PlanTrips(jobs, origin, travel, db.committed)
  if plan and gap>0 then QT.ExtendRoute(plan,jobs,travel,gap) end
  return plan
end

function QT.PowerAction(plan, player)
  local first = plan.steps[1]
  local lo, hi = QT.LevelBand(player.level)
  local tip = { L["Levels %d–%d · estimated trip: %d min"]:format(lo, hi, math.ceil(plan.seconds / 60)) }
  if plan.gap then
    table.insert(tip,L["%s XP needed · %s XP on this trip"]:format(QT.Commas(plan.gap),QT.Commas(plan.xp)))
    if plan.readySeconds and math.ceil(plan.readySeconds/60)>math.ceil(plan.seconds/60) then
      table.insert(tip,L["Ready hand-ins alone: ~%d min"]:format(math.ceil(plan.readySeconds/60)))
    end
  end
  for i=1,math.min(3,#plan.steps) do table.insert(tip, i..". "..plan.steps[i].text) end
  if first.loc then
    local destination=stopLabel(first.boarding or (not first.travel and first.loc))
    if destination then table.insert(tip,destination) end
  end
  local loc = first.loc and setmetatable({}, {__index=first.loc})
  local yards = QT.LegDistance(plan.origin, loc)
  if loc and yards < huge then loc.yards = yards end
  local reason=first.reason
  if plan.gap and not reason then
    reason=L["Level %d in ~%d min · %s XP"]:format(player.level+1,math.ceil(plan.seconds/60),QT.Commas(plan.xp))
  elseif plan.shortfall and not reason then
    reason=L["%s XP here · %s XP still needed"]:format(QT.Commas(plan.xp),QT.Commas(plan.shortfall))
  end
  local stepDetail
  if first.icon=="turnin" then
    for _,job in ipairs(plan.jobs) do
      if job.id==first.questID then
        stepDetail=handinReward(job.xp,plan.gap or (plan.shortfall and plan.shortfall+plan.xp),plan.targetLevel or player.level+1)
        break
      end
    end
  elseif first.bagReady then
    stepDetail=L["quest item in bags"]
  elseif first.travel and not first.reason and plan.steps[2] and plan.steps[2].loc and plan.steps[2].loc.name then
    stepDetail=L["Next: %s"]:format(plan.steps[2].loc.name)
  end
  return { text=first.text, planned=true, stepDetail=stepDetail, icon=first.travel and "hearth" or first.icon, sub=reason or (plan.steps[2] and plan.steps[2].text) or tip[1],
    loc=loc, kind=loc and "goto" or "quest", data=first.questID, key=first.key, skips=first.icon=="pickup" and {{questID=first.questID,title=QT.RouteQuests[first.questID] and QT.RouteQuests[first.questID].title or first.text}} or nil,
    questID=first.questID, tip=tip }
end

-- Stops of the last route that game data now shows as done (picked up, objectives complete, handed in) are
-- added to done = { {key, text}, ... } once each, so the timeline can check them off. Never on a guess:
-- a camp stop only counts once its whole quest is complete.
function QT.RecordRouteDone(prev, quests, done)
  if not prev then return end
  local log, have = {}, {}
  for _, q in ipairs(quests or {}) do log[q.questID] = q end
  for _, s in ipairs(done) do have[s.key] = true end
  local function finished(c)
    if C_QuestLog.IsQuestFlaggedCompleted(c.questID) then return true end
    local q = log[c.questID]
    return q ~= nil and (c.icon == "pickup" or (c.icon == "objective" and q.isComplete == true))
  end
  for _, stop in ipairs((QT.RouteRows(prev))) do
    local ok = stop.checks[1] ~= nil and not have[stop.key]
    for _, c in ipairs(stop.checks) do ok = ok and finished(c) end
    if ok then
      done[#done+1] = { key = stop.key, text = (stop.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) }
      have[stop.key] = true
    end
  end
end

-- The panel shows the route a few stops at a time (size). Unscrolled (offset nil) the window starts at the
-- last stop done: done, now, next. Returns the first and last step shown and the largest offset.
function QT.RouteWindow(total, done, size, offset)
  local max = math.max(0, total - size)
  local first = math.max(0, math.min(max, offset or done - 1))
  return first + 1, math.min(total, first + size), max
end
