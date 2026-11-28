local Json = require("SceneZOIAddon.Json")
local Trace = require("WitnessTrace")
local Localization = require("Localization")
local M = {}

local function coordinate(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

local function characterId(value)
    return type(value) == "string" and #value <= 20 and value:match("^[1-9]%d*$") ~= nil
end

function M.reply(owner, raw)
    local ok, query = pcall(Json.decode, raw, 8192)
    if not ok or type(query) ~= "table" or type(query.token) ~= "string" or #query.token > 100
        or type(query.revision) ~= "number" or type(query.participants) ~= "table"
        or #query.participants < 2 or #query.participants > 32 then return end
    if query.kind ~= nil and query.kind ~= "arrival" then return end
    local arrival = query.kind == "arrival"
    if arrival and type(query.points) ~= "table" then return end
    local seen = {}
    for _, id in ipairs(query.participants) do
        if not characterId(id) or seen[id] then return end
        seen[id] = true
        if arrival then
            local point = query.points[id]
            if type(point) ~= "table" or not (coordinate(point.x) and coordinate(point.y) and coordinate(point.z)) then
                return
            end
        end
    end
    local baseline
    if query.baseline ~= nil then
        if arrival or type(query.baseline) ~= "table" or #query.baseline > 128 then return end
        baseline = {}
        for _, id in ipairs(query.baseline) do
            if not characterId(id) or seen[id] or baseline[id] then return end
            baseline[id] = true
        end
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
        return Trace.sample(characters, query.participants, query.revision, arrival and query.points or nil,
            baseline, baseline ~= nil and query.arrival_reactions == true)
    end

    local sampled, rows, diagnostic, baselineAbsent, baselineVisible = pcall(sample)
    local reply = {kind = query.kind, token = query.token, revision = query.revision, language = Localization.culture()}
    if sampled then
        reply.observations = Json.array(rows)
        reply.diagnostic = diagnostic
        if baselineAbsent and baseline then reply.baseline_absent = Json.array(baselineAbsent) end
        reply.baseline_visible = baselineVisible
    else
        reply.diagnostic = tostring(rows):sub(1, 150)
    end
    inzoi.message.send_to_sim(owner:GetEntityId(), "HZoiGameplay.WitnessResult", Json.encode(reply))
end

return M
