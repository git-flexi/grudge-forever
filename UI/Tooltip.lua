local ADDON, ns = ...

local Const, L, Names = ns.Const, ns.L, ns.Names

local Tooltip = {}

local MAX_SHOWN = 3
local SEPARATOR = " \226\128\147 " -- en dash
local ORIGIN_SEPARATOR = " \194\183 " -- middle dot

local LIST_ORDER = { Const.LIST_FRIENDLY, Const.LIST_ENEMY }
local LIST_KEYS = { [Const.LIST_FRIENDLY] = "LIST_FRIENDLY", [Const.LIST_ENEMY] = "LIST_ENEMY" }
local HEADER_COLORS = {
  [Const.LIST_FRIENDLY] = { 1, 0.6, 0.2 },
  [Const.LIST_ENEMY] = { 1, 0.25, 0.25 },
}
local LINE_COLOR = { 0.9, 0.9, 0.9 }
local MUTED_COLOR = { 0.5, 0.5, 0.5 }

-- Reasons and names may come from other players, so their pipes are escaped.
local function describe(match)
  local parts = {}
  local reason = match.entry and match.entry.reason
  if reason and reason ~= "" then parts[#parts + 1] = Names.Escape(reason) end

  local origin = {}
  if match.by and match.by ~= "" then origin[#origin + 1] = L["TOOLTIP_BY"]:format(Names.Escape(match.by)) end
  local from = match.entry and match.entry.origin
  if from and from ~= "" then origin[#origin + 1] = L["TOOLTIP_ADOPTED_FROM"]:format(Names.Escape(from)) end
  if #origin > 0 then parts[#parts + 1] = table.concat(origin, ORIGIN_SEPARATOR) end

  local text = table.concat(parts, SEPARATOR)
  if match.muted then text = text .. " (" .. L["TOOLTIP_MUTED"] .. ")" end
  return text
end

-- matches: Store:Lookup results, possibly for both lists. Returns { {text, r, g, b} ... }.
function Tooltip.BuildLines(matches)
  local byList = { [Const.LIST_FRIENDLY] = {}, [Const.LIST_ENEMY] = {} }
  for _, m in ipairs(matches) do
    local bucket = m.entry and byList[m.entry.list]
    if bucket then bucket[#bucket + 1] = m end
  end

  local lines = {}
  for _, list in ipairs(LIST_ORDER) do
    local group = byList[list]
    if #group > 0 then
      local c = HEADER_COLORS[list]
      lines[#lines + 1] = { text = L["TOOLTIP_HEADER"]:format(L[LIST_KEYS[list]]), r = c[1], g = c[2], b = c[3] }
      for i = 1, math.min(#group, MAX_SHOWN) do
        local color = group[i].muted and MUTED_COLOR or LINE_COLOR
        lines[#lines + 1] = { text = describe(group[i]), r = color[1], g = color[2], b = color[3] }
      end
      if #group > MAX_SHOWN then
        lines[#lines + 1] = { text = L["TOOLTIP_MORE"]:format(#group - MAX_SHOWN),
                              r = LINE_COLOR[1], g = LINE_COLOR[2], b = LINE_COLOR[3] }
      end
    end
  end
  return lines
end

function Tooltip.Install(store)
  if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
          and Enum and Enum.TooltipDataType) then
    return
  end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
    if not tooltip or not tooltip.GetUnit then return end
    local _, unit = tooltip:GetUnit()
    if unit == nil or Names.IsSecret(unit) then return end
    local name = Names.FromUnit(unit)
    if not name then return end
    for _, line in ipairs(Tooltip.BuildLines(store:Lookup(name))) do
      tooltip:AddLine(line.text, line.r, line.g, line.b)
    end
  end)
end

ns.Tooltip = Tooltip
