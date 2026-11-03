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
  "CreateFrame", "UIParent", "GrudgeForeverDB", "TooltipDataProcessor", "Enum", "Menu",
  "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "C_GuildInfo", "GetCVarBool",
  "IsInGroup", "IsInRaid", "GetNumGroupMembers", "PlaySound", "PlaySoundFile", "DEFAULT_CHAT_FRAME",
  "SlashCmdList", "SLASH_GRUDGEFOREVER1", "SLASH_GRUDGEFOREVER2", "date",
  -- installed by wow.installUI() only
  "hooksecurefunc", "securecallfunction", "GetTime", "GetFramerate", "ChatThrottleLib", "C_UIFileAsset",
  "ButtonFrameTemplate_HidePortrait", "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab",
  "CreateScrollBoxListLinearView", "CreateDataProvider", "ScrollUtil", "ScrollBoxConstants",
  "StaticPopupDialogs", "StaticPopup_Show", "UISpecialFrames",
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

-- Secret values are unique strings recorded in a registry: they look like
-- ordinary strings, so only the issecretvalue stub can tell them apart.
local secrets = {}
local secretCount = 0

local function runFile(path, ...)
  local chunk, err = loadfile(path)
  if not chunk then error(err, 3) end
  return chunk(...)
end

-- Creates a string value that the issecretvalue stub reports as secret.
function wow.secret(value)
  secretCount = secretCount + 1
  local str = "<secret#" .. secretCount .. ":" .. tostring(value) .. ">"
  secrets[str] = true
  return str
end

local function isSecret(v)
  return type(v) == "string" and secrets[v] == true
end

function wow.reset()
  for _, name in ipairs(GLOBALS) do _G[name] = nil end

  -- Controllable state ---------------------------------------------------
  wow.locale = "enUS"
  wow.now = 1700000000      -- value returned by GetServerTime
  wow.inGuild = false
  wow.lockdown = false      -- value returned by C_ChatInfo.InChatMessagingLockdown
  -- unit token -> { name=, surname=, player=true, faction="Alliance",
  --                 secret=false (both secret), secretName=false, secretSurname=false }
  wow.units = {}
  wow.timers = {}           -- pending C_Timer.After calls: { delay=, fn= }
  wow.prefixes = {}         -- registered addon message prefixes
  wow.sent = {}             -- C_ChatInfo.SendAddonMessage calls: { prefix=, text=, channel=, target= }
  wow.guildName = nil       -- GetGuildInfo("player"); nil while unknown or not in a guild
  wow.roster = {}           -- GetGuildRosterInfo(i) names
  wow.rosterRequests = 0    -- C_GuildInfo.GuildRoster calls
  wow.cvars = {}            -- GetCVarBool values
  wow.group = nil           -- nil (solo) or { raid = bool, size = n } with units in wow.units
  wow.sounds = {}           -- PlaySound / PlaySoundFile calls: { kit= } or { file= }
  wow.chat = {}             -- DEFAULT_CHAT_FRAME:AddMessage texts
  wow.tickers = {}          -- C_Timer.NewTicker calls: { interval=, fn= }

  -- Stubs ----------------------------------------------------------------
  secrets = {}
  secretCount = 0
  _G.issecretvalue = isSecret

  _G.UnitExists = function(unit) return wow.units[unit] ~= nil end
  _G.UnitIsPlayer = function(unit)
    local u = wow.units[unit]
    return u ~= nil and u.player == true
  end
  _G.UnitName = function(unit)
    local u = wow.units[unit]
    if not u then return nil, nil end
    local name, surname = u.name, u.surname
    if u.secret or u.secretName then name = wow.secret(name) end
    if surname ~= nil and (u.secret or u.secretSurname) then surname = wow.secret(surname) end
    return name, surname
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
    NewTimer = function(delay, fn)
      local timer = { delay = delay, fn = fn }
      table.insert(wow.timers, timer)
      return { Cancel = function() timer.cancelled = true end }
    end,
    NewTicker = function(interval, fn)
      local ticker = { interval = interval, fn = fn }
      table.insert(wow.tickers, ticker)
      return { Cancel = function() ticker.cancelled = true end }
    end,
  }
  _G.C_ChatInfo = {
    InChatMessagingLockdown = function() return wow.lockdown end,
    RegisterAddonMessagePrefix = function(prefix)
      table.insert(wow.prefixes, prefix)
      return true
    end,
    SendAddonMessage = function(prefix, text, channel, target)
      table.insert(wow.sent, { prefix = prefix, text = text, channel = channel, target = target })
      return 0
    end,
  }

  _G.GetGuildInfo = function(unit)
    if unit ~= "player" then return nil end
    return wow.guildName
  end
  _G.GetNumGuildMembers = function() return #wow.roster, #wow.roster end
  _G.GetGuildRosterInfo = function(i) return wow.roster[i] end
  _G.C_GuildInfo = { GuildRoster = function() wow.rosterRequests = wow.rosterRequests + 1 end }
  _G.GetCVarBool = function(name) return wow.cvars[name] == true end

  _G.IsInGroup = function() return wow.group ~= nil end
  _G.IsInRaid = function() return wow.group ~= nil and wow.group.raid == true end
  _G.GetNumGroupMembers = function() return wow.group and wow.group.size or 0 end

  _G.PlaySound = function(kit) table.insert(wow.sounds, { kit = kit }) end
  _G.PlaySoundFile = function(file) table.insert(wow.sounds, { file = file }) end
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) table.insert(wow.chat, text) end }
  _G.SlashCmdList = {}
  _G.date = os.date

  -- Real libraries via a fresh LibStub.
  for _, path in ipairs(LIB_FILES) do runFile(path) end
