local ADDON, ns = ...

-- Bootstrap: builds the modules at login, wires game events to them and owns the shared helpers
-- the UI and slash commands use (Print, Change, ManualSync, TestAlert). Last file in the TOC.
local Const, L, Names = ns.Const, ns.L, ns.Names

local Core = { ready = false }

local ROSTER_DEBUG_NAMES = 3
local HELLO_TIMEOUT = 10 -- seconds after login to say hello when no roster update came
local GAME_EVENTS = {
  "CHAT_MSG_WHISPER", "PARTY_INVITE_REQUEST", "GROUP_ROSTER_UPDATE", "NAME_PLATE_UNIT_ADDED",
  "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
  "IGNORELIST_UPDATE",
}

-- The current guild (or none) is known and set in the store. Until then the store holds the guild
-- this character had last time, for lookups only: sync stays off, so nothing about that guild can
-- reach a guild the character may have joined meanwhile.
local guildResolved = false

function Core.Print(text)
  DEFAULT_CHAT_FRAME:AddMessage(L["CHAT_PREFIX"] .. tostring(text))
end

local function refreshWindow()
  local window = ns.UI and ns.UI.MainWindow
  if window and window.Refresh then window.Refresh() end
end

-- Runs fn(store) as a change of the own entries and tells the guild about it. Returns fn's results.
function Core.Change(fn)
  local store = Core.store
  local id = store:GetPlayerId()
  local prevRev = store:GetRev(id)
  local results = { n = 0 }
  local function keep(...)
    results.n = select("#", ...)
    for i = 1, results.n do results[i] = select(i, ...) end
  end
  keep(fn(store))
  if store:GetRev(id) ~= prevRev then Core.sync:OnOwnChange(prevRev) end
  refreshWindow()
  return unpack(results, 1, results.n)
end

-- Whether there is a guild to sync with.
function Core.HasSyncGuild()
  return guildResolved and Core.store:GetCurrentGuild() ~= nil
end

-- "Sync now" from the window or /gf sync; reports the outcome in chat.
function Core.ManualSync()
  if Core.sv.settings.syncMode == "off" then return Core.Print(L["SYNC_OFF"]) end
  if not Core.HasSyncGuild() then return Core.Print(L["SYNC_NO_GUILD"]) end
  local ok, remaining = Core.sync:ManualSync()
  if ok then
    Core.Print(L["SYNC_STARTED"])
  else
    Core.Print(L["SYNC_COOLDOWN"]:format(math.ceil(remaining)))
  end
  refreshWindow()
end

-- Alert outputs ------------------------------------------------------------------

local function playSound(resolved)
  if resolved.kind == "kit" then
    PlaySound(resolved.id, "Master")
  elseif PlaySoundFile then
    PlaySoundFile(resolved.path, "Master")
  end
end

local outputs = { banner = ns.Banner.Show, chat = Core.Print, sound = playSound }

-- Shows a sample warning for a list with its current settings, bypassing the cooldown.
function Core.TestAlert(list)
  local s = Core.sv.settings.lists[list]
  if not s then return end
  local text, chatText = ns.Alerts.Compose(list, s, {
    name = L["TEST_NAME"], reason = L["TEST_REASON"], by = Core.store:GetCurrentChar() or L["TEST_BY"],
    trigger = L[list == Const.LIST_ENEMY and "TRIGGER_SIGHT" or "TRIGGER_WHISPER"],
  })
  if s.banner then outputs.banner(ns.Alerts.ICONS[s.icon] or s.icon, text) end
  if s.chat then outputs.chat(chatText) end
  local sound = ns.Alerts.ResolveSound(s.sound)
  if sound then outputs.sound(sound) end
end

-- Guild ------------------------------------------------------------------------------

-- Returns resolved, guildName. Unresolved while the client knows we are in a guild but has not
-- loaded its name yet (common right at login): setting "no guild" then would drop the guild cache.
local function readGuild()
  local name = GetGuildInfo("player")
  if type(name) == "string" and not Names.IsSecret(name) and name ~= "" then return true, name end
  if not IsInGuild() then return true, nil end
  return false, nil
end

local function updateGuild()
  local resolved, guild = readGuild()
  if not resolved then return end
  local store = Core.store
  if guildResolved and store:GetCurrentGuild() == guild then return end
  Core.char = Core.char or Names.FromUnit("player")
  guildResolved = true
  store:SetCurrentCharacter(Core.char, guild)
  store:DropStaleGuildCaches()
  Core.sync:OnGuildChanged()
  if guild then C_GuildInfo.GuildRoster() end
  refreshWindow()
end

local function printable(raw)
  if Names.IsSecret(raw) then return "<secret>" end
  return tostring(raw)
end

-- Hello to the guild once its name is known (Sync says it only once per guild and mode change).
local function sayHello()
  if Core.HasSyncGuild() then Core.sync:OnRosterReady() end
end

-- Prunes owners that left; only a complete roster can tell (and only if the client has the API).
local function pruneByRoster()
  if not (GetGuildRosterInfo and GetNumGuildMembers) then return end
  local total = GetNumGuildMembers() or 0
  local keys, count, samples = {}, 0, {}
  for i = 1, total do
    local raw = GetGuildRosterInfo(i)
    if #samples < ROSTER_DEBUG_NAMES then samples[#samples + 1] = printable(raw) end
    local key = Names.Normalize(raw)
    if key and not keys[key] then
      keys[key] = true
      count = count + 1
    end
  end
  if Core.sv.settings.debug then
    Core.Print(L["DEBUG_PREFIX"] .. " " .. L["DEBUG_ROSTER"]:format(total, count, table.concat(samples, ", ")))
  end

  local complete = total > 0 and count == total
  local removed = Core.sync:OnRoster(keys, complete)
  if #removed > 0 then refreshWindow() end
