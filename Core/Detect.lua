local ADDON, ns = ...

local L, Names = ns.L, ns.Names

-- Maps game events (wired up in Core) onto alerts. Pure logic: every name is
-- checked with Names.IsSecret first; secret values are never compared, stored
-- or concatenated, only reported as "<secret>" in the diagnostic log.
local Detect = {}
local Detector = {}
Detector.__index = Detector

local SECRET = "<secret>"

-- deps = { store, alerts, debug = fn() -> boolean, log = fn(text) }
function Detect.New(deps)
  return setmetatable({ deps = deps }, Detector)
end

local function printable(raw)
  if Names.IsSecret(raw) then return SECRET end
  if raw == nil then return "<nil>" end
  return tostring(raw)
end

local function debugLog(self, event, raw, outcome)
  local deps = self.deps
  if not deps.debug() then return end
  deps.log(L["DEBUG_PREFIX"] .. " " .. event .. ": " .. printable(raw) .. " -> " .. outcome)
end

-- Looks one raw name up on one list and fires an alert when it matches.
local function check(self, event, list, raw, trigger)
  local display = Names.Display(raw)
  if not display then
    debugLog(self, event, raw, "ignored")
    return
  end
  local matches = self.deps.store:Lookup(display, list)
  local found = #matches > 0
  debugLog(self, event, raw, found and "match" or "no match")
  if found then self.deps.alerts:Fire(list, display, matches, trigger) end
end

function Detector:OnWhisper(senderName)
  check(self, "whisper", "friendly", senderName, "whisper")
end

function Detector:OnInvite(inviterName)
  check(self, "invite", "friendly", inviterName, "invite")
end

-- memberNames: array of display names collected by Core (may contain gaps of secret values).
function Detector:OnGroup(memberNames)
  if #memberNames == 0 then
    self.deps.alerts:ResetGroup()
    return
  end
  for _, name in ipairs(memberNames) do
    check(self, "group", "friendly", name, "group")
  end
end

function Detector:OnUnit(unit)
  if not UnitIsPlayer(unit) then return end
  local faction, own = UnitFactionGroup(unit), UnitFactionGroup("player")
  if faction == nil or own == nil or Names.IsSecret(faction) or Names.IsSecret(own) or faction == own then
    return
  end

  local name = Names.FromUnit(unit)
  if name then
    check(self, "unit", "enemy", name, "sight")
    return
  end
  -- Unusable name (secret or empty): log it for diagnosis; printable() hides secret values.
  local first, surname = UnitName(unit)
  debugLog(self, "unit", Names.IsSecret(surname) and surname or first, "ignored")
end

ns.Detect = Detect
