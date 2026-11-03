local ADDON, ns = ...

local Const, L = ns.Const, ns.L

local Banner = {}

local DEFAULT_POINT, DEFAULT_X, DEFAULT_Y = "TOP", 0, -150
local FADE_SECONDS = 1

local frame, fade
local locked = true
local generation = 0 -- invalidates pending hide timers when a newer banner appears

local function saved()
  local db = GrudgeForeverDB
  return db and db.settings and db.settings.banner
end

local function applyPosition()
  local pos = saved()
  frame:ClearAllPoints()
  if pos and pos.point then
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
  else
    frame:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, DEFAULT_X, DEFAULT_Y)
  end
end

-- Stores the dragged position relative to the screen center, independent of the anchor the client chose.
local function savePosition()
  local cx, cy = frame:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not (cx and ux) then return end
  GrudgeForeverDB = GrudgeForeverDB or {}
  GrudgeForeverDB.settings = GrudgeForeverDB.settings or {}
  GrudgeForeverDB.settings.banner = { point = "CENTER", x = cx - ux, y = cy - uy }
  applyPosition()
end

local function create()
  frame = CreateFrame("Frame", "GrudgeForeverBanner", UIParent)
  frame:SetSize(460, 64)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not locked then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)

  frame.background = frame:CreateTexture(nil, "BACKGROUND")
  frame.background:SetAllPoints()
  frame.background:SetColorTexture(0, 0, 0, 0.6)

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetSize(44, 44)
  frame.icon:SetPoint("LEFT", 10, 0)

  frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0)
  frame.text:SetPoint("RIGHT", -10, 0)
  frame.text:SetJustifyH("LEFT")

  fade = frame:CreateAnimationGroup()
  local alpha = fade:CreateAnimation("Alpha")
  alpha:SetFromAlpha(1)
  alpha:SetToAlpha(0)
  alpha:SetDuration(FADE_SECONDS)
  fade:SetScript("OnFinished", function() frame:Hide() end)

  frame:EnableMouse(not locked)
  frame:Hide()
  applyPosition()
end

local function display(iconPath, text)
  if not frame then create() end
  generation = generation + 1
  local mine = generation
  fade:Stop()
  frame:SetAlpha(1)
  if iconPath then
    frame.icon:SetTexture(iconPath)
    frame.icon:Show()
  else
    frame.icon:Hide()
  end
  frame.text:SetText(text or "")
  frame:Show()
  if not locked then return end -- the placeholder stays until the banner is locked again
  C_Timer.After(Const.BANNER_SECONDS, function()
    if mine == generation and locked then fade:Play() end
  end)
end

function Banner.Show(iconPath, text)
  if not CreateFrame then return end
  display(iconPath, text)
end

-- Unlocked: show a draggable placeholder. Locked: hide it again.
function Banner.SetLocked(value)
  locked = value and true or false
  if not CreateFrame or (locked and not frame) then return end
  if not frame then create() end
  frame:EnableMouse(not locked)
  if locked then
    generation = generation + 1
    fade:Stop()
    frame:Hide()
  else
    display(Banner.ICON_PLACEHOLDER, L["BANNER_PLACEHOLDER"])
  end
end

function Banner.ResetPosition()
  local db = GrudgeForeverDB
  if db and db.settings then db.settings.banner = nil end
  if frame then applyPosition() end
end

Banner.ICON_PLACEHOLDER = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"

ns.Banner = Banner
