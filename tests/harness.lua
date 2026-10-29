-- Mock of the WoW 1.12 API, enough to exercise TurnItIn.lua logic.
-- Runs under texlua (Lua 5.3); shims cover the Lua 5.0 functions the addon uses.
table.getn = table.getn or function(t) return #t end
unpack = unpack or table.unpack
time = os.time   -- WoW provides time()
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end   -- Lua 5.0 has atan2

local ADDON = arg[1]
local fails, passes = 0, 0
local function check(cond, msg)
  if cond then passes = passes + 1; print("  PASS  " .. msg)
  else fails = fails + 1; print("  FAIL  " .. msg) end
end

---------------------------------------------------------------- frame mock
local allFrames, allFontStrings = {}, {}
local function Obj()
  local o = { _scripts = {}, _shown = true, _text = "", _events = {} }
  local m = {}
  function m.SetScript(self, k, fn) self._scripts[k] = fn end
  function m.RegisterEvent(self, e) self._events[e] = true end
  function m.Show(self) self._shown = true end
  function m.Hide(self) self._shown = false end
  function m.IsShown(self) return self._shown end
  function m.IsVisible(self) return self._shown end
  function m.SetText(self, t) self._text = t end
  function m.GetText(self) return self._text end
  function m.GetWidth(self) return 100 end
  function m.GetHeight(self) return 20 end
  function m.CreateFontString(self)
    local f = Obj(); table.insert(allFontStrings, f); return f
  end
  function m.CreateTexture(self)
    local t = Obj(); local tl = rawget(self, "_textures"); if not tl then tl = {}; rawset(self, "_textures", tl) end
    table.insert(tl, t); return t
  end
  function m.SetTexture(self, p) self._tex = p end
  setmetatable(o, { __index = function(t, k) return m[k] or function() end end })
  return o
end

function CreateFrame(kind, name, parent, template)
  local o = Obj()
  table.insert(allFrames, o)
  if name then
    _G[name] = o
    if template == "UIDropDownMenuTemplate" then _G[name .. "Text"] = Obj() end
  end
  return o
end
function getglobal(n) return _G[n] end

local function Fire(ev, a1)
  _G.event, _G.arg1 = ev, a1
  for _, f in ipairs(allFrames) do
    if f._events[ev] and f._scripts.OnEvent then _G.this = f; f._scripts.OnEvent() end
  end
end
local function Tick(dt)
  for _, f in ipairs(allFrames) do
    if f._shown and f._scripts.OnUpdate then _G.this = f; _G.arg1 = dt; f._scripts.OnUpdate() end
  end
end
local function Click(frame)
  _G.this = frame; _G.arg1 = "LeftButton"; frame._scripts.OnClick()
end

---------------------------------------------------------------- world state
local W
local function Reset()
  W = { npc = nil, title = nil, bag = {}, money = 0, raid = 0, zone = { 2, 9 },
        req = {}, needMoney = 0, rewardItems = {}, choices = {}, rewardMoney = 0,
        completable = true, active = {}, available = {}, calls = {}, chat = {},
        log = {}, logSel = 0, logRewards = {}, logChoices = {}, logMoney = 0, greetAvail = {} }
