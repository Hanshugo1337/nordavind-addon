-- Core.lua
-- Main addon initialization, SavedVariables, slash commands

local ADDON_NAME = ...
local NLC = NordavindLC_NS

-- Version from TOC
NLC.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"

-- State
NLC.active = false
NLC.isOfficer = false
NLC.db = {}
NLC.importData = {}
NLC.pendingSessions = {}

local function GetLastWednesdayResetUTC()
  -- Epoch (Jan 1 1970) was Thursday. First Wednesday = Jan 7 1970 = day 6.
  -- EU WoW reset = Wednesday 09:00 UTC
  local FIRST_RESET = 6 * 86400 + 9 * 3600  -- 550800
  local WEEK = 7 * 86400
  local now = time()
  local weeksSince = math.floor((now - FIRST_RESET) / WEEK)
  return FIRST_RESET + weeksSince * WEEK
end

-- Initialize
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PARTY_LEADER_CHANGED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    NordavindLC_DB = NordavindLC_DB or {
      importData = { players = {} },
      lootHistory = {},
      config = { officers = {}, timer = 90 },
      pendingExport = {},
      pendingTrades = {},
      pendingEdits = {},
      weeklyLoot = { resetTimestamp = 0, counts = {} },
    }
    NordavindLC_DB.pendingTrades = NordavindLC_DB.pendingTrades or {}
    NordavindLC_DB.pendingEdits  = NordavindLC_DB.pendingEdits  or {}
    NordavindLC_DB.weeklyLoot    = NordavindLC_DB.weeklyLoot    or { resetTimestamp = 0, counts = {} }
    NLC.db = NordavindLC_DB

    if NordavindLC_Import and NordavindLC_Import.players then
      NLC.db.importData = NLC.Utils.DeepCopy(NordavindLC_Import)
      NLC.Utils.Print("Import data loaded (" .. NLC.Utils.TableCount(NLC.db.importData.players) .. " players)")
    end

    -- Always register comms so we can receive ACTIVATE from leader
    NLC.Comms.Register()
    NLC.Utils.Print("Loaded. Use /nordlc for commands.")

  elseif event == "PLAYER_ENTERING_WORLD" or event == "PARTY_LEADER_CHANGED" then
    if IsInRaid() and not NLC.active then
      C_Timer.After(2, function()
        if IsInRaid() and not NLC.active then
          if UnitIsGroupLeader("player") then
            NLC.UI.ShowActivationPrompt()
          else
            -- Raider: poll for activation every 5s until activated (max 60s)
            NLC.Comms.Send("ACTIVATE_CHECK", "")
            if NLC._activateTicker then NLC._activateTicker:Cancel() end
            NLC._activateTicker = C_Timer.NewTicker(5, function(ticker)
              if NLC.active or not IsInRaid() then
                ticker:Cancel()
                NLC._activateTicker = nil
                return
              end
              NLC.Comms.Send("ACTIVATE_CHECK", "")
            end, 12)
          end
        end
      end)
    end
    -- Deactivate when leaving raid
    if not IsInRaid() and NLC.active then
      NLC.Deactivate()
      NLC.Utils.Print("Deaktivert (forlot raid).")
    end
    -- Weekly loot reset check (Wednesday 09:00 UTC)
    local lastReset = GetLastWednesdayResetUTC()
    if NLC.db.weeklyLoot.resetTimestamp < lastReset then
      NLC.db.weeklyLoot.counts = {}
      NLC.db.weeklyLoot.resetTimestamp = lastReset
      NLC.Utils.Print("Ukentlig loot-teller nullstilt.")
    end

  elseif event == "GROUP_ROSTER_UPDATE" then
    -- Deactivate when no longer in raid
    if not IsInRaid() and NLC.active then
      NLC.Deactivate()
      NLC.Utils.Print("Deaktivert (forlot raid).")
    end
    -- Leader re-broadcasts ACTIVATE when roster changes (new players joining)
    if NLC.active and IsInRaid() and UnitIsGroupLeader("player") then
      NLC.Comms.Send("ACTIVATE", "")
    end

  elseif event == "PLAYER_LOGOUT" then
    NordavindLC_DB = NLC.db
    -- NordavindLC_Import is managed solely by the companion app
    -- Don't write back in-session modifications (lootThisWeek etc)
  end