end

local function onRoster()
  updateGuild()
  if not Core.HasSyncGuild() then return end
  -- prune first, so the hello does not advertise owners that just left
  pruneByRoster()
  sayHello()
end

-- Options: the sync mode changed.
function Core.OnSyncModeChanged()
  Core.sync:OnModeChanged()
  refreshWindow()
end

-- Group ------------------------------------------------------------------------------

local function onGroup()
  if not IsInGroup() then return Core.detect:OnGroup({}) end
  local prefix, count = "party", 4
  if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
  local me = Names.Normalize(Core.store:GetCurrentChar() or Core.char)
  local names = {}
  for i = 1, count do
    local name = Names.FromUnit(prefix .. i)
    if name and Names.Normalize(name) ~= me then names[#names + 1] = name end
  end
  -- all names secret (e.g. in an instance): keep the "already warned" state of this group
  if #names > 0 then Core.detect:OnGroup(names) end
end

-- Startup ----------------------------------------------------------------------------

local function onAddonLoaded()
  GrudgeForeverDB = GrudgeForeverDB or {}
  local sv = GrudgeForeverDB
  Core.sv = sv
  ns.Options.Apply(sv)
  Core.store = ns.Store.New(sv, { now = GetServerTime, random = math.random })
  ns.Slash.Register()
end

local function hintNameplates(sv)
  if sv.nameplateHintShown or GetCVarBool("nameplateShowEnemies") then return end
  sv.nameplateHintShown = true
  Core.Print(L["HINT_NAMEPLATES"])
end

-- Watches the client's ignore calls (target menu, /ignore, friends frame) for new ignores.
local function installIgnoreWatch(store)
  local friends = C_FriendList
  if not (friends and hooksecurefunc and friends.IsOnIgnoredList) then return end
  Core.ignoreWatch = ns.IgnoreWatch.New({
    store = store, change = Core.Change, print = Core.Print,
    isIgnored = function(name)
      local ok, ignored = pcall(friends.IsOnIgnoredList, name)
      return ok and ignored == true
    end,
  })
  local function onCall(name) Core.ignoreWatch:OnIgnoreCall(name) end
  for _, fn in ipairs({ "AddIgnore", "AddOrDelIgnore" }) do
    if friends[fn] then hooksecurefunc(friends, fn, onCall) end
  end
end

local function onLogin(frame)
  if Core.ready then return end
  local sv, store = Core.sv, Core.store
  Core.char = Names.FromUnit("player")
  -- the character is known at once; its guild from last time stands in until the client loads it
  local last = sv.myChars[Names.Normalize(Core.char) or ""]
  store:SetCurrentCharacter(Core.char, last and last.guild)
  store:PruneTombstones()

  Core.alerts = ns.Alerts.New({ settings = function() return sv.settings end, now = GetServerTime, out = outputs })
  Core.detect = ns.Detect.New({
    store = store, alerts = Core.alerts, debug = function() return sv.settings.debug end, log = Core.Print,
  })

  local comm = {}
  LibStub("AceComm-3.0"):Embed(comm)
  Core.transport = ns.Transport.New({
    comm = comm,
    onMessage = function(msg, sender)
      Core.sync:OnMessage(msg, sender)
      refreshWindow()
    end,
  })
  Core.sync = ns.Sync.New({
    store = store,
    send = function(msg, prio) Core.transport:Send(msg, prio) end,
    now = GetServerTime,
    after = function(seconds, fn) return C_Timer.NewTimer(seconds, fn) end,
    random = math.random,
    mode = function() return guildResolved and sv.settings.syncMode or "off" end,
    sv = sv,
  })
  Core.transport:Register()
  C_Timer.NewTicker(1, function() Core.transport:Flush() end)

  ns.Tooltip.Install(store)
  ns.UnitMenu.Install(store)
  installIgnoreWatch(store)
  ns.OptionsPanel.Register(sv.settings, {
    testAlert = Core.TestAlert, bannerLock = ns.Banner.SetLocked, bannerReset = ns.Banner.ResetPosition,
    syncModeChanged = Core.OnSyncModeChanged,
  })

  Core.ready = true
  updateGuild()
  if IsInGuild() then C_GuildInfo.GuildRoster() end
  C_Timer.After(HELLO_TIMEOUT, function()
    updateGuild()
    sayHello()
  end)
  hintNameplates(sv)
  for _, event in ipairs(GAME_EVENTS) do frame:RegisterEvent(event) end
end

-- Events -----------------------------------------------------------------------------

local events = {
  CHAT_MSG_WHISPER = function(_, sender) Core.detect:OnWhisper(sender) end,
  PARTY_INVITE_REQUEST = function(inviter) Core.detect:OnInvite(inviter) end,
  GROUP_ROSTER_UPDATE = onGroup,
  NAME_PLATE_UNIT_ADDED = function(unit) Core.detect:OnUnit(unit) end,
  PLAYER_TARGET_CHANGED = function() Core.detect:OnUnit("target") end,
  UPDATE_MOUSEOVER_UNIT = function() Core.detect:OnUnit("mouseover") end,
  GUILD_ROSTER_UPDATE = onRoster,
  IGNORELIST_UPDATE = function()
    if Core.ignoreWatch then Core.ignoreWatch:OnIgnoreListUpdate() end
  end,
  PLAYER_GUILD_UPDATE = function()
    updateGuild()
    if IsInGuild() then C_GuildInfo.GuildRoster() end
  end,
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if ... == ADDON then onAddonLoaded() end
  elseif event == "PLAYER_LOGIN" then
    onLogin(self)
  elseif Core.ready and events[event] then
    events[event](...)
  end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

ns.Core = Core