end
Reset()
local function called(name) for _, c in ipairs(W.calls) do if c == name then return true end end return false end
local function link(n) return "|cffffffff|Hitem:" .. (#n * 7) .. ":0:0:0|h[" .. n .. "]|h|r" end

UnitName = function(u) if u == "npc" then return W.npc end return "Player" end
GetTitleText = function() return W.title end
GetContainerNumSlots = function(b) if b == 0 then return #W.bag end return 0 end
GetContainerItemLink = function(b, s) return link(W.bag[s].name) end
GetContainerItemInfo = function(b, s) return "tex", W.bag[s].count end
GetMoney = function() return W.money end
GetNumRaidMembers = function() return W.raid end
SetMapToCurrentZone = function() end
GetCurrentMapContinent = function() return W.zone[1] end
GetCurrentMapZone = function() return W.zone[2] end
GetNumQuestItems = function() return #W.req end
local function listFor(t) if t == "required" then return W.req elseif t == "reward" then return W.rewardItems else return W.choices end end
GetQuestItemInfo = function(t, i) local x = listFor(t)[i]; if x then return x.name, "tex_" .. x.name, x.count end end
GetQuestItemLink = function(t, i) return link(listFor(t)[i].name) end
GetQuestMoneyToGet = function() return W.needMoney end
GetRewardMoney = function() return W.rewardMoney end
GetNumQuestRewards = function() return #W.rewardItems end
GetNumQuestChoices = function() return #W.choices end
IsQuestCompletable = function() return W.completable end
CompleteQuest = function() table.insert(W.calls, "CompleteQuest") end
AcceptQuest = function() table.insert(W.calls, "AcceptQuest") end
GetQuestReward = function(c) table.insert(W.calls, "GetQuestReward:" .. tostring(c)) end
SelectGossipActiveQuest = function(i) table.insert(W.calls, "SelectGossipActiveQuest:" .. i) end
SelectGossipAvailableQuest = function(i) table.insert(W.calls, "SelectGossipAvailableQuest:" .. i) end
GetGossipActiveQuests = function() return unpack(W.active) end
GetGossipAvailableQuests = function() return unpack(W.available) end
GetNumActiveQuests = function() return 0 end
GetNumAvailableQuests = function() return #W.greetAvail end
GetAvailableTitle = function(i) return W.greetAvail[i] end
GetActiveTitle = function(i) return nil end
SelectAvailableQuest = function(i) table.insert(W.calls, "SelectAvailableQuest:" .. i) end
SelectActiveQuest = function(i) table.insert(W.calls, "SelectActiveQuest:" .. i) end
GetNumQuestLogEntries = function() return #W.log end
GetQuestLogTitle = function(i) local e = W.log[i]; return e.title, 60, nil, e.header end
GetQuestLogSelection = function() return W.logSel end
SelectQuestLogEntry = function(i) W.logSel = i end
GetQuestLogRewardMoney = function() return W.logMoney end
GetNumQuestLogRewards = function() return #W.logRewards end
GetQuestLogRewardInfo = function(i) local x = W.logRewards[i]; return x.name, "tex_" .. x.name, x.count end
GetNumQuestLogChoices = function() return #W.logChoices end
GetQuestLogChoiceInfo = function(i) local x = W.logChoices[i]; return x.name, "tex_" .. x.name, x.count end
GetQuestLogItemLink = function(t, i) return nil end
GetItemInfo = function() return nil end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(W.chat, m) end }
GameTooltip = { lines = {}, owner = nil, shown = false,
  SetOwner = function(self, o) self.owner = o; self.lines = {} end,
  SetText = function(self, t) self.lines = { t } end,
  AddLine = function(self, t) table.insert(self.lines, t) end,
  Show = function(self) self.shown = true end,
  Hide = function(self) self.shown = false end,
  SetHyperlink = function() end }
UIParent = Obj()
Minimap = Obj()
Minimap.GetCenter = function() return 100, 100 end
Minimap.GetEffectiveScale = function() return 1 end
W_cursor = { 100, 200 }
GetCursorPosition = function() return W_cursor[1], W_cursor[2] end
UISpecialFrames = {}
GetRealZoneText = function() return W.zoneName or "Test Zone" end
GetSubZoneText = function() return W.subZone or "" end
GetMapZones = function(c)
  if c == 1 then return "Ashenvale", "Durotar", "Orgrimmar" end
  return "Alterac Mountains", "Arathi Highlands", "Stranglethorn Vale"
end
WorldMapFrame = Obj(); WorldMapFrame._shown = false
QuestFrameDetailPanel = Obj(); QuestFrameDetailPanel._shown = false
QuestFrameRewardPanel = Obj(); QuestFrameRewardPanel._shown = false
UIDropDownMenu_Initialize = function() end
UIDropDownMenu_SetWidth = function() end
UIDropDownMenu_AddButton = function() end
SlashCmdList = {}
FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."

local function chatHas(s) for _, m in ipairs(W.chat) do if string.find(m, s, 1, true) then return true end end return false end
local function windowText()
  for _, f in ipairs(allFontStrings) do
    if string.find(f._text, "Turn It In", 1, true) then return f._text end
  end
  return ""
end
local function has(s) return string.find(windowText(), s, 1, true) ~= nil end

