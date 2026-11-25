local Client = require("SceneZOIAddon.Client")

local M = {}
local intimate = {non_penetrative = true, penetrative_non_coital = true, coital = true}
local prefersStop = {
    "Perfectionist", "Helper", "Risk-averse", "Arrogant", "Peacemaker", "Introvert", "Faithful",
}

function M.stopVotes(participantIds, official, hasTrait)
    local roster, stops, total = {}, 0, 0
    for _, id in ipairs(participantIds) do
        if not roster[id] then
            roster[id] = true
            total = total + 1
            if not (hasTrait(id, "Cooperator") or hasTrait(id, "Flirt")) then
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

function M.new(sessionId, participantIds)
    local roster = {}
    for _, id in ipairs(participantIds) do roster[id] = true end
    return setmetatable({
        sessionId = sessionId,
        participantIds = participantIds,
        roster = roster,
        incidents = {},
        seen = {},
        recordedPartners = {},
        ordinary_sighting = false,
    }, Watch)
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
function Watch:observe(snapshot, definitions, observations, hasTrait)
    if (snapshot.id or snapshot.session_id) ~= self.sessionId then return end
    local actions = M.actionPairs(snapshot, definitions, self.roster)
    if #actions == 0 then return end
    local firstSightings, hasOfficial, ordinary = {}, false, false
    for _, witness in ipairs(observations) do
        local who, visible = witness.id, witness.visible
        if who and not self.roster[who] and witness.revision == snapshot.revision and type(visible) == "table" then
            local saw, official = false, false
            for _, action in ipairs(actions) do
                local a, b = action.actor, action.target
                if visible[a] == true and visible[b] == true then
                    saw = true
                    local partnerships = witness.partners or {}
                    if partnerships[a] == true then
                        official = true
                        hasOfficial = recordPartner(self, who, a, b, snapshot.node_id, action.type) or hasOfficial
                    end
                    if partnerships[b] == true then
                        official = true
                        hasOfficial = recordPartner(self, who, b, a, snapshot.node_id, action.type) or hasOfficial
                    end
                end
            end
            if saw and not self.seen[who] then
                self.seen[who] = true
                firstSightings[#firstSightings + 1] = {witness_id = who, official = official}
                if not official then ordinary = true end
            end
        end
    end
    self.ordinary_sighting = self.ordinary_sighting or ordinary
    if #firstSightings == 0 and not hasOfficial then return end

    local stops, total = M.stopVotes(self.participantIds, hasOfficial, hasTrait)
    local outcome = {sightings = firstSightings, stop_votes = stops, participants = total}
    if not self.stopRequested and stops * 2 > total then
        outcome.stop_reason = hasOfficial and "caught_by_partner" or "witness_sighting"
        self.stopRequested = true
    end
    return outcome
end

return M
