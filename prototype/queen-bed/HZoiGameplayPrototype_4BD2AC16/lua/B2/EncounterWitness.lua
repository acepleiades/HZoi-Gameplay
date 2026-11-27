local Json = require("SceneZOIAddon.Json")
local Policy = require("WitnessPolicy")
local Native = require("WitnessNative")
local Traits = require("TraitOutcomes")
local Affair = require("NativeAffair")
local StopReasons = require("StopReasons")
local M = {}
local DEPARTURE_DISTANCE_SQUARED = 80 ^ 2

local function firstName(person)
    local ok, name = pcall(function() return person:GetFirstName() end)
    if ok and type(name) == "string" and not name:find("%c") then
        name = name:match("^%s*(.-)%s*$")
        if #name > 0 and #name <= 160 then return name end
    end
end

local function stopExplanation(reason, ids, participants, language)
    local strings = StopReasons[language] or StopReasons["en-us"]
    local wording = assert(strings[reason])
    if #ids == 2 then
        local first = firstName(participants[ids[1]])
        local second = firstName(participants[ids[2]])
        if first and second then
            local names = {first = first, second = second}
            local message = wording.named:gsub("{([%w_]+)}", names)
            if #message <= 512 and not message:find("\226\128[\168\169]") then return message end
        end
    end
    return wording.unnamed
end

