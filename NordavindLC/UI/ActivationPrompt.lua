-- UI/ActivationPrompt.lua
-- "Vil du bruke NordavindLC?" prompt on login/leader change
-- Choice is saved per instance (map ID) so it only asks once per raid instance.

local NLC = NordavindLC_NS
local T = NLC.Theme

local promptFrame = nil

function NLC.UI.ShowActivationPrompt(instanceKey)
  if promptFrame and promptFrame:IsShown() then return end

  if not promptFrame then
    promptFrame = CreateFrame("Frame", "NordavindLCPrompt", UIParent, "BackdropTemplate")
    promptFrame:SetSize(380, 180)
    promptFrame:SetPoint("CENTER")
    promptFrame:SetMovable(true)
    promptFrame:EnableMouse(true)
    promptFrame:RegisterForDrag("LeftButton")
    promptFrame:SetScript("OnDragStart", promptFrame.StartMoving)
    promptFrame:SetScript("OnDragStop", promptFrame.StopMovingOrSizing)
    promptFrame:SetFrameStrata("DIALOG")
    T.ApplyBackdrop(promptFrame)

    T.CreateTitleBar(promptFrame, "NordavindLC")

    local text = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", 0, -55)
    text:SetText(T.MUTED .. "Vil du bruke NordavindLC\nfor loot council?|r")
    text:SetJustifyH("CENTER")
    text:SetSpacing(6)

    local jaBtn = CreateFrame("Button", nil, promptFrame, "UIPanelButtonTemplate")
    jaBtn:SetSize(140, 34)
    jaBtn:SetPoint("BOTTOMLEFT", 35, 25)
    jaBtn:SetText("Ja")
    jaBtn:SetScript("OnClick", function()
      if promptFrame.instanceKey then
        NLC.db.instanceChoices = NLC.db.instanceChoices or {}
        NLC.db.instanceChoices[promptFrame.instanceKey] = "yes"
      end
      NLC.Activate()
      promptFrame:Hide()
    end)

    local neiBtn = CreateFrame("Button", nil, promptFrame, "UIPanelButtonTemplate")
    neiBtn:SetSize(140, 34)
    neiBtn:SetPoint("BOTTOMRIGHT", -35, 25)
    neiBtn:SetText("Nei")
    neiBtn:SetScript("OnClick", function()
      if promptFrame.instanceKey then
        NLC.db.instanceChoices = NLC.db.instanceChoices or {}
        NLC.db.instanceChoices[promptFrame.instanceKey] = "no"
      end
      promptFrame:Hide()
      NLC.Utils.Print("Deaktivert for denne instansen. Bruk /nordlc activate for a aktivere.")
    end)

    local closeBtn = CreateFrame("Button", nil, promptFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
  end

  promptFrame.instanceKey = instanceKey
  promptFrame:Show()
end
