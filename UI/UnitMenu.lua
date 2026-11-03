local ADDON, ns = ...

local Const, L, Names = ns.Const, ns.L, ns.Names

local UnitMenu = {}

UnitMenu.TAGS = {
  "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
  "MENU_UNIT_FRIEND", "MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_CHAT_ROSTER",
}

local LISTS = { Const.LIST_FRIENDLY, Const.LIST_ENEMY }

-- Full name of the player a menu was opened on, or nil when it is unknown, secret or the own character.
-- currentChar: name of the own current character (optional).
function UnitMenu.NameFromContext(contextData, currentChar)
  if type(contextData) ~= "table" then return nil end
  local name
  local unit = contextData.unit
  if unit ~= nil then
    if Names.IsSecret(unit) then return nil end
    name = Names.FromUnit(unit)
  else
    -- chat and guild entries may carry "First-Surname" in name
    name = Names.Display(Names.Join(contextData.name, contextData.surname))
  end
  if not name then return nil end
  local own = currentChar and Names.Normalize(currentChar)
  if own and Names.Normalize(name) == own then return nil end
  return name
end

-- Enemy faction means both factions are known and differ.
local function isOtherFaction(unit)
  if unit == nil or Names.IsSecret(unit) then return false end
  local theirs, mine = UnitFactionGroup(unit), UnitFactionGroup("player")
  if type(theirs) ~= "string" or type(mine) ~= "string" then return false end
  if Names.IsSecret(theirs) or Names.IsSecret(mine) then return false end
  return theirs ~= mine
end

-- Returns { {labelKey, kind, list} ... }: "add", "edit" (own entry) or "mute"/"unmute" (foreign entries only).
function UnitMenu.Actions(store, name, tag, unit)
  local actions = {}
  local foreign = {}
  for _, list in ipairs(LISTS) do
    local matches = store:Lookup(name, list)
    local own = false
    for _, m in ipairs(matches) do
      if m.isOwn then own = true end
    end
    if own then
      actions[#actions + 1] = { labelKey = "MENU_EDIT", kind = "edit", list = list }
    elseif #matches > 0 then
      foreign[#foreign + 1] = list
    end
  end
  if #actions > 0 then return actions end

  for _, list in ipairs(foreign) do
    local muted = store:IsMuted(list, name)
    actions[#actions + 1] = {
      labelKey = muted and "MENU_UNMUTE" or "MENU_MUTE", kind = muted and "unmute" or "mute", list = list,
    }
  end
  if #actions > 0 then return actions end

  local list = (tag == "MENU_UNIT_ENEMY_PLAYER" or isOtherFaction(unit)) and Const.LIST_ENEMY or Const.LIST_FRIENDLY
  return { { labelKey = "MENU_ADD", kind = "add", list = list } }
end

local function run(store, name, action)
  if action.kind == "mute" or action.kind == "unmute" then
    store:SetMuted(action.list, name, action.kind == "mute")
    return
  end
  local dialog = ns.UI and ns.UI.EditDialog
  if not dialog or not dialog.Open then return end
  local entry = action.kind == "edit" and store:GetOwnEntry(action.list, name) or nil
  dialog.Open(name, action.list, entry)
end

function UnitMenu.Install(store)
  if not (Menu and Menu.ModifyMenu) then return end
  for _, tag in ipairs(UnitMenu.TAGS) do
    Menu.ModifyMenu(tag, function(_, rootDescription, contextData)
      local name = UnitMenu.NameFromContext(contextData, store:GetCurrentChar())
      if not name then return end
      rootDescription:CreateDivider()
      rootDescription:CreateTitle(L["ADDON_TITLE"])
      for _, action in ipairs(UnitMenu.Actions(store, name, tag, contextData.unit)) do
        rootDescription:CreateButton(L[action.labelKey], function() run(store, name, action) end)
      end
    end)
  end
end

ns.UnitMenu = UnitMenu
