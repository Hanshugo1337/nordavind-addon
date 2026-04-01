-- Comms.lua
-- Addon communication using AceComm (auto-chunking for >255 byte messages)
-- and AceSerializer (safe serialization, no separator collisions with item links)

local NLC = NordavindLC_NS

local PREFIX = "NordLC"
local registered = false

local AceComm = LibStub("AceComm-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")
AceComm:Embed(NLC.Comms)
AceSerializer:Embed(NLC.Comms)

function NLC.Comms.Register()
  if registered then return end
  NLC.Comms:RegisterComm(PREFIX, function(prefix, message, channel, sender)
    NLC.Comms.OnMessage(prefix, message, channel, sender)
  end)
  registered = true
end

function NLC.Comms.Send(msgType, data)
  if not IsInRaid() then return end
  local payload = NLC.Comms:Serialize(msgType, data)
  NLC.Comms:SendCommMessage(PREFIX, payload, "RAID")
end

function NLC.Comms.OnMessage(prefix, message, channel, sender)
  if prefix ~= PREFIX then return end

  local success, msgType, data = NLC.Comms:Deserialize(message)
  if not success then return end

  -- ACTIVATE is handled before active check (activates non-leader raiders)
  if msgType == "ACTIVATE" then
    if not NLC.active then
      NLC.Activate()
      NLC.Utils.Print("Activated by raid leader.")
    end
    return
  end

  -- Non-leader asking if leader is active — respond with ACTIVATE
  if msgType == "ACTIVATE_CHECK" then
    if NLC.active and UnitIsGroupLeader("player") then
      NLC.Comms.Send("ACTIVATE", "")
    end
    return
  end

  -- SESSION_START also auto-activates (in case raider missed ACTIVATE or joined late)
  if not NLC.active and msgType == "SESSION_START" then
    NLC.Activate()
    NLC.Utils.Print("Activated by council session.")
  end

  if not NLC.active then return end

  if msgType == "SESSION_START" then
    -- Skip own broadcast — the officer who started it already has state from StartMultiSession
    local myName = UnitName("player")
    local senderName = sender:match("^([^-]+)") or sender
    if senderName == myName then
      -- do nothing, already set up
    elseif NLC.Council.OnMultiSessionStart then
      NLC.Council.OnMultiSessionStart(data.items, data.timer or 90, sender)
    end

  elseif msgType == "RESPOND" then
    if NLC.Council.OnRespond then
      NLC.Council.OnRespond(sender)
    end

  elseif msgType == "INTEREST" then
    for _, entry in ipairs(data) do
      if NLC.Council.OnInterestReceived then
        NLC.Council.OnInterestReceived(sender, entry.sessionIdx, entry.category, entry.eqIlvl, entry.tierCount, entry.note)
      end
    end

  elseif msgType == "AWARD" then
    if NLC.Council.OnAward then
      NLC.Council.OnAward(data.sessionIdx, data.itemLink, data.playerName, sender, data.category)
    end

  elseif msgType == "SESSION_CLOSE" then
    NLC.UI.HideMultiItemPopup()
    if not NLC.isOfficer and NLC.Council.OnSessionClose then
      NLC.Council.OnSessionClose(data)
    end

  elseif msgType == "ROLL_CALL" then
    NLC.Comms.Send("ROLL_CALL_ACK", "")

  elseif msgType == "ROLL_CALL_ACK" then
    if NLC.Council.OnRollCallAck then
      NLC.Council.OnRollCallAck(sender)
    end

  elseif msgType == "VERSION_CHECK" then
    NLC.Comms.Send("VERSION_REPLY", NLC.version)

  elseif msgType == "VERSION_REPLY" then
    if NLC.versionCheckResults then
      local name = sender:match("^([^-]+)") or sender
      NLC.versionCheckResults[name] = data
    end
  end
end

function NLC.Comms.SendMultiSession(items, boss)
  if not IsInRaid() then return end
  local data = { items = {}, timer = NLC.db.config.timer or 90 }
  for idx, item in ipairs(items) do
    table.insert(data.items, {
      sessionIdx = idx,
      itemLink = item.itemLink,
      itemId = item.itemId or 0,
      ilvl = item.ilvl or 0,
      equipLoc = item.equipLoc or "",
      boss = boss or "",
    })
  end
  NLC.Comms.Send("SESSION_START", data)
end

function NLC.Comms.SendMultiInterest(responses)
  NLC.Comms.Send("INTEREST", responses)
end

function NLC.Comms.SendRespond()
  NLC.Comms.Send("RESPOND", "1")
end

function NLC.Comms.SendRollCall()
  NLC.Comms.Send("ROLL_CALL", "")
end
