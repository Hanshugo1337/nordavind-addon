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
      config = { officers = {}, timer = 90 },
      pendingExport = {},
    }
    NLC.db = NordavindLC_DB

    if NordavindLC_Import and NordavindLC_Import.players then
      NLC.db.importData = NordavindLC_Import
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
            -- Only leader gets the activation prompt
            local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
            local key = tostring(instanceMapID or 0)
            NLC.db.instanceChoices = NLC.db.instanceChoices or {}
            local choice = NLC.db.instanceChoices[key]
            if choice == "yes" then
              NLC.Activate()
              NLC.Comms.Send("ACTIVATE", "")
            elseif choice == "no" then
              -- Already declined for this instance, don't ask again
            else
              NLC.UI.ShowActivationPrompt(key)
            end
          end
          -- Non-leaders activate when they receive ACTIVATE from leader
        end
      end)
    end

  elseif event == "PLAYER_LOGOUT" then
    NordavindLC_DB = NLC.db
    -- Preserve import data so companion app's writes survive logout
    if NLC.db.importData and NLC.db.importData.players and next(NLC.db.importData.players) then
      NordavindLC_Import = NLC.db.importData
    end
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
  icon:SetSize(26, 26)
  icon:SetPoint("CENTER")
  icon:SetTexture("Interface\\AddOns\\NordavindLC\\logo")
  minimapBtn.icon = icon

  -- Circular mask so the icon blends with the minimap
  local mask = minimapBtn:CreateMaskTexture()
  mask:SetSize(26, 26)
  mask:SetPoint("CENTER")
  mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
  icon:AddMaskTexture(mask)

  local border = minimapBtn:CreateTexture(nil, "OVERLAY")
  border:SetSize(52, 52)
  border:SetPoint("CENTER", 0, 0)
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
    GameTooltip:AddLine("Right-click: Deactivate", 0.6, 0.6, 0.6)
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
  NLC.Utils.Print("Activated! " .. (NLC.isOfficer and "(Officer mode)" or "(Raider mode)"))
end

function NLC.Deactivate()
  NLC.active = false
  NLC.LootDetection.Unregister()
  if minimapBtn then minimapBtn:Hide() end
  NLC.Utils.Print("Deactivated.")
end

function NLC.RecordAward(item, awardedTo, awardedBy, boss, category)
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
    -- arg contains the item link (preserved case)
    local itemLink = arg:match("|c.-|h.-|h|r")
    if not itemLink then
      NLC.Utils.Print("Usage: /nordlc add [shift-click item here]")
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
  elseif cmd == "import" then
    if NordavindLC_Import and NordavindLC_Import.players then
      NLC.db.importData = NordavindLC_Import
      NLC.Utils.Print("Import updated: " .. NLC.Utils.TableCount(NLC.db.importData.players) .. " players")
    else
      NLC.Utils.Print("No import data found. Run the companion app first.")
    end
  elseif cmd == "reset" then
    NLC.db.instanceChoices = {}
    NLC.Utils.Print("Instance choices reset. You will be prompted again.")
  elseif cmd == "status" then
    NLC.Utils.Print(NLC.active and "Active" or "Inactive")
    NLC.Utils.Print("Officer: " .. (NLC.isOfficer and "Yes" or "No"))
    NLC.Utils.Print("Import: " .. NLC.Utils.TableCount(NLC.db.importData.players or {}) .. " players")
    NLC.Utils.Print("Pending: " .. #NLC.pendingSessions .. " items")
    NLC.Utils.Print("Export queue: " .. #(NLC.db.pendingExport or {}) .. " awards")
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
      { name = "Testmage",     class = "MAGE",     cat = "catalyst", tier = 1 },
      { name = "Testrogue",    class = "ROGUE",    cat = "upgrade",  tier = 2 },
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
    NLC.Utils.Print("  /nordlc activate — Activate addon")
    NLC.Utils.Print("  /nordlc deactivate — Deactivate addon")
    NLC.Utils.Print("  /nordlc add [item] — Start council for an item (shift-click)")
    NLC.Utils.Print("  /nordlc pending — Show pending items")
    NLC.Utils.Print("  /nordlc resume <nr> — Resume pending item")
    NLC.Utils.Print("  /nordlc resume all — Resume all pending in wizard")
    NLC.Utils.Print("  /nordlc import — Load import data")
    NLC.Utils.Print("  /nordlc reset — Reset instance choices")
    NLC.Utils.Print("  /nordlc test — Test wizard with mock data")
    NLC.Utils.Print("  /nordlc testend — End test mode")
    NLC.Utils.Print("  /nordlc status — Show status")
  end
end

-- Namespaces initialized in Utils.lua
