local ADDON, ns = ...

-- Guild sync protocol. Pure logic: sending, time, timers, randomness and the sync mode come in
-- through deps, so this file never touches WoW APIs or the network.
--
-- Messages (all carry v = Const.PROTO):
--   H hello    { t="H", v, pid, char, chars = { display… }, d = { [owner] = rev }, full = bool }
--   R request  { t="R", v, pid, want = { [owner] = haveRev } }
--   A announce { t="A", v, from = pid, o, rev, base } sent SETTLE seconds before a planned D
--   D data     a Store delta plus { t="D", v, from = pid }
--
-- Answers and requests are delayed by a random 1-8 s and dropped when someone else announced or sent
-- the same data first, so a large guild answers each question about once. The delays are fractional
-- and exponentially shaped: few clients pick an early time, so the first answer is rarely followed by
-- another one before its announce arrives, however many members are online. The owner of the data
-- answers first (within 1 s). The announce matters because a large D arrives in chunks over many
-- seconds, long after the other answer timers ran out. When announces still cross on the wire, the
-- D waits SETTLE seconds and only the lowest player id among equal announces sends it.
local Names, Const, Store = ns.Names, ns.Const, ns.Store

local Sync = {}
Sync.__index = Sync

local PRIO_CONTROL, PRIO_DATA = "NORMAL", "BULK"
local DELAY_MIN, DELAY_MAX = 1, 8
local OWN_DELAY_MIN, OWN_DELAY_MAX = 0.1, 0.6 -- the owner's announce reaches everyone before DELAY_MIN
local MAX_ANSWERERS = 1000 -- online members the delay spread is tuned for
local SETTLE = 1 -- seconds between a planned answer's announce and its data; longer than control latency
local MAX_ID_LENGTH = 64

-- Validation of untrusted messages --------------------------------------------

local isCount = Store.IsCount

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

-- base < e.rev <= maxRev
local function isEntry(e, base, maxRev)
  return type(e) == "table" and isName(e.name) and e.key == Names.Normalize(e.name)
    and Store.IsList(e.list) and Store.IsValidReason(e.reason) and isOptional(e.origin, isName)
    and isCount(e.created) and isCount(e.updated) and isCount(e.rev) and e.rev > base and e.rev <= maxRev
    and isBool(e.deleted)
end

-- A dense array (keys exactly 1..n) of at most MAX_ENTRIES_PER_OWNER valid entries.
local function isEntryList(list, base, maxRev)
  if type(list) ~= "table" then return false end
  local n = 0
  for _ in pairs(list) do
    n = n + 1
    if n > Const.MAX_ENTRIES_PER_OWNER then return false end
  end
  for i = 1, n do
    if not isEntry(list[i], base, maxRev) then return false end
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
  A = function(m)
    return isId(m.from) and isId(m.o) and isCount(m.rev) and isCount(m.base) and m.base <= m.rev
  end,
  D = function(m)
    return isId(m.from) and isId(m.o) and isCount(m.rev) and isCount(m.base) and m.base <= m.rev
      and isOptional(m.chars, isCharMap) and isOptional(m.lastChar, isName) and isEntryList(m.e, m.base, m.rev)
  end,
}

local function isValid(msg)
  if type(msg) ~= "table" or msg.v ~= Const.PROTO then return false end
  local check = validators[msg.t]
  return check ~= nil and check(msg)
end

-- Construction ------------------------------------------------------------------

