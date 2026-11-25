local Json = require("SceneZOIAddon.Json")
local Trace = require("WitnessTrace")
local M = {}

function M.reply(owner, raw)
    local ok, query = pcall(Json.decode, raw, 4096)
    if not ok or type(query) ~= "table" or type(query.token) ~= "string" or #query.token > 100
        or type(query.revision) ~= "number" or type(query.participants) ~= "table"
        or #query.participants ~= 2 then return end
    for _, id in ipairs(query.participants) do
        if type(id) ~= "string" or not id:match("^%d+$") then return end
    end

    local function sample()
        local system = inzoi.UB1System.Get()
        local manager = system and system.ManagerMap:Find(inzoi.EB1ManagerType.Entity)
        if not manager then return {}, "entity_manager_unavailable" end
        local characters = {}
        for id, actor in pairs(manager.CharacterMap:ToTable()) do
            local value = type(id) == "number" and id or id.Value
            if value and actor then characters[tostring(value)] = actor end
        end
        return Trace.sample(characters, query.participants, query.revision)
    end

    local sampled, rows, diagnostic = pcall(sample)
    local reply = {token = query.token, revision = query.revision}
    if sampled then
        reply.observations = Json.array(rows)
        reply.diagnostic = diagnostic
    else
        reply.diagnostic = tostring(rows):sub(1, 150)
    end
    inzoi.message.send_to_sim(owner:GetEntityId(), "HZoiGameplay.WitnessResult", Json.encode(reply))
end

return M
