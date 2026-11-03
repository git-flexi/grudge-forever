local ADDON, ns = ...

-- Guild sync protocol. Pure logic: sending, time, timers, randomness and the sync mode come in
-- through deps, so this file never touches WoW APIs or the network.
--
-- Messages (all carry v = Const.PROTO):
--   H hello    { t="H", v, pid, char, chars = { display… }, d = { [owner] = rev }, full = bool }
--   R request  { t="R", v, pid, want = { [owner] = haveRev } }
--   D data     a Store delta plus { t="D", v, from = pid }
--
-- Answers are delayed by a random 1-5 s and dropped when someone else sent the same data first,
-- so a large guild answers each question about once.
local Names, Const, Store = ns.Names, ns.Const, ns.Store

local Sync = {}
Sync.__index = Sync

local PRIO_CONTROL, PRIO_DATA = "NORMAL", "BULK"
local DELAY_MIN, DELAY_MAX = 1, 5
local MAX_ID_LENGTH = 64

-- Validation of untrusted messages --------------------------------------------

-- finite and not negative (rejects NaN and ±inf)
local function isCount(v)
  return type(v) == "number" and v == v and v >= 0 and v < math.huge
end

local function isId(v)
  return type(v) == "string" and #v > 0 and #v <= MAX_ID_LENGTH
end

local function isName(v)
  return Names.Normalize(v) ~= nil
end

local function isBool(v)
  return type(v) == "boolean"
end

local function isOptional(v, check)
  return v == nil or check(v)
end

-- { [ownerId] = rev }
local function isRevMap(t)
  if type(t) ~= "table" then return false end
  for k, v in pairs(t) do
    if not isId(k) or not isCount(v) then return false end
  end
  return true
end

-- { display… }
local function isCharList(t)
  if type(t) ~= "table" then return false end
  for _, v in pairs(t) do
    if not isName(v) then return false end
  end
  return true
end

-- { [charKey] = display } where every key belongs to its name
local function isCharMap(t)
  if type(t) ~= "table" then return false end
  for k, v in pairs(t) do
    if not isName(v) or Names.Normalize(v) ~= k then return false end
  end
  return true
end

local function isEntry(e, maxRev)
  return type(e) == "table" and isName(e.name) and e.key == Names.Normalize(e.name)
    and Store.IsList(e.list) and Store.IsValidReason(e.reason) and isOptional(e.origin, isName)
    and isCount(e.created) and isCount(e.updated) and isCount(e.rev) and e.rev <= maxRev
    and isBool(e.deleted)
end

-- A dense array (keys exactly 1..n) of at most MAX_ENTRIES_PER_OWNER valid entries.
local function isEntryList(list, maxRev)
  if type(list) ~= "table" then return false end
  local n = 0
  for _ in pairs(list) do
    n = n + 1
    if n > Const.MAX_ENTRIES_PER_OWNER then return false end
  end
  for i = 1, n do
    if not isEntry(list[i], maxRev) then return false end
  end
  return true
end

local validators = {
  H = function(m)
    return isId(m.pid) and isName(m.char) and isCharList(m.chars) and isRevMap(m.d) and isOptional(m.full, isBool)
  end,
  R = function(m)
    return isId(m.pid) and isRevMap(m.want)
  end,
  D = function(m)
    return isId(m.from) and isId(m.o) and isCount(m.rev) and isCount(m.base) and m.base <= m.rev
      and isOptional(m.chars, isCharMap) and isOptional(m.lastChar, isName) and isEntryList(m.e, m.rev)
  end,
}

local function isValid(msg)
  if type(msg) ~= "table" or msg.v ~= Const.PROTO then return false end
  local check = validators[msg.t]
  return check ~= nil and check(msg)
end

-- Construction ------------------------------------------------------------------

-- deps = { store, send(msg, prio), now(), after(seconds, fn) -> handle, random(min, max),
--          mode() -> "auto"|"manual"|"off", sv }
function Sync.New(deps)
  return setmetatable({
    deps = deps,
    store = deps.store,
    helloSeen = {},    -- sender key -> time of the last answered hello
    requestSeen = {},  -- sender key .. "\n" .. owner -> time of the last answered request
    pendingData = {},  -- owner -> { base =, handle = }
    pendingWant = {},  -- owner -> rev to request from
    requestTimer = nil,
    helloSent = false,
  }, Sync)
end

function Sync:hasGuild()
  return self.store:GetCurrentGuild() ~= nil
end

-- Whether this client answers and requests. "manual" only does so while its "sync now" cooldown
-- runs, so that a manual sync works in both directions.
function Sync:isActive()
  local mode = self.deps.mode()
  if mode == "auto" then return true end
  local since = self.deps.now() - (self.deps.sv.lastManualSync or 0)
  return mode == "manual" and since >= 0 and since < Const.SYNC_COOLDOWN
end

function Sync:delay()
  return self.deps.random(DELAY_MIN, DELAY_MAX)
end

-- Sending -------------------------------------------------------------------------

