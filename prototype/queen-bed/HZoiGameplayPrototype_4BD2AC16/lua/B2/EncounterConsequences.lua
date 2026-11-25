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
    all = "HZoiGameplay_InSync",
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

local function defaultMoodlet(own, anyCompleted, allCompleted, result, unfamiliarStop)
    if allCompleted then return MOODLET.all end
    if own then return MOODLET.own end
    if anyCompleted then return MOODLET.other end
    local origin = result.stop_origin or {}
    if unfamiliarStop then
        return MOODLET.witnessed
    end
    if result.stop_reason == "ok" and origin.source == "framework" then
        return MOODLET.manual_exit
    end
end

local function addMoodlet(encounter, who, person, moodlet)
    local requested = NativeWitness.addMoodlet(person, moodlet)
    log(requested and "outcome_moodlet_queued" or "outcome_moodlet_unavailable", encounter, who, {buff_id = moodlet})
end

local function hasLowHygiene(person)
    local stats = person:GetComponent(inzoi.EB2ComponentType.Stat)
    local system = inzoi.getB2Subsystem("FB2StatSystem")
    if not stats or not system or not stats:HasStat("Cleanliness") then return false end
    local minimum = system:Clamp("Cleanliness", -STAT_BOUND_PROBE)
    local maximum = system:Clamp("Cleanliness", STAT_BOUND_PROBE)
    return stats:GetStat("Cleanliness") <= minimum + (maximum - minimum) * NEED_FLOOR
end

local function applyOutcomeFor(encounter, result, who, anyCompleted, allCompleted)
    local person = actor(who)
    if not person then return end
    local function hasTrait(trait)
        return NativeWitness.hasTrait(person, trait)
    end
    local own = completed(encounter, who)
    local origin = result.stop_origin or {}
    local witnesses = encounter.witnessPolicy or {}
    local incidents = witnesses.incidents or {}
    local official = origin.reason == "caught_by_partner" or #incidents > 0
    local caught = false
    for _, incident in ipairs(incidents) do
        if incident.cheater_id == who then caught = true; break end
    end
    local ordinaryStop = result.stop_reason == "addon_requested" and origin.reason == "witness_sighting"
    local ordinary = witnesses.ordinary_sighting == true
    local unfamiliar = witnesses.ordinary_unfamiliar or {}
    local stoppingUnfamiliar = witnesses.ordinary_stop_unfamiliar or {}
    local unfamiliarStop = ordinaryStop and stoppingUnfamiliar[who] == true
    local selected = Traits.select(hasTrait, {
        self_completed = own, any_completed = anyCompleted, all_completed = allCompleted,
        furniture = encounter.furniture ~= nil,
        player_exit = result.stop_reason == "ok" and origin.source == "framework",
        low_hygiene = own and hasTrait("CleanFreak") and hasLowHygiene(person),
        seen = ordinary or official, ordinary_sighting = ordinary, ordinary_stop = ordinaryStop,
        ordinary_unfamiliar = unfamiliar[who] == true, ordinary_stop_unfamiliar = unfamiliarStop,
        official_sighting = official, caught_by_own_partner = caught,
    })

    local outcome, reaction = selected.outcome, selected.witness
    if not official then
        local moodlet = Traits.buffId(outcome, hasTrait)
            or defaultMoodlet(own, anyCompleted, allCompleted, result, unfamiliarStop)
        if not outcome and (moodlet == MOODLET.all or moodlet == MOODLET.own) and hasTrait("Romantic") then
            moodlet = moodlet .. "_Romantic"
        end
        if moodlet and (not reaction or moodlet ~= MOODLET.witnessed) then addMoodlet(encounter, who, person, moodlet) end
    end
    if reaction then addMoodlet(encounter, who, person, reaction.buff_id) end
end

function M.onResult(encounter, result)
    local count = 0
    for _, who in ipairs(encounter.participants) do
        if completed(encounter, who) then count = count + 1 end
    end
    local anyCompleted = count > 0
    local allCompleted = count == #encounter.participants
    for _, who in ipairs(encounter.participants) do
        local ok, err = pcall(applyOutcomeFor, encounter, result, who, anyCompleted, allCompleted)
        if not ok then log("outcome_moodlet_failed", encounter, who, {error = tostring(err)}) end
    end
end

return M
