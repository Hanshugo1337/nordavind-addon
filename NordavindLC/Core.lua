-- Core.lua
-- Main addon initialization, SavedVariables, slash commands

local ADDON_NAME = ...
local NLC = NordavindLC_NS

-- State
NLC.active = false
NLC.isOfficer = false
NLC.db = {}
NLC.importData = {}
NLC.pendingSessions = {}

-- Initialize
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PARTY_LEADER_CHANGED")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    NordavindLC_DB = NordavindLC_DB or {
      importData = { players = {} },
      lootHistory = {},
      config = { officers = {}, timer = 30 },
      pendingExport = {},
    }
    NLC.db = NordavindLC_DB

    if NordavindLC_Import and NordavindLC_Import.players then
      NLC.db.importData = NordavindLC_Import
      NLC.Utils.Print("Import-data lastet (" .. NLC.Utils.TableCount(NLC.db.importData.players) .. " spillere)")
    end

    NLC.Utils.Print("Lastet. Bruk /nordlc for kommandoer.")

  elseif event == "PLAYER_ENTERING_WORLD" or event == "PARTY_LEADER_CHANGED" then
    if IsInRaid() and not NLC.active then
      C_Timer.After(2, function()
        if IsInRaid() and not NLC.active then
          NLC.UI.ShowActivationPrompt()
        end
      end)
    end

  elseif event == "PLAYER_LOGOUT" then
    NordavindLC_DB = NLC.db
  end
end)

function NLC.CheckOfficer()
  local name = UnitName("player")
  for _, officer in ipairs(NLC.db.config.officers or {}) do
    if officer == name then NLC.isOfficer = true; return true end
  end
  local _, _, rankIndex = GetGuildInfo("player")
  if rankIndex and rankIndex <= 2 then NLC.isOfficer = true; return true end
  NLC.isOfficer = false
  return false
end

-- Minimap button — orbits minimap edge like other addon icons
local minimapBtn = nil
local minimapAngle = 220 -- degrees, saved position around minimap

local function UpdateMinimapPosition()
  local rad = math.rad(minimapAngle)
  local x = math.cos(rad) * 80
  local y = math.sin(rad) * 80
  minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function NLC.CreateMinimapButton()
  if minimapBtn then minimapBtn:Show(); return end

  minimapBtn = CreateFrame("Button", "NordavindLCMinimap", Minimap)
  minimapBtn:SetSize(32, 32)
  minimapBtn:SetFrameStrata("MEDIUM")
  minimapBtn:SetFrameLevel(8)
  minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  minimapBtn:EnableMouse(true)
  minimapBtn:RegisterForDrag("LeftButton")

  local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  icon:SetTexture("Interface\\AddOns\\NordavindLC\\logo")
  minimapBtn.icon = icon

  local border = minimapBtn:CreateTexture(nil, "OVERLAY")
  border:SetSize(54, 54)
  border:SetPoint("CENTER")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  minimapBtn.border = border

  -- Pending count text
  local countText = minimapBtn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  countText:SetPoint("BOTTOMRIGHT", 2, 2)
  countText:SetText("")
  minimapBtn.countText = countText

  -- Restore saved angle
  if NLC.db and NLC.db.minimapAngle then
    minimapAngle = NLC.db.minimapAngle
  end
  UpdateMinimapPosition()

  minimapBtn:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
      if #NLC.pendingSessions > 0 then
        SlashCmdList["NORDLC"]("pending")
      else
        SlashCmdList["NORDLC"]("status")
      end
    elseif button == "RightButton" then
      NLC.Deactivate()
      if minimapBtn then minimapBtn:Hide() end
    end
  end)
  minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- Drag around minimap edge
  local isDragging = false
  minimapBtn:SetScript("OnDragStart", function(self)
    isDragging = true
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
      UpdateMinimapPosition()
    end)
  end)
  minimapBtn:SetScript("OnDragStop", function(self)
    isDragging = false
    self:SetScript("OnUpdate", nil)
    -- Save angle
    if NLC.db then NLC.db.minimapAngle = minimapAngle end
  end)

  minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("NordavindLC", 0, 0.8, 1)
    GameTooltip:AddLine(NLC.active and "|cff00ff00Aktiv|r" or "|cffff0000Inaktiv|r", 1, 1, 1)
    if NLC.isOfficer then
      GameTooltip:AddLine("Officer-modus", 0.5, 1, 0.5)
    end
    local pending = #NLC.pendingSessions
    if pending > 0 then
      GameTooltip:AddLine(pending .. " ventende items", 1, 0.8, 0)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Venstreklikk: Status / Pending", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Hoyreklikk: Deaktiver", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  minimapBtn:Show()
end

