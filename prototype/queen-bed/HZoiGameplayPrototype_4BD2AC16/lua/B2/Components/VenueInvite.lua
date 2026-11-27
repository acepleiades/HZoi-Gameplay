local Client = require("SceneZOIAddon.Client")
local Json = require("SceneZOIAddon.Json")
local makeArguments = require("EncounterArguments")
local FurnitureKind = require("VenueFurnitureKind")
local Bed = require("BedArrival")
local Sofa = require("SofaArrival")
local Ground = require("GroundArrival")
local Witness = require("EncounterWitness")
local WitnessNative = require("WitnessNative")
local ArrivalPrivacy = require("ArrivalPrivacy")
local Ledger = require("EncounterLedger")
local Consequences = require("EncounterConsequences")
local Relationship = require("EncounterRelationship")
local NpcVenue = require("NpcVenue")
local Urges = require("OwnedEncounterUrges")
local Initiative = require("NpcInitiative")
local Eligibility = require("InvitationEligibility")

local M = {}
local INVITE = "HZoiGameplay_Invite"
local CONVERSATION_WALK = "ClickMove_Self"
local WALK = "HZoiGameplay_Walk"
local WALK_RETRY = "HZoiGameplay_WalkRetry"
local SELECT_VENUE = "HZoiGameplay_SelectVenue"
local FIND_VENUE = "HZoiGameplay_FindVenue"
local DIALOGUE = {
    accept = "Coop_TalkLike_Before_MakeLove",
    refuse = "Coop_TalkLike_Before_MakeLove_Fail",
}
local FEATURES = {
    "partner_picker", "autonomous_scenes", "autonomous_stages", "autonomous_stage_progress",
    "autonomous_stage_priorities", "autonomous_auto_restrictions", "autonomous_joint_goal_routes",
    "autonomous_post_completion_stay", "autonomous_manual_completion_exit", "session_results",
    "preflight_start_distance", "partner_picker_candidate_filter", "autonomous_auto_speed_minimum",
    "shared_interaction_menu",
}
local client, pollNpc
local attempts, participants, romancePicks = {}, {}, {}
local OBSERVATION_INTERVAL = 8
local INVITATION_AVAILABILITY_SECONDS = 10
local VENUE_CHECK_INTERVAL = 1
local PICKER_TIMEOUT_SECONDS = 300
local CONVERSATION_RETRY_DELAY_SECONDS = 2
local CONVERSATION_RETRY_WINDOW_SECONDS = 12
local CONVERSATION_START_GRACE_SECONDS = 10
local CONVERSATION_CLEAR_GRACE_SECONDS = 2
local START_CANCEL_GRACE_SECONDS = 20
local ARRIVAL_PRIVACY_RETRIES = 3
local ARRIVAL_PRIVACY_REPLY_SECONDS = 2
local subscriptions = {}
local venueSerial, npcSerial = 0, 0
local venueClick, beginAttempt, beginVenueSearch, guarded

local function log(attempt, phase, details)
    details = details or {}
    if attempt then
        details.request, details.initiator, details.partner, details.furniture =
            attempt.nonce, attempt.initiator, attempt.partner, attempt.furniture
        details.furniture_pair = attempt.seats and attempt.seats.id
        if attempt.ground then
            details.ground = {x = attempt.ground.X, y = attempt.ground.Y, z = attempt.ground.Z}
        end
    end
    print("[HZoiGameplay] " .. phase .. " " .. Json.encode(details))
end

local function id(value)
    local kind = type(value)
    if kind == "number" or kind == "string" then return tostring(value) end
    return value and tostring(value.Value)
end

local function entity(value)
    local result = inzoi.FB1EntityId()
    if value then result.Value = tonumber(value) end
    return result
end

local function manager()
    return inzoi.getB2Manager("FB2EntityManager")
end

local function actor(who)
    return manager():FindCharacter(entity(who))
end

local function interaction(person)
    return person:GetComponent(inzoi.EB2ComponentType.Interaction)
end

local function controlledId()
    return id(inzoi.FB2ControllerSystem.GetPossessEntityId())
end

local function carrier()
    return assert(actor(controlledId()), "The SceneZOI message carrier is unavailable")
end

local function forRequest(requestId)
    local nonce = type(requestId) == "string" and requestId:match("^encounter%.([a-z0-9_%-]+)%.")
    return nonce and attempts[nonce]
end

local function release(attempt)
    attempts[attempt.nonce] = nil
    if attempt.searchVenue then NpcVenue.release(attempt.nonce) end
    participants[attempt.initiator] = nil
    if attempt.partner then participants[attempt.partner] = nil end
end

local function notify(who, code)
    inzoi.message.send_to_client(entity(who), "HZoiGameplay.Notice", code)
end

local function queue(attempt, person, target, point, bag)
    local playReason = inzoi.EB1InteractionPlayReason
    local reason = attempt.npc and playReason.Autonomy or playReason.User
    local result = interaction(person):AddInteractionQueueByParam(
        target, point, bag, reason, false, false, "HZoiGameplay", true, false)
    return result == inzoi.EB1AddInteractionQueueResult.Success, result
end

local function cancel(person, bag)
    if person then
        pcall(function()
            interaction(person):TryCancelInteractionByBagId(bag, inzoi.EB1InteractionCancelReason.User,
                "HZoi Gameplay encounter stopped")
        end)
    end
end

local function cancelDialogue(who, target, bags)
    local person = actor(who)
    if not person then return end
    local ok, problem = pcall(function()
        local actions = interaction(person)
        local matching = {}
        for _, row in ipairs(actions.InteractionQueue or {}) do
            if bags[tostring(row.InteractionBagId)] and id(row.PickedEntityId) == target then
                matching[row.InteractionQueueId] = true
            end
        end
        local current = actions:GetCurrentInteractionQueueId()
        if current and current >= 0 and bags[tostring(actions:GetCurrentInteractionBagId())]
            and id(actions:GetCurrentInteractionTargetEntityId()) == target then
            matching[current] = true
        end
        for queueId in pairs(matching) do
            actions:TryCancelInteraction(queueId, inzoi.EB1InteractionCancelReason.User,
                "HZoi Gameplay invitation stopped")
        end
    end)
    if not ok then log(nil, "dialogue_cleanup_failed", {participant = who, reason = tostring(problem)}) end
end

