-- Voluntary party addon messages contain quest IDs, remaining credits and discovered taxi IDs.
local _, QT = ...
local L = QT.L
local peers, lastSent = {}, 0
function QT.ResetPartyPlan()
  peers, lastSent = {}, 0
end

local function sharing()
  return QuestTriageCharDB.sharePlan and not InCombatLockdown() and IsInGroup() and not IsInRaid()
    and not C_ChatInfo.InChatMessagingLockdown()
end

local function member(unit)
  local name, realm = UnitFullName(unit)
  if issecretvalue(name) or issecretvalue(realm) or not name then return end
  return name .. "-" .. ((realm and realm ~= "") and realm or GetNormalizedRealmName())
end

function QT.ReceivePartyPlan(prefix,msg,channel,sender)
  if not sharing() or issecretvalue(prefix) or issecretvalue(msg) or issecretvalue(sender) or issecretvalue(channel)
      or prefix~="QTLevel1" or channel~="PARTY" or type(msg)~="string" or #msg>250 then return end
  for i=1,4 do
    local unit="party"..i
    local key=member(unit)
    if key and (key==sender or key==sender.."-"..GetNormalizedRealmName()) then
      local peer=peers[key] or {}
      peers[key]=peer
      local id,left=msg:match("^Q:(%d+):(%-?%d+)$")
      if id then
        peer.id,peer.left,peer.at=tonumber(id),tonumber(left),GetTime()
      else
        local from, destinations=msg:match("^R:(%d+):([%d,]*)$")
        if from then
          local route={at=GetTime()}
          for n in destinations:gmatch("%d+") do route[tonumber(n)]=true end
          peer.routes=peer.routes or {}
          peer.routes[tonumber(from)]=route
        end
      end
      return
    end
  end
end

function QT.PartyCanFly(from,to)
  if not sharing() then return false end
  for i=1,GetNumSubgroupMembers() do
    local peer=peers[member("party"..i)]
    local route=peer and peer.routes and peer.routes[from]
    if not route or not route[to] or GetTime()-route.at>45 then return false end
  end
  return true
end

function QT.PartyFocus()
  if not sharing() then return end
  for i=1,GetNumSubgroupMembers() do
    local unit="party"..i
    if UnitIsGroupLeader(unit) then
      local p=peers[member(unit)]
      if p and p.id~=0 and p.at and GetTime()-p.at<30 then return p.id end
    end
  end
end

function QT.UpdatePartyPlan(plan,quests,travel)
  if not sharing() then return end
  local first=plan and plan.steps[1]
  local id=first and first.questID or (plan and plan.jobs[1].id)
  local left=-1
  for _,q in ipairs(quests) do
    if q.questID==id then
      left=0
      for _,o in ipairs(q.objectives) do left=left+math.max(0,(o.need or 0)-(o.have or 0)) end
      if not q.isComplete then left=math.max(1,left) end
      break
    end
  end
  if id and left==0 and first and first.questID==id and first.icon=="turnin" then
    for i=1,GetNumSubgroupMembers() do
      local unit="party"..i
      local key=member(unit)
      local p=peers[key]
      local near,checked=UnitInRange(unit)
      if p and p.id==id and p.left>0 and GetTime()-p.at<30 and not issecretvalue(near) and not issecretvalue(checked)
          and checked and near then
        table.insert(plan.steps,1,{text=L["Help %s finish %s"]:format(key,QT.RouteQuests[id] and QT.RouteQuests[id].title or first.text),
          key="wait:"..id, work=0, icon="group", questID=id, reason=L["Party member still needs %d credits."]:format(p.left)})
        break
      end
    end
  end
  if GetTime()-lastSent<10 then return end
  lastSent=GetTime()
  C_ChatInfo.SendAddonMessage("QTLevel1","Q:"..(id or 0)..":"..left,"PARTY")
  -- Peers need a recently confirmed, affordable departure near the group.
  local routes=QuestTriageCharDB.travel.routes
  local nearest, distance=nil,math.huge
  for _,station in ipairs(travel.stations) do
    local yards=QT.LegDistance(plan and plan.origin or travel.origin,station.loc)
    if routes[station.id] and yards<distance then nearest,distance=station.id,yards end
  end
  if nearest then
    local destinations={}
    for node,fare in pairs(routes[nearest]) do
      if fare<=travel.money then table.insert(destinations,tostring(node)) end
    end
    local msg="R:"..nearest..":"..table.concat(destinations,",")
    if #msg<=250 then C_ChatInfo.SendAddonMessage("QTLevel1",msg,"PARTY") end
  end
end
