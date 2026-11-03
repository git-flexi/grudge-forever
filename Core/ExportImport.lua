local ADDON, ns = ...

-- Copy/paste backup of the own list: "GF1:" followed by a print-safe codec blob.
local Codec = ns.Codec

local ExportImport = {}

local PREFIX = "GF1:"
local VERSION = 1

function ExportImport.Export(store)
  local rows = {}
  for i, e in ipairs(store:GetOwnEntries()) do
    -- positions: name, list, reason, origin, created, updated
    rows[i] = { e.name, e.list, e.reason, e.origin or e.char, e.created, e.updated }
  end
  return PREFIX .. Codec.Encode({ v = VERSION, e = rows }, "print")
end

-- Returns added, updated; or nil plus "format" / "version".
function ExportImport.Import(store, text)
  if type(text) ~= "string" then return nil, "format" end
  -- pasted text may be wrapped or padded; the payload alphabet has no whitespace
  text = text:gsub("%s+", "")
  if text:sub(1, #PREFIX) ~= PREFIX then return nil, "format" end

  local payload = Codec.Decode(text:sub(#PREFIX + 1), "print")
  if type(payload) ~= "table" or type(payload.e) ~= "table" then return nil, "format" end
  if payload.v ~= VERSION then return nil, "version" end

  local added, updated = 0, 0
  for _, row in ipairs(payload.e) do
    if type(row) == "table" then
      local e = {
        name = row[1], list = row[2], reason = row[3], origin = row[4], created = row[5], updated = row[6],
      }
      local mine = store:GetOwnEntry(e.list, e.name)
      -- a live own entry that is at least as new wins; tombstones are revived by an explicit import
      local stale = mine and not mine.deleted and type(e.updated) == "number" and mine.updated >= e.updated
      if not stale then
        local result = store:ImportEntry(e)
        if result == "added" then
          added = added + 1
        elseif result == "updated" then
          updated = updated + 1
        end
      end
    end
  end
  return added, updated
end

ns.ExportImport = ExportImport
