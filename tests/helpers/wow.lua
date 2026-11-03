-- Test helper that emulates the slice of the WoW client the addon uses.
--
--   local wow = require("tests.helpers.wow")
--   before_each(function() wow.reset(); ns = wow.newNs(); wow.load(ns, "Core/Names.lua") end)
--
-- Tests run from the repo root, so addon paths are repo-relative.
-- Extending: add the stub to wow.reset(), list its global name in GLOBALS
-- (so reset() can clear it) and in .luacheckrc (tests/** globals + read_globals).
local wow = {}

local ADDON = "GrudgeForever"

-- Every global the helper may install; reset() clears all of them first.
local GLOBALS = {
  "issecretvalue", "UnitExists", "UnitIsPlayer", "UnitName", "UnitFactionGroup",
  "GetLocale", "GetServerTime", "C_Timer", "C_ChatInfo", "IsInGuild", "LibStub",
  "GrudgeForeverDB",
}

-- Libraries that run as plain Lua, loaded through the real LibStub.
local LIB_FILES = {
  "Libs/LibStub/LibStub.lua",
  "Libs/AceSerializer-3.0/AceSerializer-3.0.lua",
  "Libs/LibDeflate/LibDeflate.lua",
}

-- Addon files every namespace starts with (order matters: L before locale overrides).
local BASE_FILES = {
  "Locales/enUS.lua",
  "Locales/deDE.lua",
  "Core/Const.lua",
}

local SECRET = {}

local function runFile(path, ...)
  local chunk, err = loadfile(path)
  if not chunk then error(err, 3) end
  return chunk(...)
end

-- Creates a value that the issecretvalue stub reports as secret.
function wow.secret(value)
  return setmetatable({ value = value }, SECRET)
end

local function isSecret(v)
  return getmetatable(v) == SECRET
end

function wow.reset()
  for _, name in ipairs(GLOBALS) do _G[name] = nil end

  -- Controllable state ---------------------------------------------------
  wow.locale = "enUS"
  wow.now = 1700000000      -- value returned by GetServerTime
  wow.inGuild = false
  -- unit token -> { name=, surname=, player=true, faction="Alliance", secret=false }
  wow.units = {}
  wow.timers = {}           -- pending C_Timer.After calls: { delay=, fn= }
  wow.prefixes = {}         -- registered addon message prefixes
  wow.sent = {}             -- C_ChatInfo.SendAddonMessage calls: { prefix=, text=, channel=, target= }

  -- Stubs ----------------------------------------------------------------
  _G.issecretvalue = isSecret

  _G.UnitExists = function(unit) return wow.units[unit] ~= nil end
  _G.UnitIsPlayer = function(unit)
    local u = wow.units[unit]
    return u ~= nil and u.player == true
  end
  _G.UnitName = function(unit)
    local u = wow.units[unit]
    if not u then return nil, nil end
    if u.secret then
      return wow.secret(u.name), u.surname and wow.secret(u.surname) or nil
    end
    return u.name, u.surname
  end
  _G.UnitFactionGroup = function(unit)
    local u = wow.units[unit]
    if not u or not u.faction then return nil, nil end
    return u.faction, u.faction
  end

  _G.GetLocale = function() return wow.locale end
  _G.GetServerTime = function() return wow.now end
  _G.IsInGuild = function() return wow.inGuild end

  _G.C_Timer = {
    After = function(delay, fn) table.insert(wow.timers, { delay = delay, fn = fn }) end,
  }
  _G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix)
      table.insert(wow.prefixes, prefix)
      return true
    end,
    SendAddonMessage = function(prefix, text, channel, target)
      table.insert(wow.sent, { prefix = prefix, text = text, channel = channel, target = target })
      return 0
    end,
  }

  -- Real libraries via a fresh LibStub.
  for _, path in ipairs(LIB_FILES) do runFile(path) end
end

-- Runs and clears all pending C_Timer.After callbacks (one generation).
function wow.runTimers()
  local pending = wow.timers
  wow.timers = {}
  for _, timer in ipairs(pending) do timer.fn() end
end

-- Loads addon files into ns exactly as the client does: chunk(addonName, ns).
function wow.load(ns, ...)
  for _, path in ipairs({ ... }) do runFile(path, ADDON, ns) end
  return ns
end

-- Fresh namespace with Const and the locales loaded.
function wow.newNs()
  local ns = {}
  wow.load(ns, unpack(BASE_FILES))
  return ns
end

return wow
