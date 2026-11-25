local W = require("WitnessPolicy")

local defs = {
    intimate = {sexual_activity = "non_penetrative"},
    cuddle = {content_rating = "intimate"},
}
local function snapshot(revision, action)
    return {
        session_id = "one", phase = "playing", game_scale = 1,
        revision = revision, node_id = "test.scene",
        participants = {{id = "1", role = "a"}, {id = "2", role = "b"}},
        actions = {{type = action or "intimate", actor = "b", target = "a"}},
    }
end

local function witness(id, revision, relationships)
    return {id = id, revision = revision, visible = {["1"] = true, ["2"] = true}, partners = relationships}
end

local function hasNone() return false end
local function hasFlirt(id, trait)
    return id == "1" and (trait == "Flirt" or trait == "Cooperator")
end

local watch = W.new("one", {"1", "2"})
local first = snapshot(1)
assert(not watch:observe(first, defs, {witness("1", 1), witness("3", 0)}, hasNone))
assert(not watch:observe(snapshot(1, "cuddle"), defs, {witness("3", 1)}, hasNone))
local unclear = witness("3", 1, {["1"] = true})
unclear.visible["1"] = nil
assert(not watch:observe(first, defs, {unclear}, hasNone))
assert(#watch.incidents == 0)

local firstSeen = watch:observe(first, defs, {witness("3", 1)}, hasNone)
assert(firstSeen.stop_votes == 0 and not firstSeen.stop_reason and watch.ordinary_sighting)
assert(#firstSeen.sightings == 1 and firstSeen.sightings[1].witness_id == "3")
assert(not watch:observe(first, defs, {witness("3", 1)}, hasNone))
local changed = snapshot(2)
local culprit = watch:observe(changed, defs, {witness("4", 2, {["1"] = true})}, hasFlirt)
assert(culprit.stop_votes == 1 and not culprit.stop_reason)
assert(#watch.incidents == 1 and watch.incidents[1].witness_id == "4")
assert(watch.incidents[1].cheater_id == "1" and watch.incidents[1].other_participant_id == "2")
assert(not watch:observe(changed, defs, {witness("4", 2, {["1"] = true})}, hasFlirt))

local nextWatch = W.new("one", {"1", "2"})
local official = nextWatch:observe(first, defs, {witness("4", 1, {["2"] = true})}, hasNone)
assert(official.stop_votes == 2 and official.stop_reason == "caught_by_partner")
local ordinary = W.new("one", {"1", "2"})
local preference = ordinary:observe(first, defs, {witness("5", 1)}, function(_, trait)
    return trait == "Introvert"
end)
assert(preference.stop_reason == "witness_sighting")

local votes, total = W.stopVotes({"1", "2", "3", "1"}, true, hasFlirt)
assert(votes == 2 and total == 3)
local newer, same = W.stopVotes({"1", "2"}, false, function(who, trait)
    return who == "1" and trait == "Perfectionist"
end)
assert(newer == 1 and same == 2)

local Json = require("SceneZOIAddon.Json")
local Bridge = require("EncounterWitness")
local send, stops, announced, logs
inzoi = {
    EB2ComponentType = {Bio = "Bio", Relationship = "Relationship", Trait = "Trait", Howling = "Howling"},
    message = {send_to_client = function(ownerId, kind, raw)
        assert(ownerId == "1" and kind == "HZoiGameplay.WitnessTrace")
        send = Json.decode(raw)
    end},
}
local participants = {}
for _, id in ipairs({"1", "2", "3", "4"}) do
    participants[id] = {
        GetEntityId = function() return {Value = tonumber(id)} end,
        GetComponent = function(_, kind)
            if kind == "Relationship" then
                return {FindRelationshipData = function(_, candidate)
                    local entries = id == "4" and candidate.Value == 1 and {{Id = "Youth_Lover"}} or {}
                    return {RelationshipInfoList = entries}
                end}
            elseif kind == "Trait" then
                return {HasTrait = function() return false end}

            end
        end,
    }
end
local function findActor(id) return participants[id] end
local function onSight(id) announced = id end
local function onStop(reason) stops = reason end
local function log(which, data) logs = which end
local carrier = {GetEntityId = function() return "1" end}
local record = {session_id = "one", request_id = "try.start", participants = {"1", "2"}, snapshot = first}
Bridge.tick(record, defs, carrier, 1)
assert(send.token == "try.start.1" and send.revision == first.revision)
local function replyAt(time, ...)
    Bridge.reply(record, defs, Json.encode({
        token = send.token, revision = send.revision, observations = {...},
    }), findActor, time, onSight, onStop, log)
end
record.snapshot = changed
replyAt(1, witness("4", first.revision))
assert(not announced and not stops and #record.witnessPolicy.incidents == 0)
Bridge.tick(record, defs, carrier, 2)
assert(send.token == "try.start.2" and send.revision == 2)
replyAt(2, witness("3", 2), witness("4", 2))
assert(announced == "3" and stops == "caught_by_partner" and logs == "witness_sighting")
assert(#record.witnessPolicy.incidents == 1)
Bridge.finish(record, {cleanup_complete = false}, findActor, log)
assert(logs == "witness_cleanup_unconfirmed")
logs = nil
Bridge.finish(record, {cleanup_complete = true}, findActor, log)
assert(logs == nil)
print("Witness role and scene restoration guards passed")