-- deps = { store, send(msg, prio), now(), after(seconds, fn) -> handle, random() -> [0, 1),
--          mode() -> "auto"|"manual"|"off", sv }
function Sync.New(deps)
  return setmetatable({
    deps = deps,
    store = deps.store,
    helloSeen = {},    -- sender key (.. "\nfull" for manual syncs) -> time of the last answered hello
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

-- ownerId: the owner whose data an answer carries; its owner answers sooner than everyone else.
-- Others: P(delay <= DELAY_MIN + s * span) = MAX_ANSWERERS^(s - 1), a truncated exponential, so with
-- n answerers the earliest one fires near s = 1 - log(n) / log(MAX_ANSWERERS), well ahead of the rest.
function Sync:delay(ownerId)
  local x = self.deps.random()
  if ownerId ~= nil and ownerId == self.store:GetPlayerId() then
    return OWN_DELAY_MIN + x * (OWN_DELAY_MAX - OWN_DELAY_MIN)
  end
  local share = math.max(0, 1 + math.log(x) / math.log(MAX_ANSWERERS))
  return DELAY_MIN + share * (DELAY_MAX - DELAY_MIN)
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

-- Cancels a planned answer for the owner that the given announce or delta makes redundant.
-- rival: the sender's player id for an announce. An answer we announced already gives way only to a
-- wider one, or to an equal announce from a lower player id (that client drops its own for ours).
function Sync:dropCoveredData(ownerId, rev, base, rival)
  local p = self.pendingData[ownerId]
  if not p then return end
  if p.rev then
    if rev < p.rev or base > p.base then return end
    local equal = rev == p.rev and base == p.base
    if equal and rival and rival >= self.store:GetPlayerId() then return end
  elseif rev < self.store:GetRev(ownerId) or base > p.base then
    return
  end
  p.handle:Cancel()
  self.pendingData[ownerId] = nil
end

-- receivers drop oversized deltas whole, so sending one would only flood the channel
local function sendable(delta)
  return delta ~= nil and delta.rev > delta.base and #delta.e <= Const.MAX_ENTRIES_PER_OWNER
end

function Sync:sendDelta(delta)
  if not sendable(delta) then return end
  local pid = self.store:GetPlayerId()
  self:dropCoveredData(delta.o, delta.rev, delta.base)
  delta.t, delta.v, delta.from = "D", Const.PROTO, pid
  self.deps.send(delta, PRIO_DATA)
end

-- An answer: after the delay, announce it (small, fast) so other planned answers stop before the D
-- arrives; after SETTLE, send the D unless a rival announce or data took over meanwhile.
function Sync:planData(ownerId, base)
  local p = self.pendingData[ownerId]
  if p then
    if base < p.base then p.base = base end
    return
  end
  p = { base = base }
  self.pendingData[ownerId] = p
  local function usable()
    if self.pendingData[ownerId] ~= p then return false end
    if self:isActive() and self:hasGuild() then return true end
    self.pendingData[ownerId] = nil
    return false
  end
  p.handle = self.deps.after(self:delay(ownerId), function()
    if not usable() then return end
    local delta = self.store:DeltaFor(ownerId, p.base)
    if not sendable(delta) then
      self.pendingData[ownerId] = nil
      return
    end
    p.rev = delta.rev
    self.deps.send({ t = "A", v = Const.PROTO, from = self.store:GetPlayerId(), o = ownerId, rev = delta.rev,
      base = p.base }, PRIO_CONTROL)
    p.handle = self.deps.after(SETTLE, function()
      if not usable() then return end
      self.pendingData[ownerId] = nil
      self:sendDelta(self.store:DeltaFor(ownerId, p.base))
    end)
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

-- covered: whether the incoming data or request takes care of our pending want
function Sync:dropRequest(ownerId, covered)
  local want = self.pendingWant[ownerId]
  if want == nil or not covered(want) then return end
  self.pendingWant[ownerId] = nil
  if next(self.pendingWant) == nil and self.requestTimer then
    self.requestTimer:Cancel()
    self.requestTimer = nil
  end
end

-- Receiving -----------------------------------------------------------------------

function Sync:onHello(msg, sender)
  -- also while not answering: a hello proves the sender is in the guild (keeps or brings it back)
  self.store:NoteMember(msg.pid, msg.chars, msg.char)
  if not self:isActive() then return end
  local now = self.deps.now()
  -- a manual sync is limited on its own, so it still works right after the automatic login hello
  local key = msg.full and sender .. "\nfull" or sender
  local last = self.helloSeen[key]
  if last and now - last < Const.SYNC_COOLDOWN then return end
  self.helloSeen[key] = now

  local mine, theirs = self.store:Digest(), msg.d
  for ownerId, rev in pairs(mine) do
    local their = theirs[ownerId] or 0
    if rev > their then self:planData(ownerId, their) end
  end
  for ownerId, their in pairs(theirs) do
    local rev = mine[ownerId] or 0
    if their > rev and not self.store:IsPruned(ownerId) then self:planRequest(ownerId, rev) end
  end
end

function Sync:onRequest(msg, sender)
  -- someone else asking for at least as much gets an answer we can use too
  for ownerId, want in pairs(msg.want) do
    self:dropRequest(ownerId, function(mine) return want <= mine end)
  end
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

-- Suppression shared by announces and data. Returns false for owners that left the guild.
function Sync:noteData(msg)
  if self.store:IsPruned(msg.o) then return false end
  self:dropCoveredData(msg.o, msg.rev, msg.base, msg.t == "A" and msg.from or nil)
  self:dropRequest(msg.o, function(want) return msg.rev > want end)
  return true
end

function Sync:onAnnounce(msg)
  self:noteData(msg)
end

function Sync:onData(msg)
  local ownerId = msg.o
  if not self:noteData(msg) then return end
  if self.store:ApplyDelta(msg) == "need_full" and self:isActive() then
    self:planRequest(ownerId, 0)
  end
  if ownerId ~= self.store:GetPlayerId() then self.store:TryClaimIdentity(ownerId) end
end

local handlers = { H = Sync.onHello, R = Sync.onRequest, A = Sync.onAnnounce, D = Sync.onData }

-- Public API ----------------------------------------------------------------------

function Sync:OnMessage(msg, senderName)
  if self.deps.mode() == "off" or not self:hasGuild() then return end
  local sender = Names.Normalize(senderName)
  if not sender or sender == Names.Normalize(self.store:GetCurrentChar()) then return end
  if not isValid(msg) then return end
  handlers[msg.t](self, msg, sender)
end

-- When the guild roster is complete for the first time (again after OnGuildChanged).
function Sync:OnRosterReady()
  if self.helloSent or self.deps.mode() ~= "auto" or not self:hasGuild() then return end
  self.helloSent = true
  self:sendHello(false)
end

-- The current character joined, left or switched guilds: forget everything planned for the old one,
-- so the next OnRosterReady says hello to the new guild.
function Sync:OnGuildChanged()
  for _, p in pairs(self.pendingData) do p.handle:Cancel() end
  if self.requestTimer then self.requestTimer:Cancel() end
  self.pendingData, self.pendingWant, self.requestTimer = {}, {}, nil
  self.helloSeen, self.requestSeen = {}, {}
  self.helloSent = false
end

-- Seconds until "sync now" is allowed again (0 = now).
function Sync:CooldownRemaining()
  local since = self.deps.now() - (self.deps.sv.lastManualSync or 0)
  if since >= 0 and since < Const.SYNC_COOLDOWN then return Const.SYNC_COOLDOWN - since end
  return 0
end

-- Returns true, or false plus the remaining cooldown in seconds (0 when sync is off).
function Sync:ManualSync()
  if self.deps.mode() == "off" or not self:hasGuild() then return false, 0 end
  local remaining = self:CooldownRemaining()
  if remaining > 0 then return false, remaining end
  self.deps.sv.lastManualSync = self.deps.now()
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