---------------------------------------------------------------- load
local chunk = assert(loadfile(ADDON))
chunk()
local tracker = _G["TIITracker"]
Fire("ADDON_LOADED", "TurnItIn")
print("== A. load")
check(TurnItInDB and TurnItInDB.version == 2, "saved variables created with version 2")
check(has("No repeatable quests recorded yet"), "empty state message shown")

print("== B. first turn-in of a coin quest (not yet known to be repeatable)")
W.npc, W.title = "Vinchaxa", "Zulian, Razzashi, and Hakkari Coins"
W.bag = { { name = "Zulian Coin", count = 2 }, { name = "Razzashi Coin", count = 2 }, { name = "Hakkari Coin", count = 2 } }
W.req = { { name = "Zulian Coin", count = 1 }, { name = "Razzashi Coin", count = 1 }, { name = "Hakkari Coin", count = 1 } }
Fire("QUEST_PROGRESS")
W.rewardItems = { { name = "Zandalar Honor Token", count = 1 } }
Fire("QUEST_COMPLETE")
GetQuestReward()   -- what Blizzard's Complete button does
Fire("QUEST_FINISHED")
Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Zandalar Tribe increased by 25.")
Tick(2.5)
local key = "Vinchaxa::Zulian, Razzashi, and Hakkari Coins"
local q = TurnItInDB.quests[key]
check(q ~= nil, "quest record created on first turn-in")
check(q and q.completions == 1, "completions == 1")
check(q and not q.repeatable, "not marked repeatable yet")
check(q and q.observed and q.rep["Zandalar Tribe"] == 25, "observed +25 Zandalar Tribe reputation")
check(q and #q.req == 3 and #q.items == 1 and q.items[1].name == "Zandalar Honor Token", "requirements and reward item recorded")
check(q and q.zone and q.zone[1] == 2 and q.zone[2] == 9, "zone indices recorded")

print("== C. NPC offers the quest again -> repeatable")
W.available = { "Zulian, Razzashi, and Hakkari Coins", 60 }
Fire("GOSSIP_SHOW")
check(q.repeatable == true, "marked repeatable when offered again")
check(chatHas("Recorded repeatable quest"), "chat message printed")
check(tracker:IsShown(), "window auto-shown in the quest's zone")
check(TurnItInDB.selected == key, "quest selected")
print(windowText())
check(has("Turn-ins available: |cffffffff2|r"), "2 turn-ins available from 2 of each coin")
check(has("Zandalar Honor Token x2"), "projected item reward x2")
check(has("Zandalar Tribe: +50 rep"), "projected reputation +50")

print("== D. auto turn-in loop")
Click(_G["TIIAutoButton"])
W.calls = {}; W.available = {}; W.active = { "Zulian, Razzashi, and Hakkari Coins", 60 }
Fire("GOSSIP_SHOW")
check(called("SelectGossipActiveQuest:1"), "auto selects the active quest in gossip")
Fire("QUEST_PROGRESS")
check(called("CompleteQuest"), "auto completes the quest")
Fire("QUEST_COMPLETE")
check(called("GetQuestReward:nil"), "auto takes the reward (no choices)")
W.completable = false; W.chat = {}
Fire("QUEST_PROGRESS")
check(chatHas("Out of items"), "auto stops when items run out")
W.completable = true

print("== E. quest with reward choices")
W.npc, W.title = "Quartermaster", "Supply Run"
W.bag = { { name = "Supply Crate", count = 5 } }
W.req = { { name = "Supply Crate", count = 1 } }
W.choices = { { name = "Sword", count = 1 }, { name = "Shield", count = 1 } }
W.rewardMoney = 12345
Fire("QUEST_PROGRESS"); Fire("QUEST_COMPLETE"); GetQuestReward(2); Fire("QUEST_FINISHED")
Fire("QUEST_PROGRESS"); Fire("QUEST_COMPLETE"); GetQuestReward(2); Fire("QUEST_FINISHED")
local key2 = "Quartermaster::Supply Run"
local q2 = TurnItInDB.quests[key2]
check(q2 and q2.completions == 2 and q2.repeatable, "repeatable after two completions")
check(q2 and #q2.choices == 2 and q2.money == 12345, "choices and money recorded")
Tick(2.5)
TurnItInDB.selected = key2   -- what picking it in the dropdown does
SlashCmdList.TURNITIN("show")  -- refreshes the window
print(windowText())
check(has("Choose a reward below"), "prompts for a reward choice")
check(has("Rewards for 5 turn-ins"), "5 turn-ins from 5 crates")
check(has("6|cffffd700g|r 17|cffc7c7cfs|r 25"), "money 12345c x5 = 6g 17s 25c")
check(_G["TIIChoice1"]:IsShown() and _G["TIIChoice2"]:IsShown() and not _G["TIIChoice3"]:IsShown(), "two choice buttons shown")
Click(_G["TIIAutoButton"]); W.calls = {}   -- auto is now ON again (was turned off by stop? check below)
local autoOn = has("Auto") or true
-- make sure auto is ON
if not (_G["TIIAutoButton"]._text and string.find(_G["TIIAutoButton"]._text, "ON", 1, true)) then Click(_G["TIIAutoButton"]) end
check(string.find(_G["TIIAutoButton"]._text, "ON", 1, true) ~= nil, "auto is ON")
W.chat = {}
Fire("QUEST_COMPLETE")
check(not called("GetQuestReward:2") and not called("GetQuestReward:1") and chatHas("Pick a reward"), "auto refuses to turn in until a reward is picked")
Click(_G["TIIChoice2"])
check(q2.choice == "Shield", "clicking the second icon selects Shield")
Click(_G["TIIAutoButton"]); Click(_G["TIIAutoButton"])  -- off then on (it was switched off by the refusal)
W.choices = { { name = "Shield", count = 1 }, { name = "Sword", count = 1 } }  -- order changed
W.calls = {}
if not string.find(_G["TIIAutoButton"]._text, "ON", 1, true) then Click(_G["TIIAutoButton"]) end
Fire("QUEST_COMPLETE")
check(called("GetQuestReward:1"), "choice matched by name even when the order changed")

print("== F. visibility rules")
W.raid = 5; Fire("RAID_ROSTER_UPDATE")
check(not tracker:IsShown(), "hidden in a raid")
W.raid = 0; W.zone = { 2, 9 }; Fire("ZONE_CHANGED_NEW_AREA")
check(tracker:IsShown(), "shown again in a recorded zone")
W.zone = { 1, 1 }; Fire("ZONE_CHANGED_NEW_AREA")
check(not tracker:IsShown(), "hidden in an unrelated zone")

print("== G. slash commands and persistence")
SlashCmdList.TURNITIN("show"); check(tracker:IsShown(), "/tii show")
SlashCmdList.TURNITIN("hide"); check(not tracker:IsShown(), "/tii hide")
SlashCmdList.TURNITIN("toggle"); check(tracker:IsShown(), "/tii toggle")
TurnItInDB.quests["Old::Thing"] = { title = "Thing", npc = "Old", completions = 1, req = {}, items = {}, choices = {}, last = os.time() - 30 * 86400 }
local before = TurnItInDB.selected
SlashCmdList.TURNITIN("forget")
check(before ~= nil and TurnItInDB.quests[before] == nil, "/tii forget removes the selected quest")
Fire("ADDON_LOADED", "TurnItIn")
check(TurnItInDB.quests["Old::Thing"] == nil, "stale non-repeatable record pruned on load")
check(TurnItInDB.quests[key] ~= nil, "other repeatable quests kept")


print("== H. NEW quest: window shows name, items and rewards on first open")
W.npc, W.title = "Horde Warbringer", "Conquering Arathi Basin"
W.zone = { 1, 21 }
W.bag = { { name = "Arathi Basin Mark of Honor", count = 7 } }
W.req = { { name = "Arathi Basin Mark of Honor", count = 3 } }
W.choices, W.rewardItems, W.rewardMoney = {}, {}, 0
W.log = { { title = "Some Zone", header = true }, { title = "Conquering Arathi Basin" } }
W.logSel = 2; W.logMoney = 0
W.logRewards = { { name = "Defiler Token", count = 1 } }
tracker:Hide()
Fire("QUEST_PROGRESS")
local hq = TurnItInDB.quests["Horde Warbringer::Conquering Arathi Basin"]
print(windowText())
check(tracker:IsShown(), "window appears on a quest nobody has tracked yet")
check(has("Conquering Arathi Basin"), "quest name shown")
check(has("Arathi Basin Mark of Honor: 7/3"), "items to hand in shown with bag counts")
check(has("Turn-ins available: |cffffffff2|r"), "2 turn-ins from 7 marks")
check(has("Defiler Token x2"), "reward read from the quest log before the final step, x2")
check(_G["TIITrackButton"]:IsShown(), "Track quest button visible")
check(W.logSel == 2, "quest log selection restored")
check(hq and not hq.repeatable, "not marked repeatable by merely opening it")
Fire("QUEST_COMPLETE")
check(has("Defiler Token x2"), "reward still shown at the reward step")

print("== I. Track button")
Click(_G["TIITrackButton"])
check(hq.repeatable == true, "clicking Track marks the quest repeatable")
check(not _G["TIITrackButton"]:IsShown(), "Track button hides once tracked")
check(TurnItInDB.selected == "Horde Warbringer::Conquering Arathi Basin", "quest becomes the selected one")
Fire("QUEST_FINISHED")
check(tracker:IsShown(), "window stays in the quest's zone after the dialog closes")

print("== J. user's real saved data: one completion on file, NPC opens the dialog again")
TurnItInDB.quests = { ["Horde Warbringer::Conquering Arathi Basin"] = {
  last = os.time(), zone = { 1, 21 }, money = 0, xp = 0, npc = "Horde Warbringer",
  rep = { ["The Defilers"] = 50 }, completions = 1, observed = true,
  title = "Conquering Arathi Basin", honor = 40, choices = {}, items = {}, needMoney = 0,
  req = { { name = "Arathi Basin Mark of Honor", count = 3 } } } }
TurnItInDB.selected = nil
local rq = TurnItInDB.quests["Horde Warbringer::Conquering Arathi Basin"]
W.chat = {}; W.zone = { 2, 2 }
-- a) single quest, goes straight to the detail dialog
W.title = "Conquering Arathi Basin"
Fire("QUEST_DETAIL")
check(rq.repeatable == true, "QUEST_DETAIL on second sighting marks it repeatable")
check(chatHas("Recorded repeatable quest"), "player is told")
rq.repeatable = nil
-- b) several quests, QUEST_GREETING list
W.greetAvail = { "Conquering Arathi Basin" }
Fire("QUEST_GREETING")
check(rq.repeatable == true, "QUEST_GREETING list marks it repeatable")
rq.repeatable = nil; W.greetAvail = {}
-- c) gossip list with a level tag in front of the title
W.available = { "[60] Conquering Arathi Basin", 60 }
Fire("GOSSIP_SHOW")
check(rq.repeatable == true, "gossip title with a [60] level prefix still matches")
W.available = {}
print(windowText())
check(has("Honor: 80") and has("The Defilers: +100 rep"), "honor and rep projected for 2 turn-ins from remembered data")

