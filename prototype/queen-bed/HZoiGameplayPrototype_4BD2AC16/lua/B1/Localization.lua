local Json = require("SceneZOIAddon.Json")
local Translations = require("Translations")
local M = {}
local language, nextRead = "en-us", 0
local aliases = {en = "en-us", ko = "ko-kr", zh = "zh-cn", ["zh-hans"] = "zh-cn", ["zh-hant"] = "zh-tw"}

function M.culture()
    local now = os.time()
    if now < nextRead then return language end
    nextRead = now + 2
    local called, ok, _, raw = pcall(inzoi.cli.execute, "gameplay.get_settings")
    if called and ok and type(raw) == "string" then
        local decoded, settings = pcall(Json.decode, raw, 8192)
        local name = decoded and type(settings) == "table" and (settings.language or settings.Language)
        if type(name) == "string" then
            name = name:lower():gsub("_", "-"):gsub("-mod$", "")
            language = aliases[name] or name
        end
    end
    return language
end

function M.text(english, values)
    local strings = Translations[M.culture()]
    local message = strings and strings[english] or english
    return (message:gsub("{([%w_]+)}", function(name)
        return values and values[name] or "{" .. name .. "}"
    end))
end

return M
