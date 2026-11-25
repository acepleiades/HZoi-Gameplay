local Json = require("SceneZOIAddon.Json")
local Traits = require("TraitOutcomes")
local NativeWitness = require("WitnessNative")

local M = {}

local NEED_CHANGES = {
    {id = "Hunger", change = -12.5},
    {id = "Cleanliness", change = -12.5},
    {id = "Energy", change = -12.5},
    {id = "Fun", change = 5},
    {id = "Society", change = 5},
}
local NEED_FLOOR = 0.33
local STAT_BOUND_PROBE = 1e9
local MOODLET = {
    both = "HZoiGameplay_InSync",
    own = "HZoiGameplay_Satisfied",
    other = "HZoiGameplay_OutOfSync",
    witnessed = "HZoiGameplay_AwkwardTiming",
    manual_exit = "HZoiGameplay_UnfinishedMoment",
}

local function actor(who)
    local id = inzoi.FB1EntityId()
    id.Value = tonumber(who)
    return inzoi.getB2Manager("FB2EntityManager"):FindCharacter(id)
end

local function log(event, encounter, who, details)
    details.session_id = encounter.session_id
    details.participant_id = who
    print("[HZoiGameplay] " .. event .. " " .. Json.encode(details))
end

local function applyNeed(system, stats, need)
    if not stats:HasStat(need.id) then return end
    local current = stats:GetStat(need.id)
    local minimum = system:Clamp(need.id, -STAT_BOUND_PROBE)
    local maximum = system:Clamp(need.id, STAT_BOUND_PROBE)
    assert(minimum < maximum and current == current, "Invalid need value or range")
    local target
    if need.change < 0 then
        local floor = minimum + (maximum - minimum) * NEED_FLOOR
        target = math.max(current + need.change, math.min(floor, current))
    else
        target = math.min(current + need.change, maximum)
    end
    if target ~= current then
        -- Use an absolute target to keep the floor and cap even when native modifiers affect relative gains/losses.
        stats:SetStat(need.id, target, inzoi.EB1ScriptReason.Interaction)
        return {before = current, target = target, after = stats:GetStat(need.id)}
    end
end

function M.onCompletion(encounter, who, taskId, index)
    if taskId ~= "excitement" then return end
    local person = actor(who)
    local system = inzoi.getB2Subsystem("FB2StatSystem")
    local stats = person and person:GetComponent(inzoi.EB2ComponentType.Stat)
    if not (stats and system) then
        log("completion_needs_unavailable", encounter, who, {index = index})
        return
    end
    local changes = {}
    for _, need in ipairs(NEED_CHANGES) do
        local ok, result = pcall(applyNeed, system, stats, need)
        if ok then
            changes[need.id] = result
        else
            changes[need.id] = {error = tostring(result)}
        end
    end
    log("completion_needs", encounter, who, {index = index, changes = changes})
end

local function completed(encounter, who)
    local counts = encounter.completions[who]
    return counts ~= nil and (counts.excitement or 0) > 0
end

local function defaultMoodlet(own, other, result)
    if own and other then return MOODLET.both end
    if own then return MOODLET.own end
    if other then return MOODLET.other end
    local origin = result.stop_origin or {}
    if result.stop_reason == "addon_requested" and origin.reason == "witness_sighting" then
        return MOODLET.witnessed
    end
    if result.stop_reason == "ok" and origin.source == "framework" then
        return MOODLET.manual_exit
    end
end

local function addMoodlet(encounter, who, moodlet)
    local person = actor(who)
    local buffs = person and person:GetComponent(inzoi.EB2ComponentType.Buff)
    if not buffs then
        log("outcome_moodlet_unavailable", encounter, who, {buff_id = moodlet})
        return
    end
    buffs:AddBuff(moodlet)
    log("outcome_moodlet_queued", encounter, who, {buff_id = moodlet})
end

local function hasLowHygiene(person)
    local stats = person:GetComponent(inzoi.EB2ComponentType.Stat)
    local system = inzoi.getB2Subsystem("FB2StatSystem")
    if not stats or not system or not stats:HasStat("Cleanliness") then return false end
    local minimum = system:Clamp("Cleanliness", -STAT_BOUND_PROBE)
    local maximum = system:Clamp("Cleanliness", STAT_BOUND_PROBE)
    return stats:GetStat("Cleanliness") <= minimum + (maximum - minimum) * NEED_FLOOR
end

local function applyOutcomeFor(encounter, result, who, partner)
    local person = actor(who)
    if not person then return end
    local function hasTrait(trait)
        return NativeWitness.hasTrait(person, trait)
    end
    local own, other = completed(encounter, who), completed(encounter, partner)
    local origin = result.stop_origin or {}
    local witnesses = encounter.witnessPolicy or {}
    local incidents = witnesses.incidents or {}
    local official = origin.reason == "caught_by_partner" or #incidents > 0
    local caught = false
    for _, incident in ipairs(incidents) do
        if incident.cheater_id == who then caught = true; break end
    end
    local ordinaryStop = result.stop_reason == "addon_requested" and origin.reason == "witness_sighting"
    local ordinary = witnesses.ordinary_sighting == true or ordinaryStop
    local outcome, reaction = Traits.select(hasTrait, {
        self_completed = own, partner_completed = other, furniture = encounter.furniture ~= nil,
        player_exit = result.stop_reason == "ok" and origin.source == "framework",
        low_hygiene = own and hasTrait("CleanFreak") and hasLowHygiene(person),
        seen = ordinary or official, ordinary_sighting = ordinary, ordinary_stop = ordinaryStop,
        caught_by_own_partner = caught,
    })

    if not official then
        local moodlet = Traits.buffId(outcome, hasTrait) or defaultMoodlet(own, other, result)
        if not outcome and (moodlet == MOODLET.both or moodlet == MOODLET.own) and hasTrait("Romantic") then
            moodlet = moodlet .. "_Romantic"
        end
        if moodlet and (not reaction or moodlet ~= MOODLET.witnessed) then addMoodlet(encounter, who, moodlet) end
    end
    if reaction then addMoodlet(encounter, who, reaction.buff_id) end
end

function M.onResult(encounter, result)
    local first, second = encounter.participants[1], encounter.participants[2]
    for _, pair in ipairs({{first, second}, {second, first}}) do
        local who, partner = pair[1], pair[2]
        local ok, err = pcall(applyOutcomeFor, encounter, result, who, partner)
        if not ok then log("outcome_moodlet_failed", encounter, who, {error = tostring(err)}) end
    end
end

return M
