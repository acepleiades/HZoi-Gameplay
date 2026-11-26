local callbacks, clientCallbacks, pending, queued, logs = {}, nil, {}, {}, {}
local clock, ownerId, partnerId, bedId, alternateBedId = 100, 20522, 20524, 21166, 21167
local sofaId, sofaLocation = 21168, {X = 900, Y = 500, Z = 0}
local controlled, blockedSide, queueResult = ownerId, false, "Success"
local notices, privacyQueries, speech = {}, {}, {}
local observerId = 20526
local scores = {}
local partnerStage, partnerGender, ownerGender = 32, 2, 1
local walkable = function() return true end
local SELECT_VENUE = "HZoiGameplay_SelectVenue"
local pendingCoops, currentCoops = {}, {}
local nativeSchedulers = {}
local nativeQueues, nativeInteractions, nativePlayReasons = {}, {}, {}
local function entity(i) return {Value = i or -1} end
local function point(x, y, z) return {X = x, Y = y, Z = z} end
local function actor(i)
    local pos = point(0, 0, 0)
    local component = {
        IsCurrentInteractionCoop = function() return currentCoops[i] == true end,
        IsPendingCoop = function() return pendingCoops[i] == true end,
        GetCurrentCoopSchedulerId = function() return entity() end,
        IsQueueEmpty = function() return not nativeQueues[i] end,
        IsPlayingInteraction = function() return currentCoops[i] == true or nativeInteractions[i] == true end,
        GetCurrentInteractionPlayReason = function() return nativePlayReasons[i] or 0 end,
        GetCurrentInteractionBagId = function() return "None" end,
        AddInteractionQueueByParam = function(_, target, destination, bag)
            if queueResult ~= "Success" then return queueResult end
            queued[#queued + 1] = {id = i, target = target.Value, destination = destination, bag = bag}
            return "Success"
        end,
        TryCancelInteractionByBagId = function(_, bag)
            logs[#logs + 1] = "native_cancel " .. bag
        end,
    }
    return {
        GetEntityId = function() return entity(i) end,
        GetComponent = function() return component end,
        GetGrowthStep = function() return i == partnerId and partnerStage or 32 end,
        IsSpawned = function() return true end,
        GetGenderType = function() return i == ownerId and ownerGender or partnerGender end,
        GetLocation = function() return pos end,
        ClickVenue = function(_, target, location, inQueue)
            -- The real start event arrived before the current bag and ID changed.
            component.GetCurrentInteractionBagId = function() return inQueue and "None" or SELECT_VENUE end
            component.GetCurrentInteractionQueueId = function() return inQueue and -1 or 40 end
            component.GetCurrentInteractionPickedEntityId = function() return entity(target) end
            component.InteractionQueue = {
                {InteractionQueueId = 39, InteractionBagId = "Other", PickedEntityId = entity(22222),
                    ImpactPoint = point(1, 2, 3)},
            }
            if inQueue then
                component.InteractionQueue[2] = {InteractionQueueId = 40,
                    InteractionBagId = SELECT_VENUE, PickedEntityId = entity(target), ImpactPoint = location}
            end
            component.GetCurrentAction = function()
                return {NonTargetLocation = location}
            end
        end,
        MoveTo = function(_, p) pos = p end,
    }
end
local owner, partner, observer = actor(ownerId), actor(partnerId), actor(observerId)
local bed = {
    GetLocation = function() return point(300, 300, 0) end,
    GetRotation = function() return {Yaw = 90} end,
}
local manager = {
    GetAllEntities = function(_, kind)
        if kind == inzoi.EB2EntityType.CoopScheduler then return nativeSchedulers end
        return {owner, partner}
    end,
    FindCharacter = function(_, i)
        if i.Value == ownerId then return owner end
        if i.Value == partnerId then return partner end
        if i.Value == observerId then return observer end
    end,
    FindGameObject = function(_, i)
        if i.Value == bedId then return bed end
        if i.Value == sofaId then
            return {GetLocation = function() return sofaLocation end, GetRotation = bed.GetRotation}
        end
        if i.Value == alternateBedId then
            return {GetLocation = function() return point(600, 300, 0) end, GetRotation = bed.GetRotation}
        end
    end,
}
local line = print
print = function(text) logs[#logs + 1] = text end
os.time = function() return clock end
UE = {FVector = point}
inzoi = {
    FB1EntityId = entity, getB2Manager = function() return manager end,
    getB2Subsystem = function()
        return {IsOnWalkableGrid = function(_, p) return (not blockedSide or p.X >= 600) and walkable(p) end}
    end,
    EB2EntityType = {Character = 3, CoopScheduler = 4}, EB1GenderType = {Male = 1, Female = 2},
    message = {send_to_client = function(target, kind, value)
        if kind == "HZoiGameplay.WitnessTrace" then
            local query = require("SceneZOIAddon.Json").decode(value)
            query.testCarrier = target.Value
            if query.kind == "arrival" then privacyQueries[#privacyQueries + 1] = query end
        else
            assert(kind == "HZoiGameplay.Notice")
            notices[#notices + 1] = value
        end
    end},
    EB1ActionType = {Delay = 33},
    EB2ComponentType = {Interaction = 1}, EB1InteractionPlayReason = {User = 1},
    EB1InteractionCancelReason = {User = 1, CharacterOverlap = 77, FailedMoveOver = 78, CoopCanceled = 79},
    EB1AddInteractionQueueResult = {Success = "Success", EnqueueConditionCheckFail = "EnqueueConditionCheckFail"},
    FB2ControllerSystem = {GetPossessEntityId = function() return entity(controlled) end},
    event = {
        on = function(key, func) callbacks[key] = func; return 1 end,
        off = function(key) callbacks[key] = nil end,
    },
}
local completions, outcomes = {}, {}
local refusalEffects, resultEffects = {}, {}
package.loaded.EncounterRelationship = {
    onRefusal = function(attempt, initiator, partner)
        assert(initiator:GetEntityId().Value == tonumber(attempt.initiator))
        assert(partner:GetEntityId().Value == tonumber(attempt.partner))
        refusalEffects[#refusalEffects + 1] = attempt.nonce
    end,
    onResult = function(attempt, record, result, initiator, partner)
        assert(initiator:GetEntityId().Value == tonumber(attempt.initiator))
        assert(partner:GetEntityId().Value == tonumber(attempt.partner))
        assert(record.ended and result.apply_outcome and result.cleanup_complete)
        resultEffects[#resultEffects + 1] = record.session_id
    end,
}
package.loaded["EncounterConsequences"] = {
    onCompletion = function(record, who, task, index)
        completions[#completions + 1] = {session = record.session_id, who = who, task = task, index = index}
    end,
    onResult = function(record, result)
        outcomes[#outcomes + 1] = {record = record, result = result}
    end,
}
package.loaded["SceneZOIAddon.Client"] = {
    new = function(_, observers)
        clientCallbacks = observers
        return {
            client_id = "client.test",
            refresh_owner = function() end,
            tick = function() end,
            request = function(_, carrier, key, op, args)
                pending[#pending + 1] = {key = key, op = op, args = args, carrier = carrier:GetEntityId().Value}
            end,
        }
    end,
}
package.loaded.NpcInitiative = {new = function() end}
package.loaded.WitnessNative = {
    say = function(...) speech[#speech + 1] = {...} end,
    relationshipScore = function(witness, target, stat)
        assert(witness == observer, "Read the score from the observer's side")
        return scores[target:GetEntityId().Value][stat]
    end,
}
local module = require("Components.VenueInvite")
local component = {GetOwnerEntityId = function() return entity(controlled) end}
local state = {}
module.on_begin(state, component)
local function tick() module.on_tick(state, component, .05) end
local function request(op)
    local call = assert(table.remove(pending, 1), op)
    assert(call.op == op, call.op)
    return call
end
local function reply(op, value)
    local call = request(op)
    clientCallbacks.response({request_id = call.key, ok = true, result = value})
    return call
end
local json = require("SceneZOIAddon.Json")
local function privacyReply(query, seen, diagnostic)
    local receiver = {GetOwnerEntityId = function() return entity(query.testCarrier) end}
    module.on_lua_message(state, receiver, "HZoiGameplay.WitnessResult", json.encode({
        kind = "arrival", token = query.token, revision = query.revision,
        observations = seen and json.array(seen) or nil, diagnostic = diagnostic,
    }))
end
local function confirmPrivacy()
    privacyReply(assert(table.remove(privacyQueries, 1)), {})
end
local function snapshot(call, sessionId, phase, properties)
    local value = {
        addon_id = "hzoi.gameplay", addon_client_id = "client.test", request_id = call.key,
        id = sessionId, phase = phase, participants = {{id = tostring(ownerId)}, {id = tostring(partnerId)}},
    }
    for key, item in pairs(properties or {}) do value[key] = item end
    return value
end
local function taskCounts(first, second)
    return {
        {participant_id = tostring(ownerId), task_id = "excitement", completions = first},
        {participant_id = tostring(partnerId), task_id = "excitement", completions = second},
    }
end
local ordinaryEnd = {cleanup_complete = true, cleanup_code = "ok", stop_reason = "ok",
    stop_origin = {source = "framework", reason = "ok"}, playing_seconds = 1}
local function fire(kind, player, bag, victim, reason, nativeReason)
    callbacks["interaction." .. kind]({
        entity_id = entity(player), target_entity_id = entity(victim), interaction_bag_id = bag,
        reason = reason, Reason = nativeReason,
    })
end
local function features(hasStopExplanation)
    return setmetatable({stop_session_display_reason = hasStopExplanation}, {__index = function(_, feature)
        if feature ~= "stop_session_display_reason" then return 1 end
    end})
end

local function selectFurniture(furniture, eventTarget)
    local selector = controlled == ownerId and owner or partner
    selector:ClickVenue(furniture, point(99, 99, 99), true)
    fire("started", controlled, SELECT_VENUE, eventTarget or -1)
    selector:GetComponent().InteractionQueue = {}
    fire("finished", controlled, SELECT_VENUE, eventTarget or -1)
end

local function invite(partner, bed, bedStatus, rejection, cancelPicker, preflightResult)
    local before = #queued
    selectFurniture(bed)
    reply("get_version", {features = features(1)})
    local venues = reply("find_furniture", {furniture = {
        {furniture_id = tostring(bedId), profile = {kind = "bed.queen"}, status = bedStatus or "available"},
        {furniture_id = tostring(alternateBedId), profile = {kind = "bed.single"}, status = "available"}
    }})
    assert(venues.args.origin_id == tostring(controlled))

    if bedStatus == "occupied" then return end
    if partnerStage ~= 32 then
        assert(#pending == 0 and notices[#notices] == "partner_ineligible")
        return
    end
    local picker = reply("open_partner_picker", {opened = true})
    assert(#picker.args.candidate_ids == 1 and picker.args.candidate_ids[1] == tostring(partner))
    clientCallbacks.event({name = "partner_picker_finished", request_id = "unrelated", code = "selected", partner_id = "999"})
    assert(#queued == before and #pending == 0)
    if cancelPicker then
        clientCallbacks.event({name = "partner_picker_finished", request_id = picker.key, code = "cancelled"})
        return
    end
    clientCallbacks.event({name = "partner_picker_finished", request_id = picker.key,
        code = "selected", partner_id = tostring(partner)})
    reply("get_definitions", {actions = {
        handjob = {sexual_activity = "non_penetrative", content_rating = "EXPLICIT"},
        vaginal_sex = {sexual_activity = "coital", content_rating = "EXPLICIT"},
        anal_sex = {sexual_activity = "penetrative_non_coital", content_rating = "EXPLICIT"},
    }})
    queueResult = rejection or "Success"
    local preflight = reply("validate_start", preflightResult or {valid = true})
    queueResult = "Success"
    assert(preflight.args.check_start_distance == false and preflight.args.placement.max_start_distance_m == nil)
    local actions = table.concat(preflight.args.search.any_actions, ",")
    assert((actions:find("anal_sex", 1, true) ~= nil) == (ownerGender == 1 and partnerGender == 1))
    assert(preflight.args.furniture_id == tostring(bed) and preflight.args.stages == 4)
    assert(#preflight.args.goals == 2 and preflight.args.start_mode == "start_autonomous_scene")
end
local INVITE, WALK = "HZoiGameplay_Invite", "HZoiGameplay_Walk"
local COOP_WALK = "ClickMove_Self"

local function cancelNativeApproach(origin, coopId, targetId, withDialogue)
    local schedulerId = 25000
    fire("started", ownerId, INVITE, partnerId)
    fire("finished", ownerId, INVITE, partnerId)
    if withDialogue then fire("started", ownerId, "Coop_TalkLike_Before_MakeLove", partnerId) end

    local coop = {
        CoopId = coopId, OriginInteractionBagId = origin,
        HostId = entity(ownerId), MainTargetId = entity(targetId),
        GetEntityId = function() return entity(schedulerId) end,
        bSuppressNextCancelToast = false,
    }
    nativeSchedulers = {coop}
    -- In retail, started is emitted while the action is still in the queue.
    for _, who in ipairs({partnerId, ownerId}) do
        local person = who == ownerId and owner or partner
        local actions = person:GetComponent()
        actions.InteractionQueue = {{InteractionBagId = COOP_WALK, CoopSchedulerId = entity(schedulerId)}}
        fire("started", who, COOP_WALK, -1)
        actions.InteractionQueue = {}
    end
    local ownedApproach = origin == INVITE and targetId == partnerId and not withDialogue
    assert(coop.bSuppressNextCancelToast == ownedApproach,
        "Only the owned invitation approach may suppress the native cancel toast")

    fire("canceled", partnerId, COOP_WALK, -1, nil, inzoi.EB1InteractionCancelReason.FailedMoveOver)
    fire("canceled", ownerId, COOP_WALK, -1, "CoopCanceled")
    nativeSchedulers = {}
end

local function conversation(refusal, switchAfterRefusal, switchDuringDialogue)
    local first, second = controlled, controlled == ownerId and partnerId or ownerId
    local bag = INVITE
    local action = "Coop_TalkLike_Before_MakeLove" .. (refusal and "_Fail" or "")
    local count, effects = #queued, #refusalEffects
    fire("started", first, bag, second)
    fire("finished", first, bag, second)
    tick()
    assert(#queued == count and #pending == 0 and #refusalEffects == effects, "RequestCoop alone is not an answer")
    fire("started", first, action, second)
    fire("started", second, action .. "_Feedback", first)
    if switchDuringDialogue then controlled = switchDuringDialogue end
    fire("finished", first, action, second)
    tick()
    assert(#queued == count and #pending == 0 and #refusalEffects == effects, "Wait for the selected partner's response")
    fire("finished", second, action .. "_Feedback", first)
    assert(#refusalEffects == effects + (refusal and 1 or 0), "Settle the confirmed refusal immediately")
    if switchAfterRefusal then controlled = observerId end
    tick()
    if switchAfterRefusal then
        controlled = first
        fire("finished", second, action .. "_Feedback", first)
    end
    assert(#refusalEffects == effects + (refusal and 1 or 0), "Settle the confirmed refusal only once")
end


fire("finished", controlled, SELECT_VENUE, bedId)
fire("started", partnerId, SELECT_VENUE, bedId)
assert(#pending == 0, "Only a native start from the controlled Zoi opens the picker")
invite(partnerId, bedId, nil, nil, true)
assert(#queued == 0 and #pending == 0 and logs[#logs]:find("picker_cancelled"))
invite(partnerId, bedId)
assert(queued[1].bag == INVITE and queued[1].target == partnerId)
conversation(true, true)
assert(logs[#logs]:find("refused") and #queued == 1 and #pending == 0)

-- The same action can be used by another selected Zoi, at a different bed.
controlled = partnerId
blockedSide = true
queued = {}
invite(ownerId, alternateBedId)
assert(queued[1].id == partnerId and queued[1].target == ownerId)
local noticesAfterInvite = #notices
conversation(false, false, observerId)
assert(queued[2].bag == WALK and queued[2].id == partnerId
    and queued[3].bag == WALK and queued[3].id == ownerId and #pending == 0,
    "Switching to a bystander during dialogue keeps the original pair and walks")
local p1, p2 = queued[2].destination, queued[3].destination
assert(p1.X >= 600 and p2.X >= 600, "The wall-side points must be rejected")
assert((p1.X - p2.X)^2 + (p1.Y - p2.Y)^2 >= 150^2)
partner:MoveTo(point(p1.X, p1.Y, p1.Z + 90))
fire("finished", partnerId, WALK, -1)
controlled = ownerId
tick()
assert(#pending == 0 and #notices == noticesAfterInvite,
    "Switching to the invited partner during the walk still waits for both arrivals")
owner:MoveTo(point(p2.X, p2.Y, p2.Z + 90))
fire("finished", ownerId, WALK, -1)
controlled = observerId
tick()
local arrival = reply("validate_start", {valid = true, scene_id = "hzoi.bed", bindings = {male = "20522", female = "20524"}})
assert(arrival.args.check_start_distance == nil and arrival.args.furniture_id == tostring(alternateBedId)
    and arrival.args.initiator == tostring(partnerId) and arrival.carrier == observerId)
assert(#pending == 0 and #privacyQueries == 1, "Wait for sight proof before starting")
local query = table.remove(privacyQueries, 1)
assert(query.points[tostring(partnerId)].x == p1.X and query.points[tostring(ownerId)].x == p2.X)
privacyReply(query, nil, "observer_view_unavailable")
assert(#pending == 0 and #privacyQueries == 0)
controlled = ownerId
clock = clock + 1
tick()
local retryQuery = assert(table.remove(privacyQueries, 1))
assert(retryQuery.token ~= query.token and retryQuery.revision == query.revision + 1)
controlled = observerId
privacyReply(query, {})
assert(#pending == 0, "An obsolete sight reply cannot start the encounter")
scores = {[ownerId] = {Romance = 30}, [partnerId] = {Romance = 0, Friendship = 30}}
privacyReply(retryQuery, {{id = tostring(observerId)}})
local start = reply("start_autonomous_scene", {accepted = true, stages = 4})
assert(start.args.scene_id == "hzoi.bed" and start.args.bindings.male == "20522")
assert(start.args.initiator == tostring(partnerId) and start.carrier == observerId and #notices == noticesAfterInvite,
    "Accept the outstanding privacy result and dispatch playback without changing the original initiator")
assert(logs[#logs]:find("start_accepted") and not logs[#logs]:find("session_started"))
clientCallbacks.event(snapshot(start, "unrelated", "playing", {name = "session_started",
    addon_client_id = "different.client"}))
clientCallbacks.event(snapshot(start, "unrelated", "playing", {name = "session_started",
    participants = {{id = tostring(ownerId)}, {id = "999"}}}))
assert(not logs[#logs]:find("session_started"))
clientCallbacks.event(snapshot(start, "test", "playing", {name = "session_started"}))
assert(logs[#logs]:find("session_started"))

local function reportWitnessStop(session, startCall, expectedDisplayReason)
    local json = require("SceneZOIAddon.Json")
    local witness = require("EncounterWitness")
    local original = witness.reply
    local message = "Jaewoo and Minah decided to stop after someone walked in on them."
    witness.reply = function(record, _, _, _, _, _, stop)
        if session == "test" then
            assert(record.arrivalWitnesses[tostring(observerId)], "Successful arrival establishes the continuity baseline")
        end
        stop("witness_sighting", message)
    end
    module.on_lua_message(state, component, "HZoiGameplay.WitnessResult",
        json.encode({token = startCall.key .. ".1"}))
    witness.reply = original
    local stop = reply("request_stop", {accepted = true})
    assert(stop.args.session_id == session and stop.args.reason == "witness_sighting")
    assert(stop.args.display_reason == (expectedDisplayReason and message or nil))
end

reportWitnessStop("test", start, true)
local completion = snapshot(start, "test", "playing", {name = "task_completed", participant_id = tostring(ownerId),
    task = {id = "excitement", completion_index = 1}})
clientCallbacks.event(completion)
clientCallbacks.event(completion)
clientCallbacks.event(snapshot(start, "other", "ended", {name = "session_ended", task_state = taskCounts(5, 5),
    result_facts = ordinaryEnd}))
assert(#completions == 1 and #outcomes == 0, "Ignore duplicate completions and foreign sessions")
local ended = snapshot(start, "test", "ended", {name = "session_ended", task_state = taskCounts(2, 0),
    result_facts = ordinaryEnd})
clientCallbacks.event(ended)
clientCallbacks.event(ended)
assert(#completions == 2 and completions[2].index == 2 and #outcomes == 1)
assert(outcomes[1].record.completions[tostring(partnerId)].excitement == 0)
assert(outcomes[1].record.furniture == tostring(alternateBedId))
assert(outcomes[1].result.task_counts_complete and logs[#logs]:find("session_ended"))
assert(#resultEffects == 1 and resultEffects[1] == "test", "Apply the relationship result once after cleanup")

controlled, blockedSide, queued = ownerId, false, {}
invite(partnerId, bedId)
fire("canceled", ownerId, INVITE, partnerId)
tick()
assert(#pending == 0 and #queued == 1 and logs[#logs - 1]:find("failed"))

queued = {}
invite(partnerId, bedId)
local noticeCount = #notices
fire("started", ownerId, INVITE, partnerId)
fire("finished", ownerId, INVITE, partnerId)
clock = clock + 9
tick()
assert(#notices == noticeCount, "Allow time for the conversation to enter the native queue")
pendingCoops[partnerId] = true
clock = clock + 15
tick()
assert(#notices == noticeCount, "Wait while the partner's native conversation is pending")
pendingCoops[partnerId], currentCoops[ownerId] = nil, true
clock = clock + 15
tick()
assert(#notices == noticeCount, "Wait while the initiator is in the native conversation")
currentCoops[ownerId] = nil
tick()
clock = clock + 1
tick()
clock = clock + 1
tick()
assert(#notices == noticeCount, "Deferral allows the end events to be delivered after both Coops clear")
clock = clock + 1
tick()
assert(#notices == noticeCount + 1 and notices[#notices] == "failed" and #queued == 1 and #pending == 0,
    "An abandoned conversation should end promptly and never start walks or SceneZOI")

queued = {}
invite(partnerId, bedId)
noticeCount = #notices
local dialogue = "Coop_TalkLike_Before_MakeLove"
fire("started", ownerId, INVITE, partnerId)
fire("finished", ownerId, INVITE, partnerId)
fire("started", ownerId, dialogue, partnerId)
fire("started", partnerId, dialogue .. "_Feedback", ownerId)
currentCoops[ownerId], currentCoops[partnerId] = true, true
clock = clock + 15
tick()
assert(#notices == noticeCount and #queued == 1, "Keep waiting while the expected dialogue is playing")
currentCoops[ownerId], currentCoops[partnerId] = nil, nil
clock = clock + 1
tick()
clock = clock + 1
tick()
fire("finished", ownerId, dialogue, partnerId)
fire("finished", partnerId, dialogue .. "_Feedback", ownerId)
tick()
tick()
assert(#notices == noticeCount and #queued == 3 and queued[2].bag == WALK and queued[3].bag == WALK,
    "Both late dialogue endings should advance to walking once")
fire("failed", partnerId, WALK, -1)

queued = {}
invite(partnerId, bedId)
fire("started", ownerId, INVITE, partnerId)
fire("failed", ownerId, INVITE, partnerId, nil, "CannotFindSpace")
assert(logs[#logs - 1]:find("CannotFindSpace", 1, true), "Keep the native event's failure reason in diagnostics")

local acceptCoop = "HZoiGameplay_Coop_Accept"
queued = {}
invite(partnerId, bedId)
noticeCount = #notices
cancelNativeApproach(INVITE, acceptCoop, partnerId)
tick()
assert(#queued == 1, "Do not requeue in the frame of a canceled approach")
nativeQueues[partnerId] = true
clock = clock + 2
tick()
assert(#queued == 1, "Wait for the partner's native queue to empty")
nativeQueues[partnerId], nativeInteractions[partnerId] = nil, true
clock = clock + 1
tick()
assert(#queued == 1, "Wait for the partner's native overlap recovery action")
nativeInteractions[partnerId] = nil
clock = clock + 1
tick()
assert(#queued == 2 and queued[2].bag == INVITE and queued[2].id == ownerId and queued[2].target == partnerId
    and #pending == 0 and #notices == noticeCount, "Retry the same native invitation once both Zois are idle")
conversation(false)
assert(#queued == 4 and queued[3].bag == WALK and queued[4].bag == WALK,
    "Retry must await both native dialogue endings before walking")
fire("failed", partnerId, WALK, -1)

queued = {}
invite(partnerId, bedId)
cancelNativeApproach(INVITE, acceptCoop, partnerId)
clock = clock + 2
tick()
assert(#queued == 2 and queued[2].bag == INVITE)
cancelNativeApproach(INVITE, acceptCoop, partnerId)
clock = clock + 2
tick()
assert(#queued == 2 and #pending == 0, "A second native approach failure must never requeue again")
clock = clock + 91
tick()

queued = {}
invite(partnerId, bedId)
noticeCount = #notices
cancelNativeApproach(INVITE, acceptCoop, partnerId)
nativeInteractions[partnerId] = true
clock = clock + 12
tick()
nativeInteractions[partnerId] = nil
clock = clock + 1
tick()
assert(#queued == 1 and #pending == 0 and #notices == noticeCount + 1,
    "A retry must expire if either Zoi stays busy")

queued = {}
invite(partnerId, bedId)
noticeCount = #notices
cancelNativeApproach(INVITE, acceptCoop, partnerId)
nativePlayReasons[ownerId] = inzoi.EB1InteractionPlayReason.User
fire("started", ownerId, "OtherInteraction", -1)
nativePlayReasons[ownerId] = nil
clock = clock + 3
tick()
assert(#queued == 1 and #pending == 0 and #notices == noticeCount + 1,
    "A new player action must supersede the invitation retry")

for _, unrelated in ipairs({{origin = "OtherInvite", target = partnerId}, {origin = INVITE, target = observerId}}) do
    queued = {}
    invite(partnerId, bedId)
    cancelNativeApproach(unrelated.origin, acceptCoop, unrelated.target)
    clock = clock + 2
    tick()
    assert(#queued == 1 and #pending == 0, "An unrelated native cooperative walk must never requeue the invitation")
    fire("canceled", ownerId, INVITE, partnerId)
end

queued = {}
invite(partnerId, bedId)
cancelNativeApproach(INVITE, acceptCoop, partnerId, true)
clock = clock + 2
tick()
assert(#queued == 1 and #pending == 0, "Never retry after either Zoi starts the native dialogue")
fire("canceled", ownerId, INVITE, partnerId)

queued = {}
invite(partnerId, bedId)
conversation(false)
fire("failed", partnerId, WALK, -1)
tick()
assert(#pending == 0 and #queued == 3 and notices[#notices] == "walk_failed")

queued = {}
invite(partnerId, bedId)
conversation(false)
local first, second = queued[2].destination, queued[3].destination
owner:MoveTo(point(first.X, first.Y, first.Z + 300))
partner:MoveTo(point(second.X, second.Y, second.Z + 90))
fire("finished", ownerId, WALK, -1)
fire("finished", partnerId, WALK, -1)
tick()
assert(#pending == 0 and notices[#notices] == "walk_failed", "Reject another floor")

queued = {}
invite(partnerId, bedId, "occupied")
assert(#queued == 0 and notices[#notices] == "furniture_unavailable")
invite(partnerId, bedId, nil, "EnqueueConditionCheckFail")
assert(#queued == 0 and notices[#notices] == "not_eligible")

local bedActions = owner:GetComponent()
bedActions.InteractionQueue = {}
fire("started", controlled, SELECT_VENUE, bedId)
reply("get_version", {features = features(1)})
reply("find_furniture", {furniture = {{furniture_id = tostring(bedId), profile = {kind = "bed.queen"}}}})
local lostPicker = reply("open_partner_picker", {opened = true})
clock = clock + 60
tick()
selectFurniture(bedId)
assert(#pending == 0 and notices[#notices] == "busy", "Allow time for the player to choose a partner")
clock = clock + 241
tick()
assert(notices[#notices] == "timeout", "Recover a picker without a completion event")
clientCallbacks.event({name = "partner_picker_finished", request_id = lostPicker.key,
    code = "selected", partner_id = tostring(partnerId)})
assert(#pending == 0, "Ignore a selection for an expired invitation")
invite(partnerId, bedId, nil, nil, true)

line("Invitation checks passed: dynamic pair and venue, refusal, wall side, both arrivals, cleanup, cancellation, wrong floor, occupied bed and native enqueue refusal.")

local profile = {
    kind = "sofa.pair",
    sitting_spots = {
        {id = "a", offset_cm = {x = -30, y = -100, z = 0}, yaw_degrees = 0},
        {id = "b", offset_cm = {x = 30, y = -100, z = 0}, yaw_degrees = 0},
        {id = "c", offset_cm = {x = -100, y = -45, z = 0}, yaw_degrees = -90},
        {id = "d", offset_cm = {x = -100, y = 35, z = 0}, yaw_degrees = -90},
    },
}
local function sofaRow(isSide, available, furniture)
    return {furniture_id = tostring(furniture or sofaId), furniture_pair_id = isSide and "side" or "front",
        sitting_spots = isSide and {"c", "d"} or {"a", "b"}, profile = profile, available = available,
        status = available and "available" or "occupied"}
end
local function sofaInvite(available)
    queued = {}
    -- A resolved action target may differ from the originally picked object.
    selectFurniture(sofaId, bedId)
    reply("get_version", {features = setmetatable({}, {__index = function() return 1 end})})
    reply("find_furniture", {furniture = {sofaRow(false, false), sofaRow(true, false)}})
    local picker = reply("open_partner_picker", {opened = true})
    clientCallbacks.event({name = "partner_picker_finished", request_id = picker.key,
        code = "selected", partner_id = tostring(partnerId)})
    local search = reply("find_furniture", {furniture = {
        sofaRow(false, true, sofaId + 1), sofaRow(false, false), sofaRow(true, available),
    }})
    assert(search.args.participants[1] == tostring(ownerId) and search.args.participants[2] == tostring(partnerId))
    if not available then return end
    reply("get_definitions", {actions = {
        handjob = {sexual_activity = "non_penetrative", content_rating = "EXPLICIT"},
        vaginal_sex = {sexual_activity = "coital", content_rating = "EXPLICIT"},
    }})
    local preflight = reply("validate_start", {valid = true, furniture_pair_id = "side"})
    assert(preflight.args.furniture_id == tostring(sofaId) and preflight.args.furniture_pair_id == "side")
    assert(preflight.args.check_start_distance == false and #queued == 1)
end
local function arriveAtSofa()
    conversation(false)
    assert(#queued == 3 and queued[2].bag == WALK and queued[3].bag == WALK)
    local first, second = queued[2].destination, queued[3].destination
    -- Yaw 90 + pair yaw -90 faces +Y, and the pair lies 100 cm behind the
    -- object origin along world Y. The other arm would get different points.
    assert(math.abs(first.Y - 490) < .01 and math.abs(second.Y - 490) < .01)
    assert(math.abs((first.X + second.X) / 2 - 905) < .01 and math.abs(first.X - second.X) == 110)
    owner:MoveTo(point(first.X, first.Y, first.Z + 90))
    fire("finished", ownerId, WALK, -1)
    tick()
    assert(#pending == 0)
    partner:MoveTo(point(second.X, second.Y, second.Z + 90))
    fire("finished", partnerId, WALK, -1)
    tick()
end

sofaInvite(false)
assert(#pending == 0 and #queued == 0 and notices[#notices] == "sofa_unavailable")
sofaInvite(true)
conversation(true)
assert(#pending == 0 and #queued == 1 and logs[#logs]:find("refused"))
sofaInvite(true)
arriveAtSofa()
local blocked = reply("validate_start", {valid = false, code = "furniture_unavailable"})
assert(blocked.args.furniture_pair_id == "side" and blocked.args.check_start_distance == nil)
assert(#pending == 0 and notices[#notices] == "sofa_unavailable", "An alternate pair must never replace the chosen pair on arrival")
sofaInvite(true)
arriveAtSofa()
reply("validate_start", {valid = true, furniture_pair_id = "front"})
assert(#pending == 0 and notices[#notices] == "sofa_unavailable")
sofaInvite(true)
arriveAtSofa()
sofaLocation = point(900, 520, 0)
reply("validate_start", {valid = true, furniture_pair_id = "side"})
assert(#pending == 0 and notices[#notices] == "sofa_unavailable")
sofaLocation = point(900, 500, 0)
sofaInvite(true)
arriveAtSofa()
local sofaArrival = reply("validate_start", {valid = true, furniture_pair_id = "side", scene_id = "hzoi.sofa",
    bindings = {male = tostring(ownerId), female = tostring(partnerId)}})
assert(sofaArrival.args.furniture_pair_id == "side")
confirmPrivacy()
local sofaStart = reply("start_autonomous_scene", {accepted = true, stages = 4})
assert(sofaStart.args.furniture_id == tostring(sofaId) and sofaStart.args.furniture_pair_id == "side")
assert(sofaStart.args.scene_id == "hzoi.sofa")
assert(sofaStart.args.reservation == nil and sofaStart.args.sitting_spots == nil)
-- Recover a missed SceneZOI start and end event through the original request.
clock = clock + 9
tick()
local query = reply("get_request_status", {phase = "ended", session_id = "sofa"})
assert(query.args.request_id == sofaStart.key)
local recovered = reply("get_session_result", {result = snapshot(sofaStart, "sofa", "ended", {
    result_facts = ordinaryEnd, task_state = taskCounts(1, 1), plan = {outcome = "goals_met"},
})})
assert(recovered.args.session_id == "sofa" and logs[#logs]:find("session_ended"))
assert(#completions == 4 and #outcomes == 2 and outcomes[2].record.furniture_pair == "side")
line("Sofa invitations passed: actual roster, exact pair across start checks, occupied or moved sofa, refusal, rotated corner sofa approach and cleanup.")


local clickedFloor = point(900, 650, 340)
local standing = {valid = true, scene_id = "hzoi.standing", anchor_participant_id = tostring(ownerId),
    bindings = {lead = tostring(ownerId), second = tostring(partnerId)}}

local function selectGround(inQueue)
    queued = {}
    local selector = controlled == ownerId and owner or partner
    selector:ClickVenue(-1, clickedFloor, inQueue)
    fire("started", controlled, SELECT_VENUE, -1)
end

local function groundInvite()
    selectGround(controlled == ownerId)
    reply("get_version", {features = features()})
    local picker = reply("open_partner_picker", {opened = true})
    clientCallbacks.event({name = "partner_picker_finished", request_id = picker.key,
        code = "selected", partner_id = tostring(controlled == ownerId and partnerId or ownerId)})
    reply("get_definitions", {actions = {
        handjob = {sexual_activity = "non_penetrative", content_rating = "EXPLICIT"},
        vaginal_sex = {sexual_activity = "coital", content_rating = "EXPLICIT"},
    }})
    local preflight = reply("validate_start", standing)
    assert(not preflight.args.furniture_id and not preflight.args.furniture_pair_id)
    assert(#queued == 1 and queued[1].bag == INVITE)
end

-- Keep the original floor, sidestep a blocked direction, and preserve the
-- animated Zoi's anchor even when the other participant controls the picker.
local function arriveAtGround(wrongFloor)
    controlled = partnerId
    owner:MoveTo(point(900, 800, 430))
    partner:MoveTo(point(1100, 650, 430))
    groundInvite()
    walkable = function(p) return p.X <= clickedFloor.X and p.Z == clickedFloor.Z end
    conversation(false)
    assert(#queued == 3 and queued[2].id == partnerId and queued[3].id == ownerId)
    assert(queued[2].bag == WALK and queued[3].bag == WALK)
    local second, anchor = queued[2].destination, queued[3].destination
    assert(anchor.X == clickedFloor.X and anchor.Y == clickedFloor.Y and anchor.Z == clickedFloor.Z)
    assert(second.X <= anchor.X and second.Z == anchor.Z)
    assert(math.abs((anchor.X - second.X)^2 + (anchor.Y - second.Y)^2 - 150^2) < .01)
    partner:MoveTo(point(second.X, second.Y, second.Z + 90))
    fire("finished", partnerId, WALK, -1)
    tick()
    assert(#pending == 0, "A ground scene must wait for both walk actions")
    owner:MoveTo(point(anchor.X, anchor.Y, anchor.Z + (wrongFloor and 300 or 90)))
    fire("finished", ownerId, WALK, -1)
    tick()
    walkable = function() return true end
    return anchor
end

walkable = function() return false end
selectGround(true)
assert(#pending == 0 and #queued == 0 and notices[#notices] == "ground_unavailable")

-- An unrelated current action can have a point of its own. Never use it
-- when neither the ground queue row nor the active ground action exists.
local clickComponent = owner:GetComponent()
clickComponent.InteractionQueue = {}
fire("started", ownerId, SELECT_VENUE, -1)
clock = clock + 3
tick()
assert(#pending == 0 and #queued == 0 and notices[#notices] == "ground_click_missing")
walkable = function() return true end
groundInvite()
conversation(true)
assert(#queued == 1 and #pending == 0 and logs[#logs]:find("refused"))

groundInvite()
walkable = function(p) return p.X == clickedFloor.X and p.Y == clickedFloor.Y end
conversation(false)
assert(#queued == 1 and #pending == 0 and notices[#notices] == "ground_walk_failed")
walkable = function() return true end

arriveAtGround(true)
assert(#pending == 0 and notices[#notices] == "ground_walk_failed")
local anchor = arriveAtGround(false)
owner:MoveTo(point(anchor.X + 90, anchor.Y, anchor.Z + 90))
reply("validate_start", standing)
assert(#pending == 0 and notices[#notices] == "ground_walk_failed")
arriveAtGround(false)
walkable = function(p) return p.X ~= clickedFloor.X or p.Y ~= clickedFloor.Y end
reply("validate_start", standing)
assert(#pending == 0 and notices[#notices] == "ground_walk_failed")
walkable = function() return true end

arriveAtGround(false)
local arrivalCheck = reply("validate_start", standing)
assert(arrivalCheck.args.check_start_distance == nil)
assert(arrivalCheck.args.scene_id == standing.scene_id and arrivalCheck.args.bindings == standing.bindings)
confirmPrivacy()
local groundStart = reply("start_autonomous_scene", {accepted = true})
assert(groundStart.args.scene_id == standing.scene_id and groundStart.args.bindings == standing.bindings)
assert(not groundStart.args.furniture_id and not groundStart.args.furniture_pair_id)
clientCallbacks.event(snapshot(groundStart, "ground", "playing", {name = "session_started"}))
reportWitnessStop("ground", groundStart, false)
clock = clock + 9
tick()
local current = request("get_session")
assert(current.args.session_id == "ground")
clientCallbacks.response({request_id = current.key, ok = false, code = "session_not_found"})
reply("get_session_result", {result = snapshot(groundStart, "ground", "ended", {
    plan = {goals = {
        {participant_id = tostring(ownerId), task_id = "excitement", completed = 1},
        {participant_id = tostring(partnerId), task_id = "excitement", completed = 0},
    }},
    result_facts = {cleanup_complete = false, cleanup_code = "restore_timeout", stop_reason = "ok",
        stop_origin = ordinaryEnd.stop_origin},
})})
assert(logs[#logs]:find("session_ended") and #completions == 5 and #outcomes == 2)
line("Ground invitations passed: native click handoff, both answers, separate destinations, blocked ground, wrong floor, departure and revalidation.")

arriveAtGround(false)
reply("validate_start", standing)
scores[ownerId].Romance = 29
local refusalBefore, outcomeBefore = #refusalEffects, #resultEffects
local noticesBefore = #notices
privacyReply(assert(table.remove(privacyQueries, 1)), {{id = tostring(observerId)}})
assert(#pending == 0 and #notices == noticesBefore + 1 and notices[#notices] == "arrival_privacy_denied",
    "One privacy toast ends the attempt before SceneZOI starts")
assert(#speech == 0, "Save walk-in dialogue for an active encounter")
assert(#refusalEffects == refusalBefore and #resultEffects == outcomeBefore, "Keep relationships unchanged")

for _, other in ipairs({ownerId, observerId}) do
    arriveAtGround(false)
    reply("validate_start", standing)
    local query = assert(table.remove(privacyQueries, 1))
    assert(query.testCarrier == partnerId, "The initiator is controlled when the trace is requested")
    controlled = other
    local noticesBefore = #notices
    privacyReply(query, {{id = tostring(observerId)}})
    assert(logs[#logs - 1]:find("arrival_privacy_denied", 1, true) and #pending == 0 and #notices == noticesBefore,
        "A privacy denial still cancels silently while the invited partner or a bystander is controlled")
end

arriveAtGround(false)
reply("validate_start", standing)
for revision = 1, 3 do
    local missingProof = assert(table.remove(privacyQueries, 1))
    assert(missingProof.revision == revision)
    clock = clock + 2
    tick()
    privacyReply(missingProof, {})
    assert(#pending == 0, "An expired sight reply cannot start the encounter")
    if revision < 3 then clock = clock + 1; tick() end
end
assert(#privacyQueries == 0 and #speech == 0 and notices[#notices] == "failed",
    "Unresolved sight proof uses the technical failure toast")

arriveAtGround(false)
reply("validate_start", standing)
confirmPrivacy()
local startFailed = reply("start_autonomous_scene", {accepted = true})
clientCallbacks.event({name = "session_start_failed", request_id = startFailed.key, addon_id = "hzoi.gameplay",
    code = "start_failed"})
assert(notices[#notices] == "start_failed" and #completions == 5 and #outcomes == 2)

arriveAtGround(false)
reply("validate_start", standing)
confirmPrivacy()
local timedOut = reply("start_autonomous_scene", {accepted = true})
clock = clock + 60
tick()
local cancelCall = reply("cancel_start", {accepted = true})
assert(cancelCall.args.start_request_id == timedOut.key)
reply("get_request_status", {phase = "failed", code = "start_failed"})
assert(notices[#notices] == "timeout", "Confirm cancellation before dropping the owned start")

arriveAtGround(false)
reply("validate_start", standing)
confirmPrivacy()
local interrupted = reply("start_autonomous_scene", {accepted = true})
clientCallbacks.event(snapshot(interrupted, "interrupted", "playing", {name = "session_started"}))
clientCallbacks.event(snapshot(interrupted, "interrupted", "ended", {name = "session_ended",
    result_facts = {stop_reason = "runtime_error", cleanup_code = "runtime_error", cleanup_complete = true},
    task_state = taskCounts(0, 1)}))
assert(#completions == 6 and #outcomes == 2, "An interruption preserves confirmed completions")

arriveAtGround(false)
reply("validate_start", standing)
confirmPrivacy()
local missing = reply("start_autonomous_scene", {accepted = true})
clientCallbacks.event(snapshot(missing, "missing", "playing", {name = "session_started"}))
local witness = require("EncounterWitness")
local previousWitnessTick = witness.tick
witness.tick = function(record)
    record.witnessPolicy = {incidents = {{
        session_id = record.session_id, witness_id = tostring(observerId),
        cheater_id = tostring(ownerId), other_participant_id = tostring(partnerId),
    }}}
end
clock = clock + 9
tick()
witness.tick = previousWitnessTick
current = request("get_session")
clientCallbacks.response({request_id = current.key, ok = false, code = "session_not_found"})
reply("get_session_result", {result = require("SceneZOIAddon.Json").null})
assert(logs[#logs]:find("No verified ended result") and #completions == 6 and #outcomes == 2)
local terminalFailure = json.decode(assert(logs[#logs]:match("^%[HZoiGameplay%] failed (.+)$")))
assert(#terminalFailure.witness_incidents == 1
    and terminalFailure.witness_incidents[1].witness_id == tostring(observerId)
    and terminalFailure.witness_incidents[1].cheater_id == tostring(ownerId)
    and terminalFailure.witness_incidents[1].session_id == "missing",
    "Retain verified incidents when the terminal result cannot be recovered")
assert(#resultEffects == 2, "Ineligible outcomes never reach the relationship bonus")

line("Encounter results passed: request and roster matching, deduplication, lost notifications, cleanup, and unknown outcomes.")

local RETRY = "HZoiGameplay_WalkRetry"
local function recoveryAction(who, bag, reason)
    local actions = who:GetComponent()
    actions.GetCurrentInteractionQueueId = function() return bag and 76 or -1 end
    actions.GetCurrentInteractionBagId = function() return bag or "None" end
    actions.GetCurrentInteractionPlayReason = function() return reason end
    actions.InteractionQueue = {}
end

local function prepareOverlap()
    controlled, queued = ownerId, {}
    owner:MoveTo(point(0, 0, 0))
    partner:MoveTo(point(0, 0, 0))
    recoveryAction(owner)
    recoveryAction(partner)
    invite(partnerId, bedId)
    conversation(false)
    assert(#queued == 3 and #pending == 0)
    return queued[2].destination, queued[3].destination
end

local function finishWalk(who, id, position, bag)
    who:MoveTo(point(position.X, position.Y, position.Z + 90))
    fire("finished", id, bag or WALK, -1)
end

local ownerSpot, overlapSpot = prepareOverlap()
fire("canceled", partnerId, WALK, -1, "CharacterOverlap")
tick()
assert(#queued == 3, "Retry waits for the other walk")
recoveryAction(partner, "ClickMove_Self", "MoveOver")
finishWalk(owner, ownerId, ownerSpot)
tick()
assert(#queued == 3, "Retry waits for native recovery movement")
recoveryAction(partner)
tick()
local retry = assert(queued[4])
assert(#pending == 0 and retry.id == partnerId and retry.bag == RETRY)
assert(retry.destination.Z == overlapSpot.Z and retry.destination ~= overlapSpot)
assert((retry.destination.X - ownerSpot.X)^2 + (retry.destination.Y - ownerSpot.Y)^2 >= 150^2)
fire("finished", partnerId, WALK, -1)
tick()
assert(#pending == 0, "A late event from the original walk cannot confirm arrival")
finishWalk(partner, partnerId, retry.destination, RETRY)
tick()
reply("validate_start", {valid = false, code = "furniture_unavailable"})
assert(#pending == 0 and notices[#notices] == "furniture_unavailable", "Retried arrival still revalidates")

ownerSpot = prepareOverlap()
fire("canceled", partnerId, WALK, -1, 77)
fire("canceled", partnerId, "ClickMove_Self", -1, "User")
tick()
assert(#queued == 3 and #pending == 0 and notices[#notices] == "walk_failed")

ownerSpot = prepareOverlap()
fire("canceled", partnerId, WALK, -1, "CharacterOverlap")
finishWalk(owner, ownerId, ownerSpot)
recoveryAction(partner, "Eat", "User")
tick()
assert(#queued == 3 and #pending == 0 and notices[#notices] == "walk_failed")

prepareOverlap()
fire("canceled", ownerId, WALK, -1, "CharacterOverlap")
fire("canceled", partnerId, WALK, -1, "CharacterOverlap")
tick()
assert(#queued == 4 and queued[4].id == ownerId and queued[4].bag == RETRY)
finishWalk(owner, ownerId, queued[4].destination, RETRY)
tick()
assert(#queued == 5 and queued[5].id == partnerId and queued[5].bag == RETRY)
fire("canceled", partnerId, RETRY, -1, "CharacterOverlap")
tick()
assert(#queued == 5 and #pending == 0 and notices[#notices] == "walk_failed", "Only one retry per participant")

prepareOverlap()
fire("canceled", partnerId, WALK, -1, 1)
tick()
assert(#queued == 3 and #pending == 0 and notices[#notices] == "walk_failed")
line("Arrival overlap checks passed: serial retry, stale events, current native recovery, superseding actions, cancellation, and final revalidation.")

-- The same policy gates picker candidates and NPC/Urge eligibility in B2.
local life = require("LifeStageEligibility")
assert(life.allows(32) and life.allows(64) and life.allows(128) and life.allows(256))
assert(not life.allows(nil) and not life.allows(16) and not life.allows(1024))
local beforeCompatibility = #queued
partnerStage = 1024
invite(partnerId, alternateBedId)
assert(#queued == beforeCompatibility)
partnerStage, partnerGender = 32, 1
invite(partnerId, alternateBedId, nil, nil, false,
    {valid = false, code = "no_matching_scenes"})
assert(#queued == beforeCompatibility and notices[#notices] == "no_matching_scenes")
invite(partnerId, alternateBedId, nil, "EnqueueConditionCheckFail", false,
    {valid = true, scene_id = "custom.male_pair"})
assert(notices[#notices] == "not_eligible", "Same-sex content proceeds to the native invitation check")
ownerGender, partnerGender = 2, 2
invite(partnerId, alternateBedId, nil, "EnqueueConditionCheckFail", false,
    {valid = true, scene_id = "custom.female_pair"})
assert(notices[#notices] == "not_eligible", "Female/female content uses the same native invitation check")
ownerGender = 1
partnerGender = 2
