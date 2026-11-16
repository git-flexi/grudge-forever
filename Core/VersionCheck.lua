local ADDON, ns = ...

-- Tells the player when a newer GrudgeForever is around. Addons cannot ask the internet, so the
-- version comes from other players: every client announces its version to the guild and to its
-- group, and players with a newer version answer the older ones. The notice needs two different
-- players reporting a newer version (one player testing an unreleased build is no update) and
-- shows once per session. Pure logic: sending, timers, time and printing come in through deps.
--
-- Message: V version { t="V", av = version }. It stays this small and carries no protocol number,
-- so every future version still understands it.
local Names, Store, L = ns.Names, ns.Store, ns.L

local VersionCheck = {}
VersionCheck.__index = VersionCheck

local NOTICE_PLAYERS = 2   -- players that must report a newer version before the notice shows
local ANSWERS_ENOUGH = 2   -- answers by others that make our own answer unnecessary
local DELAY_MIN, DELAY_MAX = 1, 8
local ANSWER_COOLDOWN = 60 -- seconds between two answers on one channel

-- Numeric parts of a version's leading number ("1.2.0-rc2" -> 1, 2, 0), or nil when it has none.
local function parts(v)
  if not Store.IsVersion(v) then return nil end
  local number = v:match("^[%d%.]+")
  if not number then return nil end
  local out = {}
  for d in number:gmatch("%d+") do out[#out + 1] = tonumber(d) end
  return #out > 0 and out or nil
end

-- 1 if a is newer than b, -1 if older, 0 if equal; nil when one of them is no version.
-- "1.10.0" is newer than "1.9.2"; missing parts count as 0 and suffixes like "-rc2" are ignored.
function VersionCheck.Compare(a, b)
  local pa, pb = parts(a), parts(b)
  if not pa or not pb then return nil end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x > y and 1 or -1 end
  end
  return 0
end

-- deps = { version, send(msg, channel), after(seconds, fn) -> handle with :Cancel(), random() -> [0, 1),
--          now(), print(text), me() -> the current character's name }
function VersionCheck.New(deps)
  return setmetatable({
    deps = deps,
    newer = {},      -- player key -> the highest newer version that player reported
    newerCount = 0,
    noticed = false,
    pending = {},    -- channel -> { timer, answers = { player key -> true } }: our planned answer
    answered = {},   -- channel -> time of our last answer
  }, VersionCheck)
end

function VersionCheck:enabled()
  return parts(self.deps.version) ~= nil
end

function VersionCheck:send(channel)
  self.deps.send({ t = "V", av = self.deps.version }, channel)
end

function VersionCheck:Announce(channel)
  if self:enabled() then self:send(channel) end
end

-- The highest version at least NOTICE_PLAYERS players run (or newer): one tester's build is not it.
function VersionCheck:confirmed()
  local versions = {}
  for _, v in pairs(self.newer) do versions[#versions + 1] = v end
  table.sort(versions, function(a, b) return VersionCheck.Compare(a, b) > 0 end)
  return versions[NOTICE_PLAYERS]
end

function VersionCheck:noteNewer(av, sender)
  local known = self.newer[sender]
  if not known then self.newerCount = self.newerCount + 1 end
  if not known or VersionCheck.Compare(av, known) > 0 then self.newer[sender] = av end
  if self.noticed or self.newerCount < NOTICE_PLAYERS then return end
  self.noticed = true
  self.deps.print(L["VERSION_NEWER"]:format(self:confirmed(), self.deps.version))
end

-- Plans an answer to an older version, unless one is planned or we answered on this channel lately.
function VersionCheck:planAnswer(channel)
  if self.pending[channel] then return end
  local last = self.answered[channel]
  local now = self.deps.now()
  if last and now - last < ANSWER_COOLDOWN then return end
  local plan = { answers = {}, count = 0 }
  plan.timer = self.deps.after(DELAY_MIN + self.deps.random() * (DELAY_MAX - DELAY_MIN), function()
    self.pending[channel] = nil
    self.answered[channel] = self.deps.now()
    self:send(channel)
  end)
  self.pending[channel] = plan
end

-- Someone else answered on this channel with a version at least as new as ours.
function VersionCheck:noteAnswer(channel, sender)
  local plan = self.pending[channel]
  if not plan or plan.answers[sender] then return end
  plan.answers[sender] = true
  plan.count = plan.count + 1
  if plan.count < ANSWERS_ENOUGH then return end
  plan.timer:Cancel()
  self.pending[channel] = nil
end

-- A version reported by another player. channel: where an answer would go; nil for versions that
-- came along with something else (the guild hello) and need no answer.
function VersionCheck:OnVersion(av, senderName, channel)
  if not self:enabled() or Names.IsSecret(senderName) then return end
  local sender = Names.Normalize(senderName)
  if not sender or sender == Names.Normalize(self.deps.me()) then return end
  local cmp = VersionCheck.Compare(av, self.deps.version)
  if cmp == nil then return end
  if cmp > 0 then self:noteNewer(av, sender) end
  if not channel then return end
  if cmp < 0 then
    self:planAnswer(channel)
  else
    self:noteAnswer(channel, sender)
  end
end

-- A V message from the transport.
function VersionCheck:OnMessage(msg, sender, channel)
  if type(msg) ~= "table" or msg.t ~= "V" then return end
  self:OnVersion(msg.av, sender, channel)
end

ns.VersionCheck = VersionCheck
