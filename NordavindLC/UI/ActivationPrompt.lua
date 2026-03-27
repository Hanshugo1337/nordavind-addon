-- UI/ActivationPrompt.lua
-- "Vil du bruke NordavindLC?" prompt on login/leader change

local _, NLC = ...

local promptFrame = nil

function NLC.UI.ShowActivationPrompt()
  if promptFrame and promptFrame:IsShown() then return end

  if not promptFrame then
    promptFrame = CreateFrame("Frame", "NordavindLCPrompt", UIParent, "BasicFrameTemplateWithInset")
    promptFrame:SetSize(320, 140)
    promptFrame:SetPoint("CENTER")
    promptFrame:SetMovable(true)
    promptFrame:EnableMouse(true)
    promptFrame:RegisterForDrag("LeftButton")
    promptFrame:SetScript("OnDragStart", promptFrame.StartMoving)
    promptFrame:SetScript("OnDragStop", promptFrame.StopMovingOrSizing)
    promptFrame:SetFrameStrata("DIALOG")
    promptFrame.TitleBg:SetHeight(24)
    promptFrame.title = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    promptFrame.title:SetPoint("TOP", 0, -6)
    promptFrame.title:SetText("NordavindLC")

    local text = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", 0, -35)
    text:SetText("Vil du bruke NordavindLC\nfor loot council?")
    text:SetJustifyH("CENTER")

    local jaBtn = CreateFrame("Button", nil, promptFrame, "GameMenuButtonTemplate")
    jaBtn:SetSize(100, 28)
    jaBtn:SetPoint("BOTTOMLEFT", 30, 15)
    jaBtn:SetText("Ja")
    jaBtn:SetScript("OnClick", function()
      NLC.Activate()
      promptFrame:Hide()
    end)

    local neiBtn = CreateFrame("Button", nil, promptFrame, "GameMenuButtonTemplate")
    neiBtn:SetSize(100, 28)
    neiBtn:SetPoint("BOTTOMRIGHT", -30, 15)
    neiBtn:SetText("Nei")
    neiBtn:SetScript("OnClick", function()
      promptFrame:Hide()
      NLC.Utils.Print("Deaktivert. Bruk /nordlc activate for a aktivere.")
    end)
  end

  promptFrame:Show()
end
