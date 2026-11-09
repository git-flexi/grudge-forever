local ADDON, ns = ...

-- Minimap button through LibDataBroker + LibDBIcon: left click opens the main window,
-- right click the settings. Shown or hidden per settings.minimap.hide.
local L = ns.L

local MinimapButton = {}

local NAME = "GrudgeForever"
MinimapButton.ICON = "Interface\\AddOns\\GrudgeForever\\Media\\icon"

local settings

-- callbacks = { toggleWindow = fn(), openOptions = fn() }
function MinimapButton.Install(settingsTable, callbacks)
  local broker = LibStub and LibStub("LibDataBroker-1.1", true)
  local icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (broker and icon) then return end
  settings = settingsTable
  local launcher = broker:GetDataObjectByName(NAME) or broker:NewDataObject(NAME, {
    type = "launcher",
    text = NAME,
    icon = MinimapButton.ICON,
    OnClick = function(_, mouseButton)
      if mouseButton == "RightButton" then callbacks.openOptions() else callbacks.toggleWindow() end
    end,
    OnTooltipShow = function(tooltip)
      tooltip:AddLine(L["ADDON_TITLE"])
      tooltip:AddLine(L["MINIMAP_LEFT"])
      tooltip:AddLine(L["MINIMAP_RIGHT"])
    end,
  })
  if not icon:IsRegistered(NAME) then icon:Register(NAME, launcher, settings.minimap) end
end

function MinimapButton.SetShown(shown)
  local icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (icon and settings) then return end
  settings.minimap.hide = not shown
  if shown then icon:Show(NAME) else icon:Hide(NAME) end
end

ns.MinimapButton = MinimapButton
