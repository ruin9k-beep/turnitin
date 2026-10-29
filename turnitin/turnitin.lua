----------------------------------------------------------------
-- Turn It In
-- Records repeatable quests, projects their rewards and can turn
-- them in automatically. Written for the 1.12 client (Lua 5.0).
----------------------------------------------------------------

local DB
local auto = false
local seen = {}          -- per-session cache of quest requirements
local pending            -- turn-in whose honor/rep/xp is being observed
local pendingTime = 0
local Refresh            -- forward declaration
local RefreshList        -- forward declaration (quest list window)
local preview            -- key of the quest whose dialog is open (not yet tracked)
local debugOn = false

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffTurn It In:|r " .. msg)
end

local function Debug(msg)
  if debugOn then
    DEFAULT_CHAT_FRAME:AddMessage("|cff999999TII debug:|r " .. msg)
  end
end

-- Remove colour codes from a title.
local function Strip(s)
  if not s then return nil end
  s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
  s = string.gsub(s, "|r", "")
  s = string.gsub(s, "^%[%d+%+?%]%s*", "")
  return s
end

local function QuestKey(npc, title)
  return npc .. "::" .. title
end

local function Money(c)
  c = c or 0
  local g = math.floor(c / 10000)
  local s = math.floor((c - g * 10000) / 100)
  local cp = c - g * 10000 - s * 100
  local out = ""
  if g > 0 then out = out .. g .. "|cffffd700g|r " end
  if s > 0 then out = out .. s .. "|cffc7c7cfs|r " end
  if cp > 0 or out == "" then out = out .. cp .. "|cffeda55fc|r" end
  return out
end