function M.tick(record, definitions, owner, time)
    local snapshot = record.snapshot
    if not snapshot or snapshot.phase ~= "playing" or snapshot.game_scale == 0
        or not record.session_id or not definitions or type(snapshot.revision) ~= "number" then return end
    local watch = record.witnessPolicy
    if not watch then
        watch = Policy.new(record.session_id, record.participants, record.arrivalWitnesses)
        watch.arrivalPlaybackRevision = record.arrivalPlaybackRevision or snapshot.revision
        record.witnessPolicy = watch
    end
    if watch.nextTrace and time < watch.nextTrace then return end
    if watch.pendingTrace and time < watch.pendingTrace.expires then return end
    watch.nextTrace = time + 1
    if not next(watch.approved) and #Policy.actionPairs(snapshot, definitions, watch.roster) == 0 then return end

    watch.serial = (watch.serial or 0) + 1
    local token = record.request_id .. "." .. watch.serial
    local baseline = {}
    for id in pairs(watch.approved) do baseline[#baseline + 1] = id end
    table.sort(baseline)
    local checkArrival = #baseline > 0 and not watch.arrivalReactionsChecked
        and snapshot.revision == watch.arrivalPlaybackRevision
    watch.pendingTrace = {token = token, revision = snapshot.revision, expires = time + 2, arrivalReactions = checkArrival}
    inzoi.message.send_to_client(owner:GetEntityId(), "HZoiGameplay.WitnessTrace", Json.encode({
        token = token, revision = snapshot.revision, participants = record.participants,
        baseline = #baseline > 0 and baseline or nil,
        arrival_reactions = checkArrival or nil,
    }))
end

local function sayAsArrivalObserver(witness, target, participants)
    for _, participant in pairs(participants) do
        if Native.isOfficialPartner(witness, participant) then return end
    end
    local pool = "Surprise"
    if Native.hasTrait(witness, "Entertainer") then
        pool = "Troublemaker"
    elseif Native.hasTrait(witness, "Romantic") then
        pool = "Charmer"
    elseif Native.hasTrait(witness, "Helper") then
        pool = "Recluse"
    end
    local bubble = "HZoiGameplay_Arrival" .. pool .. math.random(5)
    Native.say(witness, target, bubble)
    return bubble
end

local function sayArrivalReactions(record, watch, visible, participants, actor, log)
    watch.arrivalReactionsChecked = true
    for id, targetId in pairs(visible) do
        local target = participants[targetId]
        if target and watch.approved[id] then
            local witness = actor(id)
            if witness then
                local ok, bubble = pcall(sayAsArrivalObserver, witness, target, participants)
                if not ok or bubble then
                    log("arrival_bystander_dialogue", {session = record.session_id, speaker = id,
                        bubble = ok and bubble or nil, error = not ok and tostring(bubble) or nil})
                end
            end
        end
    end
end

local function leftArrivalView(witness, arrivalLocation)
    if not witness then return true end
    if not arrivalLocation then return false end
    local here = witness:GetLocation()
    local x, y, z = here.X - arrivalLocation.X, here.Y - arrivalLocation.Y, here.Z - arrivalLocation.Z
    -- Playback can briefly occlude a sightline to a Zoi who stayed in place.
    return x * x + y * y + z * z >= DEPARTURE_DISTANCE_SQUARED
end

local function sayReactions(record, watch, result, participants, actor, log)
    local spoken = watch.participantDialogue or {}
    watch.participantDialogue = spoken
    for _, sighting in ipairs(result.sightings) do
        local witness = actor(sighting.witness_id)
        local ok, bubble = pcall(Native.sayAsWitness, witness, participants[sighting.seen_actor], sighting.pool)
        if not ok or bubble then
            log("witness_dialogue", {session = record.session_id, witness = sighting.witness_id,
                pool = sighting.pool, bubble = ok and bubble or nil, error = not ok and tostring(bubble) or nil})
        end
        for _, id in ipairs(record.participants) do
            if not spoken[id] and (sighting.official or sighting.unfamiliar[id]) then
                local participant = participants[id]
                local pool = Traits.witnessDialoguePool(function(trait)
                    return Native.hasTrait(participant, trait)
                end, sighting.stop_voters and sighting.stop_voters[id])
                if pool then
                    local line = "HZoiGameplay_Witness" .. pool .. math.random(5)
                    spoken[id] = true
                    local said, why = pcall(Native.say, participant, witness, line)
                    log("witness_participant_dialogue", {session = record.session_id, participant = id,
                        bubble = line, ok = said, reason = not said and tostring(why) or nil})
                end
            end
        end
    end
end

function M.reply(record, definitions, raw, actor, time, onSight, onStop, log)
    local watch = record.witnessPolicy
    local pending = watch and watch.pendingTrace
    if not pending or time >= pending.expires then return end
    local decoded, reply = pcall(Json.decode, raw, 32768)
    if not decoded or type(reply) ~= "table" or reply.token ~= pending.token then return end
    watch.pendingTrace = nil

    local snapshot = record.snapshot
    if not snapshot or snapshot.revision ~= pending.revision or reply.revision ~= pending.revision
        or snapshot.phase ~= "playing" or snapshot.game_scale == 0 then return end
    if reply.diagnostic then
        if not watch.traceFailed then
            watch.traceFailed = true
            log("witness_trace_unavailable", {session = record.session_id, code = reply.diagnostic})
        end
        return
    end
    watch.traceFailed = nil
    if type(reply.observations) ~= "table" then return end

    local participants = {}
    for _, id in ipairs(record.participants) do
        participants[id] = actor(id)
        if not participants[id] then return end
    end

    local observations = {}
    for _, row in ipairs(reply.observations) do
        if type(row) == "table" and type(row.id) == "string" and row.id:match("^%d+$")
            and not watch.roster[row.id] then
            local witness = actor(row.id)
            if witness then
                row.partners = {}
                row.romance = {}
                local resolved = true
                local needsRomance = not (watch.seen[row.id] or watch.approved[row.id])
                for id, participant in pairs(participants) do
                    local ok, partnered = pcall(Native.isOfficialPartner, witness, participant)
                    if not ok then resolved = false; break end
                    if partnered then row.partners[id] = true end
                    if needsRomance then
                        local read, score = pcall(Native.relationshipScore, witness, participant, "Romance")
                        if read and score ~= nil then
                            row.romance[id] = score
                        else
                            row.romance_unavailable = true
                        end
                    end
                end
                if resolved then observations[#observations + 1] = row end
            end
        end
    end

    local departed = {}
    if type(reply.baseline_absent) == "table" then
        local locations = record.arrivalWitnessLocations or {}
        for _, id in ipairs(reply.baseline_absent) do
            if type(id) == "string" and watch.approved[id] and leftArrivalView(actor(id), locations[id]) then
                departed[id] = true
            end
        end
    end
    local result = watch:observe(snapshot, definitions, observations, function(id, trait)
        return Native.hasTrait(participants[id], trait)
    end, record.initiator, departed)
    if pending.arrivalReactions and type(reply.baseline_visible) == "table" then
        sayArrivalReactions(record, watch, reply.baseline_visible, participants, actor, log)
    end
    if not result then return end
    log("witness_sighting", {session = record.session_id, sightings = result.sightings,
        incident_count = #watch.incidents, stop_votes = result.stop_votes, reason = result.stop_reason})

    sayReactions(record, watch, result, participants, actor, log)

    for _, sighting in ipairs(result.sightings) do
        if not sighting.official then
            local ok, why = pcall(onSight, sighting.witness_id, sighting.seen_actor, sighting.walk_away)
            if not ok then log("witness_walk_unavailable", {witness = sighting.witness_id, reason = tostring(why)}) end
        end
    end
    if result.stop_reason then
        onStop(result.stop_reason, stopExplanation(result.stop_reason, record.participants, participants, reply.language))
    end
end

function M.finish(record, result, actor, log)
    local watch = record.witnessPolicy
    if not watch or #watch.incidents == 0 or watch.deliveryChecked then return end
    watch.deliveryChecked = true
    if not result.cleanup_complete then
        log("witness_cleanup_unconfirmed", {session = record.session_id, incidents = watch.incidents})
        return
    end
    for _, incident in ipairs(watch.incidents) do
        local ok, outcome = pcall(function()
            return Affair.deliver(actor(incident.witness_id), actor(incident.cheater_id), actor(incident.other_participant_id))
        end)
        if not ok then outcome = {code = "native_delivery_failed", error = tostring(outcome)} end
        log("witness_native_reaction", {session = record.session_id, incident = incident, result = outcome})
    end
end

return M
