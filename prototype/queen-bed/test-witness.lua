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

local function witness(id, revision, relationships, romance)
    return {id = id, revision = revision, visible = {["1"] = true, ["2"] = true},
        partners = relationships, romance = romance}
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

local introverts = function(_, trait) return trait == "Introvert" end
local familiar = W.new("one", {"1", "2"})
local disjoint = familiar:observe(first, defs, {
    witness("3", 1, nil, {["1"] = 30, ["2"] = 29}),
    witness("4", 1, nil, {["1"] = 29, ["2"] = 60}),
}, introverts)
assert(disjoint.stop_votes == 1 and not disjoint.stop_reason, "Votes from different witnesses must not combine")
assert(disjoint.sightings[1].stop_voters["2"] and not disjoint.sightings[1].stop_voters["1"])
assert(disjoint.sightings[2].stop_voters["1"] and not disjoint.sightings[2].stop_voters["2"])
assert(disjoint.sightings[1].pool == "Familiar" and disjoint.sightings[1].walk_away)
assert(disjoint.sightings[2].pool == "Close" and not disjoint.sightings[2].walk_away)
assert(familiar.ordinary_unfamiliar["1"] and familiar.ordinary_unfamiliar["2"])
local allFamiliar = W.new("one", {"1", "2"}):observe(
    first, defs, {witness("3", 1, nil, {["1"] = 30, ["2"] = 59})}, introverts)
assert(allFamiliar.stop_votes == 0 and allFamiliar.sightings[1].pool == "Familiar")
local unfamiliar = familiar:observe(first, defs, {witness("5", 1, nil, {["1"] = 29})}, introverts)
assert(unfamiliar.stop_reason == "witness_sighting" and unfamiliar.sightings[1].pool == "Unfamiliar")
assert(familiar.ordinary_stop_unfamiliar["1"] and familiar.ordinary_stop_unfamiliar["2"])

local preapproved = W.new("one", {"1", "2"}, {["3"] = true})
assert(not preapproved:observe(first, defs, {witness("3", 1)}, introverts))
assert(not preapproved:observe(first, defs, {}, introverts))
assert(not preapproved:observe(snapshot(1, "cuddle"), defs, {}, introverts, nil, {["3"] = true}))
local returned = preapproved:observe(first, defs, {witness("3", 1)}, introverts)
assert(returned.stop_reason == "witness_sighting")
local stillVisible = W.new("one", {"1", "2"}, {["3"] = true})
local caughtAtArrival = stillVisible:observe(first, defs, {
    witness("3", 1, {["2"] = true}, {["1"] = 90, ["2"] = 90}),
}, introverts)
assert(caughtAtArrival.stop_reason == "caught_by_partner")
assert(caughtAtArrival.sightings[1].pool == "Betrayed" and caughtAtArrival.sightings[1].seen_actor == "2")

local votes, total = W.stopVotes({"1", "2", "3", "1"}, true, hasFlirt)
assert(votes == 2 and total == 3)
local newer, same = W.stopVotes({"1", "2"}, false, function(who, trait)
    return who == "1" and trait == "Perfectionist"
end)
assert(newer == 1 and same == 2)

local Json = require("SceneZOIAddon.Json")
local Bridge = require("EncounterWitness")
local send, stops, explanation, announced, logs, seenParticipant, shouldWalk
inzoi = {
    EB2ComponentType = {Bio = "Bio", Relationship = "Relationship", Trait = "Trait", Howling = "Howling"},
    message = {send_to_client = function(ownerId, kind, raw)
        assert(ownerId == "1" and kind == "HZoiGameplay.WitnessTrace")
        send = Json.decode(raw)
    end},
}
local participants, scores, stages = {}, {}, {}
for _, id in ipairs({"1", "2", "3", "4"}) do
    participants[id] = {
        GetEntityId = function() return {Value = tonumber(id)} end,
        GetFirstName = function() return id == "1" and "Jaewoo" or "Minah" end,
        GetGrowthStep = function() return stages[id] end,
        GetComponent = function(_, kind)
            if kind == "Relationship" then
                return {FindRelationshipData = function(_, candidate)
                    local entries = id == "4" and candidate.Value == 1 and {{Id = "Youth_Lover"}} or {}
                    return {RelationshipInfoList = entries}
                end, FindRelationshipStatData = function(_, candidate, stat)
                    assert(stat == "Romance")
                    local value = scores[id] and scores[id][candidate.Value]
                    return value ~= nil and {Value = value} or nil
                end}
            elseif kind == "Trait" then
                return {HasTrait = function() return false end}

            end
        end,
    }
