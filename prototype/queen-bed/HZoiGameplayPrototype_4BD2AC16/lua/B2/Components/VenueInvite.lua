local Client = require("SceneZOIAddon.Client")
local Json = require("SceneZOIAddon.Json")
local makeArguments = require("EncounterArguments")
local Sofa = require("SofaArrival")
local Ground = require("GroundArrival")
local Witness = require("EncounterWitness")
local WitnessNative = require("WitnessNative")
local Ledger = require("EncounterLedger")
local Consequences = require("EncounterConsequences")
local NpcVenue = require("NpcVenue")
local Urges = require("OwnedEncounterUrges")
local Initiative = require("NpcInitiative")
local Standing = require("NpcStandingAnchors")
local PrivateRoomMarks = require("PrivateRoomMarks")

local M = {}
local INVITE = "HZoiGameplay_Invite"
local WALK = "HZoiGameplay_Walk"
local WALK_RETRY = "HZoiGameplay_WalkRetry"
local GROUND = "HZoiGameplay_GroundInvite"
local MARK_ROOM = "HZoiGameplay_MarkPrivateRoom"
local DIALOGUE = {
    accept = "Coop_TalkLike_Before_MakeLove",
    refuse = "Coop_TalkLike_Before_MakeLove_Fail",
}
local FEATURES = {
    "partner_picker", "autonomous_scenes", "autonomous_stages", "autonomous_stage_progress",
    "autonomous_stage_priorities", "autonomous_auto_restrictions", "autonomous_joint_goal_routes",
    "autonomous_post_completion_stay", "autonomous_manual_completion_exit", "session_results",
}
local client, pollNpc
local attempts, participants = {}, {}
local OBSERVATION_INTERVAL = 8
local PRIVACY_INTERVAL = 1
local subscriptions = {}
local groundSerial, npcSerial = 0, 0
local groundClick, beginAttempt, guarded

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
    if attempt.npc then NpcVenue.release(attempt.nonce) end
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

local function fail(attempt, reason, notice)
    if not attempt then return end
    local record = attempt.encounter
    log(attempt, "failed", {phase = attempt.phase, reason = tostring(reason),
        session = record and record.session_id, completions = record and record.completions})
    -- Drop routing first. Native cancellation can publish another event immediately.
    release(attempt)
    if attempt.phase == "conversation" and attempt.invitationQueued then
        cancel(actor(attempt.initiator), INVITE)
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
    if not attempt.npc then notify(attempt.initiator, notice or "failed") end
end

local function requestId(attempt, step)
    return "encounter." .. attempt.nonce .. "." .. step
end

local function request(attempt, step, operation, data)
    client:request(carrier(), requestId(attempt, step), operation, data)
end

local function validation(attempt, step)
    local args = {start_mode = "start_autonomous_scene"}
    for key, value in pairs(attempt.args) do args[key] = value end
    -- Before asking, the pair may still be far from the venue. The real start
    -- uses SceneZOI's normal distance limit after both walk actions finish.
    if step == "invitation" or step:match("^venue%-") then
        args.placement = {max_start_distance_m = 100, exit = "restore"}
    end
    request(attempt, step, "validate_start", args)
end

local function eligible(person)
    local stage = person:GetGrowthStep()
    local steps = inzoi.EB1GrowthStep
    return stage == steps.Youth or stage == steps.Adult or stage == steps.Old or stage == steps.Elderly
end

local function idleForNpc(person)
    if not person or not eligible(person) or person:IsAutonomyEnable() ~= true then return false end
    local actions = interaction(person)
    return actions and actions:IsQueueEmpty() == true and actions:IsPlayingInteraction() == false
end