print("== K. closing the dialog on an untracked quest hides the window again")
rq.repeatable = nil
W.zone = { 1, 1 }
Fire("QUEST_DETAIL")
rq.repeatable = nil
Fire("QUEST_PROGRESS")
check(tracker:IsShown(), "shown while the dialog is open")
Fire("QUEST_FINISHED")
check(not tracker:IsShown(), "hidden after the dialog closes, outside any tracked zone")

print("== L. debug mode prints what the NPC offers")
SlashCmdList.TURNITIN("debug")
W.chat = {}; W.available = { "Some Quest", 55 }; W.active = { "Active Quest", 55 }
Fire("GOSSIP_SHOW")
check(chatHas("available[1] = [Some Quest]") and chatHas("active[1] = [Active Quest]"), "debug lists gossip titles")
check(chatHas("offered: Horde Warbringer::Some Quest known=false"), "debug explains the match result")
SlashCmdList.TURNITIN("debug")

print("== M. minimap button")
local mm = _G["TIIMinimapButton"]
local function ClickBtn(frame, btn) _G.this = frame; _G.arg1 = btn; frame._scripts.OnClick() end
local function Hover(frame) _G.this = frame; frame._scripts.OnEnter() end
local coin = false
for _, t in ipairs(rawget(mm, "_textures") or {}) do if t._tex and string.find(t._tex, "INV_Misc_Coin_01", 1, true) then coin = true end end
check(coin, "minimap icon texture is the gold coin (INV_Misc_Coin_01)")
check(mm._shown, "button visible after load")
_G.this = mm
mm._scripts.OnDragStart()
_G.this = mm; W_cursor[1], W_cursor[2] = 100, 200    -- straight above the minimap centre
mm._scripts.OnUpdate()
check(TurnItInDB.minimapAngle and math.abs(TurnItInDB.minimapAngle - 90) < 0.01, "dragging stores the angle (90 deg when straight above)")
_G.this = mm
mm._scripts.OnDragStop()
check(mm._scripts.OnUpdate == nil, "drag handler removed on release")
Hover(mm)
check(GameTooltip.lines[1] == "Turn It In", "minimap tooltip")
tracker:Show(); ClickBtn(mm, "RightButton")
check(not tracker:IsShown(), "right-click toggles the tracker window")
ClickBtn(mm, "RightButton")
check(tracker:IsShown(), "right-click again shows it")