end)


function NLC.CheckOfficer()
  -- Raid leader always gets officer access
  if UnitIsGroupLeader("player") then NLC.isOfficer = true; return true end
  local name = UnitName("player")
  for _, officer in ipairs(NLC.db.config.officers or {}) do
    if officer == name then NLC.isOfficer = true; return true end
  end
  local _, _, rankIndex = GetGuildInfo("player")
  if rankIndex and rankIndex <= 2 then NLC.isOfficer = true; return true end
  NLC.isOfficer = false
  return false
end

-- AddonCompartment handles the minimap icon via TOC fields

-- AddonCompartment (minimap addon menu) handlers
function NordavindLC_OnAddonCompartmentClick(_, button)
  if button == "LeftButton" then
    if #NLC.pendingSessions > 0 then
      SlashCmdList["NORDLC"]("pending")
    else
      SlashCmdList["NORDLC"]("status")
    end
  elseif button == "RightButton" then
    if NLC.active then
      NLC.Deactivate()
    else
      NLC.Activate()
    end
  end
end

function NordavindLC_OnAddonCompartmentEnter(_, menuButtonFrame)
  GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
  GameTooltip:AddLine("NordavindLC", 0, 0.8, 1)
  GameTooltip:AddLine(NLC.active and "|cff00ff00Active|r" or "|cffff0000Inactive|r", 1, 1, 1)
  if NLC.isOfficer then
    GameTooltip:AddLine("Officer mode", 0.5, 1, 0.5)
  end
  local pending = #NLC.pendingSessions
  if pending > 0 then
    GameTooltip:AddLine(pending .. " pending items", 1, 0.8, 0)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Left-click: Status / Pending", 0.6, 0.6, 0.6)
  GameTooltip:AddLine("Right-click: Activate/Deactivate", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

function NordavindLC_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end

function NLC.UpdateMinimapCount()
  -- No-op: compartment doesn't support dynamic count display
end

function NLC.Activate()
  NLC.active = true
  NLC.CheckOfficer()
  NLC.Comms.Register()
  NLC.LootDetection.Register()
  NLC.Utils.Print("Activated! " .. (NLC.isOfficer and "(Officer mode)" or "(Raider mode)"))
end

function NLC.Deactivate()
  NLC.active = false
  NLC.LootDetection.Unregister()
  NLC.Utils.Print("Deactivated.")
end

function NLC.RecordAward(item, awardedTo, awardedBy, boss, category, itemId)
  local entry = {
    item = item,
    awardedTo = awardedTo,
    awardedBy = awardedBy,
    boss = boss or "Unknown",
    category = category or "upgrade",
    timestamp = time(),
  }
  table.insert(NLC.db.lootHistory, entry)
  table.insert(NLC.db.pendingExport, entry)

  -- Add to pending trades
  local id = itemId or C_Item.GetItemInfoInstant(item)
  NLC.Trade.Add(item, id, awardedTo, awardedBy, boss, category)
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
      NLC.Utils.Print("Addon is not active. Use /nordlc activate first.")
      return
    end
    if not NLC.isOfficer then
      NLC.Utils.Print("Only officers can start council.")
      return
    end
    -- arg contains one or more item links (preserved case)
    local items = {}
    for itemLink in arg:gmatch("|c.-|h.-|h|r") do
      local _, _, _, ilvl, _, _, _, _, equipLoc = C_Item.GetItemInfo(itemLink)
      local itemId = C_Item.GetItemInfoInstant(itemLink)
      table.insert(items, {
        itemLink = itemLink,
        itemId = itemId or 0,
        ilvl = ilvl or 0,
        equipLoc = equipLoc or "",
        boss = "Manuelt",
      })
    end
    if #items == 0 then
      NLC.Utils.Print("Usage: /nordlc add [shift-click items here]")
      return
    end
    NLC.Council.StartMultiSession(items, "Manuelt")
    return

  elseif cmd == "activate" then
    NLC.Activate()
  elseif cmd == "deactivate" then
    NLC.Deactivate()
  elseif cmd == "pending" then
    if #NLC.pendingSessions > 0 then
      for i, session in ipairs(NLC.pendingSessions) do
        NLC.Utils.Print(string.format("  %d. %s (%s) — %d interest(s)", i, session.itemLink or "?", session.boss or "?", NLC.Utils.TableCount(session.interests)))
      end
      NLC.Utils.Print("Use /nordlc resume <number> to resume.")
    else
      NLC.Utils.Print("No pending items.")
    end
  elseif cmd == "resume" then
    if arg == "all" then
      NLC.Council.ResumeAll()
    else
      local idx = tonumber(arg)
      if idx then
        NLC.Council.ResumePending(idx)
      else
        NLC.Utils.Print("Usage: /nordlc resume <number> or /nordlc resume all")
      end
    end
  elseif cmd == "history" then
    NLC.UI.ShowHistoryFrame()
  elseif cmd == "trade" then
    NLC.UI.ShowTradeFrame()

  elseif cmd == "import" then
    if NordavindLC_Import and NordavindLC_Import.players then
      NLC.db.importData = NLC.Utils.DeepCopy(NordavindLC_Import)
      NLC.Utils.Print("Import updated: " .. NLC.Utils.TableCount(NLC.db.importData.players) .. " players")
    else
      NLC.Utils.Print("No import data found. Run the companion app first.")
    end
  elseif cmd == "reset" then
    NLC.db.pendingTrades = {}
    NLC.Utils.Print("Pending trades cleared.")
  elseif cmd == "version" then
    if not IsInRaid() then
      NLC.Utils.Print("NordavindLC v" .. NLC.version)
      return
    end
    NLC.Utils.Print("Checking addon versions in raid...")
    NLC.versionCheckResults = {}
    -- Add own version
    local myName = UnitName("player")
    NLC.versionCheckResults[myName] = NLC.version
    NLC.Comms.Send("VERSION_CHECK", "")
    -- Collect replies for 3 seconds then show results
    C_Timer.After(3, function()
      local raidCount = GetNumGroupMembers()
      local results = NLC.versionCheckResults or {}
      local hasAddon, outdated, noAddon = {}, {}, {}
      for i = 1, raidCount do
        local name = GetRaidRosterInfo(i)
        if name then
          name = name:match("^([^-]+)") or name
          local ver = results[name]
          if ver then
            if ver == NLC.version then
              table.insert(hasAddon, "|cff00ff00" .. name .. "|r (v" .. ver .. ")")
            else
              table.insert(outdated, "|cffff8800" .. name .. "|r (v" .. ver .. " — outdated!)")
            end
          else
            table.insert(noAddon, "|cff888888" .. name .. "|r")
          end
        end
      end
      NLC.Utils.Print("--- Version Check ---")
      if #hasAddon > 0 then
        NLC.Utils.Print("|cff00ff00Current:|r " .. table.concat(hasAddon, ", "))
      end
      if #outdated > 0 then
        NLC.Utils.Print("|cffff8800Outdated:|r " .. table.concat(outdated, ", "))
      end
      if #noAddon > 0 then
        NLC.Utils.Print("|cff888888No addon:|r " .. table.concat(noAddon, ", "))
      end
      NLC.Utils.Print(string.format("Total: %d/%d have addon", #hasAddon + #outdated, raidCount))
      NLC.versionCheckResults = nil
    end)
    return

  elseif cmd == "status" then
    NLC.Utils.Print(NLC.active and "Aktiv" or "Inaktiv")
    NLC.Utils.Print("Officer: " .. (NLC.isOfficer and "Ja" or "Nei"))
    NLC.Utils.Print("Import: " .. NLC.Utils.TableCount(NLC.db.importData.players or {}) .. " spillere")
    NLC.Utils.Print("Ufordelt: " .. #NLC.pendingSessions .. " items")
    NLC.Utils.Print("Pending trades: " .. #(NLC.db.pendingTrades or {}) .. " items")
    NLC.Utils.Print("Export: " .. #(NLC.db.pendingExport or {}) .. " awards")
  elseif cmd == "test" then
    NLC.isOfficer = true
    NLC.active = true

    -- Mock imported scoring data
    NLC.db.importData = NLC.db.importData or {}
    NLC.db.importData.players = NLC.db.importData.players or {}

    if not NLC._testSeeded then
      local testPlayers = {
        { name = "Testwarrior",  class = "WARRIOR",  rank = "raider", attendance = 95, wclParse = 92, defensives = 1.8, baseScore = 38.5 },
        { name = "Testshaman",   class = "SHAMAN",   rank = "raider", attendance = 90, wclParse = 88, defensives = 2.1, baseScore = 36.2 },
        { name = "Testpaladin",  class = "PALADIN",  rank = "raider", attendance = 85, wclParse = 95, defensives = 0.6, baseScore = 32.0 },
        { name = "Testmage",     class = "MAGE",     rank = "trial",  attendance = 70, wclParse = 97, defensives = 0.3, baseScore = 25.8 },
        { name = "Testrogue",    class = "ROGUE",    rank = "backup", attendance = 80, wclParse = 90, defensives = 1.2, baseScore = 30.5 },
      }
      for _, p in ipairs(testPlayers) do
        NLC.db.importData.players[p.name] = {
          attendance = p.attendance, wclParse = p.wclParse, defensives = p.defensives,
          baseScore = p.baseScore, rank = p.rank, lootThisWeek = 0, lootTotal = 2,
          mplusEffort = 10, role = "dps", deathPenalty = 0,
        }
      end
      NLC._testSeeded = true
      NLC.Utils.Print("Mock data created (5 test players)")
    end

    local fakeItems = {
      { itemLink = "|cffa335ee|Hitem:111111::::::::80:::::|h[Void-Touched Chestplate]|h|r", itemId = 111111, ilvl = 639, equipLoc = "INVTYPE_CHEST", boss = "Test Boss" },
      { itemLink = "|cffa335ee|Hitem:222222::::::::80:::::|h[Dreamrift Shoulders]|h|r", itemId = 222222, ilvl = 639, equipLoc = "INVTYPE_SHOULDER", boss = "Test Boss" },
      { itemLink = "|cffa335ee|Hitem:333333::::::::80:::::|h[Quel'Danas Legguards]|h|r", itemId = 333333, ilvl = 636, equipLoc = "INVTYPE_LEGS", boss = "Test Boss" },
    }

    local fakeSessions = {}
    local testInterests = {
      { name = "Testwarrior",  class = "WARRIOR",  cat = "upgrade",  tier = 3 },
      { name = "Testshaman",   class = "SHAMAN",   cat = "upgrade",  tier = 3 },
      { name = "Testpaladin",  class = "PALADIN",  cat = "catalyst", tier = 1 },
      { name = "Testmage",     class = "MAGE",     cat = "tmog",     tier = 1 },
      { name = "Testrogue",    class = "ROGUE",    cat = "tmog",     tier = 2 },
    }

    for _, item in ipairs(fakeItems) do
      local session = {
        itemLink = item.itemLink, itemId = item.itemId, ilvl = item.ilvl,
        equipLoc = item.equipLoc, boss = item.boss,
        timer = 999, interests = {}, phase = "ranking",
      }
      for _, p in ipairs(testInterests) do
        session.interests[p.name] = {
          category = p.cat, equippedIlvl = 626, tierCount = p.tier, class = p.class,
        }
      end
      session.ranked = NLC.Council.BuildRanking(session)
      table.insert(fakeSessions, session)
    end

    NLC.UI.ShowWizard(fakeSessions, 1)
    NLC.Utils.Print("Test wizard shown with " .. #fakeSessions .. " items. Click Award to test auto-advance.")

  elseif cmd == "testpopup" then
    local fakeItems = {
      { itemLink = "|cffa335ee|Hitem:111111::::::::80:::::|h[Void-Touched Chestplate]|h|r", itemId = 111111, ilvl = 639, equipLoc = "INVTYPE_CHEST", boss = "Test Boss" },
      { itemLink = "|cffa335ee|Hitem:222222::::::::80:::::|h[Dreamrift Shoulders]|h|r", itemId = 222222, ilvl = 639, equipLoc = "INVTYPE_SHOULDER", boss = "Test Boss" },
    }
    NLC.UI.ShowMultiItemPopup(fakeItems, 30)
    NLC.Utils.Print("Test multi-item popup shown.")

  elseif cmd == "testloot" then
    NLC.isOfficer = true
    NLC.active = true
    -- Simulate boss loot drop with multiple items
    local fakeItems = {
      { itemLink = "|cffa335ee|Hitem:111111::::::::80:::::|h[Void-Touched Chestplate]|h|r", itemId = 111111, ilvl = 639, equipLoc = "INVTYPE_CHEST", boss = "Test Boss", looter = "Player1" },
      { itemLink = "|cffa335ee|Hitem:222222::::::::80:::::|h[Dreamrift Shoulders]|h|r", itemId = 222222, ilvl = 639, equipLoc = "INVTYPE_SHOULDER", boss = "Test Boss", looter = "Player2" },
      { itemLink = "|cffa335ee|Hitem:333333::::::::80:::::|h[Quel'Danas Legguards]|h|r", itemId = 333333, ilvl = 636, equipLoc = "INVTYPE_LEGS", boss = "Test Boss", looter = "Player3" },
      { itemLink = "|cffa335ee|Hitem:444444::::::::80:::::|h[Voidspire Trinket]|h|r", itemId = 444444, ilvl = 639, equipLoc = "INVTYPE_TRINKET", boss = "Test Boss", looter = "Player1" },
    }
    NLC.UI.ShowLootDetected(fakeItems)
    NLC.Utils.Print("Test loot panel shown with 4 items. Remove unwanted items, then click Start Council.")

  elseif cmd == "testend" then
    -- Clean up test mode
    if NLC.Council._origAward then
      NLC.Council.Award = NLC.Council._origAward
      NLC.Council._origAward = nil
    end
    NLC._testSeeded = nil
    NLC.Council._testSession = nil
    NLC.Utils.Print("Test mode ended.")

  else
    NLC.Utils.Print("Commands:")
    NLC.Utils.Print("  /nordlc activate — Aktiver addon")
    NLC.Utils.Print("  /nordlc deactivate — Deaktiver addon")
    NLC.Utils.Print("  /nordlc add [item] — Start council (shift-klikk items)")
    NLC.Utils.Print("  /nordlc history — Vis award historikk")
  NLC.Utils.Print("  /nordlc trade — Vis items som venter på trade")
    NLC.Utils.Print("  /nordlc pending — Vis ufordelte items")
    NLC.Utils.Print("  /nordlc resume <nr> — Gjenoppta ufordelt item")
    NLC.Utils.Print("  /nordlc resume all — Gjenoppta alle")
    NLC.Utils.Print("  /nordlc import — Last inn import data")
    NLC.Utils.Print("  /nordlc reset — Nullstill pending trades")
    NLC.Utils.Print("  /nordlc status — Vis status")
  end
end

-- Namespaces initialized in Utils.lua
