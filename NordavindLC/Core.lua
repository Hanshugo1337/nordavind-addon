-- Core.lua
-- Main addon initialization, SavedVariables, slash commands

local ADDON_NAME, NLC = ...

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
frame:RegisterEvent("GROUP_LEADER_CHANGED")
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

  elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_LEADER_CHANGED" then
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

function NLC.Activate()
  NLC.active = true
  NLC.CheckOfficer()
  NLC.Comms.Register()
  NLC.LootDetection.Register()
  NLC.Utils.Print("Aktivert! " .. (NLC.isOfficer and "(Officer-modus)" or "(Raider-modus)"))
end

function NLC.Deactivate()
  NLC.active = false
  NLC.LootDetection.Unregister()
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
  local cmd, arg = msg:lower():trim():match("^(%S*)%s*(.*)$")
  if cmd == "activate" then
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
    NLC.Utils.Print("  /nordlc pending — Vis ventende items")
    NLC.Utils.Print("  /nordlc resume <nr> — Gjenoppta ventende item")
    NLC.Utils.Print("  /nordlc import — Last inn import-data")
    NLC.Utils.Print("  /nordlc status — Vis status")
  end
end

-- Namespaces initialized in Utils.lua
