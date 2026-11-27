local QT = ...
for _, f in ipairs({"RouteCatalog","TravelCatalog","Planner","Travel","Party"}) do
  assert(loadfile(f..".lua"))("QuestTriage",QT)
end

-- A previous default moves forward once. Explicit choices made after the
-- update and unrelated settings survive a later login.
local defaults={style="power",compact=true}
local fresh,old,single={},{style="batch",compact=false},{style="single"}
for _,opts in ipairs({fresh,old,single}) do QT.InitializeOptions(opts,defaults) end
assert(fresh.style=="power" and fresh.compact and old.style=="power" and old.compact==false)
assert(single.style=="single")
old.style="batch"
QT.InitializeOptions(old,defaults)
assert(old.style=="batch")

local counts, sample = {}, nil
for id,q in pairs(QT.RouteQuests) do
  local lo = QT.LevelBand(q.level)
  counts[lo]=(counts[lo] or 0)+1
  for _, p in ipairs({q.giver,q.finish,unpack(q.camps)}) do
    assert(p[1]>0 and p[2]>=0 and p[2]<=100 and p[3]>=0 and p[3]<=100 and p[4],id)
  end
  assert(q.xp>0 and q.title and q.min<=60)
  if id==878 then sample=q end
end
for _,lo in ipairs({1,11,16,21,26,31,36,41,46,51,56}) do assert(counts[lo]>0) end
local function never() return false end
assert(QT.RouteEligible(sample,21,2,"H",never))
assert(not QT.RouteEligible(sample,21,1,"A",never))
local follow=QT.RouteQuests[7]
assert(not QT.RouteEligible(follow,1,1,"A",never))
assert(QT.RouteEligible(follow,1,1,"A",function(id) return id==783 end))

local function at(x,instance)
  return {wx=x,wy=0,inst=instance or 1,name=tostring(x),zone="The Barrens",uiMapId=1413,x=45,y=59}
