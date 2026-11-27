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
assert(Localization.text("Your Zoi cannot ask in this mood.") == "현재 기분으로는 상대에게 제안할 수 없습니다.")
assert(reads == 1, "Toast text uses a cached language read")
time, setting = 4, "pt-BR"
assert(Localization.text("Your Zoi cannot ask in this mood.") == "Seu Zoi não pode fazer esse convite nesse estado de espírito.")
time, setting = 7, false
assert(Localization.culture() == "pt-br", "A transient settings error preserves the last language")
time, setting = 10, "unknown"
assert(Localization.text("Your Zoi cannot ask in this mood.") == "Your Zoi cannot ask in this mood.")
print("Retail language selection, native language-pack aliases, translated toasts and fallback passed.")
