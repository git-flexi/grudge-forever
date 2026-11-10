# Bundled libraries

Only the Lua/XML files needed at runtime are copied (no tests or docs).

| Library | Source | Commit | Files |
|---|---|---|---|
| LibStub, CallbackHandler-1.0, AceComm-3.0 (incl. ChatThrottleLib), AceSerializer-3.0 | https://github.com/WoWUIDev/Ace3 | `ac3d1225037e0dc74e025a72342c0f7824aae147` | `LibStub/`, `CallbackHandler-1.0/`, `AceComm-3.0/`, `AceSerializer-3.0/` |
| LibDeflate | https://github.com/SafeteeWoW/LibDeflate | `afc3b78d12fb3bcfa6b21e5332031ad3d7572e19` | `LibDeflate/LibDeflate.lua`, `LibDeflate/lib.xml` |
| LibSharedMedia-3.0 | https://github.com/Questie/Questie | `56f32655b17a109e8020a04250eb61cee28a3455` | `LibSharedMedia-3.0/` (from `Libs/LibSharedMedia-3.0/`) |
| LibDataBroker-1.1, LibDBIcon-1.0 | https://github.com/Questie/Questie | `26111d10ed0990d57fd9f59b725798affb8d55ad` | `LibDataBroker-1.1/LibDataBroker-1.1.lua`, `LibDBIcon-1.0/LibDBIcon-1.0.lua`, `LibDBIcon-1.0/lib.xml` |

Licenses:

| Library | License | Where |
|---|---|---|
| LibStub, CallbackHandler-1.0, AceComm-3.0, AceSerializer-3.0 | BSD-style (Ace3) | `LICENSE-Ace3.txt` |
| LibDeflate | zlib | `LICENSE-LibDeflate.txt` |
| LibSharedMedia-3.0 | LGPL v2.1 (header of `LibSharedMedia-3.0.lua`) | `LICENSE-LibSharedMedia.txt` |
| LibDBIcon-1.0 | BSD-style (Ace3), as stated on its [CurseForge page](https://www.curseforge.com/wow/addons/libdbicon-1-0); upstream ships no license file | – |
| LibDataBroker-1.1 | All rights reserved, as stated on its [CurseForge page](https://www.curseforge.com/wow/addons/libdatabroker-1-1); made to be embedded and shipped by addons; upstream ships no license file | – |

The packager lists every library as an embedded library of the CurseForge project (`.pkgmeta`).