function Sync:sendHello(full)
  local chars = {}
  for _, display in pairs(self.store:GetMyGuildChars()) do chars[#chars + 1] = display end
  table.sort(chars)
  self.deps.send({
    t = "H", v = Const.PROTO, pid = self.store:GetPlayerId(), char = self.store:GetCurrentChar(),
    chars = chars, d = self.store:Digest(), full = full,
  }, PRIO_CONTROL)
end

-- Cancels a planned answer for the owner that the given delta makes redundant.
function Sync:dropCoveredData(ownerId, rev, base)
  local p = self.pendingData[ownerId]
  if p and rev >= self.store:GetRev(ownerId) and base <= p.base then
    p.handle:Cancel()
    self.pendingData[ownerId] = nil
  end
end

function Sync:sendDelta(delta)
  -- receivers drop oversized deltas whole, so sending one would only flood the channel
  if delta.rev <= delta.base or #delta.e > Const.MAX_ENTRIES_PER_OWNER then return end
  delta.t, delta.v, delta.from = "D", Const.PROTO, self.store:GetPlayerId()
  self:dropCoveredData(delta.o, delta.rev, delta.base)
  self.deps.send(delta, PRIO_DATA)
end

function Sync:planData(ownerId, base)
  local p = self.pendingData[ownerId]
  if p then
    if base < p.base then p.base = base end
    return
  end
  p = { base = base }
  self.pendingData[ownerId] = p
  p.handle = self.deps.after(self:delay(), function()
    if self.pendingData[ownerId] ~= p then return end
    self.pendingData[ownerId] = nil
    if not self:isActive() or not self:hasGuild() then return end
    local delta = self.store:DeltaFor(ownerId, p.base)
    if delta then self:sendDelta(delta) end
  end)
end

-- All owners planned within one delay go out as a single request.
function Sync:planRequest(ownerId, want)
  local cur = self.pendingWant[ownerId]
  if cur == nil or want < cur then self.pendingWant[ownerId] = want end
  if self.requestTimer then return end
  self.requestTimer = self.deps.after(self:delay(), function()
    self.requestTimer = nil
    local wants = self.pendingWant
    self.pendingWant = {}
    if next(wants) == nil or not self:isActive() or not self:hasGuild() then return end
    self.deps.send({ t = "R", v = Const.PROTO, pid = self.store:GetPlayerId(), want = wants }, PRIO_CONTROL)
  end)
end

function Sync:dropCoveredRequest(ownerId, rev)
  local want = self.pendingWant[ownerId]
  if want == nil or rev <= want then return end
  self.pendingWant[ownerId] = nil
  if next(self.pendingWant) == nil and self.requestTimer then
    self.requestTimer:Cancel()
    self.requestTimer = nil
  end
end

-- Receiving -----------------------------------------------------------------------

function Sync:onHello(msg, sender)
  if not self:isActive() then return end
  local now = self.deps.now()
  local last = self.helloSeen[sender]
  if last and now - last < Const.SYNC_COOLDOWN then return end
  self.helloSeen[sender] = now

  local mine, theirs = self.store:Digest(), msg.d
  for ownerId, rev in pairs(mine) do
    local their = theirs[ownerId] or 0
    if rev > their then self:planData(ownerId, their) end
  end
  for ownerId, their in pairs(theirs) do
    local rev = mine[ownerId] or 0
    if their > rev then self:planRequest(ownerId, rev) end
  end
end

function Sync:onRequest(msg, sender)
  if not self:isActive() then return end
  local now = self.deps.now()
  for ownerId, want in pairs(msg.want) do
    local key = sender .. "\n" .. ownerId
    local last = self.requestSeen[key]
    if not (last and now - last < Const.SYNC_COOLDOWN) and want < self.store:GetRev(ownerId) then
      self.requestSeen[key] = now
      self:planData(ownerId, want)
    end
  end
end

function Sync:onData(msg)
  local ownerId = msg.o
  self:dropCoveredData(ownerId, msg.rev, msg.base)
  self:dropCoveredRequest(ownerId, msg.rev)
  if self.store:ApplyDelta(msg) == "need_full" and self:isActive() then
    self:planRequest(ownerId, 0)
  end
  if ownerId ~= self.store:GetPlayerId() then self.store:TryClaimIdentity(ownerId) end
end

local handlers = { H = Sync.onHello, R = Sync.onRequest, D = Sync.onData }

-- Public API ----------------------------------------------------------------------

function Sync:OnMessage(msg, senderName)
  if self.deps.mode() == "off" or not self:hasGuild() then return end
  local sender = Names.Normalize(senderName)
  if not sender or sender == Names.Normalize(self.store:GetCurrentChar()) then return end
  if not isValid(msg) then return end
  handlers[msg.t](self, msg, sender)
end

-- Once per session, when the guild roster is complete for the first time.
function Sync:OnRosterReady()
  if self.helloSent then return end
  self.helloSent = true
  if self.deps.mode() == "auto" and self:hasGuild() then self:sendHello(false) end
end

-- Returns true, or false plus the remaining cooldown in seconds (0 when sync is off).
function Sync:ManualSync()
  if self.deps.mode() == "off" or not self:hasGuild() then return false, 0 end
  local sv, now = self.deps.sv, self.deps.now()
  local since = now - (sv.lastManualSync or 0)
  if since >= 0 and since < Const.SYNC_COOLDOWN then return false, Const.SYNC_COOLDOWN - since end
  sv.lastManualSync = now
  self:sendHello(true)
  return true
end

-- prevRev: the own revision read before the change.
function Sync:OnOwnChange(prevRev)
  if self.deps.mode() ~= "auto" or not self:hasGuild() then return end
  self:sendDelta(self.store:DeltaFor(self.store:GetPlayerId(), prevRev or 0))
end

function Sync:OnRoster(rosterKeys, complete)
  return self.store:PruneByRoster(rosterKeys, complete)
end

ns.Sync = Sync