end
local function findActor(id) return participants[id] end
local function onSight(id, reference, depart) announced, seenParticipant, shouldWalk = id, reference, depart end
local function onStop(reason, text) stops, explanation = reason, text end
local function log(which, data) logs = which end
local carrier = {GetEntityId = function() return "1" end}
local record = {session_id = "one", request_id = "try.start", participants = {"1", "2"}, snapshot = first}
Bridge.tick(record, defs, carrier, 1)
assert(send.token == "try.start.1" and send.revision == first.revision)
local language, baselineAbsent
local function replyAt(time, ...)
    Bridge.reply(record, defs, Json.encode({
        token = send.token, revision = send.revision, observations = {...}, language = language,
        baseline_absent = baselineAbsent,
    }), findActor, time, onSight, onStop, log)
end
record.snapshot = changed
replyAt(1, witness("4", first.revision))
assert(not announced and not stops and #record.witnessPolicy.incidents == 0)
Bridge.tick(record, defs, carrier, 2)
assert(send.token == "try.start.2" and send.revision == 2)
replyAt(2, witness("3", 2), witness("4", 2))
assert(announced == "3" and stops == "caught_by_partner" and logs == "witness_sighting")
assert(shouldWalk == true)
assert(explanation == "Jaewoo and Minah decided to stop after one of their romantic partners caught them together.")
assert(#record.witnessPolicy.incidents == 1)
local original, originalName = record, participants["2"].GetFirstName
for index, nameAvailable in ipairs({true, false}) do
    local sample = snapshot(2)
    sample.session_id = "local" .. index
    record = {session_id = sample.session_id, request_id = "local", participants = {"1", "2"}, snapshot = sample}
    stops, explanation = nil, nil
    language = "fr-fr"
    if not nameAvailable then participants["2"].GetFirstName = function() return "" end end
    Bridge.tick(record, defs, carrier, 3 + index)
    replyAt(3 + index, witness("4", 2))
    assert(stops == "caught_by_partner")
    assert(explanation == (nameAvailable and "Jaewoo et Minah ont décidé de s’arrêter après que la personne avec qui l’un des deux est en couple les a surpris ensemble." or require("StopReasons")["fr-fr"].caught_by_partner.unnamed))
end
record, participants["2"].GetFirstName, language = original, originalName, nil
Bridge.finish(record, {cleanup_complete = false}, findActor, log)
assert(logs == "witness_cleanup_unconfirmed")
logs = nil
Bridge.finish(record, {cleanup_complete = true}, findActor, log)
assert(logs == nil)
local stopTraits = {"Perfectionist", "Helper", "Risk-averse", "Arrogant", "Peacemaker", "Introvert", "Faithful"}
for _, stopsForTrait in ipairs(stopTraits) do
    local stopsAlone = W.stopVotes({"1", "2"}, false, function(id, trait)
        return id == "1" and trait == stopsForTrait
    end)
    assert(stopsAlone == 1, stopsForTrait .. " lost its ordinary-witness vote")
    for _, continueTrait in ipairs({"Cooperator", "Flirt"}) do
        local function bothTraits(id, trait)
            return id == "1" and (trait == stopsForTrait or trait == continueTrait)
        end
        assert(W.stopVotes({"1", "2"}, false, bothTraits) == 0)
        assert(W.stopVotes({"1", "2"}, true, bothTraits) == 1)
    end
end

local bubbles = {}
inzoi.FB2ScriptContext = function(source, target, reason)
    return {source = source.Value, target = target.Value, reason = reason}
end
inzoi.FB1Execute = function() return {} end
inzoi.EB1ScriptReason = {Howling = "Howling"}
inzoi.EB1BaseObject = {Self = "Self"}
inzoi.EB1ExecuteType = {AddSpeechBubble = "AddSpeechBubble"}
inzoi.FB2Script_SpeechBubble = {Execute_AddSpeechBubble = function(context, command)
    assert(command.BaseObject == "Self" and command.Command == "AddSpeechBubble")
    assert(command.Prob == 1 and context.reason == "Howling")
    bubbles[#bubbles + 1] = {source = context.source, target = context.target, id = command.S1}
end}
inzoi.EB1GrowthStep = {LowTeen = 8, HighTeen = 16, Youth = 32, Adult = 64, Old = 128, Elderly = 256}
local reactionTraits = {["1"] = "Perfectionist", ["2"] = "Helper"}
for _, id in ipairs({"1", "2", "3"}) do
    local participant = participants[id]
    local fallback = participant.GetComponent
    participant.GetComponent = function(self, kind)
        if kind == "Trait" then
            return {HasTrait = function(_, trait) return trait == reactionTraits[id] end}
        end
        return fallback(self, kind)
    end
end
record = {session_id = "one", request_id = "dialogue.start", participants = {"1", "2"}, snapshot = first}
stops = nil
Bridge.tick(record, defs, carrier, 10)
replyAt(10, unclear)
assert(#bubbles == 0 and not stops)
Bridge.tick(record, defs, carrier, 11)
replyAt(11, witness("3", 1))
assert(#bubbles == 2 and stops == "witness_sighting")
assert(explanation == "Jaewoo and Minah decided to stop after someone walked in on them.")
assert(bubbles[1].source == 1 and bubbles[1].target == 3 and bubbles[1].id == "HZoiGameplay_WitnessPerfectionist")
assert(bubbles[2].source == 2 and bubbles[2].target == 3 and bubbles[2].id == "HZoiGameplay_WitnessRecluse")
Bridge.tick(record, defs, carrier, 12)
replyAt(12, witness("4", 1, {["1"] = true}))
assert(#bubbles == 2, "another sighting must not repeat the participants’ lines")

participants["1"].GetFirstName = function() return " " end
record = {session_id = "one", request_id = "no-name.start", participants = {"1", "2"}, snapshot = first}
Bridge.tick(record, defs, carrier, 13)
replyAt(13, witness("3", 1))
assert(stops == "witness_sighting")
assert(explanation == "The encounter ended after someone walked in.")

local groupSnapshot = snapshot(4)
groupSnapshot.participants[#groupSnapshot.participants + 1] = {id = "3", role = "c"}
groupSnapshot.actions = {{type = "intimate", actor = "c", target = "b"}}
local sight = {id = "4", revision = 4, visible = {["2"] = true, ["3"] = true}}
local groupRoster = {"1", "2", "3"}
local groupWatch = W.new("one", groupRoster)
local singleVote = groupWatch:observe(groupSnapshot, defs, {sight}, function(id, trait)
    return id == "3" and trait == "Helper"
end)
assert(singleVote.stop_votes == 1 and not singleVote.stop_reason and singleVote.participants == 3)
assert(singleVote.sightings[1].seen_actor == "3")
sight.partners = {["3"] = true}
groupWatch = W.new("one", groupRoster)
local groupCaught = groupWatch:observe(groupSnapshot, defs, {sight}, hasFlirt)
assert(groupCaught.stop_reason == "caught_by_partner" and groupCaught.stop_votes == 2)
assert(groupWatch.incidents[1].cheater_id == "3" and groupWatch.incidents[1].other_participant_id == "2")
sight.partners = nil
record = {session_id = "one", request_id = "group.start", initiator = "1",
    participants = groupRoster, snapshot = groupSnapshot}
Bridge.tick(record, defs, carrier, 14)
replyAt(14, sight)
assert(stops == "witness_sighting" and announced == "4" and seenParticipant == "3")
assert(explanation == "The encounter ended after someone walked in.",
    "A group stop must not show a two-name explanation")

record = {session_id = "one", request_id = "arrival.start", participants = {"1", "2"},
    arrivalWitnesses = {["3"] = true}, snapshot = first}
announced, shouldWalk, stops, bubbles = nil, nil, nil, {}
stages["3"], scores["3"] = inzoi.EB1GrowthStep.HighTeen, {[1] = 59, [2] = 30}
Bridge.tick(record, defs, carrier, 15)
assert(send.baseline[1] == "3")
replyAt(15, witness("3", 1))
assert(not announced and #bubbles == 0)
Bridge.tick(record, defs, carrier, 16)
baselineAbsent = {"3"}
replyAt(16)
baselineAbsent = nil
Bridge.tick(record, defs, carrier, 17)
assert(send.baseline == nil)
replyAt(17, witness("3", 1))
assert(announced == "3" and shouldWalk and not stops and #bubbles == 1)
assert(bubbles[1].source == 3 and bubbles[1].id:match("^HZoiGameplay_WitnessFamiliar[1-5]$"))
Bridge.tick(record, defs, carrier, 18)
replyAt(18, witness("3", 1))
assert(#bubbles == 1, "Each witness gets one line per session")

record = {session_id = "one", request_id = "younger.start", participants = {"1", "2"}, snapshot = first}
stages["3"], scores["3"] = inzoi.EB1GrowthStep.LowTeen, {[1] = 59, [2] = 0}
Bridge.tick(record, defs, carrier, 19)
replyAt(19, witness("3", 1))
assert(shouldWalk and #bubbles == 2 and bubbles[2].source == 2,
    "A quiet witness still walks and only the unfamiliar participant complains")
record = {session_id = "one", request_id = "close.start", participants = {"1", "2"}, snapshot = first}
stages["3"], scores["3"] = inzoi.EB1GrowthStep.Adult, {[1] = 30, [2] = 60}
Bridge.tick(record, defs, carrier, 20)
replyAt(20, witness("3", 1))
assert(not shouldWalk and #bubbles == 3)
assert(bubbles[3].id:match("^HZoiGameplay_WitnessClose[1-5]$"))
record = {session_id = "one", request_id = "affair.start", participants = {"1", "2"}, snapshot = first}
stages["4"], scores["4"] = inzoi.EB1GrowthStep.Adult, {[1] = 90, [2] = 90}
Bridge.tick(record, defs, carrier, 21)
replyAt(21, witness("4", 1))
assert(stops == "caught_by_partner" and #record.witnessPolicy.incidents == 1)
assert(bubbles[4].source == 4 and bubbles[4].target == 1)
assert(bubbles[4].id:match("^HZoiGameplay_WitnessBetrayed[1-5]$"))

-- Two Introverts interrupted by an unfamiliar witness each get the fallback
-- even though neither has a trait-specific line.
reactionTraits["1"], reactionTraits["2"] = "Introvert", "Introvert"
record = {session_id = "one", request_id = "introvert.start", participants = {"1", "2"}, snapshot = first}
stages["3"], scores["3"] = inzoi.EB1GrowthStep.Adult, nil
stops, bubbles = nil, {}
Bridge.tick(record, defs, carrier, 22)
replyAt(22, witness("3", 1))
assert(stops == "witness_sighting" and #bubbles == 3)
assert(bubbles[1].source == 3 and bubbles[1].id:match("^HZoiGameplay_WitnessUnfamiliar[1-5]$"))
assert(bubbles[2].source == 1 and bubbles[2].target == 3 and bubbles[2].id == "HZoiGameplay_WitnessStop")
assert(bubbles[3].source == 2 and bubbles[3].target == 3 and bubbles[3].id == "HZoiGameplay_WitnessStop")
Bridge.tick(record, defs, carrier, 23)
replyAt(23, witness("3", 1))
assert(#bubbles == 3, "The same walk-in must not repeat the fallback lines")

record = {session_id = "one", request_id = "tie.start", participants = {"1", "2"}, snapshot = first}
scores["3"] = {[1] = 30, [2] = 0}
stops, bubbles = nil, {}
Bridge.tick(record, defs, carrier, 24)
replyAt(24, witness("3", 1))
assert(not stops and #bubbles == 2 and bubbles[1].source == 3)
assert(bubbles[2].source == 2 and bubbles[2].target == 3 and bubbles[2].id == "HZoiGameplay_WitnessStop",
    "The unfamiliar participant speaks after a tie; the familiar participant does not")

reactionTraits["2"] = "Cooperator"
record = {session_id = "one", request_id = "rulebreaker-tie.start", participants = {"1", "2"}, snapshot = first}
scores["3"], stops, bubbles = nil, nil, {}
Bridge.tick(record, defs, carrier, 25)
replyAt(25, witness("3", 1))
assert(not stops and #bubbles == 2 and bubbles[1].source == 3)
assert(bubbles[2].source == 1 and bubbles[2].target == 3 and bubbles[2].id == "HZoiGameplay_WitnessStop",
    "An Introvert reacts when the Rulebreaker prefers to continue")
Bridge.tick(record, defs, carrier, 26)
replyAt(26, witness("3", 1))
assert(not stops and #bubbles == 2, "A tie must not repeat a participant's line")

reactionTraits["2"] = "Introvert"
reactionTraits["3"] = "Introvert"
record = {session_id = "one", request_id = "mixed-group.start",
    participants = groupRoster, snapshot = groupSnapshot}
scores["4"] = {[1] = 30, [2] = 0, [3] = 0}
stops, bubbles = nil, {}
Bridge.tick(record, defs, carrier, 25)
replyAt(25, sight)
assert(stops == "witness_sighting" and #bubbles == 3)
assert(bubbles[1].source == 4 and bubbles[1].id:match("^HZoiGameplay_WitnessFamiliar[1-5]$"))
assert(bubbles[2].source == 2 and bubbles[2].id == "HZoiGameplay_WitnessStop")
assert(bubbles[3].source == 3 and bubbles[3].id == "HZoiGameplay_WitnessStop",
    "Only participants who voted for a stop can say the fallback line")

record = {session_id = "one", request_id = "introvert-affair.start", participants = {"1", "2"}, snapshot = first}
stops, bubbles = nil, {}
Bridge.tick(record, defs, carrier, 26)
replyAt(26, witness("4", 1))
assert(stops == "caught_by_partner" and #bubbles == 1 and bubbles[1].source == 4,
    "The ordinary fallback must not override native cheating reactions")

local native = require("WitnessNative")
local removals = {}
inzoi.FB1EntityId = function() return {} end
inzoi.EB1ExecuteType.RemoveSpeechBubble = "RemoveSpeechBubble"
inzoi.FB2Script_SpeechBubble.Execute_RemoveSpeechBubble = function(context, command)
    assert(command.BaseObject == "Self" and command.Command == "RemoveSpeechBubble")
    assert(command.S1 ~= "None" and context.source == context.target)
    removals[#removals + 1] = {speaker = context.source, id = command.S1}
end
native.clearSpeech()
removals = {}

local realTime, now = os.time, 100
os.time = function() return now end
local one, two = participants["1"], participants["2"]
local line = "HZoiGameplay_WitnessPerfectionist"
local otherLine = "HZoiGameplay_WitnessRecluse"
native.say(one, two, line)
native.say(two, one, line)
now = 103
native.say(two, one, line) -- Replaying the same speech extends only this Zoi's deadline.
native.say(one, two, otherLine, 1)
native.tickSpeech()
assert(#removals == 0)
now = 104
native.tickSpeech()
assert(#removals == 1 and removals[1].speaker == 1 and removals[1].id == otherLine)
now = 105
native.tickSpeech()
native.tickSpeech()
assert(#removals == 2 and removals[2].speaker == 1 and removals[2].id == line)
now = 107
native.tickSpeech()
assert(#removals == 2)
now = 108
native.tickSpeech()
assert(#removals == 3 and removals[3].speaker == 2 and removals[3].id == line)
native.say(two, one, line)
native.clearSpeech()
native.clearSpeech()
assert(#removals == 4 and removals[4].speaker == 2 and removals[4].id == line)
os.time = realTime
print("Witness roles, restoration, all trait votes, and native speech dispatch passed")