-- Turn a printf-style global string into a Lua pattern.
local function FormatToPattern(fmt)
  local p = string.gsub(fmt, "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
  p = string.gsub(p, "%%s", "(.+)")
  p = string.gsub(p, "%%d", "(%%d+)")
  return p
end

local repPattern = FACTION_STANDING_INCREASED and FormatToPattern(FACTION_STANDING_INCREASED)

local function ParseRep(msg)
  local _, _, f, a
  if repPattern then _, _, f, a = string.find(msg, repPattern) end
  if not f then
    _, _, f, a = string.find(msg, "[Rr]eputation with (.+) increased by (%d+)")
  end
  if f and a then return f, tonumber(a) end
  return nil
end

local function ParseHonor(msg)
  local _, _, n = string.find(msg, "(%d+)%s+[Hh]onor")
  if n then return tonumber(n) end
  return nil
end

local function ParseXP(msg)
  local _, _, n = string.find(msg, "(%d+)%s+[Ee]xperience")
  if n then return tonumber(n) end
  return nil
end

----------------------------------------------------------------
-- Bags and quest data capture
----------------------------------------------------------------
local function CountItem(name)
  local total = 0
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      if link then
        local _, _, n = string.find(link, "%[(.-)%]")
        if n == name then
          local _, c = GetContainerItemInfo(bag, slot)
          total = total + (c or 1)
        end
      end
    end
  end
  return total
end

-- The zone is stored as world-map indices, so it works in any language.
local function CurrentZone()
  if WorldMapFrame and WorldMapFrame:IsVisible() then return nil end
  SetMapToCurrentZone()
  local c, z = GetCurrentMapContinent(), GetCurrentMapZone()
  if not c or c < 1 or not z or z < 1 then return nil end
  return { c, z }
end

-- Remember where the NPC is: map indices for logic, names for display.
local function StampLocation(q)
  local zone = CurrentZone()
  if zone then q.zone = zone end
  local zn = GetRealZoneText and GetRealZoneText()
  if zn and zn ~= "" then q.zoneName = zn end
  if GetSubZoneText then q.subZone = GetSubZoneText() or "" end
end

-- Items (and money) the quest asks for. Valid while the progress window is open.
local function CaptureRequirements()
  local req = {}
  for i = 1, GetNumQuestItems() do
    local name, texture, count = GetQuestItemInfo("required", i)
    if name and name ~= "" then
      table.insert(req, { name = name, count = count or 1 })
    end
  end
  local money = 0
  if GetQuestMoneyToGet then money = GetQuestMoneyToGet() or 0 end
  return req, money
end

-- Rewards on offer. Valid while the offer or reward window is open.
local function CaptureRewards()
  local money = 0
  if GetRewardMoney then money = GetRewardMoney() or 0 end
  local items, choices = {}, {}
  for i = 1, GetNumQuestRewards() do
    local name, texture, count = GetQuestItemInfo("reward", i)
    if name and name ~= "" then
      table.insert(items, { name = name, texture = texture, count = count or 1,
                            link = GetQuestItemLink("reward", i) })
    end
  end
  for i = 1, GetNumQuestChoices() do
    local name, texture, count = GetQuestItemInfo("choice", i)
    if name and name ~= "" then
      table.insert(choices, { name = name, texture = texture, count = count or 1,
                              link = GetQuestItemLink("choice", i) })
    end
  end
  return money, items, choices
end

-- Rewards of a quest that is in the player's log. The turn-in window only
-- shows rewards on its last step, the log shows them earlier.
local function ReadQuestLog(title)
  local found = nil
  for i = 1, GetNumQuestLogEntries() do
    local t, _, _, isHeader = GetQuestLogTitle(i)
    if t and not isHeader and Strip(t) == title then
      found = i
      break
    end
  end
  if not found then return nil end

  local prev = GetQuestLogSelection()
  SelectQuestLogEntry(found)
  local money = GetQuestLogRewardMoney() or 0
  local items, choices = {}, {}
  for i = 1, GetNumQuestLogRewards() do
    local name, texture, count = GetQuestLogRewardInfo(i)
    if name and name ~= "" then
      table.insert(items, { name = name, texture = texture, count = count or 1,
                            link = GetQuestLogItemLink and GetQuestLogItemLink("reward", i) })
    end
  end
  for i = 1, GetNumQuestLogChoices() do
    local name, texture, count = GetQuestLogChoiceInfo(i)
    if name and name ~= "" then
      table.insert(choices, { name = name, texture = texture, count = count or 1,
                              link = GetQuestLogItemLink and GetQuestLogItemLink("choice", i) })
    end
  end
  if prev and prev > 0 then SelectQuestLogEntry(prev) end
  return money, items, choices
end

-- Only overwrite stored rewards when the new reading actually contains some.
local function MergeRewards(q, money, items, choices)
  items = items or {}
  choices = choices or {}
  if (money and money > 0) or table.getn(items) > 0 or table.getn(choices) > 0 then
    q.money = money or 0
    q.items = items
    q.choices = choices
  end
end

local function EnsureQuest(key, title, npc)
  local q = DB.quests[key]
  if not q then
    q = { title = title, npc = npc, completions = 0, req = {}, needMoney = 0,
          money = 0, items = {}, choices = {} }
    DB.quests[key] = q
  end
  return q
end

local function Selected()
  if DB and DB.selected then
    local q = DB.quests[DB.selected]
    if q and q.repeatable then return q end
  end
  return nil
end

-- The quest the window shows: the one being talked about, else the selected one.
local function View()
  if preview and DB.quests[preview] then return DB.quests[preview], true end
  return Selected(), false
end

local function RepeatableList()
  local list = {}
  for key, q in pairs(DB.quests) do
    if q.repeatable then table.insert(list, key) end
  end
  table.sort(list, function(a, b)
    local qa, qb = DB.quests[a], DB.quests[b]
    if qa.title ~= qb.title then return qa.title < qb.title end
    return qa.npc < qb.npc
  end)
  return list
end

local function DisplayName(key, list)
  local q = DB.quests[key]
  for i = 1, table.getn(list) do
    local o = DB.quests[list[i]]
    if list[i] ~= key and o.title == q.title then
      return q.title .. " (" .. q.npc .. ")"
    end
  end
  return q.title
end

-- How many times the quest can be turned in with what is in the bags.
local function Possible(q)
  local n = nil
  for i = 1, table.getn(q.req) do
    local r = q.req[i]
    local p = math.floor(CountItem(r.name) / (r.count or 1))
    if n == nil or p < n then n = p end
  end
  if q.needMoney and q.needMoney > 0 then
    local p = math.floor(GetMoney() / q.needMoney)
    if n == nil or p < n then n = p end
  end
  return n
end

----------------------------------------------------------------
-- Tracker window
----------------------------------------------------------------
local tracker = CreateFrame("Frame", "TIITracker", UIParent)
tracker:SetWidth(270)
tracker:SetHeight(80)
tracker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
tracker:SetMovable(true)
tracker:EnableMouse(true)
tracker:RegisterForDrag("LeftButton")
tracker:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
tracker:SetBackdropColor(0, 0, 0, 0.8)
tracker:SetScript("OnDragStart", function() this:StartMoving() end)
tracker:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
tracker:Hide()

local text = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
text:SetPoint("TOPLEFT", tracker, "TOPLEFT", 8, -8)
text:SetJustifyH("LEFT")

-- Quest selector (only shown when more than one quest is known)
local dropdown = CreateFrame("Frame", "TIIDropDown", tracker, "UIDropDownMenuTemplate")
dropdown:SetPoint("TOPLEFT", tracker, "TOPLEFT", -10, -6)
local dropdownText = getglobal("TIIDropDownText")

local function InitDropDown()
  if not DB then return end
  local list = RepeatableList()
  for i = 1, table.getn(list) do
    local info = {}
    info.text = DisplayName(list[i], list)
    info.value = list[i]
    info.checked = (DB.selected == list[i])
    info.func = function()
      DB.selected = this.value
      Refresh()
    end
    UIDropDownMenu_AddButton(info)
  end
end

UIDropDownMenu_Initialize(dropdown, InitDropDown)
UIDropDownMenu_SetWidth(200, dropdown)

-- Reward choice buttons (a quest offers at most 6 choices)
local choiceLabel = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
choiceLabel:SetText("|cffffd100Reward (choose one):|r")
choiceLabel:Hide()

local choiceButtons = {}
for i = 1, 6 do
  local b = CreateFrame("Button", "TIIChoice" .. i, tracker)
  b:SetWidth(30)
  b:SetHeight(30)
  b:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
  icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
  b.icon = icon
  local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
  b.count = count
  b.index = i
  b:SetScript("OnClick", function()
    local q = View()
    local c = q and q.choices[this.index]
    if c then
      q.choice = c.name
      Refresh()
    end
  end)
  b:SetScript("OnEnter", function()
    local q = View()
    local c = q and q.choices[this.index]
    if not c then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    local _, _, itemString = string.find(c.link or "", "(item:%d+:%d+:%d+:%d+)")
    if itemString and GetItemInfo(itemString) then
      GameTooltip:SetHyperlink(itemString)
    else
      GameTooltip:SetText(c.name)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  choiceButtons[i] = b
end

-- Auto turn-in on/off button (bottom right)
local autoButton = CreateFrame("Button", "TIIAutoButton", tracker, "UIPanelButtonTemplate")
autoButton:SetWidth(80)
autoButton:SetHeight(20)
autoButton:SetPoint("BOTTOMRIGHT", tracker, "BOTTOMRIGHT", -6, 6)
autoButton:SetScript("OnClick", function()
  auto = not auto
  Refresh()
end)

-- "Track quest" button (bottom left, only while a new quest is open)
local trackButton = CreateFrame("Button", "TIITrackButton", tracker, "UIPanelButtonTemplate")
trackButton:SetWidth(90)
trackButton:SetHeight(20)
trackButton:SetPoint("BOTTOMLEFT", tracker, "BOTTOMLEFT", 6, 6)
trackButton:SetText("Track quest")
trackButton:SetScript("OnClick", function()
  local q = preview and DB.quests[preview]
  if not q then return end
  q.repeatable = true
  StampLocation(q)
  DB.selected = preview
  preview = nil
  Print("Tracking: " .. q.title)
  Refresh()
end)
trackButton:Hide()

Refresh = function()
  if not DB then return end

  local list = RepeatableList()
  local n = table.getn(list)

  -- Keep the selection valid
  local cur = DB.selected and DB.quests[DB.selected]
  if not (cur and cur.repeatable) then DB.selected = list[1] end
  local q, isPreview = View()

  local extra = 0
  text:ClearAllPoints()
  if n > 1 and not isPreview then
    dropdown:Show()
    dropdownText:SetText(DisplayName(DB.selected, list))
    text:SetPoint("TOPLEFT", tracker, "TOPLEFT", 8, -38)
    extra = 30
  else
    dropdown:Hide()
    text:SetPoint("TOPLEFT", tracker, "TOPLEFT", 8, -8)
  end

  local out, lines = "", 0
  local function Add(s)
    if lines > 0 then out = out .. "\n" end
    out = out .. s
    lines = lines + 1
  end

  if isPreview then
    Add("|cffffd100Turn It In|r |cff999999- new quest|r")
  else
    Add("|cffffd100Turn It In|r")
  end

  local nChoices = 0
  if not q then
    Add("|cff999999No repeatable quests recorded yet.|r")
    Add("|cff999999Open a quest with an NPC and press|r")
    Add("|cff999999Track quest, or turn it in twice.|r")
  else
    Add("|cff00ff00" .. q.title .. "|r |cff999999(" .. q.npc .. ")|r")
    if isPreview then
      if q.completions > 0 then
        Add("|cff999999Turned in " .. q.completions .. "x so far - not tracked yet|r")
      else
        Add("|cff999999Not tracked yet|r")
      end
    end

    if table.getn(q.req) > 0 then
      Add("|cffffd100Hand in:|r")
      for i = 1, table.getn(q.req) do
        local r = q.req[i]
        Add("   " .. r.name .. ": " .. CountItem(r.name) .. "/" .. (r.count or 1))
      end
    elseif isPreview then
      Add("|cff999999Items needed appear when you reach|r")
      Add("|cff999999the hand-in step of the quest.|r")
    end
    if q.needMoney and q.needMoney > 0 then
      Add("   Cost: " .. Money(q.needMoney))
    end

    local possible = Possible(q)
    local mult = 1
    if possible then Add("Turn-ins available: |cffffffff" .. possible .. "|r") end
    if possible and possible > 0 then
      mult = possible
      Add("|cffffd100Rewards for " .. possible .. " turn-in" ..
          (possible > 1 and "s" or "") .. ":|r")
    else
      Add("|cffffd100Rewards per turn-in:|r")
    end

    if q.money and q.money > 0 then
      Add("   Money: " .. Money(q.money * mult))
    end
    for i = 1, table.getn(q.items) do
      local it = q.items[i]
      Add("   " .. it.name .. " x" .. (it.count * mult))
    end
    nChoices = table.getn(q.choices)
    if nChoices > 0 then
      local picked = nil
      for i = 1, nChoices do
        if q.choices[i].name == q.choice then picked = q.choices[i] end
      end
      if picked then
        Add("   " .. picked.name .. " x" .. (picked.count * mult))
      else
        Add("   |cffff8800Choose a reward below|r")
      end
    end

    if q.observed then
      if q.honor and q.honor > 0 then
        Add("   Honor: " .. (q.honor * mult))
      end
      if q.rep then
        for faction, amt in pairs(q.rep) do
          if amt > 0 then Add("   " .. faction .. ": +" .. (amt * mult) .. " rep") end
        end
      end
      if q.xp and q.xp > 0 then
        Add("   Experience: " .. (q.xp * mult))
      end
    else
      Add("   |cff999999Honor, reputation and XP are|r")
      Add("   |cff999999learned from your next turn-in.|r")
    end
  end

  text:SetText(out)

  local top = 8 + extra + lines * 12
  local height = top + 34

  -- Reward choice row
  if nChoices > 0 then
    choiceLabel:ClearAllPoints()
    choiceLabel:SetPoint("TOPLEFT", tracker, "TOPLEFT", 8, -(top + 6))
    choiceLabel:Show()
    height = height + 50
  else
    choiceLabel:Hide()
  end
  for i = 1, 6 do
    local b = choiceButtons[i]
    if i <= nChoices then
      local c = q.choices[i]
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", tracker, "TOPLEFT", 8 + (i - 1) * 34, -(top + 20))
      b.icon:SetTexture(c.texture)
      if c.count and c.count > 1 then b.count:SetText(tostring(c.count)) else b.count:SetText("") end
      if q.choice == c.name then
        b:SetBackdropBorderColor(0, 1, 0)
      else
        b:SetBackdropBorderColor(0.5, 0.5, 0.5)
      end
      b:Show()
    else
      b:Hide()
    end
  end

  if isPreview then trackButton:Show() else trackButton:Hide() end
  autoButton:SetText(auto and "|cff00ff00Auto: ON|r" or "|cffff0000Auto: OFF|r")

  tracker:SetHeight(height)
  tracker:SetWidth(math.max(270, text:GetWidth() + 16))

  if RefreshList then RefreshList() end
end

----------------------------------------------------------------
-- Quest list window and minimap button
----------------------------------------------------------------
local ROW_HEIGHT = 18

-- Zone name for display; falls back to the client's own map names so quests
-- recorded before names were stored still get one.
local function LocationName(q)
  if q.zoneName and q.zoneName ~= "" then return q.zoneName end
  if q.zone then
    local zones = { GetMapZones(q.zone[1]) }
    if zones[q.zone[2]] then return zones[q.zone[2]] end
  end
  return "Unknown location"
end

local list = CreateFrame("Frame", "TIIList", UIParent)
list:SetWidth(440)
list:SetHeight(420)
list:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
list:SetFrameStrata("DIALOG")
list:SetMovable(true)
list:EnableMouse(true)
list:RegisterForDrag("LeftButton")
list:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
list:SetScript("OnDragStart", function() this:StartMoving() end)
list:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
list:Hide()
table.insert(UISpecialFrames, "TIIList")   -- Escape closes it

local listTitle = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listTitle:SetPoint("TOP", list, "TOP", 0, -18)
listTitle:SetText("Turn It In - Known Quests")

local listClose = CreateFrame("Button", "TIIListClose", list, "UIPanelCloseButton")
listClose:SetPoint("TOPRIGHT", list, "TOPRIGHT", -6, -6)

local modeQuest = CreateFrame("Button", "TIIModeQuest", list, "UIPanelButtonTemplate")
modeQuest:SetWidth(120)
modeQuest:SetHeight(22)
modeQuest:SetPoint("TOPLEFT", list, "TOPLEFT", 20, -42)
modeQuest:SetScript("OnClick", function()
  DB.listMode = "quest"
  RefreshList()
end)

local modeLoc = CreateFrame("Button", "TIIModeLocation", list, "UIPanelButtonTemplate")
modeLoc:SetWidth(150)
modeLoc:SetHeight(22)
modeLoc:SetPoint("LEFT", modeQuest, "RIGHT", 6, 0)
modeLoc:SetScript("OnClick", function()
  DB.listMode = "location"
  RefreshList()
end)

local listCount = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
listCount:SetPoint("TOPRIGHT", list, "TOPRIGHT", -40, -48)
listCount:SetJustifyH("RIGHT")

local scroll = CreateFrame("ScrollFrame", "TIIListScroll", list, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 18, -74)
scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -36, 18)
local child = CreateFrame("Frame", "TIIListChild", scroll)
child:SetWidth(380)
child:SetHeight(10)
scroll:SetScrollChild(child)

local function ShowQuestTooltip(owner, q)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(q.title, 1, 0.82, 0)
  GameTooltip:AddLine(q.npc .. " - " .. LocationName(q), 0.8, 0.8, 0.8)

  if table.getn(q.req) > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Hand in:", 1, 0.82, 0)
    for i = 1, table.getn(q.req) do
      local r = q.req[i]
      GameTooltip:AddLine("  " .. r.name .. " x" .. (r.count or 1) ..
        "  (you have " .. CountItem(r.name) .. ")", 1, 1, 1)
    end
  end
  if q.needMoney and q.needMoney > 0 then
    GameTooltip:AddLine("  Cost: " .. Money(q.needMoney), 1, 1, 1)
  end

  local hasReward = (q.money and q.money > 0) or table.getn(q.items) > 0
                    or table.getn(q.choices) > 0 or q.observed
  if hasReward then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Rewards per turn-in:", 1, 0.82, 0)
    if q.money and q.money > 0 then
      GameTooltip:AddLine("  " .. Money(q.money), 1, 1, 1)
    end
    for i = 1, table.getn(q.items) do
      GameTooltip:AddLine("  " .. q.items[i].name .. " x" .. q.items[i].count, 1, 1, 1)
    end
    if table.getn(q.choices) > 0 then
      local names = ""
      for i = 1, table.getn(q.choices) do
        if i > 1 then names = names .. ", " end
        names = names .. q.choices[i].name
      end
      GameTooltip:AddLine("  Choose one: " .. names, 1, 1, 1)
    end
    if q.observed then
      if q.honor and q.honor > 0 then
        GameTooltip:AddLine("  Honor: " .. q.honor, 1, 1, 1)
      end
      if q.rep then
        for faction, amt in pairs(q.rep) do
          if amt > 0 then GameTooltip:AddLine("  " .. faction .. ": +" .. amt .. " rep", 1, 1, 1) end
        end
      end
      if q.xp and q.xp > 0 then
        GameTooltip:AddLine("  Experience: " .. q.xp, 1, 1, 1)
      end
    end
  end

  GameTooltip:AddLine(" ")
  if q.repeatable then
    GameTooltip:AddLine("Click to show it in the tracker window", 0.5, 1, 0.5)
  else
    GameTooltip:AddLine("Not tracked yet - click to track it", 0.5, 1, 0.5)
  end
  GameTooltip:Show()
end

local rows = {}
local function GetRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", "TIIListRow" .. i, child)
  r:SetWidth(380)
  r:SetHeight(ROW_HEIGHT)
  r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

  local fs = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("LEFT", r, "LEFT", 4, 0)
  fs:SetWidth(290)
  fs:SetHeight(16)
  fs:SetJustifyH("LEFT")
  r.text = fs

  local rt = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  rt:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  rt:SetJustifyH("RIGHT")
  r.right = rt

  r:SetScript("OnClick", function()
    local q = this.key and DB.quests[this.key]
    if not q then return end
    if not q.repeatable then
      q.repeatable = true
      Print("Tracking: " .. q.title)
    end
    DB.selected = this.key
    preview = nil
    tracker:Show()
    Refresh()
  end)
  r:SetScript("OnEnter", function()
    local q = this.key and DB.quests[this.key]
    if q then ShowQuestTooltip(this, q) end
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)

  rows[i] = r
  return r
end

RefreshList = function()
  if not DB or not list:IsShown() then return end
  if DB.listMode ~= "location" then DB.listMode = "quest" end

  -- Known quests: tracked first, then alphabetical
  local keys = {}
  for key in pairs(DB.quests) do table.insert(keys, key) end
  table.sort(keys, function(a, b)
    local qa, qb = DB.quests[a], DB.quests[b]
    local ta = qa.repeatable and true or false
    local tb = qb.repeatable and true or false
    if ta ~= tb then return ta end
    if qa.title ~= qb.title then return qa.title < qb.title end
    return qa.npc < qb.npc
  end)

  local entries = {}
  if DB.listMode == "location" then
    local groups, order = {}, {}
    for i = 1, table.getn(keys) do
      local q = DB.quests[keys[i]]
      local label = LocationName(q) .. " - " .. q.npc
      if q.subZone and q.subZone ~= "" then
        label = label .. " |cff999999(" .. q.subZone .. ")|r"
      end
      if not groups[label] then
        groups[label] = {}
        table.insert(order, label)
      end
      table.insert(groups[label], keys[i])
    end
    table.sort(order)
    for i = 1, table.getn(order) do
      table.insert(entries, { header = order[i] })
      local g = groups[order[i]]
      for j = 1, table.getn(g) do table.insert(entries, { key = g[j] }) end
    end
  else
    for i = 1, table.getn(keys) do table.insert(entries, { key = keys[i] }) end
  end

  modeQuest:SetText(DB.listMode == "quest" and "|cff00ff00By quest|r" or "By quest")
  modeLoc:SetText(DB.listMode == "location" and "|cff00ff00By turn-in location|r" or "By turn-in location")
  listCount:SetText(table.getn(keys) .. " known")

  local used = 0
  if table.getn(entries) == 0 then
    used = 1
    local r = GetRow(1)
    r.key = nil
    r.text:SetText("|cff999999No quests known yet. Open a repeatable|r")
    r.right:SetText("")
    r:Show()
    local r2 = GetRow(2)
    r2.key = nil
    r2.text:SetText("|cff999999quest with an NPC to record it.|r")
    r2.right:SetText("")
    r2:Show()
    used = 2
  end

  for i = 1, table.getn(entries) do
    local e = entries[i]
    local r = GetRow(i)
    used = i
    r.key = e.key
    if e.header then
      r.text:SetText("|cffffd100" .. e.header .. "|r")
      r.right:SetText("")
    else
      local q = DB.quests[e.key]
      local color = q.repeatable and "|cffffffff" or "|cff999999"
      if DB.selected == e.key then color = "|cff00ff00" end
      local label = color .. q.title .. "|r"
      if DB.listMode == "location" then
        label = "   " .. label
      else
        label = label .. " |cff999999(" .. q.npc .. ")|r"
      end
      r.text:SetText(label)

      if not q.repeatable then
        r.right:SetText("|cff999999not tracked|r")
      else
        local p = Possible(q)
        if p == nil then
          r.right:SetText("")
        elseif p > 0 then
          r.right:SetText("|cff00ff00" .. p .. " ready|r")
        else
          r.right:SetText("|cff999999none ready|r")
        end
      end
    end
    r:Show()
  end

  for i = used + 1, table.getn(rows) do rows[i]:Hide() end
  child:SetHeight(math.max(10, used * ROW_HEIGHT))
end

list:SetScript("OnShow", function() RefreshList() end)

-- Minimap button (gold coin icon)
local mm = CreateFrame("Button", "TIIMinimapButton", Minimap)
mm:SetWidth(31)
mm:SetHeight(31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local mmIcon = mm:CreateTexture(nil, "BACKGROUND")
mmIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
mmIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
mmIcon:SetWidth(17)
mmIcon:SetHeight(17)
mmIcon:SetPoint("TOPLEFT", mm, "TOPLEFT", 7, -6)

local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetWidth(53)
mmBorder:SetHeight(53)
mmBorder:SetPoint("TOPLEFT", mm, "TOPLEFT", 0, 0)

local function PlaceMinimapButton()
  local angle = math.rad((DB and DB.minimapAngle) or 200)
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
end

local function InitMinimapButton()
  PlaceMinimapButton()
  if DB.minimapHidden then mm:Hide() else mm:Show() end
end

mm:SetScript("OnDragStart", function()
  this:LockHighlight()
  this:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    DB.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
    PlaceMinimapButton()
  end)
end)
mm:SetScript("OnDragStop", function()
  this:SetScript("OnUpdate", nil)
  this:UnlockHighlight()
end)

mm:SetScript("OnClick", function()
  if not DB then return end
  if arg1 == "RightButton" then
    if tracker:IsShown() then
      tracker:Hide()
    else
      tracker:Show()
      Refresh()
    end
  else
    if list:IsShown() then
      list:Hide()
    else
      list:Show()
      RefreshList()
    end
  end
end)
mm:SetScript("OnEnter", function()
  GameTooltip:SetOwner(this, "ANCHOR_LEFT")
  GameTooltip:SetText("Turn It In", 1, 0.82, 0)
  GameTooltip:AddLine("Left-click: known quests", 1, 1, 1)
  GameTooltip:AddLine("Right-click: tracker window", 1, 1, 1)
  GameTooltip:AddLine("Drag: move this icon", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

----------------------------------------------------------------
-- Visibility: shown in zones where a repeatable quest was recorded,
-- hidden everywhere else and while in a raid
----------------------------------------------------------------
local function UpdateVisibility()
  if not DB then return end
  if GetNumRaidMembers() > 0 then
    tracker:Hide()
    return
  end
  if preview then return end
  if WorldMapFrame and WorldMapFrame:IsVisible() then return end

  SetMapToCurrentZone()
  local c, z = GetCurrentMapContinent(), GetCurrentMapZone()
  for key, q in pairs(DB.quests) do
    if q.repeatable and q.zone and q.zone[1] == c and q.zone[2] == z then
      tracker:Show()
      Refresh()
      return
    end
  end
  tracker:Hide()
end

----------------------------------------------------------------
-- Observing what a turn-in actually gives (honor, reputation, XP)
----------------------------------------------------------------
local timerFrame = CreateFrame("Frame")
timerFrame:Hide()

local function FinalizePending()
  if not pending then return end
  local q = DB.quests[pending.key]
  if q then
    q.honor = pending.honor
    q.xp = pending.xp
    q.rep = pending.rep
    q.observed = true
  end
  pending = nil
  timerFrame:Hide()
  Refresh()
end

timerFrame:SetScript("OnUpdate", function()
  pendingTime = pendingTime + arg1
  if pendingTime >= 2 then FinalizePending() end
end)

-- Called just before the reward is actually accepted.
local function OnReward()
  if not DB then return end
  local npc, title = UnitName("npc"), Strip(GetTitleText())
  if not npc or not title then return end

  FinalizePending()

  local key = QuestKey(npc, title)
  local q = EnsureQuest(key, title, npc)
  local s = seen[key]
  if s then
    q.req = s.req
    q.needMoney = s.needMoney
  end
  MergeRewards(q, CaptureRewards())
  q.completions = q.completions + 1
  q.last = time()
  StampLocation(q)
  if q.completions >= 2 then q.repeatable = true end

  pending = { key = key, rep = {}, honor = 0, xp = 0 }
  pendingTime = 0
  timerFrame:Show()
end

local origGetQuestReward = GetQuestReward
GetQuestReward = function(choice)
  OnReward()
  return origGetQuestReward(choice)
end

----------------------------------------------------------------
-- Detecting repeatable quests
-- The 1.12 client does not flag repeatable quests, so a quest counts
-- as repeatable once it is offered again after being turned in
-- (or once it has been turned in twice).
----------------------------------------------------------------
local function MarkAvailable(title)
  local npc = UnitName("npc")
  if not npc or not title then return end
  local q = DB.quests[QuestKey(npc, Strip(title))]
  Debug("offered: " .. QuestKey(npc, Strip(title)) .. " known=" .. tostring(q ~= nil) ..
        (q and (" completions=" .. q.completions .. " repeatable=" .. tostring(q.repeatable)) or ""))
  if q and not q.repeatable and q.completions >= 1 then
    q.repeatable = true
    StampLocation(q)
    Print("Recorded repeatable quest: " .. q.title)
    UpdateVisibility()
    Refresh()
  end
end

-- Record what the open quest dialog shows and display it in the window right
-- away, tracked or not.
local function Observe(stage)
  local npc, title = UnitName("npc"), Strip(GetTitleText())
  if not npc or not title or title == "" then return nil end
  local key = QuestKey(npc, title)
  local q = EnsureQuest(key, title, npc)
  q.last = time()
  StampLocation(q)

  if stage == "progress" then
    local req, needMoney = CaptureRequirements()
    seen[key] = { req = req, needMoney = needMoney }
    q.req = req
    q.needMoney = needMoney
    local ok, money, items, choices = pcall(ReadQuestLog, title)
    if ok and money then MergeRewards(q, money, items, choices) end
  else
    MergeRewards(q, CaptureRewards())
    local s = seen[key]
    if s and table.getn(q.req) == 0 then
      q.req = s.req
      q.needMoney = s.needMoney
    end
  end

  Debug(stage .. ": " .. key .. " req=" .. table.getn(q.req) ..
        " items=" .. table.getn(q.items) .. " choices=" .. table.getn(q.choices) ..
        " repeatable=" .. tostring(q.repeatable))

  if q.repeatable then
    preview = nil
    DB.selected = key
  else
    preview = key
    if GetNumRaidMembers() == 0 then tracker:Show() end
  end
  Refresh()
  return q
end

-- When talking to an NPC, switch the window to one of their quests.
local function FocusNPC()
  local npc = UnitName("npc")
  local cur = Selected()
  if not npc or (cur and cur.npc == npc) then return end
  local list = RepeatableList()
  for i = 1, table.getn(list) do
    if DB.quests[list[i]].npc == npc then
      DB.selected = list[i]
      Refresh()
      return
    end
  end
end

----------------------------------------------------------------
-- Auto turn-in (only for the quest selected in the dropdown)
----------------------------------------------------------------
local function IsSelectedQuest(title)
  local q = Selected()
  if not q or not title then return false end
  return Strip(title) == q.title and UnitName("npc") == q.npc
end

-- Gossip lists return title, level pairs; count only the titles.
local function PickGossip(list)
  local idx = 0
  for i = 1, table.getn(list) do
    if type(list[i]) == "string" then
      idx = idx + 1
      if IsSelectedQuest(list[i]) then return idx end
    end
  end
  return nil
end

local function HandleGossip()
  local i = PickGossip({ GetGossipActiveQuests() })
  if i then SelectGossipActiveQuest(i) return end
  i = PickGossip({ GetGossipAvailableQuests() })
  if i then SelectGossipAvailableQuest(i) end
end

local function HandleGreeting()
  for i = 1, GetNumActiveQuests() do
    if IsSelectedQuest(GetActiveTitle(i)) then SelectActiveQuest(i) return end
  end
  for i = 1, GetNumAvailableQuests() do
    if IsSelectedQuest(GetAvailableTitle(i)) then SelectAvailableQuest(i) return end
  end
end

-- Index of the reward the user picked, matched by item name.
local function ChoiceIndex(q)
  local nChoices = GetNumQuestChoices()
  if q.choice then
    for i = 1, nChoices do
      local name = GetQuestItemInfo("choice", i)
      if name == q.choice then return i end
    end
    return nil
  end
  if nChoices == 1 then
    q.choice = GetQuestItemInfo("choice", 1)
    return 1
  end
  return nil
end

local function DoReward(q)
  if GetNumQuestChoices() > 0 then
    local idx = ChoiceIndex(q)
    if idx then
      GetQuestReward(idx)
    else
      auto = false
      Print("Pick a reward in the Turn It In window first - auto turn-in stopped.")
    end
  else
    GetQuestReward()
  end
end

----------------------------------------------------------------
-- Events
----------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("BAG_UPDATE")
f:RegisterEvent("PLAYER_MONEY")
f:RegisterEvent("GOSSIP_SHOW")
f:RegisterEvent("QUEST_GREETING")
f:RegisterEvent("QUEST_DETAIL")
f:RegisterEvent("QUEST_PROGRESS")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("QUEST_FINISHED")
f:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
f:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
f:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")

f:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if string.lower(arg1 or "") ~= "turnitin" then return end
    if not TurnItInDB or TurnItInDB.version ~= 2 then
      TurnItInDB = { version = 2, quests = {} }
    end
    DB = TurnItInDB
    -- Forget quests that were turned in once and never came back
    local now = time()
    for key, q in pairs(DB.quests) do
      if not q.repeatable and q.last and now - q.last > 7 * 86400 then
        DB.quests[key] = nil
      end
    end
    DB.listMode = DB.listMode or "quest"
    InitMinimapButton()
    Refresh()
    return
  end
  if not DB then return end

  if event == "PLAYER_ENTERING_WORLD"
     or event == "ZONE_CHANGED_NEW_AREA"
     or event == "RAID_ROSTER_UPDATE" then
    UpdateVisibility()

  elseif event == "BAG_UPDATE" or event == "PLAYER_MONEY" then
    if tracker:IsShown() then Refresh() end

  elseif event == "GOSSIP_SHOW" then
    local av = { GetGossipAvailableQuests() }
    if debugOn then
      local ac = { GetGossipActiveQuests() }
      Debug("GOSSIP_SHOW npc=" .. tostring(UnitName("npc")))
      for i = 1, table.getn(av) do Debug("  available[" .. i .. "] = [" .. tostring(av[i]) .. "]") end
      for i = 1, table.getn(ac) do Debug("  active[" .. i .. "] = [" .. tostring(ac[i]) .. "]") end
    end
    for i = 1, table.getn(av) do
      if type(av[i]) == "string" then MarkAvailable(av[i]) end
    end
    FocusNPC()
    if auto then HandleGossip() end

  elseif event == "QUEST_GREETING" then
    Debug("QUEST_GREETING npc=" .. tostring(UnitName("npc")) ..
          " available=" .. GetNumAvailableQuests() .. " active=" .. GetNumActiveQuests())
    for i = 1, GetNumAvailableQuests() do
      local t = GetAvailableTitle(i)
      Debug("  available[" .. i .. "] = [" .. tostring(t) .. "]")
      MarkAvailable(t)
    end
    FocusNPC()
    if auto then HandleGreeting() end

  elseif event == "QUEST_DETAIL" then
    local title = Strip(GetTitleText())
    Debug("QUEST_DETAIL npc=" .. tostring(UnitName("npc")) .. " title=[" .. tostring(title) .. "]")
    if not UnitName("npc") or not title then return end
    MarkAvailable(title)
    Observe("detail")
    if auto and IsSelectedQuest(title) then AcceptQuest() end

  elseif event == "QUEST_PROGRESS" then
    local title = Strip(GetTitleText())
    Debug("QUEST_PROGRESS npc=" .. tostring(UnitName("npc")) .. " title=[" .. tostring(title) .. "]")
    if not UnitName("npc") or not title then return end
    Observe("progress")
    if auto and IsSelectedQuest(title) then
      if IsQuestCompletable() then
        CompleteQuest()
      else
        auto = false
        Print("Out of items - auto turn-in stopped.")
        Refresh()
      end
    end

  elseif event == "QUEST_COMPLETE" then
    local title = Strip(GetTitleText())
    Debug("QUEST_COMPLETE npc=" .. tostring(UnitName("npc")) .. " title=[" .. tostring(title) .. "]")
    if not UnitName("npc") or not title then return end
    Observe("complete")
    if auto and IsSelectedQuest(title) then DoReward(Selected()) end
    Refresh()

  elseif event == "QUEST_FINISHED" then
    if preview then
      preview = nil
      UpdateVisibility()
      Refresh()
    end

  elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
    if pending then
      local faction, amount = ParseRep(arg1 or "")
      if faction then pending.rep[faction] = (pending.rep[faction] or 0) + amount end
    end

  elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
    if pending then
      local h = ParseHonor(arg1 or "")
      if h then pending.honor = pending.honor + h end
    end

  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    if pending then
      local x = ParseXP(arg1 or "")
      if x then pending.xp = pending.xp + x end
    end
  end
end)

----------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------
SLASH_TURNITIN1 = "/tii"
SLASH_TURNITIN2 = "/turnitin"
SlashCmdList["TURNITIN"] = function(msg)
  if not DB then return end
  msg = string.lower(msg or "")

  if msg == "" or msg == "toggle" then
    if tracker:IsShown() then tracker:Hide() else tracker:Show() Refresh() end
  elseif msg == "show" then
    tracker:Show()
    Refresh()
  elseif msg == "hide" then
    tracker:Hide()
  elseif msg == "auto" then
    auto = not auto
    Print("Auto turn-in " .. (auto and "ON" or "OFF") ..
      ". Right-click the quest NPC to start.")
    Refresh()
  elseif msg == "list" or msg == "quests" then
    if list:IsShown() then
      list:Hide()
    else
      list:Show()
      RefreshList()
    end
  elseif msg == "minimap" then
    DB.minimapHidden = not DB.minimapHidden
    InitMinimapButton()
    Print("Minimap button " .. (DB.minimapHidden and "hidden" or "shown"))
  elseif msg == "debug" then
    debugOn = not debugOn
    Print("Debug output " .. (debugOn and "ON" or "OFF"))
  elseif msg == "track" then
    -- Force-record the quest in the open dialog as repeatable
    local npc, title = UnitName("npc"), Strip(GetTitleText())
    if not npc or not title or title == "" then
      Print("Open the quest's window with an NPC first.")
      return
    end
    local key = QuestKey(npc, title)
    local q = EnsureQuest(key, title, npc)
    local s = seen[key]
    if s then q.req = s.req q.needMoney = s.needMoney end
    local detail = QuestFrameDetailPanel and QuestFrameDetailPanel:IsVisible()
    local reward = QuestFrameRewardPanel and QuestFrameRewardPanel:IsVisible()
    if detail or reward then MergeRewards(q, CaptureRewards()) end
    q.repeatable = true
    StampLocation(q)
    DB.selected = key
    Print("Recorded repeatable quest: " .. title)
    UpdateVisibility()
    Refresh()
  elseif msg == "forget" then
    local q = Selected()
    if q then
      Print("Forgot " .. q.title)
      DB.quests[DB.selected] = nil
      DB.selected = nil
      Refresh()
    end
  else
    Print("/tii [toggle] | show | hide | list | minimap | auto | track | forget | debug")
  end
end