print("== N. quest list window")
local lst = _G["TIIList"]
local function rowText(i) local r = _G["TIIListRow" .. i]; return r and r._shown and r.text._text or nil end
local function rowRight(i) local r = _G["TIIListRow" .. i]; return r and r.right._text end
check(not lst._shown, "list starts closed")
check(table.concat(UISpecialFrames, ","):find("TIIList", 1, true) ~= nil, "registered for Escape-to-close")
TurnItInDB.quests = {
  ["Horde Warbringer::Conquering Arathi Basin"] = { title = "Conquering Arathi Basin", npc = "Horde Warbringer",
    completions = 1, repeatable = true, zone = { 1, 3 }, zoneName = "Orgrimmar", subZone = "Valley of Strength",
    req = { { name = "Arathi Basin Mark of Honor", count = 3 } }, needMoney = 0, money = 0, items = {}, choices = {},
    observed = true, honor = 40, xp = 0, rep = { ["The Defilers"] = 50 } },
  ["Vinchaxa::Zulian Coins"] = { title = "Zulian, Razzashi, and Hakkari Coins", npc = "Vinchaxa",
    completions = 2, repeatable = true, zone = { 2, 3 },
    req = { { name = "Zulian Coin", count = 1 } }, needMoney = 0, money = 0, choices = {},
    items = { { name = "Zandalar Honor Token", count = 1 } } },
  ["Old Man::Wolf Pelts"] = { title = "Wolf Pelts", npc = "Old Man", completions = 0, zone = { 2, 2 },
    req = {}, needMoney = 0, money = 0, items = {}, choices = {} },
}
TurnItInDB.selected = "Horde Warbringer::Conquering Arathi Basin"
W.bag = { { name = "Arathi Basin Mark of Honor", count = 7 } }
ClickBtn(mm, "LeftButton")
check(lst._shown, "left-click opens the list window")
check(rowText(1) and rowText(1):find("Conquering Arathi Basin", 1, true), "tracked quest listed first")
check(rowText(2) and rowText(2):find("Zulian, Razzashi", 1, true), "second tracked quest listed")
check(rowText(3) and rowText(3):find("Wolf Pelts", 1, true), "untracked quest listed last")
check(rowRight(1) and rowRight(1):find("2 ready", 1, true), "ready count shown (7 marks / 3 = 2)")
check(rowRight(2) and rowRight(2):find("none ready", 1, true), "none ready when no coins")
check(rowRight(3) and rowRight(3):find("not tracked", 1, true), "untracked flagged")
check(rowText(1):find("Horde Warbringer", 1, true), "NPC shown next to quest in the by-quest view")
check(_G["TIIModeQuest"]._text:find("By quest", 1, true) and _G["TIIModeQuest"]._text:find("cff00ff00", 1, true), "By quest highlighted")
check(_G["TIIListRow4"] == nil or not _G["TIIListRow4"]._shown, "no extra rows")

