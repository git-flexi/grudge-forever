local ADDON, ns = ...

-- Thin layer between the Sync protocol and AceComm on the GUILD addon channel.
-- During a chat messaging lockdown (instances, encounters) outgoing messages
-- wait in a small queue; the core flushes it on a timer.
local Transport = {}
Transport.__index = Transport

local MAX_QUEUE = 50

local function inLockdown()
  local fn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  return fn ~= nil and fn() and true or false
end

-- deps = { comm = <AceComm-embedded table>, onMessage = function(msg, sender) }
function Transport.New(deps)
  return setmetatable({
    comm = deps.comm,
    onMessage = deps.onMessage,
    queue = {},
  }, Transport)
end

function Transport:transmit(text, prio)
  self.comm:SendCommMessage(ns.Const.PREFIX, text, "GUILD", nil, prio)
end

-- prio is "NORMAL" or "BULK". Messages are encoded right away so a queued
-- message cannot change afterwards.
function Transport:Send(msg, prio)
  if not IsInGuild() then return end
  local text = ns.Codec.Encode(msg, "comm")
  if inLockdown() then
    table.insert(self.queue, { text = text, prio = prio })
    if #self.queue > MAX_QUEUE then table.remove(self.queue, 1) end
    return
  end
  self:transmit(text, prio)
end

-- Sends the queued messages in order once the lockdown is over.
function Transport:Flush()
  if #self.queue == 0 or inLockdown() then return end
  local queue = self.queue
  self.queue = {}
  if not IsInGuild() then return end
  for _, item in ipairs(queue) do
    self:transmit(item.text, item.prio)
  end
end

function Transport:OnComm(prefix, data, distribution, sender)
  if prefix ~= ns.Const.PREFIX or distribution ~= "GUILD" then return end
  local ok, msg = pcall(ns.Codec.Decode, data, "comm")
  if not ok or type(msg) ~= "table" then return end
  self.onMessage(msg, sender)
end

function Transport:Register()
  self.comm:RegisterComm(ns.Const.PREFIX, function(prefix, data, distribution, sender)
    self:OnComm(prefix, data, distribution, sender)
  end)
end

ns.Transport = Transport
