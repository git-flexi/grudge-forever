local ADDON, ns = ...

-- Shared wire format: AceSerializer -> raw deflate -> channel/print-safe text.
-- "comm" suits addon channels, "print" survives chat and copy/paste.
local Codec = {}

local function libs()
  return LibStub("AceSerializer-3.0"), LibStub("LibDeflate")
end

function Codec.Encode(tbl, mode)
  local serializer, deflate = libs()
  local compressed = deflate:CompressDeflate(serializer:Serialize(tbl))
  if mode == "comm" then
    return deflate:EncodeForWoWAddonChannel(compressed)
  end
  return deflate:EncodeForPrint(compressed)
end

-- Returns the decoded value, or nil plus "decode" / "decompress" / "deserialize".
function Codec.Decode(str, mode)
  if type(str) ~= "string" then return nil, "decode" end
  local serializer, deflate = libs()
  local compressed
  if mode == "comm" then
    compressed = deflate:DecodeForWoWAddonChannel(str)
  else
    compressed = deflate:DecodeForPrint(str)
  end
  if not compressed then return nil, "decode" end
  local serialized = deflate:DecompressDeflate(compressed)
  if not serialized then return nil, "decompress" end
  local ok, value = serializer:Deserialize(serialized)
  if not ok then return nil, "deserialize" end
  return value
end

ns.Codec = Codec
