// node tools/build-route-catalog.cjs <path to extracted QuestieDB 1.1.3 Forever addon>
const fs = require("node:fs");
const path = require("node:path");
const root = process.argv[2];
if (!root) throw Error("Expected the path to the QuestieDB Forever addon");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const toc = read("QuestieDB_Forever.toc");
if (!/^## Version: 1\.1\.3\s*$/m.test(toc)) throw Error("Review schema and provenance before changing the source version");

const fields = new Map();
for (const line of toc.split(/\r?\n/)) {
  const match = /^## X-((?:Quest|Npc|Object|Item)-[\d-]+(?:S|\d)): (\S+)$/.exec(line);
  if (match) fields.set(match[1], match[2]);
}

// The baked TOC stores individual fields as base64 CBOR, with oversized values split into parts.
function field(type, id, index = "S") {
  const key = [type, id, index].join("-");
  let payload = fields.get(key);
  if (!payload) return;
  if (payload.startsWith("~")) {
    payload = Array.from({length: Number(payload.slice(1,-1))}, (_, i) => fields.get(key + "-" + (i+1))).join("");
  }
  const data = Buffer.from(payload, "base64");
  let offset = 0;
  function decode() {
    const head = data[offset++], type = head >> 5, size = head & 31;
    if (type === 7) {
      if (size === 22) return null;
      if (size === 25) {
        const bits = data.readUInt16BE(offset); offset += 2;
        const exponent = (bits >> 10) & 31, fraction = (bits & 1023) / 1024;
        return (bits & 32768 ? -1 : 1) * (exponent ? 1 + fraction : fraction) * 2 ** ((exponent || 1) - 15);
      }
      if (size === 26) { offset += 4; return data.readFloatBE(offset - 4); }
      if (size === 27) { offset += 8; return data.readDoubleBE(offset - 8); }
      throw Error("Unexpected CBOR simple value in " + key);
    }
    let n = size;
    if (size >= 24) {
      const bytes = 2 ** (size - 24);
      n = bytes === 8 ? Number(data.readBigUInt64BE(offset)) : data.readUIntBE(offset, bytes);
      offset += bytes;
    }
    if (type === 0) return n;
    if (type === 1) return -1 - n;
    if (type === 2 || type === 3) { offset += n; return data.toString("utf8", offset - n, offset); }
    if (type === 4) return Array.from({length:n}, decode);
    if (type === 5) {
      const object = {};
      for (let i = 0; i < n; i++) object[decode()] = decode();
      return object;
    }
    throw Error("Unexpected CBOR type in " + key);
  }
  return decode();
}

const regions = [
  [1411,1412,1420,1426,1429,1438,2521], [1413,1436,1432,1439,1421], [1413,1433,1439,1421,1436,1432],
  [1413,1431,1440,1437,1424,1442], [1441,1437,1431,1424,1440], [1441,1434,1417,1443],
  [1434,1445,1417,1443], [1446,1444,1434,1425], [1446,1444,1425,1427], [1449,1448,1422,1428], [1452,1423,1422,1451,1428],
];
const maps = new Map([...read("support/Forever/Zones/areaIdToUiMapId.lua").matchAll(/\[(\d+)\]\s*=\s*(\d+),\s*--/g)]
  .map(m => [Number(m[1]), Number(m[2])]));
const rewards = new Map([...read("support/Forever/QuestXP/xpDB-traces.lua").matchAll(/db\[(\d+)\] = \{\d+, (\d+)\}/g)]
  .map(m => [Number(m[1]), Number(m[2])]));

function location(type, id, area) {
  const info = field(type, id), spawns = field(type, id, type === "Npc" ? 7 : 4);
  if (!info || !spawns) return;
  for (const zone of [area, ...Object.keys(spawns)]) {
    const point = spawns[zone]?.[0], map = maps.get(Number(zone));
    if (map && point?.[0] > 0 && point[1] > 0) return [map, +point[0].toFixed(2), +point[1].toFixed(2), info[1], id];
  }
}
function quest(id) {
  const q = field("Quest", id), get = (index) => field("Quest", id, index);
  const level = q[5], area = q[17], xp = rewards.get(id);
  if (!(level >= 1 && level <= 60 && maps.has(area) && xp > 0)) return;
  // Skip class, skill, reputation, timed and other special conditions which the standalone planner cannot establish.
  if ([7,24,25,30,31,32,33,34,36].some(index => q[index]) || [9,15,16,18,19,20,21,29,35].some(get)) return;
  const start = get(2)?.[0]?.[0], end = get(3)?.[0]?.[0];
  const giver = location("Npc",start,area), finish = location("Npc",end,area);
  const band = Math.max(0, Math.ceil((level - 10) / 5));
  if (!giver || !finish || !regions[band].includes(giver[0])) return;
  const objectives = get(10) || {}, camps = [];
  for (const [slot, rows] of Object.entries(objectives)) {
    const kind = Number(slot) + (Array.isArray(objectives) ? 1 : 0);
    for (const row of rows || []) {
      if (!row) continue;
      const entity = row[0];
      let camp;
      if (kind === 1) camp = location("Npc",entity,area);
      if (kind === 2) camp = location("Object",entity,area);
      if (kind === 3) camp = location("Npc",field("Item",entity,2)?.[0],area) || location("Object",field("Item",entity,3)?.[0],area);
      if (!camp) return;
      camps.push(camp);
    }
  }
  if ((!camps.length && start === end) || [giver,finish,...camps].some(p => p[1] > 100 || p[2] > 100)) return;
  const any = get(13) || [], all = get(12) || [];
  if ([...any,...all].some(req => req <= 0) || q[22] < 0) return;
  const data = {title:q[1],level,min:q[4] || 1,races:q[6] || 0,faction:field("Npc",start)[13] || "AH",xp,giver,finish,camps};
  // Quest 5052 requests one Blood Shard. The baked objectives identify the item
  // but omit its quantity. Preserve this reviewed count for inventory-aware routing.
  if (id === 5052 && objectives[3]?.[0]?.[0] === 5075) data.items = [[5075,1]];
  if (any.length) data.any = any;
  if (all.length) data.all = all;
  if (q[22]) data.closedBy = q[22];
  return data;
}
function lua(value) {
  return Array.isArray(value) ? "{" + value.map(lua).join(", ") + "}" : JSON.stringify(value);
}
const inns = [], quests = [];
for (const key of fields.keys()) {
  const m = /^(Npc|Quest)-(\d+)-S$/.exec(key);
  if (!m) continue;
  const id = Number(m[2]);
  if (m[1] === "Quest") {
    const data = quest(id);
    if (data) quests.push("  [" + id + "] = { " + Object.entries(data).map(([k,v]) => k + " = " + lua(v)).join(", ") + " },");
  } else {
    const npc = field("Npc",id);
    if (!npc[13] || npc[14] !== "Innkeeper") continue;
    const loc = location("Npc",id,npc[9]);
    if (loc && regions.some(band => band.includes(loc[0]))) inns.push([npc[13],loc]);
  }
}
if (!quests.length || !inns.length) throw Error("Source yielded no quests or inns");
const rows = (values) => values.map(value => "  " + lua(value) + ",").join("\n");
const out = [
  "-- Quest and NPC facts selected from QuestieDB Forever 1.1.3, 8b8df2d. See Libs/LICENSES.md.",
  "-- Generated by tools/build-route-catalog.cjs. Location tuples: map, x%, y%, name, entity ID.",
  "local _, QT = ...", "QT.RouteRegions = {", rows(regions), "}", "QT.RouteInns = {", rows(inns), "}",
  "QT.RouteQuests = {", ...quests, "}", "",
];
fs.writeFileSync(path.join(__dirname,"../RouteCatalog.lua"), out.join("\n"));
console.log("Exported %d quests and %d innkeepers", quests.length, inns.length);
