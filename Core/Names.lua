local ADDON, ns = ...

-- Name handling for the "secret values" client: names read from units may be
-- secret and must never be compared, concatenated or stored.
local Names = {}

local function IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Returns v only if it is a usable (non-secret) string, else nil.
local function Plain(v)
  if type(v) ~= "string" or IsSecret(v) then return nil end
  return v
end

local function Trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Names.IsSecret(v)
  return IsSecret(v)
end

function Names.Join(name, surname)
  name = Plain(name)
  if not name then return nil end
  name = Trim(name)
  if name == "" then return nil end
  -- A secret surname makes the full name unknowable: never fall back to the first name alone.
  if surname ~= nil and IsSecret(surname) then return nil end
  surname = Plain(surname)
  surname = surname and Trim(surname) or ""
  if surname == "" then return name end
  return name .. " " .. surname
end

-- Display form: hyphens and whitespace runs collapse to a single space.
function Names.Display(name)
  name = Plain(name)
  if not name then return nil end
  name = Trim(name:gsub("[%-%s]+", " "))
  if name == "" then return nil end
  return name
end

-- Matching key: Display() lower-cased. string.lower only touches ASCII, so
-- UTF-8 bytes pass through unchanged and umlaut names still match themselves.
function Names.Normalize(name)
  local display = Names.Display(name)
  return display and display:lower() or nil
end

function Names.FromUnit(unit)
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
  local name, surname = UnitName(unit)
  return Names.Join(name, surname)
end

ns.Names = Names
