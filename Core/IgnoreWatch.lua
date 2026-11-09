local ADDON, ns = ...

-- Puts players the user ignores on the Blacklist. The client's ignore list itself only shows
-- Battle.net accounts, so the character name is taken from the ignore call as it happens.
local Const, L, Names = ns.Const, ns.L, ns.Names

local IgnoreWatch = { REASON = "IgnoreList Import" }

local Watch = {}
Watch.__index = Watch

-- deps = { store, change = fn(fn(store)), isIgnored = fn(name) -> bool, print = fn(text) }
function IgnoreWatch.New(deps)
  return setmetatable({ deps = deps, pending = {} }, Watch)
end

-- C_FriendList.AddIgnore / AddOrDelIgnore was called with name. Whether it added or removed the
-- player is only known once the ignore list has updated.
function Watch:OnIgnoreCall(name)
  local display = Names.Display(name)
  -- a first name alone does not identify a player
  if not display or not display:find(" ", 1, true) then return end
  self.pending[#self.pending + 1] = { call = name, name = display }
end

function Watch:OnIgnoreListUpdate()
  local pending = self.pending
  if #pending == 0 then return end
  self.pending = {}
  local deps = self.deps
  for _, p in ipairs(pending) do
    local own = deps.store:GetOwnEntry(Const.LIST_FRIENDLY, p.name)
    if deps.isIgnored(p.call) and not (own and not own.deleted) then
      deps.change(function(store) return store:AddOrUpdate(Const.LIST_FRIENDLY, p.name, IgnoreWatch.REASON) end)
      deps.print(L["IGNORE_ADDED"]:format(Names.Escape(p.name)))
    end
  end
end

ns.IgnoreWatch = IgnoreWatch