end
local origin=at(0)
local target=at(2400)
local jobs={{id=878,xp=1600,steps={
  {loc=origin,text="Pick up",icon="pickup",questID=878,work=5,key="pickq:878"},
  {loc=target,text="Work",icon="objective",questID=878,work=60,key="do:878"},
  {loc=origin,text="Hand in",icon="turnin",questID=878,work=5,key="end:878"},
}}}
local travel={speed=7,edges={},stations={{id=25,loc=origin},{id=77,loc=target}},inns={}}
local plan=QT.PlanTrips(jobs,origin,travel)
assert(#plan.steps==3 and plan.steps[1].icon=="pickup")
QT.PlanTravelUnlock(plan,origin,travel)
assert(plan.steps[1].key=="learn:25" and #plan.steps==4,"learn now for a future return leg, even with both nodes unknown")
for _,s in ipairs(plan.steps) do assert(not s.text:match("^Fly")) end
travel.stations[1].known,travel.stations[2].known=true,true
travel.edges={{from=origin,to=target,seconds=45,text="Fly outbound"}}
local flown=QT.PlanTrips(jobs,origin,travel)
assert(flown.steps[2].text=="Fly outbound" and flown.seconds<plan.seconds)
assert(flown.steps[#flown.steps].text=="Hand in","outbound flight does not imply return service")

-- Run through the production catalog reader and card with an empty log and no Questie.
QuestTriageCharDB={hidden={},deferred={},notOffered={},travel={known={},routes={},times={}}}
C_QuestLog={GetNumQuestLogEntries=function() return 0,0 end,GetMaxNumQuestsCanAccept=function() return 20 end,
  IsQuestFlaggedCompleted=never,GetLogIndexForQuestID=function() end,GetQuestTagInfo=function() end}
UnitRace=function() return "Orc","Orc",2 end
UnitFactionGroup=function() return "Horde" end
QT.GuideReady=never
QT.MapLocation=function(map,x,y,name)
  -- Only the Barrens is reachable in this fixture.
  local p=at(x*10000,map==1413 and 1 or map)
  p.wy,p.name,p.uiMapId,p.x,p.y=y*10000,name,map,x*100,y*100
  return p
end
local player={level=21,zone="The Barrens",greenRange=6}
local buckets=QT.Triage({},player)
local camp=QT.MapLocation(1413,0.4455,0.5926,"Camp Taurajo")
local p=assert(QT.BuildPowerPlan(player,buckets,nil,camp,{speed=7,edges={}}))
local row=QT.BuildRows(buckets,player,{}, {style="power",plan=p,compact=true})[1]
assert(row.key:match("^pickq:") and row.loc and #row.tip>=3)
local id=p.steps[1].questID
QuestTriageCharDB.notOffered[id]=true
local replaced=QT.BuildPowerPlan(player,buckets,nil,camp,{speed=7,edges={}})
assert(not replaced or replaced.steps[1].questID~=id)
QuestTriageCharDB.notOffered[id]=nil
local doneQuest={questID=id,title=QT.RouteQuests[id].title,isComplete=true,level=21,loc=camp,xp=4000,objectives={}}
local resumed=QT.BuildPowerPlan(player,QT.Triage({doneQuest},player),nil,camp,{speed=7,edges={}})
assert(resumed.steps[1].icon=="turnin" and resumed.steps[1].questID==id)
local timer={questID=998,title="Timer",level=21,timeLeft=15,loc=camp,objectives={}}
local timed=QT.BuildRows(QT.Triage({timer},player),player,{}, {style="power",plan=p})[1]
assert(timed.questID==998)

-- The Barrens screenshot. A banked 3,850 XP can require an intercontinental
-- delivery. The planner has to beat that complete trip, not its first stop.
local function ready(id,title,xp,loc)
  return {id=id,title=title,xp=xp,steps={{icon="turnin",questID=id,key="end:"..id,
    text="Hand in "..title,loc=loc,work=6}}}
end
local campA,campB,remote=at(160),at(360),at(5000,2)
local banked={ready(878,"Tribes at War",1650,campA),ready(6629,"Kill Grundig Darkcloud",1350,campB),
  ready(3301,"Mura Runetotem",850,remote)}
local function nearby(xp,camp)
  local job=ready(400,"Local quest",xp,camp)
  table.insert(job.steps,1,{icon="objective",questID=400,key="do:400",text="Work nearby",loc=camp,work=60})
  return job
end
local transit={speed=7,edges={{from=at(5000),to=remote,seconds=120,text="Ride to Silverpine"}}}
local gap=3663
local selected=assert(QT.PlanToLevel(banked,origin,transit,gap))
assert(#selected.jobs==3 and selected.xp==3850 and selected.readySeconds==selected.seconds)
banked[4]=nearby(700,campB)
local localTrip=assert(QT.PlanToLevel(banked,origin,transit,gap))
assert(localTrip.xp==3700 and #localTrip.jobs==3 and localTrip.seconds<localTrip.readySeconds)
for _,s in ipairs(localTrip.steps) do assert(s.questID~=3301) end
local player21={level=21,xp=20337,xpMax=24000}
local log={}
for _,job in ipairs(banked) do
  log[#log+1]={questID=job.id,title=job.title,level=21,xp=job.xp,objectives={},
    loc=job.steps[1].loc,isComplete=job.steps[1].icon=="turnin"}
end
local actual=QT.Triage(log,player21)
local label,_,details=QT.QuestForecast(actual,player21,true,localTrip)
assert(label=="Level 22 · hand in 2 ready + finish 1" and details.turnin.xp==3000 and details.now.xp==700)
for _,style in ipairs({"power","batch","single"}) do
  local rows=QT.BuildRows(actual,player21,{bagQuest={name="Item",link="X"}},{style=style,plan=localTrip})
  assert(rows[1].text==localTrip.steps[1].text and rows[1].planned)
  local found=false
  for _,row in ipairs(rows) do if row.style=="forecast" then assert(row.text==label); found=true end end
  assert(found)
end
banked[4]=nearby(662,campB)
assert(QT.PlanToLevel(banked,origin,{speed=7,edges={}},gap)==nil,"one XP short cannot promise a level")
local short=QT.PlanToLevel({banked[1]},campA,transit,399)
assert(#short.steps==1 and short.steps[1].icon=="turnin")

-- Early in a level the next step is the best trip, but the expanded route still runs to the ding.
local spread={ready(1,"A",500,at(100)),ready(2,"B",500,at(200)),ready(3,"C",500,at(3000))}
local early=assert(QT.PlanTrips(spread,origin,{speed=7,edges={}}))
local firstStep=early.steps[1]
QT.ExtendRoute(early,spread,{speed=7,edges={}},1400)
assert(early.steps[1]==firstStep and early.more and early.xp+early.more.xp==1500,"extension keeps the next step")
local routeRows,routeTitle=QT.RouteRows(early,21)
assert(routeTitle:match("^Level 22 in") and #routeRows==3,"one stop per hand-in, all the way to level 22")
UnitLevel=function() return 21 end
assert(QT.RouteOverview(early):find("Hand in C",1,true),"/qt route shows the whole route too")

-- The real Taurajo follow-up becomes eligible after Tribes. A shard already in
-- the bags makes it a second hand-in with no hunting leg.
local originalGuide=QT.GuideReady
QT.GuideReady=function() return true end
local carryShard=true
C_Item={GetItemCount=function(id) return id==5075 and carryShard and 1 or 0 end}
local readyLog={}
for i=1,3 do
  local job=banked[i]
  local f=QT.RouteQuests[job.id].finish
  local loc=QT.MapLocation(f[1],f[2]/100,f[3]/100,f[4])
  readyLog[i]={questID=job.id,title=job.title,level=21,xp=job.xp,loc=loc,isComplete=true,objectives={}}
end
local function replay()
  return assert(QT.BuildPowerPlan(player21,QT.Triage(readyLog,player21),{},camp,{speed=7,edges={}},true))
end
local bagged=replay()
assert(bagged.xp==4250 and bagged.steps[1].questID==878)
local accepted,handed=false,false
for _,s in ipairs(bagged.steps) do
  if s.questID==5052 then
    assert(s.icon~="objective")
    if s.icon=="pickup" then accepted=true elseif s.icon=="turnin" then assert(accepted); handed=true end
  end
end
assert(handed)

-- Replay the player's five actions. The hearth lands at the Crossroads and the
-- last walk ends at the NPC. The report groups the three Taurajo interactions.
local thungrim=QT.MapLocation(1413,.5723,.3034,"Thun'grim Firegaze")
local crossroads=QT.MapLocation(1413,.52,.30,"The Crossroads")
readyLog[4]={questID=1825,title="Speak with Thun'grim",level=20,xp=775,loc=thungrim,isComplete=true,objectives={}}
local hearth={from=nil,to=crossroads,seconds=12,once="hearth",text="Hearth to The Crossroads"}
local hearthTrip=assert(QT.BuildPowerPlan(player21,QT.Triage(readyLog,player21),{},camp,{speed=7,edges={hearth}},true))
assert(hearthTrip.xp==3675 and #hearthTrip.steps==5)
local report=QT.RouteOverview(hearthTrip)
assert(report:find("3,663 XP needed · 3,675 XP on this trip",1,true))
assert(report:find("1. Mangletooth · The Barrens · 44.5",1,true) or report:find("1. Mangletooth · The Barrens · 44.6",1,true))
assert(report:find("Hand in Tribes at War · +1,650 XP · 2,013 XP left",1,true))
assert(report:find("Pick up Blood Shards of Agamaggan · quest item in bags",1,true))
assert(report:find("Hand in Blood Shards of Agamaggan · +1,250 XP · 763 XP left",1,true))
assert(report:find("2. Hearth to The Crossroads\n",1,true))
assert(report:find("3. Thun'grim Firegaze · The Barrens · 57.2, 30.3",1,true))
assert(report:find("Hand in Speak with Thun'grim · +775 XP · Level 22",1,true))
assert(not report:find("1–10",1,true))
local visible=QT.BuildRows(QT.Triage(readyLog,player21),player21,{},{plan=hearthTrip,style="power",compact=true})
assert(#visible==1 and visible[1].sub=="+1,650 XP · 2,013 XP left" and visible[1].planned)
local expanded=QT.BuildRows(QT.Triage(readyLog,player21),player21,{},{plan=hearthTrip,style="power"})
local stops,actions={},0
for _,row in ipairs(expanded) do
  assert(row.style~="routeStep","one row per stop")
  assert(not (row.style=="header" and row.data=="route"),"the stepper hangs off the Next card, no header")
  if row.style=="routeMore" then assert(row.text:match("^Level 22 in ~%d+ min$") and not row.kind and not row.rail and row.tip[1]:find("XP needed",1,true)) end
  if row.style=="routeStop" then
    stops[#stops+1]=row
    for i=2,#row.tip do actions=actions+1; assert(report:find(row.tip[i],1,true)) end
  end
end
assert(#stops==3 and actions==4,"every stop, steps in the tooltip")
assert(stops[1].current and stops[1].num==1 and stops[1].text=="Hand in Tribes at War" and stops[1].right=="+2,900 XP")
assert(not stops[2].num and stops[2].text:find("Hearth to The Crossroads",1,true),"travel has no number")
assert(stops[3].num==2 and stops[3].last and stops[3].loc==thungrim and stops[3].kind=="goto" and stops[3].text=="Hand in Speak with Thun'grim")
-- Game data checks a stop off: Tribes and the shards handed in finish the Mangletooth stop, once.
local flagged=C_QuestLog.IsQuestFlaggedCompleted
C_QuestLog.IsQuestFlaggedCompleted=function(id) return id==878 or id==5052 end
local done={}
QT.RecordRouteDone(hearthTrip,readyLog,done)
QT.RecordRouteDone(hearthTrip,readyLog,done)
assert(#done==1 and done[1].text=="Hand in Tribes at War","only the stop game data shows done, once")
C_QuestLog.IsQuestFlaggedCompleted=function() return false end
local partial={}
QT.RecordRouteDone(hearthTrip,{},partial)
assert(#partial==0,"nothing done, nothing checked")
C_QuestLog.IsQuestFlaggedCompleted=flagged
-- Every stop is listed in order (done, current, the rest); the panel shows ten at a time from the last done.
local realRows=QT.RouteRows
QT.RouteRows=function() local s={} for i=1,30 do s[i]={style="routeStop",text="S"..i,tip={},checks={{}}} end return s,"Level 22 in ~9 min" end
local list,foot={}
for _,r in ipairs(QT.BuildRows(QT.Triage(readyLog,player21),player21,{},{plan=hearthTrip,style="power",routeDone={{text="A"},{text="B"}}})) do
  if r.style=="routeStop" then list[#list+1]=r elseif r.style=="routeMore" then foot=r end
end
assert(#list==32 and list[2].done and list[2].step==2 and list[3].current and list[3].num==3 and list[32].step==32)
assert(foot.total==32 and foot.doneCount==2 and not foot.done and foot.title=="Level 22 in ~9 min")
QT.RouteRows=realRows
local first,last,max=QT.RouteWindow(32,2,3)
assert(first==2 and last==4 and max==29,"folded: the last done, now, next")
assert(select(2,QT.RouteWindow(32,0,3))==3,"nothing done yet: now and the next two")
first,last,max=QT.RouteWindow(32,2,10)
assert(first==2 and last==11 and max==22,"open: ten from the last done")
assert(select(2,QT.RouteWindow(6,3,10))==6,"short routes show whole")
first,last=QT.RouteWindow(32,2,10,99)
assert(first==23 and last==32,"scrolling stops at the end")

-- Rebuild the normal panel from the next two snapshots of XP, log and offers.
-- Neither route advancement nor the inventory hint uses a slash command.
local afterTribes={level=21,xp=player21.xp+1650,xpMax=player21.xpMax}
local laterLog={readyLog[2],readyLog[3],readyLog[4]}
local laterBuckets=QT.Triage(laterLog,afterTribes)
local oldCompleted=C_QuestLog.IsQuestFlaggedCompleted
C_QuestLog.IsQuestFlaggedCompleted=function(id) return id==878 end
local nextPlan=assert(QT.BuildPowerPlan(afterTribes,laterBuckets,{{questID=5052}},camp,{speed=7,edges={hearth}}))
local nextCard=QT.BuildRows(laterBuckets,afterTribes,{},{plan=nextPlan,style="power",compact=true})[1]
assert(nextCard.questID==5052 and nextCard.icon=="pickup" and nextCard.sub=="quest item in bags")
local afterShards={level=21,xp=afterTribes.xp+1250,xpMax=afterTribes.xpMax}
C_QuestLog.IsQuestFlaggedCompleted=function(id) return id==878 or id==5052 end
local finalLeg=assert(QT.BuildPowerPlan(afterShards,laterBuckets,{},camp,{speed=7,edges={hearth}}))
assert(finalLeg.steps[1].text=="Hearth to The Crossroads" and finalLeg.gap==763)
local arrived=assert(QT.BuildPowerPlan(afterShards,laterBuckets,{},crossroads,{speed=7,edges={}}))
local lastCard=QT.BuildRows(laterBuckets,afterShards,{},{plan=arrived,style="power",compact=true})[1]
assert(lastCard.questID==1825 and lastCard.sub=="+775 XP · Level 22")
C_QuestLog.IsQuestFlaggedCompleted=oldCompleted

readyLog[4]=nil
carryShard=false
local hunt=false
for _,s in ipairs(replay().steps) do if s.questID==5052 and s.icon=="objective" then hunt=true end end
assert(hunt)
-- The Warsong Reports: three helpers across the zone, one marker. Never priced as a single stop.
local finisher=QT.QuestFinisher
QT.QuestFinisher=function() return campB end
local reports={questID=6543,title="The Warsong Reports",level=19,xp=1800,loc=camp,objectives={{text="x",have=0,need=3}}}
local function routed()
  return QT.BuildPowerPlan(player21,QT.Triage({reports},player21),{},camp,{speed=7,edges={}})
end
assert(routed().steps[1].questID==6543)
reports.helpers=true
assert(not routed())
QT.QuestFinisher=finisher
QT.GuideReady=originalGuide

C_Map={GetMapInfo=function(id) return {name="Map"..id} end}
local bands=QT.RouteBands()
local mid=bands:match("16–20  ([^\n]+)")
assert(mid and mid:find("Map1413",1,true) and not mid:find("Map1432",1,true))
assert(not QT.RouteOverview(nil):find("1–10",1,true))

-- Exercise the actual Forever taxi records through map discovery, fare changes, and peer confirmation.
local coins,t,grouped,locked=45,100,false,false
GetMoney=function() return coins end
GetTime=function() return t end
GetTaxiMapID=function() return 1413 end
Enum={FlightPathState={Current=0,Reachable=1,Unreachable=2}}
C_TaxiMap={GetTaxiNodesForMap=function() return {{nodeID=25,isUndiscovered=false},{nodeID=77,isUndiscovered=true}} end,
  GetAllTaxiNodes=function() return {{slotIndex=1,nodeID=25,state=0},{slotIndex=2,nodeID=77,state=1}} end}
TaxiNodeCost=function() return 50 end
QT.TransportLocation=function(point) return QT.MapLocation(point[1],point[2]/100,point[3]/100,point[4]) end
IsInGroup=function() return grouped end
InCombatLockdown=function() return locked end
IsMounted=never
GetBindLocation=function() return "?" end
C_Item={GetItemCount=function() return 0 end}
C_Container={GetItemCooldown=function() return 0,0,1 end}
C_SpellBook={IsSpellKnown=never}
local function flight()
  for _,edge in ipairs(QT.ReadTravel(camp).edges) do if edge.fare then return edge end end
end
assert(not flight() and QuestTriageCharDB.travel.known[25] and not QuestTriageCharDB.travel.known[77])
QT.NoteTaxiMap()
assert(QuestTriageCharDB.travel.known[77] and not flight())
coins=50
QuestTriageCharDB.travel.times["25:77"]=65
assert(flight().fare==50 and flight().seconds==73)
grouped,QuestTriageCharDB.sharePlan=true,true
IsInRaid=never
C_ChatInfo={InChatMessagingLockdown=never}
UnitFullName=function(unit) if unit=="party1" then return "Rider","Realm" end end
issecretvalue=never
GetNumSubgroupMembers=function() return 1 end
assert(not flight())
QT.ReceivePartyPlan("QTLevel1","R:25:77","PARTY","Rider-Realm")
assert(flight())
t=t+46
assert(not flight())
locked=true
assert(not QT.PartyCanFly(25,77))

local island=at(0,3)
local connect={speed=7,money=50,edges={{from=origin,to=remote,seconds=60,text="Boat"},
  {from=remote,to=island,seconds=30,fare=50,text="Fly"}}}
local across=QT.PlanTrips({ready(1,"Arrival",100,island)},origin,connect)
assert(across.steps[1].text=="Boat" and across.steps[2].text=="Fly")
connect.edges[1].fare=1
assert(not QT.PlanTrips({ready(1,"Arrival",100,island)},origin,connect))
