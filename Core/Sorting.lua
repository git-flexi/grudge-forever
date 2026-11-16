local ADDON, ns = ...

-- Column sorting for the main window lists. Pure logic, no WoW APIs.
local Names = ns.Names

local Sorting = {}

-- Newest first is the default on every tab.
Sorting.DEFAULT_PLAYERS = { column = "date", desc = true }
Sorting.DEFAULT_MEMBERS = { column = "seen", desc = true }

-- Columns whose first click sorts newest, highest or true first; text columns start at A.
local FIRST_DESC = { date = true, status = true, online = true, addon = true, version = true, seen = true }

function Sorting.FirstDesc(column)
  return FIRST_DESC[column] == true
end

local function text(v)
  if type(v) ~= "string" or v == "" then return nil end
  return Names.Normalize(v) or v:lower()
end

local function flag(v)
  return v and 1 or 0
end

-- "1.10.0" after "1.9.2": numeric parts are zero-padded so they compare as numbers.
local function version(v)
  if type(v) ~= "string" or v == "" then return nil end
  return (v:lower():gsub("%d+", function(d)
    return #d < 12 and ("0"):rep(12 - #d) .. d or d
  end))
end

-- The newest change of all entries shown for a player.
local function newest(matches)
  local out = 0
  for _, m in ipairs(matches) do out = math.max(out, m.entry.updated or 0) end
  return out
end

-- Value of one column for a player row { key, matches } (first match = the one shown).
local PLAYER_VALUES = {
  name = function(p) return p.key end,
  reason = function(p) return text(p.matches[1].entry.reason) end,
  by = function(p) return text(p.matches[1].by) end,
  date = function(p) return newest(p.matches) end,
  status = function(p) return flag(p.matches[1].muted) end,
}

-- Value of one column for a guild member row (GuildMembers.Build).
local MEMBER_VALUES = {
  name = function(m) return m.key end,
  online = function(m) return flag(m.online) end,
  addon = function(m) return flag(m.hasAddon) end,
  version = function(m) return version(m.version) end,
  seen = function(m) return m.seen end,
}

local function byKey(a, b)
  return a.key < b.key
end

-- The guild tab's natural order: online first, then members with the addon, then by name.
local function memberOrder(a, b)
  if a.online ~= b.online then return a.online == true end
  if a.hasAddon ~= b.hasAddon then return a.hasAddon == true end
  return a.key < b.key
end

-- Sorts rows in place by value(row), reversed for desc. Rows without a value come last either way;
-- ties keep the order of tiebreak, a strict total order (table.sort is not stable).
local function sortBy(rows, value, desc, tiebreak)
  local cache = {}
  for _, r in ipairs(rows) do cache[r] = value(r) end
  table.sort(rows, function(a, b)
    local va, vb = cache[a], cache[b]
    if va ~= vb then
      if va == nil then return false end
      if vb == nil then return true end
      if desc then return va > vb end
      return va < vb
    end
    return tiebreak(a, b)
  end)
  return rows
end

-- players = { { key, matches } ... }; column = a PLAYER_VALUES key, unknown columns sort by name.
function Sorting.SortPlayers(players, column, desc)
  return sortBy(players, PLAYER_VALUES[column] or PLAYER_VALUES.name, desc, byKey)
end

-- rows = GuildMembers.Build rows; column = a MEMBER_VALUES key, unknown columns sort by name.
function Sorting.SortMembers(rows, column, desc)
  return sortBy(rows, MEMBER_VALUES[column] or MEMBER_VALUES.name, desc, memberOrder)
end

ns.Sorting = Sorting