function NLC.UpdateMinimapCount()
  if not minimapBtn then return end
  local pending = #NLC.pendingSessions
  if pending > 0 then
    minimapBtn.countText:SetText("|cffff8800" .. pending .. "|r")
  else
    minimapBtn.countText:SetText("")
  end
end

function NLC.Activate()
  NLC.active = true
  NLC.CheckOfficer()
  NLC.Comms.Register()
  NLC.LootDetection.Register()
  NLC.CreateMinimapButton()
  NLC.Utils.Print("Aktivert! " .. (NLC.isOfficer and "(Officer-modus)" or "(Raider-modus)"))
end

function NLC.Deactivate()
  NLC.active = false
  NLC.LootDetection.Unregister()
  if minimapBtn then minimapBtn:Hide() end
  NLC.Utils.Print("Deaktivert.")
end

function NLC.RecordAward(item, awardedTo, awardedBy, boss)
  local entry = {
    item = item,
    awardedTo = awardedTo,
    awardedBy = awardedBy,
    boss = boss or "Unknown",
    timestamp = time(),
  }
  table.insert(NLC.db.lootHistory, entry)
  table.insert(NLC.db.pendingExport, entry)
end

SLASH_NORDLC1 = "/nordlc"
SlashCmdList["NORDLC"] = function(msg)
  local trimmed = msg:trim()
  local cmd = trimmed:match("^(%S+)") or ""
  cmd = cmd:lower()
  local arg = trimmed:match("^%S+%s+(.+)$") or ""

  if cmd == "add" then
    -- Manual council: /nordlc add [item-link]
    if not NLC.active then
      NLC.Utils.Print("Addon er ikke aktivert. Bruk /nordlc activate forst.")
      return
    end
    if not NLC.isOfficer then
      NLC.Utils.Print("Kun officers kan starte council.")
      return
    end
    -- arg contains the item link (preserved case)
    local itemLink = arg:match("|c.-|h.-|h|r")
    if not itemLink then
      NLC.Utils.Print("Bruk: /nordlc add [shift-klikk item her]")
      return
    end
    local _, _, _, ilvl, _, _, _, _, equipLoc = C_Item.GetItemInfo(itemLink)
    local itemId = C_Item.GetItemInfoInstant(itemLink)
    NLC.Council.StartSession(itemLink, itemId or 0, ilvl or 0, equipLoc or "", "Manuelt")
    return

  elseif cmd == "activate" then
    NLC.Activate()
  elseif cmd == "deactivate" then
    NLC.Deactivate()
  elseif cmd == "pending" then
    if #NLC.pendingSessions > 0 then
      for i, session in ipairs(NLC.pendingSessions) do
        NLC.Utils.Print(string.format("  %d. %s (%s) — %d interesse(r)", i, session.itemLink or "?", session.boss or "?", NLC.Utils.TableCount(session.interests)))
      end
      NLC.Utils.Print("Bruk /nordlc resume <nummer> for a gjenoppta.")
    else
      NLC.Utils.Print("Ingen ventende items.")
    end
  elseif cmd == "resume" then
    local idx = tonumber(arg)
    if idx then
      NLC.Council.ResumePending(idx)
    else
      NLC.Utils.Print("Bruk: /nordlc resume <nummer>")
    end
  elseif cmd == "import" then
    if NordavindLC_Import and NordavindLC_Import.players then
      NLC.db.importData = NordavindLC_Import
      NLC.Utils.Print("Import oppdatert: " .. NLC.Utils.TableCount(NLC.db.importData.players) .. " spillere")
    else
      NLC.Utils.Print("Ingen import-data funnet. Kjor companion-appen forst.")
    end
  elseif cmd == "status" then
    NLC.Utils.Print(NLC.active and "Aktiv" or "Inaktiv")
    NLC.Utils.Print("Officer: " .. (NLC.isOfficer and "Ja" or "Nei"))
    NLC.Utils.Print("Import: " .. NLC.Utils.TableCount(NLC.db.importData.players or {}) .. " spillere")
    NLC.Utils.Print("Ventende: " .. #NLC.pendingSessions .. " items")
    NLC.Utils.Print("Eksport-ko: " .. #(NLC.db.pendingExport or {}) .. " awards")
  else
    NLC.Utils.Print("Kommandoer:")
    NLC.Utils.Print("  /nordlc activate — Aktiver addon")
    NLC.Utils.Print("  /nordlc deactivate — Deaktiver addon")
    NLC.Utils.Print("  /nordlc add [item] — Start council for et item (shift-klikk)")
    NLC.Utils.Print("  /nordlc pending — Vis ventende items")
    NLC.Utils.Print("  /nordlc resume <nr> — Gjenoppta ventende item")
    NLC.Utils.Print("  /nordlc import — Last inn import-data")
    NLC.Utils.Print("  /nordlc status — Vis status")
  end
end

-- Namespaces initialized in Utils.lua
