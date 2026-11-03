local ADDON, ns = ...

-- Pure data layer over GrudgeForeverDB. Time and randomness are injected
-- (deps.now / deps.random) so the store never touches WoW globals.
local Names, Const = ns.Names, ns.Const

local Store = {}
Store.__index = Store

local HEX = "0123456789abcdef"
local ID_LENGTH = 16

local function isList(list)
  return list == Const.LIST_FRIENDLY or list == Const.LIST_ENEMY
end

local function entryId(list, key)
  return list .. ":" .. key
end

-- Length in UTF-8 characters (Lua 5.1 has no utf8 library): continuation bytes do not count.
local function charLength(s)
  return #(s:gsub("[\128-\191]", ""))
end

-- Copies an entry; the local-only creator character is left out unless asked for.
local function copyEntry(e, withChar)
  return {
    key = e.key, name = e.name, list = e.list, reason = e.reason,
    char = withChar and e.char or nil,
    origin = e.origin, created = e.created, updated = e.updated, rev = e.rev, deleted = e.deleted,
  }
end

local function copyMap(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function sortMatches(matches)
  table.sort(matches, function(a, b)
    if a.isOwn ~= b.isOwn then return a.isOwn end
    if a.entry.updated ~= b.entry.updated then return a.entry.updated > b.entry.updated end
    return a.ownerId < b.ownerId
  end)
  return matches
end

function Store.New(sv, deps)
  local self = setmetatable({ sv = sv, deps = deps }, Store)

  sv.schema = sv.schema or 1
  sv.lastManualSync = sv.lastManualSync or 0
  sv.myChars = sv.myChars or {}
  sv.own = sv.own or {}
  sv.own.rev = sv.own.rev or 0
  sv.own.entries = sv.own.entries or {}
  sv.guilds = sv.guilds or {}
  sv.mutes = sv.mutes or {}
  sv.settings = sv.settings or {}

  if type(sv.playerId) ~= "string" or sv.playerId == "" then
    local id = {}
    for i = 1, ID_LENGTH do
      local n = deps.random(#HEX)
      id[i] = HEX:sub(n, n)
    end
    sv.playerId = table.concat(id)
  end

  return self
end

-- Identity and current character ------------------------------------------

function Store:GetPlayerId()
  return self.sv.playerId
end

function Store:SetCurrentCharacter(charName, guildName)
  local key = Names.Normalize(charName)
  if not key then return end
  if guildName == "" then guildName = nil end
  self.sv.myChars[key] = { name = Names.Display(charName), guild = guildName, lastSeen = self.deps.now() }
  self.currentKey = key
end

function Store:GetCurrentChar()
  local c = self.currentKey and self.sv.myChars[self.currentKey]
  return c and c.name or nil
end

function Store:GetCurrentGuild()
  local c = self.currentKey and self.sv.myChars[self.currentKey]
  return c and c.guild or nil
end

function Store:GetMyGuildChars()
  local out, guild = {}, self:GetCurrentGuild()
  if not guild then return out end
  for key, c in pairs(self.sv.myChars) do
    if c.guild == guild then out[key] = c.name end
  end
  return out
end

-- Own entries ---------------------------------------------------------------

function Store:AddOrUpdate(list, name, reason)
  if not isList(list) then return nil, "invalid_list" end
  local key = Names.Normalize(name)
  if not key then return nil, "invalid_name" end
  if type(reason) ~= "string" or Names.IsSecret(reason) then reason = "" end
  if charLength(reason) > Const.REASON_MAX then return nil, "reason_too_long" end

  local own, now = self.sv.own, self.deps.now()
  own.rev = own.rev + 1
  local id = entryId(list, key)
  local e = own.entries[id]
  if not e then
    e = { key = key, name = Names.Display(name), list = list, created = now }
    own.entries[id] = e
  elseif e.deleted then
    -- reviving a tombstone starts a fresh entry of our own
    e.created, e.origin = now, nil
  end
  e.reason, e.updated, e.rev, e.deleted = reason, now, own.rev, false
  e.char = self:GetCurrentChar()
  return e
end

function Store:Delete(list, name)
  if not isList(list) then return false end
  local key = Names.Normalize(name)
  if not key then return false end
  local own = self.sv.own
  local e = own.entries[entryId(list, key)]
  if not e or e.deleted then return false end
  own.rev = own.rev + 1
  e.deleted, e.reason, e.updated, e.rev = true, "", self.deps.now(), own.rev
  return true
end

function Store:GetOwnEntries()
  local out = {}
  for _, e in pairs(self.sv.own.entries) do
    if not e.deleted then out[#out + 1] = e end
  end
  table.sort(out, function(a, b)
    if a.updated ~= b.updated then return a.updated > b.updated end
    return entryId(a.list, a.key) < entryId(b.list, b.key)
  end)
  return out
end

-- Guild caches --------------------------------------------------------------

function Store:GetOwners()
  local guild = self:GetCurrentGuild()
  local g = guild and self.sv.guilds[guild]
  return g and g.owners or {}
end

-- Owner table of the current guild, created on demand; nil without a guild.
function Store:ownerFor(ownerId)
  local guild = self:GetCurrentGuild()
  if not guild then return nil end
  local g = self.sv.guilds[guild]
  if not g then g = { owners = {} }; self.sv.guilds[guild] = g end
  local o = g.owners[ownerId]
  if not o then
    o = { rev = 0, chars = {}, seenInRoster = false, entries = {} }
    g.owners[ownerId] = o
  end
  return o
end

-- Lookup ---------------------------------------------------------------------

function Store:IsMuted(list, name)
  local key = Names.Normalize(name)
  if not key or not isList(list) then return false end
  return self.sv.mutes[entryId(list, key)] == true
end

function Store:SetMuted(list, name, muted)
  local key = Names.Normalize(name)
  if not key or not isList(list) then return end
  self.sv.mutes[entryId(list, key)] = muted and true or nil
end

-- All live matches for one player on one list (unsorted).
function Store:matchesFor(list, key)
  local id, out = entryId(list, key), {}
  local muted = self.sv.mutes[id] == true
  local own = self.sv.own.entries[id]
  if own and not own.deleted then
    out[#out + 1] = { entry = own, ownerId = self.sv.playerId, isOwn = true, by = self:GetCurrentChar(), muted = muted }
  end
  for ownerId, owner in pairs(self:GetOwners()) do
    local e = owner.entries[id]
    if e and not e.deleted then
      out[#out + 1] = { entry = e, ownerId = ownerId, isOwn = false, by = owner.lastChar, muted = muted }
    end
  end
  return out
end

function Store:Lookup(name, list)
  local key = Names.Normalize(name)
  if not key then return {} end
  local lists = { Const.LIST_FRIENDLY, Const.LIST_ENEMY }
  if list ~= nil then
    if not isList(list) then return {} end
    lists = { list }
  end
  local out = {}
  for _, l in ipairs(lists) do
    for _, m in ipairs(self:matchesFor(l, key)) do out[#out + 1] = m end
  end
  return sortMatches(out)
end

-- Every player on a list: { [key] = Match[] }, shaped and ordered like Lookup.
function Store:ListAll(list)
  local out = {}
  if not isList(list) then return out end
  local keys = {}
  for _, e in pairs(self.sv.own.entries) do
    if e.list == list and not e.deleted then keys[e.key] = true end
  end
  for _, owner in pairs(self:GetOwners()) do
    for _, e in pairs(owner.entries) do
      if e.list == list and not e.deleted then keys[e.key] = true end
    end
  end
  for key in pairs(keys) do out[key] = sortMatches(self:matchesFor(list, key)) end
  return out
end

-- Adoption ------------------------------------------------------------------

function Store:Adopt(ownerId, id)
  local owner = self:GetOwners()[ownerId]
  if not owner then return 0 end
  local own, now = self.sv.own, self.deps.now()

  local candidates = {}
  if id then
    candidates[1] = owner.entries[id]
  else
    for _, k in ipairs(sortedKeys(owner.entries)) do candidates[#candidates + 1] = owner.entries[k] end
  end

  local rev, count = own.rev + 1, 0
  for _, e in ipairs(candidates) do
    local eid = entryId(e.list, e.key)
    local mine = own.entries[eid]
    if not e.deleted and not (mine and not mine.deleted) then
      own.entries[eid] = {
        key = e.key, name = e.name, list = e.list, reason = e.reason, char = self:GetCurrentChar(),
        origin = e.origin or owner.lastChar, created = e.created or now, updated = now, rev = rev, deleted = false,
      }
      count = count + 1
    end
  end
  if count > 0 then own.rev = rev end
  return count
end

-- Sync support ----------------------------------------------------------------

function Store:GetRev(ownerId)
  if ownerId == self.sv.playerId then return self.sv.own.rev end
  local owner = self:GetOwners()[ownerId]
  return owner and owner.rev or 0
end

function Store:Digest()
  local out = { [self.sv.playerId] = self.sv.own.rev }
  for ownerId, owner in pairs(self:GetOwners()) do out[ownerId] = owner.rev end
  return out
end

function Store:DeltaFor(ownerId, sinceRev)
  local src, chars, lastChar
  if ownerId == self.sv.playerId then
    src, chars, lastChar = self.sv.own, self:GetMyGuildChars(), self:GetCurrentChar()
  else
    src = self:GetOwners()[ownerId]
    if not src then return nil end
    chars, lastChar = copyMap(src.chars), src.lastChar
  end

  local list = {}
  for _, e in pairs(src.entries) do
    if e.rev > sinceRev then list[#list + 1] = e end
  end
  table.sort(list, function(a, b)
    if a.rev ~= b.rev then return a.rev < b.rev end
    return entryId(a.list, a.key) < entryId(b.list, b.key)
  end)
  local entries = {}
  for i, e in ipairs(list) do entries[i] = copyEntry(e, false) end

  return { o = ownerId, rev = src.rev, base = sinceRev, chars = chars, lastChar = lastChar, e = entries }
end

-- Expects a well-formed delta; Sync validates untrusted messages first.
function Store:ApplyDelta(delta)
  local ownerId = delta.o
  local isOwn = ownerId == self.sv.playerId
  if not isOwn and not self:GetCurrentGuild() then return "stale" end

  local known = self:GetRev(ownerId)
  if delta.rev <= known then return "stale" end
  if delta.base > known then return "need_full" end

  local target = isOwn and self.sv.own or self:ownerFor(ownerId)
  for _, e in ipairs(delta.e or {}) do
    local id = entryId(e.list, e.key)
    local existing = target.entries[id]
    local fresh = copyEntry(e, false)
    if isOwn then
      -- the local creator character survives; entries new to this device get the sender's character
      fresh.char = existing and existing.char or delta.lastChar
    end
    if existing then
      for k in pairs(existing) do existing[k] = nil end
      for k, v in pairs(fresh) do existing[k] = v end
    else
      target.entries[id] = fresh
    end
  end
  target.rev = delta.rev
  if not isOwn then
    for k, v in pairs(delta.chars or {}) do target.chars[k] = v end
    if delta.lastChar then target.lastChar = delta.lastChar end
  end
  return "applied"
end

function Store:TryClaimIdentity(ownerId)
  local sv = self.sv
  if ownerId == sv.playerId or sv.own.rev ~= 0 or next(sv.own.entries) ~= nil then return false end
  local owner = self:GetOwners()[ownerId]
  if not owner or not self.currentKey or not owner.chars[self.currentKey] then return false end

  for _, e in pairs(owner.entries) do e.char = owner.lastChar or self:GetCurrentChar() end
  sv.playerId = ownerId
  sv.own = { rev = owner.rev, entries = owner.entries }
  self.sv.guilds[self:GetCurrentGuild()].owners[ownerId] = nil
  return true
end

-- Maintenance -----------------------------------------------------------------

function Store:PruneByRoster(rosterKeys, complete)
  local removed, owners = {}, self:GetOwners()
  for _, ownerId in ipairs(sortedKeys(owners)) do
    local owner = owners[ownerId]
    local present = false
    for charKey in pairs(owner.chars) do
      if rosterKeys[charKey] then present = true; break end
    end
    if present then
      owner.seenInRoster = true
    elseif complete == true and owner.seenInRoster == true then
      owners[ownerId] = nil
      removed[#removed + 1] = ownerId
    end
  end
  return removed
end

function Store:DropStaleGuildCaches()
  local mine = {}
  for _, c in pairs(self.sv.myChars) do
    if c.guild then mine[c.guild] = true end
  end
  for guild in pairs(self.sv.guilds) do
    if not mine[guild] then self.sv.guilds[guild] = nil end
  end
end

function Store:PruneTombstones()
  local cutoff = self.deps.now() - Const.TOMBSTONE_TTL
  local function prune(entries)
    for id, e in pairs(entries) do
      if e.deleted and e.updated < cutoff then entries[id] = nil end
    end
  end
  prune(self.sv.own.entries)
  for _, g in pairs(self.sv.guilds) do
    for _, owner in pairs(g.owners) do prune(owner.entries) end
  end
end

ns.Store = Store
