local ADDON, ns = ...

local Const, L, Skin = ns.Const, ns.L, ns.Skin

local Banner = {}

local DEFAULT_POINT, DEFAULT_X, DEFAULT_Y = "TOP", 0, -150
local FADE_SECONDS = 1
local PADDING = 10
local WIDTH, HEIGHT = 520, 70
local FADE_EDGE = 62 -- width of the band's fading ends
local LINE_INSET = 42 -- the gold lines start this far from the ends
local SIDE = 48 -- icon and text keep this distance from the ends
local ICON_SIZE, GLOW_SIZE = 40, 64
local INTRO_SECONDS, INTRO_RISE = 0.2, 12
local BG_ALPHA = 0.9
local MAX_LINES = 2 -- longer text is cut off inside the banner instead of spilling out
local DETAIL_GAP, DETAIL_PADDING = 4, 14 -- reason line: gap below the text, room above and below both

local frame, fade, intro
local locked = true
local generation = 0 -- invalidates pending hide timers when a newer banner appears

local function saved()
  local db = GrudgeForeverDB
  return db and db.settings and db.settings.banner
end

-- `lift` raises the banner for the intro slide-in; the saved position itself is never changed.
local function applyPosition(lift)
  local pos = saved()
  lift = lift or 0
  frame:ClearAllPoints()
  if pos and pos.point then
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, (pos.y or 0) + lift)
  else
    frame:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, DEFAULT_X, DEFAULT_Y + lift)
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

local rgba = Skin.RGBA

-- Gold hairline along one edge: two halves fading in from the ends toward the center.
local function createLine(edge)
  local gold = Skin.COLORS.gold
  local left = frame:CreateTexture(nil, "ARTWORK")
  left:SetPoint(edge .. "LEFT", frame, edge .. "LEFT", LINE_INSET, 0)
  left:SetPoint(edge .. "RIGHT", frame, edge, 0, 0)
  left:SetHeight(1)
  Skin.Gradient(left, "HORIZONTAL", rgba(gold, 0), rgba(gold, 1))
  local right = frame:CreateTexture(nil, "ARTWORK")
  right:SetPoint(edge .. "LEFT", frame, edge, 0, 0)
  right:SetPoint(edge .. "RIGHT", frame, edge .. "RIGHT", -LINE_INSET, 0)
  right:SetHeight(1)
  Skin.Gradient(right, "HORIZONTAL", rgba(gold, 1), rgba(gold, 0))
  return left, right
end

local function bannerFont()
  if _G.GameFontNormalHuge then return "GameFontNormalHuge" end
  return Skin.Font("GameFontNormalLarge")
end

local function create()
  frame = CreateFrame("Frame", "GrudgeForeverBanner", UIParent)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if locked then return end
    intro:Stop()
    applyPosition()
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)

  local black = { r = 0, g = 0, b = 0, a = 1 }
  frame.bgLeft = frame:CreateTexture(nil, "BACKGROUND")
  frame.bgLeft:SetPoint("TOPLEFT")
  frame.bgLeft:SetPoint("BOTTOMLEFT")
  frame.bgLeft:SetWidth(FADE_EDGE)
  Skin.Gradient(frame.bgLeft, "HORIZONTAL", rgba(black, 0), rgba(black, BG_ALPHA))

  frame.bgRight = frame:CreateTexture(nil, "BACKGROUND")
  frame.bgRight:SetPoint("TOPRIGHT")
  frame.bgRight:SetPoint("BOTTOMRIGHT")
  frame.bgRight:SetWidth(FADE_EDGE)
  Skin.Gradient(frame.bgRight, "HORIZONTAL", rgba(black, BG_ALPHA), rgba(black, 0))

  frame.bgCenter = frame:CreateTexture(nil, "BACKGROUND")
  frame.bgCenter:SetPoint("TOPLEFT", frame.bgLeft, "TOPRIGHT")
  frame.bgCenter:SetPoint("BOTTOMRIGHT", frame.bgRight, "BOTTOMLEFT")
  frame.bgCenter:SetColorTexture(0, 0, 0, BG_ALPHA)

  frame.lineTopLeft, frame.lineTopRight = createLine("TOP")
  frame.lineBottomLeft, frame.lineBottomRight = createLine("BOTTOM")

  frame.iconGlow = frame:CreateTexture(nil, "BORDER")
  frame.iconGlow:SetSize(GLOW_SIZE, GLOW_SIZE)
  frame.iconGlow:SetPoint("CENTER", frame, "LEFT", SIDE + ICON_SIZE / 2, 0)
  frame.iconGlow:SetBlendMode("ADD")
  frame.iconGlow:SetAlpha(0.35)

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetSize(ICON_SIZE, ICON_SIZE)
  frame.icon:SetPoint("LEFT", SIDE, 0)

  local text = Skin.COLORS.text
  frame.text = frame:CreateFontString(nil, "OVERLAY", bannerFont())
  frame.text:SetTextColor(text.r, text.g, text.b, 1)
  frame.text:SetJustifyH("LEFT")
  frame.text:SetWordWrap(true)
  frame.text:SetMaxLines(MAX_LINES)

  -- the reason line below the text (only when the alert text has a reason)
  frame.detail = frame:CreateFontString(nil, "OVERLAY", Skin.Font("GameFontHighlight"))
  frame.detail:SetTextColor(text.r, text.g, text.b, 1)
  frame.detail:SetJustifyH("LEFT")
  frame.detail:SetWordWrap(true)
  frame.detail:SetMaxLines(MAX_LINES)
  frame.detail:Hide()

  -- Slides in from INTRO_RISE above while fading in; display() lifts the anchor, OnFinished restores it.
  intro = frame:CreateAnimationGroup()
  local introAlpha = intro:CreateAnimation("Alpha")
  introAlpha:SetFromAlpha(0)
  introAlpha:SetToAlpha(1)
  introAlpha:SetDuration(INTRO_SECONDS)
  local slide = intro:CreateAnimation("Translation")
  slide:SetOffset(0, -INTRO_RISE)
  slide:SetDuration(INTRO_SECONDS)
  intro:SetScript("OnFinished", function() applyPosition() end)
  intro:SetScript("OnStop", function() applyPosition() end) -- display() re-lifts right after its own Stop

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

