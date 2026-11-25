local Client = require("SceneZOIAddon.Client")

local M = {}
local intimate = {non_penetrative = true, penetrative_non_coital = true, coital = true}
local prefersStop = {
    "Perfectionist", "Helper", "Risk-averse", "Arrogant", "Peacemaker", "Introvert", "Faithful",
}

function M.stopVotes(participantIds, official, hasTrait, unfamiliar)
    local roster, stops, total = {}, 0, 0
    for _, id in ipairs(participantIds) do
        if not roster[id] then
            roster[id] = true
            total = total + 1
            if (official or not unfamiliar or unfamiliar[id])
                and not (hasTrait(id, "Cooperator") or hasTrait(id, "Flirt")) then
                local stop = official
                if not stop then
                    for _, trait in ipairs(prefersStop) do
                        if hasTrait(id, trait) then stop = true; break end
                    end
                end
                if stop then stops = stops + 1 end
            end
        end
    end
    return stops, total
end

function M.actionPairs(snapshot, definitions, roster)
    local pairs = {}
    if snapshot.phase ~= "playing" or snapshot.game_scale == 0 then return pairs end
    for _, action in ipairs(Client.actions(snapshot)) do
        local descriptor = definitions[action.type]
        if descriptor and intimate[descriptor.sexual_activity]
            and action.actor ~= action.target and roster[action.actor] and roster[action.target] then
            pairs[#pairs + 1] = action
        end
    end
    return pairs
end

local Watch = {}
Watch.__index = Watch

function M.new(sessionId, participantIds, arrivalWitnesses)
    local roster, approved = {}, {}
    for _, id in ipairs(participantIds) do roster[id] = true end
    for id in pairs(arrivalWitnesses or {}) do approved[id] = true end
    return setmetatable({
        sessionId = sessionId,
        participantIds = participantIds,
        roster = roster,
        incidents = {},
        seen = {},
        approved = approved,
        recordedPartners = {},
        ordinary_sighting = false,
        ordinary_unfamiliar = {},
        ordinary_stop_unfamiliar = {},
    }, Watch)
end

local function ordinarySighting(watch, witness, seenActor)
    local highest, unfamiliar = -math.huge, {}
    local romance = witness.romance or {}
    for _, id in ipairs(watch.participantIds) do
        local score = romance[id] or 0
        highest = math.max(highest, score)
        if score < 30 then
            unfamiliar[id] = true
            watch.ordinary_unfamiliar[id] = true
        end
    end
    watch.ordinary_sighting = true
    return {
        witness_id = witness.id, official = false, seen_actor = seenActor,
        pool = highest >= 60 and "Close" or highest >= 30 and "Familiar" or "Unfamiliar",
        walk_away = highest < 60, unfamiliar = unfamiliar,
    }
end

local function recordPartner(watch, witness, cheater, other, nodeId, actionType)
    local confirmed = watch.recordedPartners[witness]
    if not confirmed then
        confirmed = {}
        watch.recordedPartners[witness] = confirmed
    end
    if confirmed[cheater] then return false end
    confirmed[cheater] = true
    watch.incidents[#watch.incidents + 1] = {
        session_id = watch.sessionId, witness_id = witness, cheater_id = cheater,
        other_participant_id = other, node_id = nodeId, action_type = actionType,
    }
    return true
end

-- Each observation is scoped to this session and its current node revision.
-- visible[id] means a native trace reached that participant. Missing checks are unknown.
-- partners[id] means the relationship is an established partnership at the time of sight.
-- romance[id] is the raw score from the witness toward that participant.
function Watch:observe(snapshot, definitions, observations, hasTrait, referenceId, departed)
    if (snapshot.id or snapshot.session_id) ~= self.sessionId then return end
    for id in pairs(departed or {}) do self.approved[id] = nil end
    local actions = M.actionPairs(snapshot, definitions, self.roster)
    if #actions == 0 then return end
    local firstSightings, hasOfficial, bestOrdinary = {}, false, nil
    for _, witness in ipairs(observations) do
        local who, visible = witness.id, witness.visible
        if who and not self.roster[who] and witness.revision == snapshot.revision and type(visible) == "table" then
            local seenActor, betrayedActor
            for _, action in ipairs(actions) do
                local a, b = action.actor, action.target
                if visible[a] == true and visible[b] == true then
                    seenActor = seenActor or a
                    if referenceId == a or referenceId == b then seenActor = referenceId end
                    local partnerships = witness.partners or {}
                    if partnerships[a] == true then
                        betrayedActor = betrayedActor or a
                        hasOfficial = recordPartner(self, who, a, b, snapshot.node_id, action.type) or hasOfficial
                    end
                    if partnerships[b] == true then
                        betrayedActor = betrayedActor or b
                        hasOfficial = recordPartner(self, who, b, a, snapshot.node_id, action.type) or hasOfficial
                    end
                end
            end
            if seenActor and not self.seen[who] then
                local sighting
                if betrayedActor then
                    sighting = {witness_id = who, official = true, seen_actor = betrayedActor, pool = "Betrayed"}
                elseif not self.approved[who] and not witness.romance_unavailable then
                    sighting = ordinarySighting(self, witness, seenActor)
                    sighting.stop_votes = M.stopVotes(self.participantIds, false, hasTrait, sighting.unfamiliar)
                    if not bestOrdinary or sighting.stop_votes > bestOrdinary.stop_votes then
                        bestOrdinary = sighting
                    end
                end
                if sighting then
                    self.seen[who] = true
                    firstSightings[#firstSightings + 1] = sighting
                end
            end
        end
    end
    if #firstSightings == 0 and not hasOfficial then return end

    local stops, total
    if hasOfficial then
        stops, total = M.stopVotes(self.participantIds, true, hasTrait)
    else
        stops = bestOrdinary and bestOrdinary.stop_votes or 0
        total = 0
        for _ in pairs(self.roster) do total = total + 1 end
    end
    local outcome = {sightings = firstSightings, stop_votes = stops, participants = total}
    if not self.stopRequested and stops * 2 > total then
        outcome.stop_reason = hasOfficial and "caught_by_partner" or "witness_sighting"
        self.stopRequested = true
        if not hasOfficial then self.ordinary_stop_unfamiliar = bestOrdinary.unfamiliar end
    end
    return outcome
end

return M
