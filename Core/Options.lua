local ADDON, ns = ...

local Const, L = ns.Const, ns.L

local Options = {}

local SYNC_MODES = { auto = true, manual = true, off = true }
Options.COOLDOWN_MIN, Options.COOLDOWN_MAX = 10, 3600

local function listDefaults(icon)
  return {
    enabled = true, sound = "raidwarning", icon = icon, text = L["DEFAULT_TEXT"],
    banner = true, chat = true, cooldown = Const.ALERT_COOLDOWN,
  }
end

-- Read at call time so the active locale decides the default text.
function Options.Defaults()
  return {
    syncMode = "auto", debug = false, banner = nil,
    lists = { friendly = listDefaults("exclamation"), enemy = listDefaults("skull") },
  }
end

-- Adds missing keys from defaults, never touching existing values (false included).
local function fill(target, defaults)
  for key, value in pairs(defaults) do
    if target[key] == nil or (type(value) == "table" and type(target[key]) ~= "table") then
      target[key] = value
    elseif type(value) == "table" then
      fill(target[key], value)
    end
  end
end

local function fixCooldown(list)
  local c = list.cooldown
  if type(c) ~= "number" or c ~= c or c < Options.COOLDOWN_MIN or c > Options.COOLDOWN_MAX then
    list.cooldown = Const.ALERT_COOLDOWN
  end
end

function Options.Apply(sv)
  sv.settings = sv.settings or {}
  local settings = sv.settings
  fill(settings, Options.Defaults())

  if not SYNC_MODES[settings.syncMode] then settings.syncMode = "auto" end
  for _, list in pairs(settings.lists) do
    if type(list) == "table" then fixCooldown(list) end
  end
  return settings
end

ns.Options = Options
