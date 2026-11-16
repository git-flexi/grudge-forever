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

-- Hyphens and whitespace runs collapse to a single space; nil for nothing left.
local function Clean(name)
  name = Plain(name)
  if not name then return nil end
  name = Trim(name:gsub("[%-%s]+", " "))
  if name == "" then return nil end
  return name
end

-- string.lower/upper only touch ASCII. The uppercase Latin-1 letters À-Þ (UTF-8 \195\128-\195\158, except
-- the multiplication sign \195\151) have their lowercase form à-þ 32 code points higher, in the same lead byte
-- (the division sign \195\183 sits where the multiplication sign's lowercase would be).
local function lowerLatin1(lead, byte)
  local b = byte:byte()
  if b == 151 then return nil end
  return lead .. string.char(b + 32)
end

local function upperLatin1(lead, byte)
  local b = byte:byte()
  if b == 183 then return nil end
  return lead .. string.char(b - 32)
end

local function Lower(s)
  return (s:lower():gsub("(\195)([\128-\158])", lowerLatin1))
end

-- "sPITZ" -> "Spitz": first letter capital, the rest lower case, umlauts included.
local function Capitalize(word)
  word = Lower(word)
  local first, rest = word:match("^(\195[\160-\190])(.*)$")
  if first then return first:gsub("(\195)(.)", upperLatin1) .. rest end
  return word:sub(1, 1):upper() .. word:sub(2)
end

-- Display form: Clean() with every word starting with a capital letter, the way the game writes names.
function Names.Display(name)
  name = Clean(name)
  if not name then return nil end
  return (name:gsub("%S+", Capitalize))
end

-- Matching key: Clean() lower-cased, umlauts and other Latin-1 letters included. Names match whatever
-- their casing.
function Names.Normalize(name)
  name = Clean(name)
  if not name then return nil end
  return Lower(name)
end

-- Text safe to show in a font string or chat frame: "|" starts UI escape codes (colors, links,
-- textures), "||" shows a plain pipe. Doubles every lone pipe and keeps pairs, so remote text cannot
-- inject codes. nil becomes "".
function Names.Escape(text)
  if text == nil then return "" end
  return (tostring(text):gsub("|+", function(run)
    if #run % 2 == 1 then return run .. "|" end
  end))
end

function Names.FromUnit(unit)
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
  local name, surname = UnitName(unit)
  return Names.Join(name, surname)
end

ns.Names = Names
