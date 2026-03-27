-- UI/ActivationPrompt.lua
-- "Vil du bruke NordavindLC?" prompt on login/leader change

local NLC = NordavindLC_NS

local promptFrame = nil

function NLC.UI.ShowActivationPrompt()
  if promptFrame and promptFrame:IsShown() then return end

  if not promptFrame then
    promptFrame = CreateFrame("Frame", "NordavindLCPrompt", UIParent, "BasicFrameTemplateWithInset")
    promptFrame:SetSize(360, 170)
    promptFrame:SetPoint("CENTER")
    promptFrame:SetMovable(true)
    promptFrame:EnableMouse(true)
    promptFrame:RegisterForDrag("LeftButton")
    promptFrame:SetScript("OnDragStart", promptFrame.StartMoving)
    promptFrame:SetScript("OnDragStop", promptFrame.StopMovingOrSizing)
    promptFrame:SetFrameStrata("DIALOG")
    promptFrame.TitleBg:SetHeight(30)
    promptFrame.title = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    promptFrame.title:SetPoint("TOP", 0, -8)
    promptFrame.title:SetText("NordavindLC")

    local text = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", 0, -50)
    text:SetText("Vil du bruke NordavindLC\nfor loot council?")
    text:SetJustifyH("CENTER")
    text:SetSpacing(4)

    local jaBtn = CreateFrame("Button", nil, promptFrame, "GameMenuButtonTemplate")
    jaBtn:SetSize(130, 32)
    jaBtn:SetPoint("BOTTOMLEFT", 30, 20)
    jaBtn:SetText("Ja")
    jaBtn:SetScript("OnClick", function()
      NLC.Activate()
      promptFrame:Hide()
    end)

    local neiBtn = CreateFrame("Button", nil, promptFrame, "GameMenuButtonTemplate")
    neiBtn:SetSize(130, 32)
    neiBtn:SetPoint("BOTTOMRIGHT", -30, 20)
    neiBtn:SetText("Nei")
    neiBtn:SetScript("OnClick", function()
      promptFrame:Hide()
      NLC.Utils.Print("Deaktivert. Bruk /nordlc activate for a aktivere.")
    end)
  end

  promptFrame:Show()
end
