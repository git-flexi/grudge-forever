local ADDON, ns = ...

-- Thin layer between the protocols and AceComm. Sync talks on the GUILD addon channel only; the
-- version check also uses the group channels (PARTY, RAID, INSTANCE_CHAT).
-- During a chat messaging lockdown (instances, encounters) outgoing messages
-- wait in a small queue; the core flushes it on a timer.
local Transport = {}
Transport.__index = Transport

local MAX_QUEUE = 50

local HOME = LE_PARTY_CATEGORY_HOME or 1
local INSTANCE = LE_PARTY_CATEGORY_INSTANCE or 2

-- channel -> whether we may send there right now
local CHANNELS = {
  GUILD = function() return IsInGuild() end,
  PARTY = function() return IsInGroup(HOME) end,
  RAID = function() return IsInGroup(HOME) end,
  INSTANCE_CHAT = function() return IsInGroup(INSTANCE) end,
}

local function canSend(channel)
  local check = CHANNELS[channel]
  return check ~= nil and check() and true or false
end

local function inLockdown()
  local fn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  return fn ~= nil and fn() and true or false
end

-- deps = { comm = <AceComm-embedded table>, onMessage = function(msg, sender, channel) }
function Transport.New(deps)
  return setmetatable({
    comm = deps.comm,
    onMessage = deps.onMessage,
    queue = {},
  }, Transport)
end

function Transport:transmit(text, prio, channel)
  self.comm:SendCommMessage(ns.Const.PREFIX, text, channel, nil, prio)
end

-- prio is "NORMAL" or "BULK"; channel is "GUILD" (the default) or a group channel. Messages are
-- encoded right away so a queued message cannot change afterwards. Messages still queued from a
-- lockdown that ended go out first, so nothing overtakes them.
function Transport:Send(msg, prio, channel)
  channel = channel or "GUILD"
  if not canSend(channel) then return end
  local text = ns.Codec.Encode(msg, "comm")
  if inLockdown() then
    table.insert(self.queue, { text = text, prio = prio, channel = channel })
    if #self.queue > MAX_QUEUE then table.remove(self.queue, 1) end
    return
  end
  self:Flush()
  self:transmit(text, prio, channel)
end

-- Sends the queued messages in order once the lockdown is over; messages for a guild or group that
-- was left meanwhile are dropped.
function Transport:Flush()
  if #self.queue == 0 or inLockdown() then return end
  local queue = self.queue
  self.queue = {}
  for _, item in ipairs(queue) do
    if canSend(item.channel) then self:transmit(item.text, item.prio, item.channel) end
  end
end

function Transport:OnComm(prefix, data, distribution, sender)
  if prefix ~= ns.Const.PREFIX or not CHANNELS[distribution] then return end
  local ok, msg = pcall(ns.Codec.Decode, data, "comm")
  if not ok or type(msg) ~= "table" then return end
  -- a failing handler must not break AceComm's delivery of later messages; the error is still shown
  local handled, err = pcall(self.onMessage, msg, sender, distribution)
  if not handled and geterrorhandler then geterrorhandler()(err) end
end

function Transport:Register()
  self.comm:RegisterComm(ns.Const.PREFIX, function(prefix, data, distribution, sender)
    self:OnComm(prefix, data, distribution, sender)
  end)
end

ns.Transport = Transport