local function stringHeight(fs)
  local h = fs:GetStringHeight()
  return type(h) == "number" and h or 0
end

-- The text starts right of the icon, or at the banner's left edge when there is none. With a reason
-- line, both sit at the top and the banner grows to fit them; without one, the text is centered.
local function layoutText(withIcon, detail)
  local t, d = frame.text, frame.detail
  t:ClearAllPoints()
  d:ClearAllPoints()
  local x = withIcon and (SIDE + ICON_SIZE + PADDING) or SIDE
  if not detail then
    if withIcon then
      t:SetPoint("LEFT", frame.icon, "RIGHT", PADDING, 0)
    else
      t:SetPoint("LEFT", SIDE, 0)
    end
    t:SetPoint("RIGHT", -SIDE, 0)
    d:Hide()
    frame:SetHeight(HEIGHT)
    return
  end
  t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -DETAIL_PADDING)
  t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -DETAIL_PADDING)
  d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -DETAIL_GAP)
  d:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, -DETAIL_GAP)
  d:Show()
  local needed = DETAIL_PADDING * 2 + stringHeight(t) + DETAIL_GAP + stringHeight(d)
  frame:SetHeight(math.max(HEIGHT, needed))
end

local function display(iconPath, text, detail)
  if not frame then create() end
  generation = generation + 1
  local mine = generation
  fade:Stop()
  intro:Stop()
  frame:SetAlpha(1)
  local withIcon = iconPath ~= nil and iconPath ~= ""
  if withIcon then
    frame.icon:SetTexture(iconPath)
    frame.icon:Show()
    frame.iconGlow:SetTexture(iconPath)
    frame.iconGlow:Show()
  else
    frame.icon:Hide()
    frame.iconGlow:Hide()
  end
  if detail == "" then detail = nil end
  frame.text:SetText(text or "")
  frame.detail:SetText(detail or "")
  layoutText(withIcon, detail)
  applyPosition(INTRO_RISE)
  frame:Show()
  intro:Play()
  if not locked then return end -- the placeholder stays until the banner is locked again
  C_Timer.After(Const.BANNER_SECONDS, function()
    if mine == generation and locked then fade:Play() end
  end)
end

-- detail: the reason line shown below the text (optional).
function Banner.Show(iconPath, text, detail)
  if not CreateFrame then return end
  display(iconPath, text, detail)
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
    intro:Stop()
    frame:Hide()
    applyPosition()
  else
    display(Banner.ICON_PLACEHOLDER, L["BANNER_PLACEHOLDER"])
  end
end

function Banner.ResetPosition()
  local db = GrudgeForeverDB
  if db and db.settings then db.settings.banner = nil end
  if frame then
    intro:Stop()
    applyPosition()
  end
end

Banner.ICON_PLACEHOLDER = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"

ns.Banner = Banner
