local ADDON, ns = ...

-- Who in the guild runs GrudgeForever: the guild roster joined with the members the addon knows
-- (from their hellos or from entry data passed along by others). Pure logic, no WoW APIs.
local Names = ns.Names

local GuildMembers = {}

-- roster = { { name, online } ... }; owners = Store:GetOwners(); me = { chars = { key -> display },
-- version, now }. Returns rows { name, key, online, hasAddon, version, seen, isMe }, sorted.
function GuildMembers.Build(roster, owners, me)
  local known = {}
  for _, owner in pairs(owners) do
    for key in pairs(owner.chars or {}) do known[key] = owner end
    local last = Names.Normalize(owner.lastChar)
    if last then known[last] = owner end
  end

  local rows, index = {}, {}
  for _, member in ipairs(roster) do
    local key = Names.Normalize(member.name)
    if key then
      local row = index[key]
      if row then
        row.online = row.online or member.online == true
      else
        row = { name = Names.Display(member.name), key = key, online = member.online == true, hasAddon = false }
        local owner = known[key]
        if me.chars[key] then
          row.hasAddon, row.version, row.seen, row.isMe = true, me.version, me.now, true
        elseif owner then
          row.hasAddon, row.version, row.seen = true, owner.version, owner.seen
        end
        index[key] = row
        rows[#rows + 1] = row
      end
    end
  end

  table.sort(rows, function(a, b)
    if a.online ~= b.online then return a.online end
    if a.hasAddon ~= b.hasAddon then return a.hasAddon end
    return a.key < b.key
  end)
  return rows
end

-- Returns members with the addon, all members.
function GuildMembers.Count(rows)
  local withAddon = 0
  for _, row in ipairs(rows) do
    if row.hasAddon then withAddon = withAddon + 1 end
  end
  return withAddon, #rows
end

ns.GuildMembers = GuildMembers
