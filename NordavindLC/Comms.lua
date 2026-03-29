-- Comms.lua
-- Addon message communication for raid-wide council sync

local NLC = NordavindLC_NS

local PREFIX = "NordLC"
local registered = false

function NLC.Comms.Register()
  if registered then return end
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  registered = true
end

function NLC.Comms.Send(msgType, data)
  if not IsInRaid() then return end
  local payload = msgType .. ":" .. (data or "")
  C_ChatInfo.SendAddonMessage(PREFIX, payload, "RAID")
end

function NLC.Comms.OnMessage(prefix, message, channel, sender)
  if prefix ~= PREFIX or not NLC.active then return end

  local msgType, data = message:match("^(%w+):(.*)$")
  if not msgType then return end

  if msgType == "SESSION_START" then
    local items = {}
    for itemData in data:gmatch("[^|]+") do
      local itemLink, itemId, ilvl, equipLoc, boss = itemData:match("^(.*);(%d+);(%d+);([^;]*);(.*)$")
      if itemLink then
        table.insert(items, {
          itemLink = itemLink,
          itemId = tonumber(itemId),
          ilvl = tonumber(ilvl),
          equipLoc = equipLoc,
          boss = boss,
        })
      end
    end
    local timer = 90
    if NLC.Council.OnMultiSessionStart then
      NLC.Council.OnMultiSessionStart(items, timer, sender)
    end

  elseif msgType == "RESPOND" then
    if NLC.Council.OnRespond then
      NLC.Council.OnRespond(sender)
    end

  elseif msgType == "INTEREST" then
    for entry in data:gmatch("[^,]+") do
      local itemId, category, eqIlvl, tierCount, note = entry:match("^(%d+):(%w+):(%d+):(%d+):?(.*)$")
      if itemId and NLC.Council.OnInterestReceived then
        NLC.Council.OnInterestReceived(sender, tonumber(itemId), category, tonumber(eqIlvl), tonumber(tierCount), note)
      end
    end

  elseif msgType == "AWARD" then
    local itemLink, playerName = data:match("^(.+):([^:]+)$")
    if itemLink and NLC.Council.OnAward then
      NLC.Council.OnAward(itemLink, playerName, sender)
    end

  elseif msgType == "COUNCIL_CLOSE" then
    if NLC.Council.OnCouncilClose then
      NLC.Council.OnCouncilClose(data)
    end
  end
end

function NLC.Comms.SendMultiSession(items, boss)
  if not IsInRaid() then return end
  local parts = {}
  for _, item in ipairs(items) do
    table.insert(parts, string.format("%s;%d;%d;%s;%s",
      item.itemLink, item.itemId or 0, item.ilvl or 0, item.equipLoc or "", boss or ""))
  end
  local payload = "SESSION_START:" .. table.concat(parts, "|")
  C_ChatInfo.SendAddonMessage(PREFIX, payload, "RAID")
end

function NLC.Comms.SendMultiInterest(responses)
  local parts = {}
  for _, r in ipairs(responses) do
    table.insert(parts, string.format("%d:%s:%d:%d:%s",
      r.itemId or 0, r.category, r.eqIlvl or 0, r.tierCount or 0, r.note or ""))
  end
  NLC.Comms.Send("INTEREST", table.concat(parts, ","))
end

function NLC.Comms.SendRespond()
  NLC.Comms.Send("RESPOND", "1")
end

local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
  if event == "CHAT_MSG_ADDON" then
    NLC.Comms.OnMessage(prefix, message, channel, sender)
  end
end)
