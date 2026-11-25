-- B1 reads the player's native language, including a language-pack selection.
package.path = "HZoiGameplayPrototype_4BD2AC16/lua/B1/?.lua;" .. package.path
local time, reads, setting = 1, 0, "ko-KR_mod"
local Json = require("SceneZOIAddon.Json")
os.time = function() return time end
inzoi = {cli = {execute = function(command)
    assert(command == "gameplay.get_settings")
    reads = reads + 1
    if setting == false then error("Settings unavailable") end
    return true, "", Json.encode({language = setting})
end}}
local Localization = require("Localization")
assert(Localization.culture() == "ko-kr")
assert(Localization.text("Have sex here") == "여기서 성관계하기")
assert(reads == 1, "Menu text uses a cached language read")
time, setting = 4, "pt-BR"
assert(Localization.text("Your Zoi wants some private time with {partner}.", {partner = "Ana%Do"})
    == "Seu Zoi quer um tempo a sós com Ana%Do.")
time, setting = 7, false
assert(Localization.culture() == "pt-br", "A transient settings error preserves the last language")
time, setting = 10, "unknown"
assert(Localization.text("Have sex here") == "Have sex here")
print("Retail language selection, native language-pack aliases, toast formatting and fallback passed.")