end

-- Frame stub for loading UI code: every capitalized key of a proxy is itself a callable proxy, so
-- child regions (frame.Inset) and methods (frame:SetPoint()) both work. Calls return a fresh proxy,
-- except for the few methods below that keep state the code reads back.
local proxyMeta = {}

local function newProxy(name)
  return setmetatable({ _state = { name = name, scripts = {}, events = {}, text = "", shown = false } }, proxyMeta)
end

-- Changing visibility runs OnShow / OnHide like the client does.
local function setShown(self, shown)
  if self._state.shown == shown then return end
  self._state.shown = shown
  local fn = self._state.scripts[shown and "OnShow" or "OnHide"]
  if fn then fn(self) end
end

local STATEFUL = {
  SetScript = function(self, script, fn) self._state.scripts[script] = fn end,
  HookScript = function(self, script, fn)
    local prev = self._state.scripts[script]
    self._state.scripts[script] = prev and function(...) prev(...); fn(...) end or fn
  end,
  GetScript = function(self, script) return self._state.scripts[script] end,
  RegisterEvent = function(self, event) self._state.events[event] = true end,
  UnregisterEvent = function(self, event) self._state.events[event] = nil end,
  IsEventRegistered = function(self, event) return self._state.events[event] == true end,
  SetText = function(self, text) self._state.text = text end,
  GetText = function(self) return self._state.text end,
  SetChecked = function(self, v) self._state.checked = v end,
  GetChecked = function(self) return self._state.checked == true end,
  Show = function(self) setShown(self, true) end,
  Hide = function(self) setShown(self, false) end,
  SetShown = function(self, v) setShown(self, v and true or false) end,
  IsShown = function(self) return self._state.shown end,
  IsVisible = function(self) return self._state.shown end,
  GetName = function(self) return self._state.name end,
  SetID = function(self, id) self._state.id = id end,
  GetID = function(self) return self._state.id or 0 end,
  GetCenter = function() return nil end,
}

proxyMeta.__index = function(self, key)
  if STATEFUL[key] then return STATEFUL[key] end
  -- client methods and template children are capitalized; lowercase keys belong to the addon
  if type(key) ~= "string" or not key:find("^%u") then return nil end
  local child = newProxy()
  rawset(self, key, child)
  return child
end
proxyMeta.__call = function() return newProxy() end

function wow.proxy(name)
  return newProxy(name)
end

-- Installs CreateFrame (recording every frame in wow.frames), UIParent and the client helpers
-- the bundled libraries and UI templates use.
function wow.installUI()
  wow.frames = {}
  _G.CreateFrame = function(_, name)
    local frame = newProxy(name)
    table.insert(wow.frames, frame)
    return frame
  end
  _G.UIParent = newProxy("UIParent")
  _G.hooksecurefunc = function() end
  _G.securecallfunction = function(fn, ...) return fn(...) end
  _G.GetTime = function() return wow.now end
  _G.GetFramerate = function() return 60 end
  _G.C_UIFileAsset = { IsKnownFile = function() return true end }
  _G.Enum = _G.Enum or {}
  local function stub() return newProxy() end
  _G.ButtonFrameTemplate_HidePortrait = stub
  _G.PanelTemplates_SetNumTabs = stub
  _G.PanelTemplates_SetTab = stub
  _G.CreateScrollBoxListLinearView = stub
  _G.CreateDataProvider = stub
  _G.ScrollUtil = newProxy()
  _G.ScrollBoxConstants = { RetainScrollPosition = true }
  _G.StaticPopupDialogs = {}
  _G.StaticPopup_Show = stub
  _G.UISpecialFrames = {}
end

-- The recorded frame that registered the event, or nil.
function wow.frameFor(event)
  for _, frame in ipairs(wow.frames or {}) do
    if frame._state.events[event] then return frame end
  end
  return nil
end

-- Calls a recorded script of a stub frame.
function wow.fire(frame, script, ...)
  local fn = frame._state.scripts[script]
  if fn then return fn(frame, ...) end
end

-- Runs and clears all pending C_Timer.After callbacks (one generation).
function wow.runTimers()
  local pending = wow.timers
  wow.timers = {}
  for _, timer in ipairs(pending) do
    if not timer.cancelled then timer.fn() end
  end
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