print("== O. view by turn-in location")
Click(_G["TIIModeLocation"])
check(TurnItInDB.listMode == "location", "mode saved")
for i = 1, 8 do if rowText(i) then print("   row" .. i .. ": " .. rowText(i)) end end
check(rowText(1) and rowText(1):find("Arathi Highlands - Old Man", 1, true), "location name taken from the map indices {2,2} when none was stored")
check(rowText(3) and rowText(3):find("Orgrimmar - Horde Warbringer", 1, true) and rowText(3):find("Valley of Strength", 1, true), "header: stored zone name, NPC and sub-zone")
check(rowText(4) and rowText(4):find("Conquering Arathi Basin", 1, true) and rowText(4):find("^   "), "quests indented under their header")
check(rowText(1):find("Arathi Highlands", 1, true) and rowText(3):find("Orgrimmar", 1, true) and rowText(5):find("Stranglethorn Vale - Vinchaxa", 1, true), "headers sorted alphabetically by zone")
check(_G["TIIModeLocation"]._text:find("cff00ff00", 1, true), "By turn-in location highlighted")

print("== P. tooltip, click to select / track")
Hover(_G["TIIListRow4"])
local tip = table.concat(GameTooltip.lines, "|")
check(tip:find("Arathi Basin Mark of Honor x3", 1, true) and tip:find("you have 7", 1, true), "tooltip lists items to hand in with bag count")
check(tip:find("Honor: 40", 1, true) and tip:find("The Defilers: +50 rep", 1, true), "tooltip lists honor and reputation")
check(tip:find("Orgrimmar", 1, true), "tooltip shows location")
Hover(_G["TIIListRow6"])
tip = table.concat(GameTooltip.lines, "|")
check(tip:find("Zandalar Honor Token x1", 1, true), "tooltip lists item rewards")
tracker:Hide(); TurnItInDB.selected = nil
Click(_G["TIIListRow4"])
check(TurnItInDB.selected == "Horde Warbringer::Conquering Arathi Basin" and tracker:IsShown(), "clicking a tracked quest selects it and shows the tracker")
local wolf = TurnItInDB.quests["Old Man::Wolf Pelts"]
local selBefore = TurnItInDB.selected
Click(_G["TIIListRow1"]); Click(_G["TIIListRow3"]); Click(_G["TIIListRow5"])   -- the three header rows
check(not wolf.repeatable and TurnItInDB.selected == selBefore, "header rows ignore clicks")
Hover(_G["TIIListRow1"])
check(GameTooltip.lines[1] ~= "Wolf Pelts", "header rows show no quest tooltip")
Click(_G["TIIModeQuest"])
-- by-quest view: tracked quests first, so Wolf Pelts (untracked) is row 3
check(rowText(3):find("Wolf Pelts", 1, true), "untracked quest is row 3 in the by-quest view")
Click(_G["TIIListRow3"])
check(wolf.repeatable == true and TurnItInDB.selected == "Old Man::Wolf Pelts", "clicking an untracked quest tracks and selects it")

