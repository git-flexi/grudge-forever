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

-- The id Adopt takes for a single entry.
function Store.EntryId(list, key)
  return entryId(list, key)
end

-- Shared validators: Sync checks untrusted messages with the same rules.

-- A finite, non-negative number (rejects NaN and ±inf).
function Store.IsCount(v)
  return type(v) == "number" and v == v and v >= 0 and v < math.huge
end

-- A short version string such as "0.3.0" or "1.2.0-beta".
function Store.IsVersion(v)
  return type(v) == "string" and not Names.IsSecret(v) and #v <= 20 and v:find("^[%w%.%-]+$") ~= nil
end

function Store.IsList(list)
  return isList(list)
end

function Store.IsValidReason(reason)
  return type(reason) == "string" and not Names.IsSecret(reason) and charLength(reason) <= Const.REASON_MAX
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
    e.created, e.origin, e.originGuild = now, nil, nil
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

-- The own entry for a list/name, tombstones included.
function Store:GetOwnEntry(list, name)
  local key = Names.Normalize(name)
  if not key or not isList(list) then return nil end
  return self.sv.own.entries[entryId(list, key)]
end

-- Writes an entry from an import row ({ name, list, reason, origin, created, updated }).
-- It becomes an own entry of the current character; created/updated are kept.
-- Returns "added" / "updated", or nil plus an error key for invalid rows.
function Store:ImportEntry(e)
  if not isList(e.list) then return nil, "invalid_list" end
  local key = Names.Normalize(e.name)
  if not key then return nil, "invalid_name" end
  if not Store.IsValidReason(e.reason) then return nil, "invalid_reason" end
  -- a bad time would sort wrong and poison every later full delta of the own entries
  if not Store.IsCount(e.created) or not Store.IsCount(e.updated) then return nil, "invalid_time" end

  -- a creator that is one of our own characters is no origin
  local origin = Names.Display(e.origin)
  if origin and self.sv.myChars[Names.Normalize(origin)] then origin = nil end

  local own = self.sv.own
  local id = entryId(e.list, key)
  local existing = own.entries[id]
  local result = (existing and not existing.deleted) and "updated" or "added"

  own.rev = own.rev + 1
  own.entries[id] = {
    key = key, name = Names.Display(e.name), list = e.list, reason = e.reason, char = self:GetCurrentChar(),
    origin = origin, created = e.created, updated = e.updated, rev = own.rev, deleted = false,
  }
  return result
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
        origin = e.origin or owner.lastChar, originGuild = self:GetCurrentGuild(),
        created = e.created or now, updated = now, rev = rev, deleted = false,
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
  local isOwn = ownerId == self.sv.playerId
  if isOwn then
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
  for i, e in ipairs(list) do
    entries[i] = copyEntry(e, false)
    -- an own origin names a creator of the guild it was adopted in; imported origins stay local
    if isOwn and e.originGuild ~= self:GetCurrentGuild() then entries[i].origin = nil end
  end

  return { o = ownerId, rev = src.rev, base = sinceRev, chars = chars, lastChar = lastChar, e = entries }
end

-- Expects a well-formed delta; Sync validates untrusted messages first.
-- A full delta (base 0) of another owner is that owner's whole state and replaces the cached entries,
-- so entries whose tombstones the owner already dropped do not live on here. Own entries are always
-- merged: local ones must never be lost to a relayed state.
function Store:ApplyDelta(delta)
  local ownerId = delta.o
  local isOwn = ownerId == self.sv.playerId
  if not isOwn and not self:GetCurrentGuild() then return "stale" end

  local known = self:GetRev(ownerId)
  if delta.rev <= known then return "stale" end
  if delta.base > known then return "need_full" end

  local target = isOwn and self.sv.own or self:ownerFor(ownerId)
  if not isOwn and delta.base == 0 then target.entries = {} end
  for _, e in ipairs(delta.e or {}) do
    local id = entryId(e.list, e.key)
    local existing = target.entries[id]
    local fresh = copyEntry(e, false)
    if isOwn then
      -- the local creator character survives; entries new to this device get the sender's character
      fresh.char = existing and existing.char or delta.lastChar
      if fresh.origin then
        -- the sender only shares origins of this guild
        fresh.originGuild = self:GetCurrentGuild()
      elseif existing and existing.origin and existing.created == fresh.created then
        -- same entry, but its origin is not shared here: keep the local one
        fresh.origin, fresh.originGuild = existing.origin, existing.originGuild
      end
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

  for _, e in pairs(owner.entries) do
    e.char = owner.lastChar or self:GetCurrentChar()
    -- the guild shared these origins, so they belong to it
    if e.origin then e.originGuild = self:GetCurrentGuild() end
  end
  sv.playerId = ownerId
  sv.own = { rev = owner.rev, entries = owner.entries }
  self.sv.guilds[self:GetCurrentGuild()].owners[ownerId] = nil
  return true
end

-- A member said hello on the guild channel, which proves it is in the guild: learn its characters
-- (also a twink no data mentioned yet), remember the speaking one for "by", and take it back if it
-- was pruned. charList: display names; char: the speaking character.
-- version: the addon version the member sent (only newer addons send one).
function Store:NoteMember(ownerId, charList, char, version)
  if ownerId == self.sv.playerId then return end
  local owner = self:ownerFor(ownerId)
  if not owner then return end
  owner.seen = self.deps.now()
  if Store.IsVersion(version) then owner.version = version end
  for _, name in ipairs(charList or {}) do
    local key = Names.Normalize(name)
    if key then owner.chars[key] = Names.Display(name) end
  end
  local key = Names.Normalize(char)
  if key then
    owner.chars[key] = Names.Display(char)
    owner.lastChar = Names.Display(char)
  end
  local g = self.sv.guilds[self:GetCurrentGuild()]
  if g.pruned then g.pruned[ownerId] = nil end
end

-- Maintenance -----------------------------------------------------------------

local function anyInRoster(chars, rosterKeys)
  for charKey in pairs(chars) do
    if rosterKeys[charKey] then return true end
  end
  return false
end

-- Whether the owner was pruned from the current guild (it left); Sync neither requests nor applies it.
function Store:IsPruned(ownerId)
  local guild = self:GetCurrentGuild()
  local g = guild and self.sv.guilds[guild]
  return g ~= nil and g.pruned ~= nil and g.pruned[ownerId] ~= nil
end

function Store:PruneByRoster(rosterKeys, complete)
  local removed = {}
  local guild = self:GetCurrentGuild()
  local g = guild and self.sv.guilds[guild]
  if not g then return removed end
  complete = complete == true
  -- our own character in a complete roster proves the roster uses our name format
  local verified = self.currentKey ~= nil and rosterKeys[self.currentKey] ~= nil
  for _, ownerId in ipairs(sortedKeys(g.owners)) do
    local owner = g.owners[ownerId]
    if anyInRoster(owner.chars, rosterKeys) then
      owner.seenInRoster = true
    elseif complete and (verified or owner.seenInRoster == true) then
      g.owners[ownerId] = nil
      g.pruned = g.pruned or {}
      g.pruned[ownerId] = { at = self.deps.now(), chars = copyMap(owner.chars) }
      removed[#removed + 1] = ownerId
    end
  end
  if complete and g.pruned then
    for ownerId, p in pairs(g.pruned) do
      -- a returning member is welcome again
      if anyInRoster(p.chars, rosterKeys) then g.pruned[ownerId] = nil end
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
    for ownerId, p in pairs(g.pruned or {}) do
      if p.at < cutoff then g.pruned[ownerId] = nil end
    end
  end
end

ns.Store = Store
