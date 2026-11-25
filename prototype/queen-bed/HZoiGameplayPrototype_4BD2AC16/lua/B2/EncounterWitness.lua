local Json = require("SceneZOIAddon.Json")
local Policy = require("WitnessPolicy")
local Native = require("WitnessNative")
local Affair = require("NativeAffair")
local M = {}

function M.tick(record, definitions, owner, time)
    local snapshot = record.snapshot
    if not snapshot or not record.session_id or not definitions or type(snapshot.revision) ~= "number" then return end
    local watch = record.witnessPolicy
    if not watch then
        watch = Policy.new(record.session_id, record.participants)
        record.witnessPolicy = watch
    end
    if watch.nextTrace and time < watch.nextTrace then return end
    if watch.pendingTrace and time < watch.pendingTrace.expires then return end
    watch.nextTrace = time + 1
    if #Policy.actionPairs(snapshot, definitions, watch.roster) == 0 then return end

    watch.serial = (watch.serial or 0) + 1
    local token = record.request_id .. "." .. watch.serial
    watch.pendingTrace = {token = token, revision = snapshot.revision, expires = time + 2}
    inzoi.message.send_to_client(owner:GetEntityId(), "HZoiGameplay.WitnessTrace", Json.encode({
        token = token, revision = snapshot.revision, participants = record.participants,
    }))
end

function M.reply(record, definitions, raw, actor, time, onSight, onStop, log)
    local watch = record.witnessPolicy
    local pending = watch and watch.pendingTrace
    if not pending or time >= pending.expires then return end
    local decoded, reply = pcall(Json.decode, raw, 8192)
    if not decoded or type(reply) ~= "table" or reply.token ~= pending.token then return end
    watch.pendingTrace = nil

    local snapshot = record.snapshot
    if not snapshot or snapshot.revision ~= pending.revision or reply.revision ~= pending.revision
        or snapshot.phase ~= "playing" then return end
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
                local resolved = true
                for id, participant in pairs(participants) do
                    local ok, partnered = pcall(Native.isOfficialPartner, witness, participant)
                    if not ok then resolved = false; break end
                    if partnered then row.partners[id] = true end
                end
                if resolved then observations[#observations + 1] = row end
            end
        end
    end

    local result = watch:observe(snapshot, definitions, observations, function(id, trait)
        return Native.hasTrait(participants[id], trait)
    end)
    if not result then return end
    log("witness_sighting", {session = record.session_id, sightings = result.sightings,
        incident_count = #watch.incidents, stop_votes = result.stop_votes, reason = result.stop_reason})

    for _, sighting in ipairs(result.sightings) do
        if not sighting.official then
            local ok, why = pcall(onSight, sighting.witness_id)
            if not ok then log("witness_walk_unavailable", {witness = sighting.witness_id, reason = tostring(why)}) end
        end
    end
    if result.stop_reason then onStop(result.stop_reason) end
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
