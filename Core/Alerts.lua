local ADDON, ns = ...

local Const, L, Names = ns.Const, ns.L, ns.Names

local Alerts = {}

local MAX_SHOWN = 3

Alerts.ICONS = {
  skull = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
  cross = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
  exclamation = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
}

local SOUND_KITS = { raidwarning = 8959, mapping = 3175 }

local TRIGGER_KEYS = {
  whisper = "TRIGGER_WHISPER",
  invite = "TRIGGER_INVITE",
  group = "TRIGGER_GROUP",
  sight = "TRIGGER_SIGHT",
}

-- Placeholders: English names plus the German aliases used by the German default text.
local ALIASES = { grund = "reason", von = "by", anlass = "trigger" }

function Alerts.Render(template, vars)
  return (template:gsub("{(%w+)}", function(token)
    local key = token:lower()
    local value = vars[ALIASES[key] or key]
    if value == nil then return nil end -- unknown placeholders stay as written
    return tostring(value)
  end))
end

-- Joins distinct non-empty values, at most MAX_SHOWN, followed by " +N" for the rest.
local function joinDistinct(values, separator)
  local seen, distinct = {}, {}
  for _, v in ipairs(values) do
    if v ~= nil and v ~= "" and not seen[v] then
      seen[v] = true
      distinct[#distinct + 1] = v
    end
  end
  local shown = {}
  for i = 1, math.min(#distinct, MAX_SHOWN) do shown[i] = distinct[i] end
  local text = table.concat(shown, separator)
  if #distinct > MAX_SHOWN then text = text .. " +" .. (#distinct - MAX_SHOWN) end
  return text
end

function Alerts.Summarize(matches)
  local reasons, creators = {}, {}
  for _, m in ipairs(matches) do
    if not m.muted then
      reasons[#reasons + 1] = m.entry and m.entry.reason
      creators[#creators + 1] = m.by
    end
  end
  return joinDistinct(reasons, "; "), joinDistinct(creators, ", ")
end

function Alerts.ResolveSound(key)
  if key == nil or key == "" or key == "none" then return nil end
  if SOUND_KITS[key] then return { kind = "kit", id = SOUND_KITS[key] } end
  local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
  local path = lsm and lsm:Fetch("sound", key, true)
  if path then return { kind = "file", path = path } end
  return nil
end

local Alert = {}
Alert.__index = Alert

-- deps = { settings = fn() -> settings, now = fn() -> seconds, out = { banner, chat, sound } }
function Alerts.New(deps)
  return setmetatable({ deps = deps, last = {}, groupSeen = {} }, Alert)
end

function Alert:ResetGroup()
  self.groupSeen = {}
end

local function usable(matches)
  for _, m in ipairs(matches) do
    if not m.muted then return true end
  end
  return false
end

-- Returns true when a warning was shown.
function Alert:Fire(list, displayName, matches, trigger)
  local s = self.deps.settings().lists[list]
  if not s or not s.enabled or not usable(matches) then return false end
  local key = Names.Normalize(displayName)
  if not key then return false end

  local id, now = list .. ":" .. key, self.deps.now()
  local last = self.last[id]
  if last and now - last < (s.cooldown or Const.ALERT_COOLDOWN) then return false end
  if trigger == "group" and self.groupSeen[id] then return false end

  self.last[id] = now
  if trigger == "group" then self.groupSeen[id] = true end

  local reason, by = Alerts.Summarize(matches)
  local text = Alerts.Render((s.text and s.text ~= "") and s.text or L["DEFAULT_TEXT"], {
    name = displayName, reason = reason, by = by, trigger = L[TRIGGER_KEYS[trigger] or trigger],
  })

  local out = self.deps.out
  if s.banner and out.banner then
    out.banner(Alerts.ICONS[s.icon] or s.icon, text)
  end
  if s.chat and out.chat then out.chat(text) end
  if out.sound then
    local resolved = Alerts.ResolveSound(s.sound)
    if resolved then out.sound(resolved) end
  end
  return true
end

ns.Alerts = Alerts