local function fail(attempt, reason, notice, pickerMessage)
    if not attempt then return end
    local record = attempt.encounter
    local incidents = record and record.witnessPolicy and record.witnessPolicy.incidents
    log(attempt, "failed", {phase = attempt.phase, reason = tostring(reason),
        session = record and record.session_id, completions = record and record.completions,
        witness_incidents = incidents and #incidents > 0 and incidents or nil})
    -- Drop routing first. Native cancellation can publish another event immediately.
    release(attempt)
    if attempt.phase == "conversation" and attempt.invitationQueued then
        cancel(actor(attempt.initiator), INVITE)
        if attempt.conversationStarted then
            local requestBags, feedbackBags = {}, {}
            for branch, bag in pairs(DIALOGUE) do
                if not attempt.branch or attempt.branch == branch then
                    requestBags[bag], feedbackBags[bag .. "_Feedback"] = true, true
                end
            end
            cancelDialogue(attempt.initiator, attempt.partner, requestBags)
            cancelDialogue(attempt.partner, attempt.initiator, feedbackBags)
        end
    elseif attempt.phase == "walking" then
        for who, walk in pairs(attempt.walks) do
            if walk.bag and not walk.finished then cancel(actor(who), walk.bag) end
        end
    end
    if attempt.kind == "sofa.pair" then
        if notice == "furniture_unavailable" then notice = "sofa_unavailable" end
        if notice == "walk_failed" then notice = "sofa_walk_failed" end
    elseif attempt.ground and notice == "walk_failed" then
        notice = "ground_walk_failed"
    end
    if notice == "arrival_privacy_denied" then
        if controlledId() == attempt.initiator then notify(attempt.initiator, notice) end
    elseif notice == "game_paused" and type(pickerMessage) == "string" and not attempt.npc then
        inzoi.message.send_to_client(entity(attempt.initiator), "HZoiGameplay.PickerPaused", pickerMessage)
    elseif not attempt.npc then
        notify(attempt.initiator, notice or "failed")
    end
end

local function requestId(attempt, step)
    return "encounter." .. attempt.nonce .. "." .. step
end

local function request(attempt, step, operation, data)
    client:request(carrier(), requestId(attempt, step), operation, data)
end

local function cancelPendingStart(attempt, reason, notice)
    attempt.startCancellation = {reason = reason, notice = notice}
    attempt.deadline = os.time() + START_CANCEL_GRACE_SECONDS
    attempt.nextObservation = os.time()
    log(attempt, "start_cancel_requested", {reason = reason})
    request(attempt, "cancel-start", "cancel_start", {start_request_id = attempt.encounter.request_id})
end

local function validation(attempt, step)
    local args = {start_mode = "start_autonomous_scene"}
    for key, value in pairs(attempt.args) do args[key] = value end
    -- The two walks have not started yet. Keep the live furniture and joint
    -- goal checks, and defer the proximity check until both walks finish.
    if step == "invitation" or step:match("^venue%-") then
        args.check_start_distance = false
    end
    request(attempt, step, "validate_start", args)
end

local function confirmPair(attempt)
    local initiator, partner = actor(attempt.initiator), actor(attempt.partner)
    assert(initiator and partner, "Selected pair is unavailable")
    if attempt.npc then
        assert(Initiative.isPresent(initiator) and Initiative.isPresent(partner), "Selected pair is unavailable")
        assert(Initiative.canAct(initiator), "The initiator no longer has autonomy enabled")
    end
    if attempt.searchVenue then
        assert(Eligibility.canSelect(initiator, partner),
            "The selected pair no longer meets the invitation rules")
    end
    return initiator, partner
end

local function distanceSquared(a, b)
    return (a.X - b.X)^2 + (a.Y - b.Y)^2 + (a.Z - b.Z)^2
end

local function arrivalPoints(venue, initiator, partner, floor)
    if venue.ground then
        local first = venue.groundAnchor == id(initiator:GetEntityId())
        local other = first and partner or initiator
        local spot = Ground.partnerPoint(floor, venue.ground, other:GetLocation())
        if not spot then return end
        return first and {venue.ground, spot} or {spot, venue.ground}
    end
    local furniture = manager():FindGameObject(entity(venue.furniture))
    if not furniture then return nil, nil, "furniture_unavailable" end
    if not venue.seats then return Bed.points(furniture, floor, initiator, partner), furniture end
    local points = Sofa.points(venue.seats, furniture, floor)
    if points and distanceSquared(initiator:GetLocation(), points[1]) + distanceSquared(partner:GetLocation(), points[2]) >
        distanceSquared(initiator:GetLocation(), points[2]) + distanceSquared(partner:GetLocation(), points[1]) then
        points[1], points[2] = points[2], points[1]
    end
    return points, furniture
end

local function roomReady(attempt, initiator, partner, points)
    local available, reason = NpcVenue.recheck(attempt.nonce, initiator, partner, points)
    if not available then
        fail(attempt, "Private venue became unavailable: " .. tostring(reason), reason)
    end
    return available
end

local function furnitureStillThere(attempt)
    if not attempt.furniture then return true end
    local furniture = manager():FindGameObject(entity(attempt.furniture))
    if furniture and distanceSquared(furniture:GetLocation(), attempt.furnitureLocation) <= 1
        and math.abs((furniture:GetRotation().Yaw - attempt.furnitureYaw + 180) % 360 - 180) <= .1 then
        return furniture
    end
end

local function queueWalk(attempt, person, who, walk, bag)
    walk.bag = bag
    local spot = walk.point
    local queued, reason = queue(attempt, person, entity(), spot, bag)
    if not queued then
        walk.bag = nil
        fail(attempt, "Native walk could not be queued for " .. who .. ": " .. tostring(reason), "walk_failed")
        return false
    end
    if attempts[attempt.nonce] ~= attempt then return false end
    log(attempt, bag == WALK_RETRY and "walk_retry_queued" or "walk_queued",
        {participant = who, x = spot.X, y = spot.Y, z = spot.Z})
    return true
end

local function cancelReason(value, name)
    local expected = inzoi.EB1InteractionCancelReason[name]
    return tostring(value) == name or (expected ~= nil and value == expected)
end

local function overlapRecovery(bag, reason)
    local reasons = inzoi.EB1InteractionPlayReason
    return bag == WALK or tostring(reason) == "CharacterOverlap" or tostring(reason) == "MoveOver"
        or (reason ~= nil and (reason == reasons.CharacterOverlap or reason == reasons.MoveOver))
end

-- A native collision can leave the walk or its recovery action in the queue
-- until a later simulation tick. Let those settle and respect unrelated actions.
local function queueReadyForRetry(person)
    local actions = interaction(person)
    if actions:GetCurrentInteractionQueueId() > 0 then
        if overlapRecovery(tostring(actions:GetCurrentInteractionBagId()), actions:GetCurrentInteractionPlayReason()) then
            return false
        end
        return nil
    end
    local waiting = false
    for _, row in ipairs(actions.InteractionQueue or {}) do
        if not overlapRecovery(tostring(row.InteractionBagId), row.PlayReason) then return nil end
        waiting = true
    end
    return not waiting
end

local function alternativeBedPoint(original, partnerPoint, partnerLocation, bed, floor)
    local angle = math.atan(original.Y - partnerPoint.Y, original.X - partnerPoint.X)
    local center = bed:GetLocation()
    for _, turn in ipairs({0, .25, -.25, .5, -.5, .75, -.75}) do
        local yaw = angle + turn * math.pi
        local x, y = math.cos(yaw) * 110, math.sin(yaw) * 110
        local point = UE.FVector(original.X + x, original.Y + y, original.Z)
        local actualDx, actualDy = point.X - partnerLocation.X, point.Y - partnerLocation.Y
        if distanceSquared(point, center) <= 290^2 and distanceSquared(point, partnerPoint) >= 150^2
            and actualDx^2 + actualDy^2 >= 150^2 and floor:IsOnWalkableGrid(point)
            and floor:IsOnWalkableGrid(UE.FVector(original.X + x / 2, original.Y + y / 2, original.Z)) then
            return point
        end
    end
    return original
end

local function retryWalk(attempt)
    local first, second = attempt.walks[attempt.initiator], attempt.walks[attempt.partner]
    if not first or not second or not (first.retryPending or second.retryPending) then return end
    local who, walk, other, otherId
    if first.retryPending and (second.finished or second.retryPending) then
        who, walk, other, otherId = attempt.initiator, first, second, attempt.partner
    elseif second.retryPending and first.finished then
        who, walk, other, otherId = attempt.partner, second, first, attempt.initiator
    else
        return
    end
    local initiator, partner = confirmPair(attempt)
    local person, otherPerson = actor(who), actor(otherId)
    local ready = queueReadyForRetry(person)
    if ready == nil then
        fail(attempt, "A different action superseded the walk for " .. who, "walk_failed")
        return
    end
    if not ready then return end

    local floor = assert(inzoi.getB2Subsystem("FB2PathFindSystem"), "Path finder unavailable")
    local furniture = furnitureStillThere(attempt)
    if not furniture then
        fail(attempt, "The selected furniture changed before the walk could retry", "furniture_unavailable")
        return
    end
    if attempt.searchVenue then
        if not roomReady(attempt, initiator, partner, {first.point, second.point}) then return end
    elseif FurnitureKind.isBed(attempt.kind) then
        walk.point = alternativeBedPoint(walk.point, other.point, otherPerson:GetLocation(), furniture, floor)
    end
    if not floor:IsOnWalkableGrid(walk.point) then
        fail(attempt, "The arrival point became unavailable for " .. who, "walk_failed")
        return
    end
    walk.retryPending = nil
    queueWalk(attempt, person, who, walk, WALK_RETRY)
end

local function hasPlayerAction(person)
    local actions = interaction(person)
    local user = inzoi.EB1InteractionPlayReason.User
    if actions:IsPlayingInteraction() and actions:GetCurrentInteractionPlayReason() == user then return true end
    for _, row in ipairs(actions.InteractionQueue or {}) do
        if row.PlayReason == user then return true end
    end
    return false
end

local function beginWalking(attempt)
    local initiator, partner = confirmPair(attempt)
    if attempt.npc and (hasPlayerAction(initiator) or hasPlayerAction(partner)) then
        fail(attempt, "A player action superseded the autonomous approach", "busy")
        return
    end
    local floor = assert(inzoi.getB2Subsystem("FB2PathFindSystem"), "Path finder unavailable")
    local points, furniture, reason
    if attempt.searchVenue then
        points = attempt.candidate.arrival_points
        if not roomReady(attempt, initiator, partner, points) then return end
        if attempt.furniture then
            furniture = manager():FindGameObject(entity(attempt.furniture))
            if not furniture or distanceSquared(furniture:GetLocation(), attempt.candidate.point) > 1
                or math.abs((furniture:GetRotation().Yaw - attempt.candidate.furniture_yaw + 180) % 360 - 180) > .1 then
                fail(attempt, "The selected furniture moved during the invitation", "furniture_unavailable")
                return
            end
        end
    else
        points, furniture, reason = arrivalPoints(attempt, initiator, partner, floor)
    end
    if not points then fail(attempt, "No two separate arrival points at the selected venue", reason or "walk_failed"); return end
    if furniture then
        attempt.furnitureLocation = furniture:GetLocation()
        attempt.furnitureYaw = furniture:GetRotation().Yaw
    end
    attempt.phase, attempt.deadline = "walking", os.time() + 60
    for index, person in ipairs({initiator, partner}) do
        local who, spot = id(person:GetEntityId()), points[index]
        local walk = {point = spot}
        attempt.walks[who] = walk
        if not queueWalk(attempt, person, who, walk, WALK) then return end
    end
end

local function positiveId(value)
    local candidate = id(value)
    return candidate and candidate:match("^[1-9]%d*$")
end

local function readVenueClick(person, eventTarget)
    local actions = interaction(person)
    local isCurrent = tostring(actions:GetCurrentInteractionBagId()) == SELECT_VENUE
    local currentId = isCurrent and actions:GetCurrentInteractionQueueId()
    local eventFurniture = positiveId(eventTarget)
    if eventFurniture and not manager():FindGameObject(entity(eventFurniture)) then eventFurniture = nil end
    -- interaction.started fires before the game assigns the current bag and
    -- queue ID. The unique queued request still holds the original selection.
    for _, row in ipairs(actions.InteractionQueue or {}) do
        if tostring(row.InteractionBagId) == SELECT_VENUE and (not isCurrent or row.InteractionQueueId == currentId) then
            local picked = id(row.PickedEntityId)
            local furniture = positiveId(picked) or eventFurniture
            if furniture then return furniture end
            if tonumber(picked) and row.ImpactPoint then return nil, row.ImpactPoint end
            break
        end
    end
    if eventFurniture then return eventFurniture end
    if isCurrent then
        local picked = id(actions:GetCurrentInteractionPickedEntityId())
        local furniture = positiveId(picked)
        if furniture then return furniture end
        if not tonumber(picked) then return end
        local ok, action = pcall(actions.GetCurrentAction, actions, inzoi.EB1ActionType.Delay)
        if ok and action then return nil, action.NonTargetLocation end
    end
end

local function consumeVenueClick(who)
    if not venueClick or venueClick.who ~= who then return end
    if who ~= controlledId() then
        venueClick = nil
        return
    end
    local person = actor(who)
    if not person then return end
    local furniture, point = readVenueClick(person, venueClick.target)
    if not furniture and not point then return end
    venueClick = nil
    venueSerial = venueSerial + 1
    local nonce = ("venue-%d-%d"):format(os.time(), venueSerial)
    beginAttempt(who, nonce, furniture, point and UE.FVector(point.X, point.Y, point.Z))
end

local function deliverRelationship(attempt, name, ...)
    local ok, effect = pcall(Relationship[name], attempt, ...)
    if not ok then
        log(attempt, "relationship_effect_failed", {handler = name, reason = tostring(effect)})
    elseif effect then
        log(attempt, "relationship_effect", effect)
    end
end

local function finishRefusal(attempt)
    local first, second = attempt.initiator, attempt.partner
    if attempt.branch ~= "refuse" or not attempt.conversationDispatched
        or attempt.dialogue[first] ~= "finished" or attempt.dialogue[second] ~= "finished" then return end
    -- Settle the completed native response before subsequent eligibility changes can cancel it.
    deliverRelationship(attempt, "onRefusal", actor(first), actor(second))
    log(attempt, "refused")
    release(attempt)
end

local function startingQueueEntry(actions, bag)
    local row = (actions.InteractionQueue or {})[1]
    return row and tostring(row.InteractionBagId) == bag and row or nil
end

local function invitationCoop(attempt, scheduler)
    for _, coop in pairs(manager():GetAllEntities(inzoi.EB2EntityType.CoopScheduler) or {}) do
        if (not scheduler or id(coop:GetEntityId()) == scheduler)
            and tostring(coop.OriginInteractionBagId) == INVITE
            and id(coop.HostId) == attempt.initiator and id(coop.MainTargetId) == attempt.partner then
            return coop
        end
    end
end

local function conversationDispatched(attempt, coop)
    attempt.coopHandoffUntil = nil
    attempt.conversationDispatched = os.time()
    if coop then
        log(attempt, "conversation_handoff", {scheduler = id(coop:GetEntityId()),
            coop = tostring(coop.CoopId), result = tostring(coop.CurrentResult)})
    end
    finishRefusal(attempt)
end

local function recordConversationWalk(attempt, who)
    local actions = interaction(actor(who))
    -- "started" arrives before the game moves the action from the queue to current.
    local row = startingQueueEntry(actions, CONVERSATION_WALK)
    local scheduler = row and row.CoopSchedulerId or actions:GetCurrentCoopSchedulerId()
    local schedulerId = positiveId(id(scheduler))
    local coop = schedulerId and invitationCoop(attempt, schedulerId)
    if not coop then return end
    -- HZoi reports terminal invitation failures itself. A blocked
    -- approach can recover, so the native cancel toast is premature.
    if not attempt.npc then coop.bSuppressNextCancelToast = true end
    attempt.conversationWalks = attempt.conversationWalks or {}
    attempt.conversationWalks[who] = true
    if attempt.coopHandoffUntil then conversationDispatched(attempt, coop) end
end

local function onConversationWalk(attempt, kind, who, reason)
    if kind == "started" then
        -- The same move bag is used by unrelated native conversations.
        if not attempt.branch then recordConversationWalk(attempt, who) end
        return
    end
    local walks = attempt.conversationWalks
    if not walks or not walks[who] then return end
    walks[who] = nil
    if kind == "finished" then return end
    log(attempt, "conversation_walk_failed", {participant = who, reason = tostring(reason)})
    if cancelReason(reason, "FailedMoveOver") and not attempt.branch then
        if attempt.npc or attempt.conversationRetried then
            fail(attempt, "Could not reach the native conversation spot: FailedMoveOver")
            return
        end
        local now = os.time()
        attempt.conversationRetry = {earliest = now + CONVERSATION_RETRY_DELAY_SECONDS,
            expires = now + CONVERSATION_RETRY_WINDOW_SECONDS}
    elseif cancelReason(reason, "User") then
        fail(attempt, "The player canceled the conversation approach")
    end
end

local function onAttemptAction(attempt, kind, event, who, target, bag)
    local initiator, partner = attempt.initiator, attempt.partner
    local reason = event.Reason or event.reason
    if attempt.phase == "conversation" and who == initiator and target == partner and bag == INVITE then
        if kind == "started" then
            attempt.conversationStarted = true
            log(attempt, "conversation_started")
        elseif kind == "finished" then
            -- RequestCoop finishes before either Zoi starts talking.
            if attempt.conversationStarted then conversationDispatched(attempt) end
        elseif kind == "canceled" and attempt.conversationStarted and cancelReason(reason, "Coop") then
            -- The scheduler can replace RequestCoop with its own role actions.
            -- Only a scheduler for this invitation and pair proves that handoff.
            local coop = invitationCoop(attempt)
            if coop then
                conversationDispatched(attempt, coop)
            else
                attempt.coopHandoffUntil = os.time() + CONVERSATION_CLEAR_GRACE_SECONDS
            end
        else
            fail(attempt, "Invitation " .. kind .. ": " .. tostring(reason))
        end
    elseif attempt.phase == "conversation" and attempt.conversationStarted then
        if bag == CONVERSATION_WALK then
            onConversationWalk(attempt, kind, who, reason)
            return
        end
        if attempt.conversationRetry and kind == "started" then
            local actions = interaction(actor(who))
            local row = startingQueueEntry(actions, bag)
            local playReason = event.play_reason or (row and row.PlayReason) or actions:GetCurrentInteractionPlayReason()
            if tostring(playReason) == "User" or playReason == inzoi.EB1InteractionPlayReason.User then
                fail(attempt, "A new player action superseded the invitation retry")
                return
            end
        end
        local branch
        for answer, dialogue in pairs(DIALOGUE) do
            if (who == initiator and target == partner and bag == dialogue)
                or (who == partner and target == initiator and bag == dialogue .. "_Feedback") then
                branch = answer
                break
            end
        end
        if not branch then return end
        if kind == "started" then
            if attempt.branch and attempt.branch ~= branch then
                fail(attempt, "The two Zoi conversation roles selected different responses")
                return
            end
            attempt.conversationRetry = nil
            attempt.branch, attempt.dialogue[who] = branch, "started"
        elseif attempt.branch == branch and attempt.dialogue[who] == "started" then
            if kind == "finished" then
                attempt.dialogue[who] = "finished"
                log(attempt, "dialogue_finished", {participant = who, branch = branch})
                finishRefusal(attempt)
            else
                fail(attempt, "Conversation " .. kind .. " for " .. who .. ": " .. tostring(reason))
            end
        end
    elseif attempt.phase == "walking" then
        local walk = attempt.walks[who]
        if not walk then return end
        if walk.finished then
            local reason = event.play_reason or event.reason
            if attempt.searchVenue and kind == "started" and bag ~= walk.bag
                and (tostring(reason) == "User" or (reason ~= nil and reason == inzoi.EB1InteractionPlayReason.User)) then
                walk.userAction = true
            end
            return
        end
        if walk.retryPending and kind == "canceled" and cancelReason(event.reason, "User") then
            fail(attempt, "Walk retry canceled by the player for " .. who, "walk_failed")
        elseif bag == walk.bag then
            if kind == "finished" then
                walk.finished = true
            elseif bag == WALK and kind == "canceled" and cancelReason(event.reason, "CharacterOverlap") then
                walk.bag, walk.retryPending = nil, true
                walk.hadOverlap = true
                log(attempt, "walk_retry_waiting", {participant = who, reason = "CharacterOverlap"})
            elseif kind ~= "started" then
                fail(attempt, "Walk " .. kind .. " for " .. who .. ": " .. tostring(event.reason), "walk_failed")
            end
        end
    end
end

local function onNativeEvent(kind, event)
    local who, target = id(event.entity_id), id(event.target_entity_id)
    local bag = tostring(event.interaction_bag_id)
    if bag == FIND_VENUE then
        if not who then return end
        if kind == "started" then
            local person = actor(who)
            local actions = person and interaction(person)
            local queued = actions and startingQueueEntry(actions, FIND_VENUE)
            if who == controlledId() or (queued and queued.PlayReason == inzoi.EB1InteractionPlayReason.User) then
                romancePicks[who] = {partner = queued and positiveId(id(queued.PickedEntityId)) or positiveId(target)}
            end
        else
            local pick = romancePicks[who]
            romancePicks[who] = nil
            if kind == "finished" and pick then
                local partner = pick.partner or positiveId(target)
                local started, notice = beginVenueSearch(who, partner)
                if not started and notice and who == controlledId() then notify(who, notice) end
            end
        end
        return
    end
    if bag == SELECT_VENUE then
        if kind == "started" and who == controlledId() then
            venueClick = {who = who, target = target, deadline = os.time() + 2}
        elseif kind == "failed" or kind == "canceled" then
            if venueClick and venueClick.who == who then venueClick = nil end
            return
        end
        if venueClick and venueClick.who == who then
            if not positiveId(venueClick.target) then venueClick.target = target end
            pcall(consumeVenueClick, who)
        end
        return
    end
    local active = participants[who]
    if active then guarded(active, onAttemptAction, kind, event, who, target, bag) end
end

local function validated(attempt, step, result)
    if not result.valid or result.route_uncertain then
        fail(attempt, step .. ": " .. tostring(result.code or "uncertain goal route"), result.code or "no_matching_scenes")
        return false
    end
    if attempt.seats and result.furniture_pair_id ~= attempt.seats.id then
        fail(attempt, step .. ": SceneZOI did not confirm the selected sofa pair", "furniture_unavailable")
        return false
    end
    return true
end

local function discoverVenue(attempt, step, participants)
    request(attempt, step, "find_furniture", {origin_id = attempt.initiator, radius_m = 100,
        include_unavailable = true, participants = participants})
end

local function selectSofaSeats(attempt, rows)
    local furniture = manager():FindGameObject(entity(attempt.furniture))
    if not furniture then fail(attempt, "Selected sofa is no longer loaded", "furniture_unavailable"); return end
    local floor = assert(inzoi.getB2Subsystem("FB2PathFindSystem"), "Path finder unavailable")
    local hasSeats = false
    for _, row in ipairs(rows) do
        if row.furniture_id == attempt.furniture and row.profile.kind == "sofa.pair" and row.available then
            hasSeats = true
            local seats = Sofa.seats(row)
            if seats and Sofa.points(seats, furniture, floor) then
                attempt.seats = seats
                log(attempt, "sofa_pair_selected", {spots = row.sitting_spots})
                request(attempt, "definitions", "get_definitions")
                return
            end
        end
    end
    if hasSeats then
        fail(attempt, "No walkable approach to an available sofa pair", "walk_failed")
    else
        fail(attempt, "No adjacent sofa seats available for this roster", "furniture_unavailable")
    end
end

local function openPicker(attempt)
    if controlledId() ~= attempt.initiator then
        release(attempt)
        return
    end
    local owner = actor(attempt.initiator)
    if not Eligibility.moodAllowsInvitation(owner) then
        fail(attempt, "The initiator's mood does not allow an invitation", "mood_blocked")
        return
    end
    local candidates = Json.array({})
    local actors = manager()
    for _, current in pairs(actors:GetAllEntities(inzoi.EB2EntityType.Character)) do
        local nativeId = current:GetEntityId()
        if id(nativeId) ~= attempt.initiator and current:IsSpawned() then
            local candidate = actors:FindCharacter(nativeId)
            if Eligibility.canSelect(owner, candidate) then candidates[#candidates + 1] = id(nativeId) end
        end
    end
    if #candidates == 0 then
        fail(attempt, "No eligible partners are loaded", "no_eligible_partners")
        return
    end
    attempt.phase, attempt.deadline = "picking", os.time() + PICKER_TIMEOUT_SECONDS
    request(attempt, "picker", "open_partner_picker", {candidate_ids = candidates})
end

local function recoverDisplacedZoi(attempt, who, walk, other, initiator, partner)
    if not attempt.searchVenue or attempt.phase ~= "walking" or attempt.reapproachUsed
        or not walk.reported or walk.hadOverlap or not other.hadOverlap or walk.userAction then return false end
    local person = actor(who)
    local ready = queueReadyForRetry(person)
    if ready == nil then return false end
    if not ready then return true end
    if not furnitureStillThere(attempt) then
        fail(attempt, "The selected furniture changed before the Zoi could return", "furniture_unavailable")
        return true
    end
    if not roomReady(attempt, initiator, partner,
        {attempt.walks[attempt.initiator].point, attempt.walks[attempt.partner].point}) then return true end

    attempt.reapproachUsed = true
    walk.finished, walk.reported = nil, nil
    log(attempt, "walk_return_after_overlap", {participant = who})
    queueWalk(attempt, person, who, walk, WALK_RETRY)
    return true
end

local function arrived(attempt)
    local initiator, partner = confirmPair(attempt)
    local first, second = attempt.walks[attempt.initiator], attempt.walks[attempt.partner]
    local bothFinished = first and second and first.finished and second.finished
    local floor = attempt.ground and inzoi.getB2Subsystem("FB2PathFindSystem")
    local displaced
    for _, who in ipairs({attempt.initiator, attempt.partner}) do
        local walk = attempt.walks[who]
        if walk and walk.finished then
            if attempt.ground and not Ground.walkable(floor, walk.point) then
                fail(attempt, "A ground arrival point became unavailable for " .. who, "walk_failed")
                return false
            end
            local person = who == attempt.initiator and initiator or partner
            local position = person:GetLocation()
            local horizontal = math.sqrt((position.X - walk.point.X)^2 + (position.Y - walk.point.Y)^2)
            -- ClickMove takes a floor point; GetLocation includes the Zoi's capsule height.
            local height = math.abs(position.Z - walk.point.Z)
            local limit = attempt.ground and 65 or 80
            if horizontal <= limit and height <= 125 then
                if not walk.reported then
                    walk.reported = true
                    log(attempt, "walk_arrived", {participant = who, horizontal_cm = horizontal, height_cm = height})
                end
            elseif bothFinished then
                local problem = string.format("Walk ended away from the target for %s (%.1f cm across, %.1f cm in height)",
                    who, horizontal, height)
                if displaced or height > 125 then
                    fail(attempt, problem, "walk_failed")
                    return false
                end
                displaced = {who = who, walk = walk, other = walk == first and second or first, problem = problem}
            end
        end
    end
    -- A paired walk can push the first arrival away before the other walk or
    -- its native recovery finishes. Only try to return to an already verified spot.
    if displaced then
        if not recoverDisplacedZoi(attempt, displaced.who, displaced.walk, displaced.other, initiator, partner) then
            fail(attempt, displaced.problem, "walk_failed")
        end
        return false
    end
    return bothFinished == true
end

local function deliverConsequence(attempt, name, ...)
    local ok, problem = pcall(Consequences[name], ...)
    if not ok then log(attempt, "consequence_failed", {handler = name, reason = tostring(problem)}) end
end

local function observeWitnesses(attempt, callback, ...)
    local ok, problem = pcall(callback, ...)
    if not ok and not attempt.witnessError then
        attempt.witnessError = true
        log(attempt, "witness_update_failed", {reason = tostring(problem)})
    end
end

local function onOrdinarySighting(attempt, who, seenParticipant, shouldWalkAway)
    local witness, nearbyParticipant = actor(who), actor(seenParticipant)
    local ok, requested = pcall(WitnessNative.addMoodlet, witness, "HZoiGameplay_SawEncounter", nearbyParticipant)
    if not ok then
        log(attempt, "witness_moodlet_failed", {witness = who, reason = tostring(requested)})
    elseif requested then
        log(attempt, "witness_surprised", {witness = who})
    end
    if not shouldWalkAway or who == controlledId() or participants[who] then return end
    local result = WitnessNative.walkAway(witness, nearbyParticipant)
    if result then log(attempt, "witness_walk", {witness = who, enqueue_result = tostring(result)}) end
end

local function stopForWitness(attempt, reason, explanation)
    local args = {session_id = attempt.encounter.session_id, reason = reason}
    if attempt.stopDisplayReason then args.display_reason = explanation end
    request(attempt, "witness-stop", "request_stop", args)
end

local function completed(attempt, record, who, task, index)
    log(attempt, "task_completed", {session = record.session_id, participant = who, task = task, index = index})
    deliverConsequence(attempt, "onCompletion", record, who, task, index)
    local person = actor(who)
    if person then
        local ok, earned = pcall(Urges.onCompletion, record, person, task)
        if ok and earned then log(attempt, "urge_completed", {participant = who, session = record.session_id}) end
        if not ok then log(attempt, "urge_handoff_failed", {participant = who, reason = tostring(earned)}) end
    end
end

local function observeSession(attempt, snapshot)
    local record = attempt.encounter
    local wasStarted = record.started
    local observed, countsComplete = Ledger.observe(record, snapshot, function(...) completed(attempt, ...) end)
    if not observed then return false end
    if record.started and not wasStarted then
        if snapshot.phase == "playing" then record.arrivalPlaybackRevision = snapshot.revision end
        log(attempt, "session_started", {scene = snapshot.node_id, session = record.session_id})
        local onPlaybackStarted = attempt.onPlaybackStarted
        attempt.onPlaybackStarted = nil
        if onPlaybackStarted then
            local cooldown = onPlaybackStarted()
            if cooldown then log(attempt, "initiative_cooldown", cooldown) end
        end
    end
    if snapshot.phase == "ended" or snapshot.name == "session_ended" then
        local result = Ledger.finish(record, snapshot, countsComplete)
        log(attempt, "session_ended", {session = record.session_id, outcome = result.plan and result.plan.outcome,
            reason = result.stop_reason, cleanup = result.cleanup_code, restored = result.cleanup_complete,
            completions = record.completions, task_counts_complete = countsComplete,
            outcome_eligible = result.apply_outcome})
        observeWitnesses(attempt, Witness.finish, record, result, function(who)
            if not participants[who] or participants[who] == attempt then return actor(who) end
        end, function(...) log(attempt, ...) end)
        if result.apply_outcome then
            deliverRelationship(attempt, "onResult", record, result, actor(attempt.initiator), actor(attempt.partner))
            deliverConsequence(attempt, "onResult", record, result)
        end
        release(attempt)
    elseif snapshot.phase == "exiting" then
        attempt.phase = "exiting"
    elseif record.started and attempt.phase == "starting" then
        attempt.phase = "playing"
    end
    return true
end

local function observeByRequest(attempt, operation, args)
    attempt.observationSerial = attempt.observationSerial + 1
    local step = "observe-" .. attempt.observationSerial
    attempt.observation = {step = step, operation = operation}
    attempt.nextObservation = os.time() + OBSERVATION_INTERVAL
    request(attempt, step, operation, args)
end

local function readEndedResult(attempt)
    observeByRequest(attempt, "get_session_result", {session_id = attempt.encounter.session_id})
end

local function onObservation(attempt, reply)
    local operation = attempt.observation.operation
    attempt.observation = nil
    local result = reply.result
    if not reply.ok then
        if operation == "get_session" and reply.code == "session_not_found" then
            readEndedResult(attempt)
            return
        end
        attempt.observationFailures = (attempt.observationFailures or 0) + 1
        if attempt.observationFailures >= 2 then fail(attempt, "Session outcome unavailable: " .. tostring(reply.code)) end
        return
    end
    attempt.observationFailures = nil
    if operation == "get_request_status" then
        if result.phase == "failed" then
            local cancellation = attempt.startCancellation
            fail(attempt, cancellation and cancellation.reason or result.code or "start_failed",
                cancellation and cancellation.notice or result.code)
        elseif type(result.session_id) == "string" then
            if result.phase == "ended" then
                attempt.encounter.session_id = result.session_id
                readEndedResult(attempt)
            else
                observeByRequest(attempt, "get_session", {session_id = result.session_id})
            end
        end
    elseif operation == "get_session" then
        if not result.session or not observeSession(attempt, result.session) then fail(attempt, "Could not match the current session") end
    elseif not result.result or not observeSession(attempt, result.result) then
        fail(attempt, "No verified ended result for the selected encounter")
    end
end

local function prepareArguments(attempt, initiator, partner)
    local male = inzoi.EB1GenderType.Male
    -- Iteration 1 uses the native two-Zoi invitation and approach.
    local roster = {attempt.initiator, attempt.partner}
    local args, reason = makeArguments(attempt.actionDefinitions, attempt.initiator, roster, attempt.furniture,
        attempt.seats and attempt.seats.id,
        initiator:GetGenderType() == male and partner:GetGenderType() == male)
    if not args then fail(attempt, reason, reason); return false end
    if attempt.npc then args.background = true end
    attempt.args = args
    return true
end

local function nextVenue(attempt)
    attempt.candidateIndex = (attempt.candidateIndex or 0) + 1
    local candidate = attempt.candidates[attempt.candidateIndex]
    if not candidate then
        fail(attempt, "No compatible reachable venue", "no_matching_scenes")
        return
    end
    attempt.candidate = candidate
    attempt.kind, attempt.furniture, attempt.seats = candidate.kind, candidate.furniture_id, candidate.seats
    attempt.ground, attempt.groundAnchor = candidate.ground, candidate.groundAnchor
    local initiator, partner = confirmPair(attempt)
    if prepareArguments(attempt, initiator, partner) then
        validation(attempt, "venue-" .. attempt.candidateIndex)
    end
end

local function collectVenues(attempt, rows)
    local initiator, partner = confirmPair(attempt)
    local fallbackAnchor = initiator:GetGenderType() == inzoi.EB1GenderType.Male
        and attempt.initiator or attempt.partner
    local candidates, reason, rejected = NpcVenue.candidates(initiator, partner, rows, nil, function(option, floor)
        option.furniture = option.furniture_id
        if option.kind == "sofa.pair" then
            option.seats = Sofa.seats(option.row)
            if not option.seats then return end
        elseif option.kind == "ground" then
            option.ground, option.groundAnchor = option.point, fallbackAnchor
        end
        local points, furniture = arrivalPoints(option, initiator, partner, floor)
        if furniture then option.furniture_yaw = furniture:GetRotation().Yaw end
        return points
    end)
    attempt.candidates = candidates
    log(attempt, "venues_ranked", {count = #candidates, reason = reason, rejected = rejected, furniture_rows = #rows})
    if #candidates == 0 then
        fail(attempt, reason or "No reachable venue", "no_reachable_venue")
        return
    end
    request(attempt, "definitions", "get_definitions")
end

local function queueInvitation(attempt, initiator, partner)
    if not Eligibility.canInvite(initiator, partner) then
        fail(attempt, "The pair no longer meets the native invitation rules", "not_eligible")
        return
    end
    local queued, reason = queue(attempt, initiator, partner:GetEntityId(), partner:GetLocation(), INVITE)
    if not queued then
        local denied = reason == inzoi.EB1AddInteractionQueueResult.EnqueueConditionCheckFail
        fail(attempt, "Invitation enqueue failed: " .. tostring(reason), denied and "not_eligible" or "queue_failed")
        return
    end
    attempt.invitationQueued = true
    log(attempt, attempt.conversationRetried and "invitation_requeued" or "invitation_queued")
end

local function ask(attempt, initiator, partner, result)
    if attempt.ground then
        -- Keep the preflight's scene and roles so the same Zoi anchors playback
        -- at the clicked or explicitly selected location.
        attempt.args.scene_id, attempt.args.bindings = result.scene_id, result.bindings
        attempt.groundAnchor = assert(result.anchor_participant_id, "SceneZOI did not identify the ground anchor")
    end
    attempt.phase, attempt.deadline = "conversation", os.time() + 90
    queueInvitation(attempt, initiator, partner)
end

local function askWhenAvailable(attempt, initiator, partner, result)
    local first, second = Initiative.readiness(initiator), Initiative.readiness(partner)
    if not first or not second then
        fail(attempt, "A Zoi became unavailable for the autonomous invitation", "busy")
    elseif first == "ready" and second == "ready" and Initiative.isSimulationRunning() then
        if attempt.phase == "awaiting_availability"
            and not roomReady(attempt, initiator, partner, attempt.candidate.arrival_points) then return end
        attempt.pendingInvitationResult = nil
        ask(attempt, initiator, partner, result)
    elseif attempt.phase ~= "awaiting_availability" then
        attempt.phase, attempt.deadline = "awaiting_availability", os.time() + INVITATION_AVAILABILITY_SECONDS
        attempt.pendingInvitationResult = result
        log(attempt, "invitation_waiting_for_availability", {initiator_state = first, partner_state = second})
    end
end

local function considerVenue(attempt, result)
    if not result.valid or result.route_uncertain
        or (attempt.seats and result.furniture_pair_id ~= attempt.seats.id) then
        log(attempt, "venue_rejected", {reason = result.code or "route_uncertain"})
        nextVenue(attempt)
        return
    end
    local initiator, partner = confirmPair(attempt)
    if attempt.npc and not (Initiative.readiness(initiator) and Initiative.readiness(partner)) then
        fail(attempt, "The NPC pair is busy", "busy")
        return
    end
    local candidate = attempt.candidate
    local actualAnchor = attempt.ground and assert(result.anchor_participant_id, "SceneZOI did not identify the ground anchor")
    if actualAnchor and actualAnchor ~= candidate.groundAnchor then
        local points = candidate.arrival_points
        points[1], points[2] = points[2], points[1]
        candidate.groundAnchor = actualAnchor
    end
    local claimed, reason = NpcVenue.claim(attempt.nonce, candidate, initiator, partner)
    if not claimed then
        log(attempt, "venue_rejected", {reason = reason})
        nextVenue(attempt)
        return
    end
    log(attempt, "venue_claimed", {site = candidate.site_id, room = candidate.room_purpose,
        kind = candidate.kind, furniture_id = candidate.furniture_id, assigned_bed = candidate.assigned,
        occupied_room_fallback = candidate.occupied})
    if attempt.npc then
        askWhenAvailable(attempt, initiator, partner, result)
    else
        ask(attempt, initiator, partner, result)
    end
end

local function arrivalReady(attempt)
    local initiator, partner = confirmPair(attempt)
    if not arrived(attempt) then
        if attempts[attempt.nonce] == attempt then
            fail(attempt, "Could not confirm both arrivals", "walk_failed")
        end
        return
    end
    local points = {attempt.walks[attempt.initiator].point, attempt.walks[attempt.partner].point}
    if attempt.searchVenue and not roomReady(attempt, initiator, partner, points) then return end
    local floor = inzoi.getB2Subsystem("FB2PathFindSystem")
    if not floor or not floor:IsOnWalkableGrid(points[1]) or not floor:IsOnWalkableGrid(points[2]) then
        fail(attempt, "The arrival points became unavailable", "walk_failed")
        return
    end
    if not furnitureStillThere(attempt) then
        fail(attempt, "The selected furniture changed during arrival", "furniture_unavailable")
        return
    end
    return initiator, partner
end

local function startAfterPrivacy(attempt, witnesses)
    attempt.phase, attempt.deadline = "starting", os.time() + 60
    attempt.encounter = Ledger.new(requestId(attempt, "start"), client.client_id, attempt, attempt.args.participants)
    attempt.encounter.arrivalWitnesses = witnesses
    local locations = {}
    for witnessId in pairs(witnesses) do
        local witness = actor(witnessId)
        if witness then locations[witnessId] = witness:GetLocation() end
    end
    attempt.encounter.arrivalWitnessLocations = locations
    attempt.observationSerial, attempt.nextObservation = 0, os.time() + OBSERVATION_INTERVAL
    request(attempt, "start", "start_autonomous_scene", attempt.args)
end

local function retryPrivacy(attempt, reason, witness)
    local privacy = attempt.arrivalPrivacy
    privacy.pending = nil
    log(attempt, "arrival_privacy_unresolved", {revision = privacy.revision, reason = reason, witness = witness})
    if privacy.revision >= ARRIVAL_PRIVACY_RETRIES then
        fail(attempt, "Could not confirm privacy at the venue: " .. reason)
        return
    end
    privacy.next = os.time() + 1
end

local function requestPrivacy(attempt)
    if not arrivalReady(attempt) then return end
    local privacy = attempt.arrivalPrivacy
    privacy.revision = privacy.revision + 1
    local token = requestId(attempt, "arrival-privacy-" .. privacy.revision)
    local owner = carrier()
    privacy.pending = {token = token, carrier = id(owner:GetEntityId()), expires = os.time() + ARRIVAL_PRIVACY_REPLY_SECONDS}
    local points = {}
    for _, who in ipairs(attempt.args.participants) do
        local point = attempt.walks[who].point
        points[who] = {x = point.X, y = point.Y, z = point.Z}
    end
    local ok, problem = pcall(inzoi.message.send_to_client, owner:GetEntityId(), "HZoiGameplay.WitnessTrace",
        Json.encode({kind = "arrival", token = token, revision = privacy.revision,
            participants = attempt.args.participants, points = points}))
    if not ok then retryPrivacy(attempt, tostring(problem)) end
end

local function onArrivalPrivacy(attempt, reply, who)
    local privacy = attempt.arrivalPrivacy
    local pending = privacy and privacy.pending
    if not pending or pending.token ~= reply.token or pending.carrier ~= who
        or reply.revision ~= privacy.revision or os.time() >= pending.expires then return end
    if reply.diagnostic then
        retryPrivacy(attempt, tostring(reply.diagnostic))
        return
    end
    local meta = type(reply.observations) == "table" and getmetatable(reply.observations)
    if not meta or meta.__jsonkind ~= "array" then
        retryPrivacy(attempt, "observations_invalid")
        return
    end
    if not arrivalReady(attempt) then return end
    local ok, witnesses, reason, witness = pcall(ArrivalPrivacy.evaluate, attempt.args.participants,
        reply.observations, actor, WitnessNative.relationshipScore)
    if not ok or witnesses == nil then
        retryPrivacy(attempt, ok and reason or tostring(witnesses), witness)
        return
    end
    if witnesses == false then
        log(attempt, "arrival_privacy_denied", {witness = witness})
        fail(attempt, reason, "arrival_privacy_denied")
        return
    end
    log(attempt, "arrival_privacy_confirmed", {visible = #reply.observations})
    attempt.arrivalPrivacy = nil
    startAfterPrivacy(attempt, witnesses)
end

local function onResponse(attempt, reply)
    local prefix = "encounter." .. attempt.nonce .. "."
    if reply.request_id:sub(1, #prefix) ~= prefix then return end
    local step = reply.request_id:sub(#prefix + 1)
    if step == "cancel-start" then
        log(attempt, "start_cancel_reply", {ok = reply.ok, code = reply.code})
        return
    end
    if step == "witness-stop" then
        log(attempt, "witness_stop_reply", {ok = reply.ok, code = reply.code})
        return
    end
    if step:match("^observe%-") then
        if attempt.observation and step == attempt.observation.step then onObservation(attempt, reply) end
        return
    end
    if not reply.ok and step == "start" and reply.code == "transport_timeout" then
        -- A missing acknowledgment does not prove that playback failed to start.
        if attempt.phase == "starting" then attempt.nextObservation = os.time() end
        return
    end
    if not reply.ok then
        local pickerMessage = step == "picker" and reply.code == "game_paused" and reply.message
        fail(attempt, step .. ": " .. tostring(reply.code) .. " " .. tostring(reply.message or ""),
            reply.code, pickerMessage)
        return
    end
    local result = reply.result
    if step == "features" then
        for _, key in ipairs(FEATURES) do
            if result.features[key] ~= 1 then fail(attempt, "Missing SceneZOI feature " .. key, "update_scenezoi"); return end
        end
        attempt.stopDisplayReason = result.features.stop_session_display_reason == 1
        if attempt.searchVenue then
            if attempt.npc and result.features.background_sessions ~= 1 then
                fail(attempt, "SceneZOI does not support background sessions", "update_scenezoi")
                return
            end
            discoverVenue(attempt, "venues", {attempt.initiator, attempt.partner})
        elseif attempt.ground then
            openPicker(attempt)
        else
            discoverVenue(attempt, "venue")
        end
    elseif step == "venues" then
        collectVenues(attempt, result.furniture)
    elseif step == "venue-" .. tostring(attempt.candidateIndex) then
        considerVenue(attempt, result)
    elseif step == "picker" then
        assert(result.opened, "The native partner picker did not open")
    elseif step == "venue" then
        local selected
        for _, furniture in ipairs(result.furniture) do
            if furniture.furniture_id == attempt.furniture
                and FurnitureKind.supported(furniture.profile.kind) then
                selected = furniture
                break
            end
        end
        if not selected then fail(attempt, "Selected object has no supported furniture profile", "unsupported_venue"); return end
        attempt.kind = selected.profile.kind
        -- A sofa pair can be usable if one of its occupants is chosen in the picker.
        if FurnitureKind.isBed(attempt.kind) and selected.status == "occupied" then
            fail(attempt, "Selected bed is occupied", "furniture_unavailable")
            return
        end
        openPicker(attempt)
    elseif step == "sofa_seats" then
        confirmPair(attempt)
        selectSofaSeats(attempt, result.furniture)
    elseif step == "definitions" then
        attempt.actionDefinitions = result.actions
        if attempt.searchVenue then
            nextVenue(attempt)
        else
            local initiator, partner = confirmPair(attempt)
            if prepareArguments(attempt, initiator, partner) then validation(attempt, "invitation") end
        end
    elseif step == "invitation" then
        if not validated(attempt, step, result) then return end
        local initiator, partner = confirmPair(attempt)
        ask(attempt, initiator, partner, result)
    elseif step == "arrival" then
        if attempt.phase ~= "arrival" or not validated(attempt, step, result) then return end
        if attempt.ground then
            if result.scene_id ~= attempt.args.scene_id or not result.bindings
                or result.anchor_participant_id ~= attempt.groundAnchor then
                fail(attempt, "SceneZOI could not confirm the selected ground scene", "no_matching_scenes")
                return
            end
            for role, who in pairs(attempt.args.bindings) do
                if result.bindings[role] ~= who then
                    fail(attempt, "SceneZOI changed the roles after the ground approach", "no_matching_scenes")
                    return
                end
            end
        end
        attempt.args.scene_id, attempt.args.bindings = result.scene_id, result.bindings
        attempt.phase, attempt.deadline = "arrival_privacy", os.time() + 12
        attempt.arrivalPrivacy = {revision = 0}
        requestPrivacy(attempt)
    elseif step == "start" then
        assert(result.accepted, "SceneZOI did not accept the start")
        log(attempt, "start_accepted", {scene = result.scene_id, stages = result.stages})
    end
end

local function onSessionEvent(attempt, event)
    local prefix = "encounter." .. attempt.nonce
    if event.name == "partner_picker_finished" and event.request_id == prefix .. ".picker"
        and attempt.phase == "picking" then
        if event.code == "cancelled" then
            log(attempt, "picker_cancelled")
            release(attempt)
        elseif event.code == "selected" and type(event.partner_id) == "string"
            and event.partner_id:match("^%d+$") and event.partner_id ~= attempt.initiator then
            if not Eligibility.canInvite(actor(attempt.initiator), actor(event.partner_id)) then
                fail(attempt, "The selected pair no longer meets the native invitation rules", "not_eligible")
                return
            end
            if participants[event.partner_id] then
                fail(attempt, "The selected partner is already preparing another encounter", "busy")
                return
            end
            attempt.partner = event.partner_id
            participants[attempt.partner] = attempt
            attempt.phase, attempt.deadline = "preflight", os.time() + 45
            confirmPair(attempt)
            if attempt.kind == "sofa.pair" then
                discoverVenue(attempt, "sofa_seats", {attempt.initiator, attempt.partner})
            else
                request(attempt, "definitions", "get_definitions")
            end
        else
            local notice = event.code == "partner_ineligible" and event.code or "picker_unavailable"
            fail(attempt, "Partner picker finished: " .. tostring(event.code), notice)
        end
        return
    end
    if not attempt.encounter or event.request_id ~= attempt.encounter.request_id
        or event.addon_id ~= "hzoi.gameplay" then return end
    if event.name == "session_start_failed" and not attempt.encounter.started then
        local cancellation = attempt.startCancellation
        fail(attempt, cancellation and cancellation.reason or event.code, cancellation and cancellation.notice or event.code)
    elseif event.name == "session_preparing" or event.name == "session_started" or event.name == "task_completed"
        or event.name == "node_entered" or event.name == "node_preparing"
        or event.name == "game_clock_changed" or event.name == "session_ending" or event.name == "session_ended" then
        observeSession(attempt, event)
    end
end

guarded = function(attempt, callback, ...)
    if not attempt or attempts[attempt.nonce] ~= attempt then return end
    local ok, problem = pcall(callback, attempt, ...)
    if not ok and attempts[attempt.nonce] == attempt then
        local notice = attempt.phase == "walking" and "walk_failed" or nil
        fail(attempt, problem, notice)
    end
end

function M.on_begin()
    if client then return end
    client = Client.new("hzoi.gameplay", {
        response = function(reply) guarded(forRequest(reply.request_id), onResponse, reply) end,
        event = function(event) guarded(forRequest(event.request_id), onSessionEvent, event) end,
        instance_changed = function()
            for _, active in pairs(attempts) do guarded(active, fail, "SceneZOI restarted", "update_scenezoi") end
        end,
    })
    for _, kind in ipairs({"started", "finished", "failed", "canceled"}) do
        local name = "interaction." .. kind
        subscriptions[name] = inzoi.event.on(name, function(info) onNativeEvent(kind, info) end)
    end
    pollNpc = Initiative.new(M.beginNpc, Urges, Eligibility.canInvite, function(who)
        return participants[who] ~= nil or romancePicks[who] ~= nil
    end)
    log(nil, "simulation_ready")
end

local function newAttempt(who, nonce, partner)
    if not client or attempts[nonce] or participants[who] or (partner and participants[partner]) then return end
    local attempt = {nonce = nonce, initiator = who, partner = partner, phase = "preflight",
        deadline = os.time() + 45, walks = {}, dialogue = {}}
    attempts[nonce], participants[who] = attempt, attempt
    if partner then participants[partner] = attempt end
    return attempt
end

beginAttempt = function(who, nonce, furniture, ground)
    if not client or who ~= controlledId() then return end
    local attempt = newAttempt(who, nonce)
    if not attempt then notify(who, "busy"); return end
    attempt.furniture, attempt.ground = furniture, ground
    guarded(attempt, function(active)
        local owner = actor(active.initiator)
        if not Eligibility.moodAllowsInvitation(owner) then
            fail(active, "The initiator's mood does not allow an invitation", "mood_blocked")
            return
        end
        if ground then
            log(attempt, "ground_selected")
            if not Ground.walkable(inzoi.getB2Subsystem("FB2PathFindSystem"), ground) then
                fail(attempt, "The selected ground is not walkable", "ground_unavailable")
                return
            end
        else
            log(attempt, "furniture_selected")
        end
        request(attempt, "features", "get_version")
    end)
end

beginVenueSearch = function(initiatorId, partnerId, npc, onPlaybackStarted)
    if not client then return false, "simulation_unavailable" end
    local first, second = positiveId(initiatorId), positiveId(partnerId)
    if not first or not second or first == second then return false, "partner_ineligible" end
    local initiator, partner = actor(first), actor(second)
    if not Eligibility.canInvite(initiator, partner) then return false, "not_eligible" end
    if npc and not (Initiative.canAct(initiator) and Initiative.readiness(initiator)
        and Initiative.readiness(partner)) then return false, "busy" end
    npcSerial = npcSerial + 1
    local nonce = ("%s-%d-%d"):format(npc and "npc" or "romance", os.time(), npcSerial)
    local attempt = newAttempt(first, nonce, second)
    if not attempt then return false, "busy" end
    attempt.searchVenue, attempt.npc = true, npc
    attempt.onPlaybackStarted = onPlaybackStarted
    if npc then log(attempt, "initiative_selected") end
    guarded(attempt, request, "features", "get_version")
    -- The attempt already reported any synchronous failure.
    if attempts[nonce] ~= attempt then return false end
    return true, nonce
end

function M.beginNpc(initiatorId, partnerId, onPlaybackStarted)
    return beginVenueSearch(initiatorId, partnerId, true, onPlaybackStarted)
end

function M.on_lua_message(self, component, kind, content)
    if not client then return end
    local who = id(component:GetOwnerEntityId())
    if kind == "HZoiGameplay.FurnitureInvite" then
        local nonce, initiator, furniture = content:match("^(invite%-%d+%-%d+)|([1-9]%d*)|([1-9]%d*)$")
        if nonce and initiator == who then beginAttempt(who, nonce, furniture) end
        return
    end
    if kind == "HZoiGameplay.WitnessResult" then
        local decoded, reply = pcall(Json.decode, content, 32768)
        local active = decoded and type(reply) == "table" and forRequest(reply.token)
        if active and active.phase == "arrival_privacy" and reply.kind == "arrival" then
            guarded(active, onArrivalPrivacy, reply, who)
        elseif active and active.phase == "playing" and active.encounter and reply.kind == nil then
            observeWitnesses(active, Witness.reply, active.encounter, active.actionDefinitions, content,
                actor, os.time(), function(...) onOrdinarySighting(active, ...) end,
                function(...) stopForWitness(active, ...) end, function(...) log(active, ...) end)
        end
        return
    end
    client:on_message(kind, content)
end

local function conversationBusy(actions)
    return actions:IsCurrentInteractionCoop() or actions:IsPendingCoop()
end

local function retryConversation(attempt, retry, now)
    if now >= retry.expires then
        fail(attempt, "The native conversation approach failed and the Zois did not become free to retry")
        return
    end
    if now < retry.earliest or now == retry.lastCheck then return end
    retry.lastCheck = now
    local initiator, partner = confirmPair(attempt)
    local first, second = interaction(initiator), interaction(partner)
    if conversationBusy(first) or conversationBusy(second) or first:IsPlayingInteraction()
        or second:IsPlayingInteraction() or not first:IsQueueEmpty() or not second:IsQueueEmpty() then return end
    attempt.conversationStarted, attempt.conversationDispatched, attempt.conversationWalks = nil, nil, nil
    attempt.coopClearedAt, attempt.lastCoopCheck, attempt.conversationRetry = nil, nil, nil
    attempt.invitationQueued, attempt.conversationRetried = nil, true
    -- The native queue still applies the same acceptance and refusal rules.
    queueInvitation(attempt, initiator, partner)
end

local function tickAttempt(attempt)
    local now = os.time()
    -- SceneZOI can disable the participants' native autonomy during
    -- preparation. Check the option until we hand it the start request.
    if attempt.npc and not attempt.encounter and now >= (attempt.nextAutonomyCheck or 0) then
        attempt.nextAutonomyCheck = now + VENUE_CHECK_INTERVAL
        local first, second = actor(attempt.initiator), actor(attempt.partner)
        if not (Initiative.isPresent(first) and Initiative.isPresent(second)) then
            fail(attempt, "Selected pair is unavailable")
            return
        end
        if not Initiative.canAct(first) then
            fail(attempt, "The initiator no longer has autonomy enabled")
            return
        end
    end
    if attempt.encounter then
        if attempt.phase == "playing" then
            observeWitnesses(attempt, Witness.tick, attempt.encounter, attempt.actionDefinitions, carrier(), os.time())
        end
        if attempt.phase == "starting" then
            local cancellation = attempt.startCancellation
            if cancellation and now >= attempt.deadline then
                fail(attempt, cancellation.reason, cancellation.notice)
                return
            elseif not cancellation and now >= attempt.deadline then
                cancelPendingStart(attempt, "Session start timed out", "timeout")
            end
        end
        if attempt.observation or os.time() < attempt.nextObservation then return end
        local record = attempt.encounter
        if record.session_id then
            observeByRequest(attempt, "get_session", {session_id = record.session_id})
        else
            observeByRequest(attempt, "get_request_status", {request_id = record.request_id})
        end
        return
    end
    -- The picker belongs to the initiating player. After selection, the
    -- invitation and walks belong to the two Zois even if possession changes.
    if not attempt.npc and not attempt.partner and controlledId() ~= attempt.initiator then
        release(attempt)
        return
    end
    if attempt.phase == "awaiting_availability" then
        if not Initiative.isSimulationRunning() then return end
        if now >= attempt.deadline then
            fail(attempt, "The Zois did not become available for the autonomous invitation", "busy")
            return
        end
        local initiator, partner = confirmPair(attempt)
        askWhenAvailable(attempt, initiator, partner, attempt.pendingInvitationResult)
        return
    end
    if now >= attempt.deadline then fail(attempt, "Timed out", "timeout"); return end
    if attempt.phase == "arrival_privacy" then
        local privacy = attempt.arrivalPrivacy
        if privacy.pending then
            if os.time() >= privacy.pending.expires then retryPrivacy(attempt, "trace_reply_timeout") end
        elseif os.time() >= privacy.next then
            requestPrivacy(attempt)
        end
        return
    end
    if attempt.searchVenue and attempt.phase == "walking" and os.time() >= (attempt.nextVenueCheck or 0) then
        attempt.nextVenueCheck = os.time() + VENUE_CHECK_INTERVAL
        local initiator, partner = confirmPair(attempt)
        if not roomReady(attempt, initiator, partner) then return end
    end
    if attempt.phase == "conversation" then
        local retry = attempt.conversationRetry
        if retry then
            retryConversation(attempt, retry, now)
            return
        end
        if attempt.coopHandoffUntil then
            local coop = invitationCoop(attempt)
            if coop then
                conversationDispatched(attempt, coop)
            elseif now >= attempt.coopHandoffUntil then
                fail(attempt, "Invitation canceled: Coop (no matching scheduler)")
            end
            return
        end
        local first, second = attempt.initiator, attempt.partner
        local dispatched = attempt.conversationDispatched
        if not dispatched then return end
        local answered = attempt.branch == "accept" and attempt.dialogue[first] == "finished"
            and attempt.dialogue[second] == "finished"
        if not answered then
            if now < dispatched + CONVERSATION_START_GRACE_SECONDS or now == attempt.lastCoopCheck then return end
            attempt.lastCoopCheck = now
        end
        local initiator, partner = confirmPair(attempt)
        local initiatorActions, partnerActions = interaction(initiator), interaction(partner)
        if conversationBusy(initiatorActions) or conversationBusy(partnerActions) then
            attempt.coopClearedAt = nil
        elseif answered then
            log(attempt, "accepted")
            beginWalking(attempt)
        elseif not attempt.coopClearedAt then
            -- Coop state can clear before its final events are delivered.
            attempt.coopClearedAt = now
        elseif now >= attempt.coopClearedAt + CONVERSATION_CLEAR_GRACE_SECONDS then
            fail(attempt, "Native invitation ended before both Zois answered")
        end
        return
    end
    if attempt.phase ~= "walking" then return end
    retryWalk(attempt)
    if attempts[attempt.nonce] ~= attempt or not arrived(attempt) then return end
    log(attempt, "both_arrived")
    attempt.phase, attempt.deadline = "arrival", os.time() + 30
    validation(attempt, "arrival")
end

function M.tick(dt)
    if venueClick then
        local who = venueClick.who
        local ok, problem = pcall(consumeVenueClick, who)
        if venueClick and (not ok or os.time() >= venueClick.deadline) then
            venueClick = nil
            log(nil, "venue_click_unresolved", {initiator = who, reason = tostring(problem or "Native action ended")})
            notify(who, "ground_click_missing")
        end
    end
    if not client then return end
    if pollNpc then pollNpc() end
    if next(attempts) == nil then return end
    local who = controlledId()
    if not who then return end
    local owner = actor(who)
    if not owner then return end
    client:tick(dt, owner)
    for _, active in pairs(attempts) do guarded(active, tickAttempt) end
end

function M.on_end(self, component)
    local who = id(component:GetOwnerEntityId())
    romancePicks[who] = nil
    local active = participants[who]
    if active and not active.encounter then guarded(active, fail, "Participant unloaded") end
end

function M.shutdown()
    for _, active in pairs(attempts) do
        guarded(active, fail, "Gameplay mod unloaded")
    end
    for name, handle in pairs(subscriptions) do
        if handle and handle ~= 0 then inzoi.event.off(name, handle) end
    end
    subscriptions, client, venueClick, pollNpc = {}, nil, nil, nil
    romancePicks = {}
    attempts, participants = {}, {}
    Urges.reset()
end

return M
