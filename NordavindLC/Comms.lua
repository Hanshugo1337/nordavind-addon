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

  if msgType == "COUNCIL_START" then
    local itemLink, timer = data:match("^(.+):(%d+)$")
    if itemLink and NLC.Council.OnCouncilStart then
      NLC.Council.OnCouncilStart(itemLink, tonumber(timer), sender)
    end

  elseif msgType == "INTEREST" then
    local itemId, category, eqIlvl, tierCount = data:match("^(%d+):(%w+):(%d+):(%d+)$")
    if itemId and NLC.Council.OnInterestReceived then
      NLC.Council.OnInterestReceived(sender, tonumber(itemId), category, tonumber(eqIlvl), tonumber(tierCount))
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

local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
  if event == "CHAT_MSG_ADDON" then
    NLC.Comms.OnMessage(prefix, message, channel, sender)
  end
end)