local function confirmPair(attempt)
    local controlled = controlledId()
    if attempt.npc then
        assert(controlled ~= attempt.initiator and controlled ~= attempt.partner, "A player took control of an NPC")
    else
        assert(controlled == attempt.initiator, "Controlled Zoi changed")
    end
    local initiator, partner = actor(attempt.initiator), actor(attempt.partner)
    assert(initiator and partner and eligible(initiator) and eligible(partner), "Selected pair is unavailable")
    if attempt.npc then
        assert(Initiative.canAct(initiator) and Initiative.canAct(partner), "The NPC pair no longer has autonomy enabled")
        local pending = Urges.pending(initiator)
        assert(pending and pending.partner == attempt.partner and Urges.canInvite(initiator, partner),
            "The NPC invitation is no longer eligible")
    end
    return initiator, partner
end

local function distanceSquared(a, b)
    return (a.X - b.X)^2 + (a.Y - b.Y)^2 + (a.Z - b.Z)^2
end

local function bedArrivalPoints(bed, floor)
    local center = bed:GetLocation()
    local yaw = math.rad(bed:GetRotation().Yaw)
    local points = {}
    for _, radius in ipairs({150, 200, 250}) do
        for orientation = 1, 8 do
            local angle = yaw + orientation * math.pi / 4
            local spot = UE.FVector(center.X + radius * math.cos(angle), center.Y + radius * math.sin(angle), center.Z)
            if floor:IsOnWalkableGrid(spot) and (#points == 0 or distanceSquared(spot, points[1]) >= 150^2) then
                points[#points + 1] = spot
                if #points == 2 then return points end
            end
        end
    end
    return nil
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
    local points = venue.seats and Sofa.points(venue.seats, furniture, floor)
    if not venue.seats then points = bedArrivalPoints(furniture, floor) end
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
        if reason == "room_occupied" then
            local ok, problem = pcall(WitnessNative.privacyComplaint, initiator, partner)
            log(attempt, "privacy_feedback", {ok = ok, reason = not ok and tostring(problem) or nil})
        end
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
    if attempt.npc then
        if not roomReady(attempt, initiator, partner, {first.point, second.point}) then return end
    elseif attempt.kind == "bed.queen" then
        walk.point = alternativeBedPoint(walk.point, other.point, otherPerson:GetLocation(), furniture, floor)
    end
    if not floor:IsOnWalkableGrid(walk.point) then
        fail(attempt, "The arrival point became unavailable for " .. who, "walk_failed")
        return
    end
    walk.retryPending = nil
    queueWalk(attempt, person, who, walk, WALK_RETRY)
end

local function beginWalking(attempt)
    local initiator, partner = confirmPair(attempt)
    local floor = assert(inzoi.getB2Subsystem("FB2PathFindSystem"), "Path finder unavailable")
    local points, furniture, reason
    if attempt.npc then
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

local function readGroundPoint(person, bag)
    local actions = interaction(person)
    local isCurrent = tostring(actions:GetCurrentInteractionBagId()) == bag
    local currentId = isCurrent and actions:GetCurrentInteractionQueueId()
    -- interaction.started fires while the unique ground request is still in
    -- the queue. The game sets its current bag and queue ID after that event.
    for _, row in ipairs(actions.InteractionQueue or {}) do
        if tostring(row.InteractionBagId) == bag and (not isCurrent or row.InteractionQueueId == currentId) then
            return row.ImpactPoint
        end
    end
    if isCurrent then
        local ok, action = pcall(actions.GetCurrentAction, actions, inzoi.EB1ActionType.Delay)
        if ok and action then return action.NonTargetLocation end
    end
end

local function consumeGroundClick(who)
    if not groundClick or groundClick.who ~= who then return end
    if who ~= controlledId() then
        groundClick = nil
        return
    end
    local bag = groundClick.bag
    local person = actor(who)
    local point = person and readGroundPoint(person, bag)
    if not point then return end
    groundClick = nil
    if bag == MARK_ROOM then
        local ok, result = pcall(PrivateRoomMarks.toggle, person, point)
        if not ok then log(nil, "private_room_mark_error", {initiator = who, reason = tostring(result)}) end
        notify(who, ok and result or "private_room_unavailable")
        return
    end
    groundSerial = groundSerial + 1
    beginAttempt(who, ("ground-%d-%d"):format(os.time(), groundSerial), nil,
        UE.FVector(point.X, point.Y, point.Z))
end

local function onAttemptAction(attempt, kind, event, who, target, bag)
    local initiator, partner = attempt.initiator, attempt.partner
    if attempt.phase == "conversation" and who == initiator and target == partner and bag == INVITE then
        if kind == "started" then
            attempt.conversationStarted = true
            log(attempt, "conversation_started")
        elseif kind == "finished" then
            -- RequestCoop finishes before either Zoi starts talking.
            if attempt.conversationStarted then attempt.conversationDispatched = true end
        else
            fail(attempt, "Invitation " .. kind .. ": " .. tostring(event.reason))
        end
    elseif attempt.phase == "conversation" and attempt.conversationStarted then
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
            attempt.branch, attempt.dialogue[who] = branch, "started"
        elseif attempt.branch == branch and attempt.dialogue[who] == "started" then
            if kind == "finished" then
                attempt.dialogue[who] = "finished"
                log(attempt, "dialogue_finished", {participant = who, branch = branch})
            else
                fail(attempt, "Conversation " .. kind .. " for " .. who .. ": " .. tostring(event.reason))
            end
        end
    elseif attempt.phase == "walking" then
        local walk = attempt.walks[who]
        if not walk then return end
        if walk.finished then
            local reason = event.play_reason or event.reason
            if attempt.npc and kind == "started" and bag ~= walk.bag
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
    if bag == GROUND or bag == MARK_ROOM then
        if kind == "started" and who == controlledId() then
            groundClick = {who = who, bag = bag, deadline = os.time() + 2}
        end
        if groundClick and groundClick.who == who and groundClick.bag == bag then pcall(consumeGroundClick, who) end
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
    attempt.phase = "picking"
    request(attempt, "picker", "open_partner_picker")
end

local function recoverDisplacedZoi(attempt, who, walk, other, initiator, partner)
    if not attempt.npc or attempt.phase ~= "walking" or attempt.reapproachUsed
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

local function onOrdinarySighting(attempt, who)
    if who == controlledId() or participants[who] then return end
    local witness = actor(who)
    local buffs = witness and witness:GetComponent(inzoi.EB2ComponentType.Buff)
    if buffs then
        buffs:AddBuff("HZoiGameplay_SawEncounter")
        log(attempt, "witness_surprised", {witness = who})
    end
    local result = WitnessNative.walkAway(witness, actor(attempt.initiator))
    if result then log(attempt, "witness_walk", {witness = who, enqueue_result = tostring(result)}) end
end

local function stopForWitness(attempt, reason)
    request(attempt, "witness-stop", "request_stop", {session_id = attempt.encounter.session_id, reason = reason})
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

local function observeScene(attempt, snapshot)
    local record = attempt.encounter
    local wasStarted = record.started
    local observed, countsComplete = Ledger.observe(record, snapshot, function(...) completed(attempt, ...) end)
    if not observed then return false end
    if record.started and not wasStarted then
        log(attempt, "scene_started", {scene = snapshot.node_id, session = record.session_id})
    end
    if snapshot.phase == "ended" or snapshot.name == "session_ended" then
        local result = Ledger.finish(record, snapshot, countsComplete)
        log(attempt, "scene_ended", {session = record.session_id, outcome = result.plan and result.plan.outcome,
            reason = result.stop_reason, cleanup = result.cleanup_code, restored = result.cleanup_complete,
            completions = record.completions, task_counts_complete = countsComplete,
            outcome_eligible = result.apply_outcome})
        observeWitnesses(attempt, Witness.finish, record, result, function(who)
            if not participants[who] or participants[who] == attempt then return actor(who) end
        end, function(...) log(attempt, ...) end)
        if result.apply_outcome then deliverConsequence(attempt, "onResult", record, result) end
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
        if attempt.observationFailures >= 2 then fail(attempt, "Scene outcome unavailable: " .. tostring(reply.code)) end
        return
    end
    attempt.observationFailures = nil
    if operation == "get_request_status" then
        if result.phase == "failed" then
            fail(attempt, result.code or "start_failed", result.code)
        elseif type(result.session_id) == "string" then
            if result.phase == "ended" then
                attempt.encounter.session_id = result.session_id
                readEndedResult(attempt)
            else
                observeByRequest(attempt, "get_session", {session_id = result.session_id})
            end
        end
    elseif operation == "get_session" then
        if not result.session or not observeScene(attempt, result.session) then fail(attempt, "Could not match the current scene") end
    elseif not result.result or not observeScene(attempt, result.result) then
        fail(attempt, "No verified ended result for the selected encounter")
    end
end

local function prepareArguments(attempt, initiator, partner)
    local male = inzoi.EB1GenderType.Male
    local args, reason = makeArguments(attempt.actionDefinitions, attempt.initiator, attempt.partner, attempt.furniture,
        attempt.seats and attempt.seats.id,
        initiator:GetGenderType() == male and partner:GetGenderType() == male)
    if not args then fail(attempt, reason, reason); return false end
    if attempt.npc then args.background = true end
    attempt.args = args
    return true
end

local function nextNpcVenue(attempt)
    attempt.candidateIndex = (attempt.candidateIndex or 0) + 1
    local candidate = attempt.candidates[attempt.candidateIndex]
    if not candidate then
        fail(attempt, "No compatible reachable private venue", "no_matching_scenes")
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

local function collectNpcVenues(attempt, rows)
    local initiator, partner = confirmPair(attempt)
    local fallbackAnchor = initiator:GetGenderType() == inzoi.EB1GenderType.Male
        and attempt.initiator or attempt.partner
    local candidates, reason = NpcVenue.candidates(initiator, partner, rows, attempt.groundAnchors, function(option, floor)
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
    log(attempt, "npc_venues_ranked", {count = #candidates, reason = reason})
    if #candidates == 0 then
        fail(attempt, reason or "No reachable vacant private venue", reason)
        return
    end
    request(attempt, "definitions", "get_definitions")
end

local function ask(attempt, initiator, partner, result)
    if attempt.ground then
        -- Keep the preflight's scene and roles so the same Zoi anchors playback
        -- at the clicked or explicitly selected location.
        attempt.args.scene_id, attempt.args.bindings = result.scene_id, result.bindings
        attempt.groundAnchor = result.bindings.male or attempt.initiator
    end
    attempt.phase, attempt.deadline = "conversation", os.time() + 90
    local queued, reason = queue(attempt, initiator, partner:GetEntityId(), partner:GetLocation(), INVITE)
    if not queued then
        local denied = reason == inzoi.EB1AddInteractionQueueResult.EnqueueConditionCheckFail
        fail(attempt, "Invitation enqueue failed: " .. tostring(reason), denied and "not_eligible" or "queue_failed")
        return
    end
    attempt.invitationQueued = true
    log(attempt, "invitation_queued")
end

local function considerNpcVenue(attempt, result)
    if not result.valid or result.route_uncertain
        or (attempt.seats and result.furniture_pair_id ~= attempt.seats.id) then
        log(attempt, "npc_venue_rejected", {reason = result.code or "route_uncertain"})
        nextNpcVenue(attempt)
        return
    end
    local initiator, partner = confirmPair(attempt)
    if not (idleForNpc(initiator) and idleForNpc(partner)) then
        fail(attempt, "The NPC pair is busy", "busy")
        return
    end
    local candidate = attempt.candidate
    local actualAnchor = attempt.ground and (result.bindings.male or attempt.initiator)
    if actualAnchor and actualAnchor ~= candidate.groundAnchor then
        local points = candidate.arrival_points
        points[1], points[2] = points[2], points[1]
        candidate.groundAnchor = actualAnchor
    end
    local claimed, reason = NpcVenue.claim(attempt.nonce, candidate, initiator, partner)
    if not claimed then
        log(attempt, "npc_venue_rejected", {reason = reason})
        nextNpcVenue(attempt)
        return
    end
    log(attempt, "npc_venue_claimed", {site = candidate.site_id, room = candidate.room_class})
    ask(attempt, initiator, partner, result)
end

local function onResponse(attempt, reply)
    local prefix = "encounter." .. attempt.nonce .. "."
    if reply.request_id:sub(1, #prefix) ~= prefix then return end
    local step = reply.request_id:sub(#prefix + 1)
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
        fail(attempt, step .. ": " .. tostring(reply.code) .. " " .. tostring(reply.message or ""), reply.code)
        return
    end
    local result = reply.result
    if step == "features" then
        for _, key in ipairs(FEATURES) do
            if result.features[key] ~= 1 then fail(attempt, "Missing SceneZOI feature " .. key, "update_scenezoi"); return end
        end
        if attempt.npc then
            if result.features.background_sessions ~= 1 then
                fail(attempt, "SceneZOI does not support background sessions", "update_scenezoi")
                return
            end
            discoverVenue(attempt, "npc_venues", {attempt.initiator, attempt.partner})
        elseif attempt.ground then
            openPicker(attempt)
        else
            discoverVenue(attempt, "venue")
        end
    elseif step == "npc_venues" then
        collectNpcVenues(attempt, result.furniture)
    elseif step == "venue-" .. tostring(attempt.candidateIndex) then
        considerNpcVenue(attempt, result)
    elseif step == "picker" then
        assert(result.opened, "The native partner picker did not open")
    elseif step == "venue" then
        local selected
        for _, furniture in ipairs(result.furniture) do
            if furniture.furniture_id == attempt.furniture
                and (furniture.profile.kind == "bed.queen" or furniture.profile.kind == "sofa.pair") then
                selected = furniture
                break
            end
        end
        if not selected then fail(attempt, "Selected object has no supported furniture profile", "unsupported_venue"); return end
        attempt.kind = selected.profile.kind
        -- A sofa pair can be usable if one of its occupants is chosen in the picker.
        if attempt.kind == "bed.queen" and selected.status == "occupied" then
            fail(attempt, "Selected queen bed is occupied", "furniture_unavailable")
            return
        end
        openPicker(attempt)
    elseif step == "sofa_seats" then
        confirmPair(attempt)
        selectSofaSeats(attempt, result.furniture)
    elseif step == "definitions" then
        attempt.actionDefinitions = result.actions
        if attempt.npc then
            nextNpcVenue(attempt)
        else
            local initiator, partner = confirmPair(attempt)
            if prepareArguments(attempt, initiator, partner) then validation(attempt, "invitation") end
        end
    elseif step == "invitation" then
        if not validated(attempt, step, result) then return end
        local initiator, partner = confirmPair(attempt)
        ask(attempt, initiator, partner, result)
    elseif step == "arrival" then
        if not validated(attempt, step, result) then return end
        if attempt.npc then
            local initiator, partner = confirmPair(attempt)
            if not roomReady(attempt, initiator, partner) or not arrived(attempt) then return end
        end
        if attempt.ground then
            if not attempt.npc and not arrived(attempt) then return end
            if result.scene_id ~= attempt.args.scene_id or not result.bindings then
                fail(attempt, "SceneZOI could not confirm the selected ground scene", "no_matching_scenes")
                return
            end
            for role, who in pairs(attempt.args.bindings) do
                if result.bindings[role] ~= who then
                    fail(attempt, "SceneZOI changed the roles after the ground approach", "no_matching_scenes")
                    return
                end
            end
        else
            confirmPair(attempt)
        end
        if not furnitureStillThere(attempt) then
            fail(attempt, "The selected furniture changed during arrival", "furniture_unavailable")
            return
        end
        attempt.args.scene_id, attempt.args.bindings = result.scene_id, result.bindings
        attempt.phase, attempt.deadline = "starting", os.time() + 60
        attempt.encounter = Ledger.new(requestId(attempt, "start"), client.client_id, attempt)
        attempt.observationSerial, attempt.nextObservation = 0, os.time() + OBSERVATION_INTERVAL
        request(attempt, "start", "start_autonomous_scene", attempt.args)
    elseif step == "start" then
        assert(result.accepted, "SceneZOI did not accept the start")
        log(attempt, "start_accepted", {scene = result.scene_id, stages = result.stages})
    end
end

local function onSceneEvent(attempt, event)
    local prefix = "encounter." .. attempt.nonce
    if event.name == "partner_picker_finished" and event.request_id == prefix .. ".picker"
        and attempt.phase == "picking" then
        if event.code == "cancelled" then
            log(attempt, "picker_cancelled")
            release(attempt)
        elseif event.code == "selected" and type(event.partner_id) == "string"
            and event.partner_id:match("^%d+$") and event.partner_id ~= attempt.initiator then
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
            fail(attempt, "Partner picker finished: " .. tostring(event.code), "picker_unavailable")
        end
        return
    end
    if not attempt.encounter or event.request_id ~= attempt.encounter.request_id
        or event.addon_id ~= "hzoi.gameplay" then return end
    if event.name == "session_start_failed" and not attempt.encounter.session_id then
        fail(attempt, event.code, event.code)
    elseif event.name == "session_preparing" or event.name == "session_started" or event.name == "task_completed"
        or event.name == "node_entered" or event.name == "node_preparing"
        or event.name == "game_clock_changed" or event.name == "session_ending" or event.name == "session_ended" then
        observeScene(attempt, event)
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
        event = function(event) guarded(forRequest(event.request_id), onSceneEvent, event) end,
        instance_changed = function()
            for _, active in pairs(attempts) do guarded(active, fail, "SceneZOI restarted", "update_scenezoi") end
        end,
    })
    for _, kind in ipairs({"started", "finished", "failed", "canceled"}) do
        local name = "interaction." .. kind
        subscriptions[name] = inzoi.event.on(name, function(info) onNativeEvent(kind, info) end)
    end
    pollNpc = Initiative.new(M.beginNpc, function(site, initiator, partner)
        return Standing.find(site, initiator, partner, NpcVenue.roomClass)
    end, Urges)
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
        assert(owner and eligible(owner), "The initiator is unavailable")
        if ground then
            log(attempt, "ground_selected")
            if not Ground.walkable(inzoi.getB2Subsystem("FB2PathFindSystem"), ground) then
                fail(attempt, "The selected ground is not walkable", "ground_unavailable")
                return
            end
        end
        request(attempt, "features", "get_version")
    end)
end

-- Start a background invitation after the scheduler finds an eligible pair.
function M.beginNpc(initiatorId, partnerId, groundAnchors)
    if not client then return false, "simulation_unavailable" end
    local first, second = tostring(initiatorId), tostring(partnerId)
    if not first:match("^[1-9]%d*$") or not second:match("^[1-9]%d*$")
        or first == second or first == controlledId() or second == controlledId() then return false, "invalid_pair" end
    local initiator, partner = actor(first), actor(second)
    if not (idleForNpc(initiator) and idleForNpc(partner)) then return false, "busy" end
    local pending = Urges.pending(initiator)
    if not pending or pending.partner ~= second or not Urges.canInvite(initiator, partner) then
        return false, "urge_unavailable"
    end
    npcSerial = npcSerial + 1
    local nonce = ("npc-%d-%d"):format(os.time(), npcSerial)
    local attempt = newAttempt(first, nonce, second)
    if not attempt then return false, "busy" end
    attempt.npc, attempt.groundAnchors = true, groundAnchors
    guarded(attempt, function(active) request(active, "features", "get_version") end)
    if attempts[nonce] ~= attempt then return false, "request_failed" end
    return true, nonce
end

function M.on_lua_message(self, component, kind, content)
    if not client then return end
    local who = id(component:GetOwnerEntityId())
    if kind == "HZoiGameplay.WitnessResult" then
        local decoded, reply = pcall(Json.decode, content, 8192)
        local active = decoded and type(reply) == "table" and forRequest(reply.token)
        if active and active.phase == "playing" and active.encounter then
            observeWitnesses(active, Witness.reply, active.encounter, active.actionDefinitions, content,
                actor, os.time(), function(...) onOrdinarySighting(active, ...) end,
                function(...) stopForWitness(active, ...) end, function(...) log(active, ...) end)
        end
        return
    end
    if kind ~= "HZoiGameplay.Invite" then
        client:on_message(kind, content)
        return
    end
    local nonce, initiator, furniture = content:match("^([a-z0-9_%-]+)|(%d+)|(%d+)$")
    if nonce and #nonce <= 48 and who == initiator then beginAttempt(who, nonce, furniture) end
end

local function tickAttempt(attempt)
    if attempt.encounter then
        if attempt.phase == "playing" then
            observeWitnesses(attempt, Witness.tick, attempt.encounter, attempt.actionDefinitions, carrier(), os.time())
        end
        if attempt.phase == "starting" and os.time() >= attempt.deadline then
            fail(attempt, "Scene start timed out", "timeout")
            return
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
    if not attempt.npc and controlledId() ~= attempt.initiator then
        fail(attempt, "Controlled Zoi changed")
        return
    end
    if attempt.phase == "picking" then return end
    if os.time() >= attempt.deadline then fail(attempt, "Timed out", "timeout"); return end
    if attempt.npc and attempt.phase == "walking" and os.time() >= (attempt.nextPrivacyCheck or 0) then
        attempt.nextPrivacyCheck = os.time() + PRIVACY_INTERVAL
        local initiator, partner = confirmPair(attempt)
        if not roomReady(attempt, initiator, partner) then return end
    end
    if attempt.phase == "conversation" then
        local first, second = attempt.initiator, attempt.partner
        if not attempt.conversationDispatched or attempt.dialogue[first] ~= "finished"
            or attempt.dialogue[second] ~= "finished" then return end
        local initiator, partner = confirmPair(attempt)
        if interaction(initiator):IsCurrentInteractionCoop() or interaction(partner):IsCurrentInteractionCoop() then return end
        if attempt.branch == "refuse" then
            log(attempt, "refused")
            release(attempt)
        else
            log(attempt, "accepted")
            beginWalking(attempt)
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

function M.on_tick(self, component, dt)
    local who = id(component:GetOwnerEntityId())
    if groundClick and who == groundClick.who then
        local ok, problem = pcall(consumeGroundClick, who)
        if groundClick and (not ok or os.time() >= groundClick.deadline) then
            local mark = groundClick.bag == MARK_ROOM
            groundClick = nil
            log(nil, "ground_click_missing_location", {initiator = who, reason = tostring(problem or "Native action ended")})
            notify(who, mark and "private_room_unavailable" or "ground_click_missing")
        end
    end
    if not client or who ~= controlledId() then return end
    if pollNpc then pollNpc() end
    if next(attempts) == nil then return end
    local owner = actor(who)
    if not owner then return end
    client:tick(dt, owner)
    for _, active in pairs(attempts) do guarded(active, tickAttempt) end
end

function M.on_end(self, component)
    local who = id(component:GetOwnerEntityId())
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
    subscriptions, client, groundClick, pollNpc = {}, nil, nil, nil
    attempts, participants = {}, {}
    Urges.reset()
    PrivateRoomMarks.reset()
end

return M
