local ADDON, ns = ...

-- Missing keys return the key itself, so untranslated strings stay readable.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

L["ADDON_TITLE"] = "GrudgeForever"
L["ADDON_NOTES"] = "Keep a list of players you hold a grudge against, and friends you like - shared with your friends."