print("== Q. housekeeping")
W.chat = {}
SlashCmdList.TURNITIN("minimap")
check(TurnItInDB.minimapHidden == true and not mm._shown, "/tii minimap hides the button")
SlashCmdList.TURNITIN("minimap")
check(mm._shown, "/tii minimap shows it again")
lst:Hide()
SlashCmdList.TURNITIN("list")
check(lst._shown, "/tii list opens the window")
SlashCmdList.TURNITIN("list")
check(not lst._shown, "/tii list closes it")
-- empty database
TurnItInDB.quests = {}; TurnItInDB.selected = nil
lst:Show(); Fire("BAG_UPDATE")
check(rowText(1) and rowText(1):find("No quests known yet", 1, true), "empty state message")
-- location stamping on a fresh quest
W.zoneName, W.subZone = "Orgrimmar", "Valley of Honor"
W.npc, W.title = "Horde Warbringer", "Conquering Arathi Basin"
W.zone = { 1, 3 }
Fire("QUEST_PROGRESS")
local nq = TurnItInDB.quests["Horde Warbringer::Conquering Arathi Basin"]
check(nq and nq.zoneName == "Orgrimmar" and nq.subZone == "Valley of Honor", "zone and sub-zone names stored when a quest is seen")
check(rowText(1) and rowText(1):find("Conquering Arathi Basin", 1, true), "list refreshes live when a quest is recorded")

print(string.format("\n%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
