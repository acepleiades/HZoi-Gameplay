local Client = require("SceneZOIAddon.Client")
local Json = require("SceneZOIAddon.Json")
local makeArguments = require("EncounterArguments")
local Sofa = require("SofaArrival")

local M = {}
local INVITE = "HZoiGameplay_Invite"
local WALK = "HZoiGameplay_Walk"
local DIALOGUE = {
    accept = "Coop_TalkLike_Before_MakeLove",
    refuse = "Coop_TalkLike_Before_MakeLove_Fail",
}
local FEATURES = {
    "partner_picker", "autonomous_scenes", "autonomous_stages", "autonomous_stage_progress",
    "autonomous_stage_priorities", "autonomous_auto_restrictions", "autonomous_joint_goal_routes",
    "autonomous_post_completion_stay", "autonomous_manual_completion_exit",
}
local owner, client, attempt
local subscriptions = {}

local function log(phase, details)
    details = details or {}
    if attempt then
        details.request, details.initiator, details.partner, details.furniture =
            attempt.nonce, attempt.initiator, attempt.partner, attempt.furniture
        details.furniture_pair = attempt.seats and attempt.seats.id
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

local function notify(who, code)
    inzoi.message.send_to_client(entity(who), "HZoiGameplay.Notice", code)
end

local function queue(person, target, point, bag)
    local result = interaction(person):AddInteractionQueueByParam(
        target, point, bag, inzoi.EB1InteractionPlayReason.User, false, false, "HZoiGameplay", true, false)
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

local function fail(reason, notice)
    if not attempt then return end
    local active = attempt
    log("failed", {phase = active.phase, reason = tostring(reason)})
    attempt = nil
    if active.phase == "conversation" and active.invitationQueued then
        cancel(owner, INVITE)
    elseif active.phase == "walking" then
        for who in pairs(active.walks) do cancel(actor(who), WALK) end
    end
    if active.kind == "sofa.pair" then
        if notice == "furniture_unavailable" then notice = "sofa_unavailable" end
        if notice == "walk_failed" then notice = "sofa_walk_failed" end
    end
    notify(active.initiator, notice or "failed")
end

local function request(step, operation, data)
    client:request(owner, "encounter." .. attempt.nonce .. "." .. step, operation, data)
end

local function validation(step)
    local args = {start_mode = "start_autonomous_scene"}
    for key, value in pairs(attempt.args) do args[key] = value end
    -- Before asking, the pair may still be far from the venue. The real start
    -- uses SceneZOI's normal distance limit after both walk actions finish.
    if step == "invitation" then args.placement = {max_start_distance_m = 100, exit = "restore"} end
    request(step, "validate_start", args)
end

local function eligible(person)
    local stage = person:GetGrowthStep()
    local steps = inzoi.EB1GrowthStep
    return stage == steps.Youth or stage == steps.Adult or stage == steps.Old or stage == steps.Elderly
end

local function confirmPair()
    assert(id(inzoi.FB2ControllerSystem.GetPossessEntityId()) == attempt.initiator, "Controlled Zoi changed")
    local initiator, partner = actor(attempt.initiator), actor(attempt.partner)
    assert(initiator and partner and eligible(initiator) and eligible(partner), "Selected pair is unavailable")
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

local function beginWalking()
    local initiator, partner = confirmPair()
    local furniture = manager():FindGameObject(entity(attempt.furniture))
    if not furniture then fail("The selected furniture is no longer loaded", "furniture_unavailable"); return end
    local floor = assert(inzoi.getB2Subsystem("FB2PathFindSystem"), "Path finder unavailable")
    local points
    if attempt.seats then
        points = Sofa.points(attempt.seats, furniture, floor)
        attempt.sofaLocation = furniture:GetLocation()
        attempt.sofaYaw = furniture:GetRotation().Yaw
    else
        points = bedArrivalPoints(furniture, floor)
    end
    if not points then fail("No two separate arrival points at the selected venue", "walk_failed"); return end
    attempt.phase, attempt.deadline = "walking", os.time() + 60
    if distanceSquared(initiator:GetLocation(), points[1]) + distanceSquared(partner:GetLocation(), points[2]) >
       distanceSquared(initiator:GetLocation(), points[2]) + distanceSquared(partner:GetLocation(), points[1]) then
        points[1], points[2] = points[2], points[1]
    end
    for index, person in ipairs({initiator, partner}) do
        local who, spot = id(person:GetEntityId()), points[index]
        local queued, reason = queue(person, entity(), spot, WALK)
        assert(queued, "Native walk could not be queued for " .. who .. ": " .. tostring(reason))
        attempt.walks[who] = {point = spot}
        log("walk_queued", {participant = who, x = spot.X, y = spot.Y, z = spot.Z})
    end
end

local function onNativeEvent(kind, event)
    if not attempt then return end
    local who, target = id(event.entity_id), id(event.target_entity_id)
    local bag = tostring(event.interaction_bag_id)
    local initiator, partner = attempt.initiator, attempt.partner
    if attempt.phase == "conversation" and who == initiator and target == partner and bag == INVITE then
        if kind == "started" then
            attempt.conversationStarted = true
            log("conversation_started")
        elseif kind == "finished" then
            -- RequestCoop finishes before either Zoi starts talking.
            if attempt.conversationStarted then attempt.conversationDispatched = true end
        else
            fail("Invitation " .. kind .. ": " .. tostring(event.reason))
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
                fail("The two Zoi conversation roles selected different responses")
                return
            end
            attempt.branch, attempt.dialogue[who] = branch, "started"
        elseif attempt.branch == branch and attempt.dialogue[who] == "started" then
            if kind == "finished" then
                attempt.dialogue[who] = "finished"
                log("dialogue_finished", {participant = who, branch = branch})
            else
                fail("Conversation " .. kind .. " for " .. who .. ": " .. tostring(event.reason))
            end
        end
    elseif attempt.phase == "walking" and bag == WALK and attempt.walks[who] then
        if kind == "finished" then
            attempt.walks[who].finished = true
        elseif kind ~= "started" then
            fail("Walk " .. kind .. " for " .. who .. ": " .. tostring(event.reason), "walk_failed")
        end
    end
end

local function validated(step, result)
    if not result.valid or result.route_uncertain then
        fail(step .. ": " .. tostring(result.code or "uncertain goal route"), result.code or "no_matching_scenes")
        return false
    end
    if attempt.seats and result.furniture_pair_id ~= attempt.seats.id then
        fail(step .. ": SceneZOI did not confirm the selected sofa pair", "furniture_unavailable")
        return false
    end
    return true
end

local function discoverVenue(step, participants)
    request(step, "find_furniture", {origin_id = attempt.initiator, radius_m = 100,
        include_unavailable = true, participants = participants})
end

local function selectSofaSeats(rows)
    local furniture = manager():FindGameObject(entity(attempt.furniture))
    if not furniture then fail("Selected sofa is no longer loaded", "furniture_unavailable"); return end
    local floor = assert(inzoi.getB2Subsystem("FB2PathFindSystem"), "Path finder unavailable")
    local hasSeats = false
    for _, row in ipairs(rows) do
        if row.furniture_id == attempt.furniture and row.profile.kind == "sofa.pair" and row.available then
            hasSeats = true
            local seats = Sofa.seats(row)
            if seats and Sofa.points(seats, furniture, floor) then
                attempt.seats = seats
                log("sofa_pair_selected", {spots = row.sitting_spots})
                request("definitions", "get_definitions")
                return
            end
        end
    end
    if hasSeats then
        fail("No walkable approach to an available sofa pair", "walk_failed")
    else
        fail("No adjacent sofa seats available for this roster", "furniture_unavailable")
    end
end

local function onResponse(reply)
    if not attempt then return end
    local prefix = "encounter." .. attempt.nonce .. "."
    if reply.request_id:sub(1, #prefix) ~= prefix then return end
    local step = reply.request_id:sub(#prefix + 1)
    if not reply.ok then
        fail(step .. ": " .. tostring(reply.code) .. " " .. tostring(reply.message or ""), reply.code)
        return
    end
    local result = reply.result
    if step == "features" then
        for _, key in ipairs(FEATURES) do
            if result.features[key] ~= 1 then fail("Missing SceneZOI feature " .. key, "update_scenezoi"); return end
        end
        discoverVenue("venue")
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
        if not selected then fail("Selected object has no supported furniture profile", "unsupported_venue"); return end
        attempt.kind = selected.profile.kind
        -- A sofa pair can be usable if one of its occupants is chosen in the picker.
        if attempt.kind == "bed.queen" and selected.status == "occupied" then
            fail("Selected queen bed is occupied", "furniture_unavailable")
            return
        end
        attempt.phase = "picking"
        request("picker", "open_partner_picker")
    elseif step == "sofa_seats" then
        confirmPair()
        selectSofaSeats(result.furniture)
    elseif step == "definitions" then
        local initiator, partner = confirmPair()
        local male = inzoi.EB1GenderType.Male
        local args, reason = makeArguments(result.actions, attempt.initiator, attempt.partner, attempt.furniture,
            attempt.seats and attempt.seats.id,
            initiator:GetGenderType() == male and partner:GetGenderType() == male)
        if not args then fail(reason, reason); return end
        attempt.args = args
        validation("invitation")
    elseif step == "invitation" then
        if not validated(step, result) then return end
        local initiator, partner = confirmPair()
        attempt.phase, attempt.deadline = "conversation", os.time() + 90
        local queued, reason = queue(initiator, partner:GetEntityId(), partner:GetLocation(), INVITE)
        if not queued then
            local denied = reason == inzoi.EB1AddInteractionQueueResult.EnqueueConditionCheckFail
            fail("Invitation enqueue failed: " .. tostring(reason), denied and "not_eligible" or "queue_failed")
            return
        end
        attempt.invitationQueued = true
        log("invitation_queued")
    elseif step == "arrival" then
        if not validated(step, result) then return end
        confirmPair()
        if attempt.seats then
            local sofa = manager():FindGameObject(entity(attempt.furniture))
            if not sofa
                or distanceSquared(sofa:GetLocation(), attempt.sofaLocation) > 1
                or math.abs((sofa:GetRotation().Yaw - attempt.sofaYaw + 180) % 360 - 180) > .1 then
                fail("The selected sofa pair changed during arrival", "furniture_unavailable")
                return
            end
        end
        attempt.args.scene_id, attempt.args.bindings = result.scene_id, result.bindings
        attempt.phase, attempt.deadline = "starting", os.time() + 60
        request("start", "start_autonomous_scene", attempt.args)
    elseif step == "start" then
        assert(result.accepted, "SceneZOI did not accept the start")
        log("start_accepted", {scene = result.scene_id, stages = result.stages})
    end
end

local function onSceneEvent(event)
    if not attempt then return end
    local prefix = "encounter." .. attempt.nonce
    if event.name == "partner_picker_finished" and event.request_id == prefix .. ".picker"
        and attempt.phase == "picking" then
        if event.code == "cancelled" then
            log("picker_cancelled")
            attempt = nil
        elseif event.code == "selected" and type(event.partner_id) == "string"
            and event.partner_id:match("^%d+$") and event.partner_id ~= attempt.initiator then
            attempt.partner = event.partner_id
            attempt.phase, attempt.deadline = "preflight", os.time() + 45
            confirmPair()
            if attempt.kind == "sofa.pair" then
                discoverVenue("sofa_seats", {attempt.initiator, attempt.partner})
            else
                request("definitions", "get_definitions")
            end
        else
            fail("Partner picker finished: " .. tostring(event.code), "picker_unavailable")
        end
        return
    end
    if event.request_id ~= prefix .. ".start" then return end
    if event.name == "session_start_failed" then
        fail(event.code, event.code)
    elseif event.name == "session_started" then
        attempt.phase = "playing"
        log("scene_started", {scene = event.node_id, session = event.session_id})
    elseif event.name == "session_ended" then
        local facts = event.result_facts or {}
        log("scene_ended", {session = event.session_id, outcome = event.plan and event.plan.outcome,
            reason = facts.stop_reason or event.code, cleanup = facts.cleanup_code, restored = facts.cleanup_complete})
        attempt = nil
    end
end

local function guarded(callback, ...)
    local ok, problem = pcall(callback, ...)
    if not ok then
        local notice = attempt and attempt.phase == "walking" and "walk_failed" or nil
        fail(problem, notice)
    end
end

function M.on_begin()
    if client then return end
    client = Client.new("hzoi.gameplay", {
        response = function(reply) guarded(onResponse, reply) end,
        event = function(event) guarded(onSceneEvent, event) end,
        instance_changed = function() fail("SceneZOI restarted", "update_scenezoi") end,
    })
    for _, kind in ipairs({"started", "finished", "failed", "canceled"}) do
        local name = "interaction." .. kind
        subscriptions[name] = inzoi.event.on(name, function(info) guarded(onNativeEvent, kind, info) end)
    end
    log("simulation_ready")
end

function M.on_lua_message(self, component, kind, content)
    if not client then return end
    local who = id(component:GetOwnerEntityId())
    if kind ~= "HZoiGameplay.Invite" then
        if attempt and who == attempt.initiator then client:on_message(kind, content) end
        return
    end
    local nonce, initiator, furniture = content:match("^([a-z0-9_%-]+)|(%d+)|(%d+)$")
    if not nonce or #nonce > 48 or who ~= initiator
        or who ~= id(inzoi.FB2ControllerSystem.GetPossessEntityId()) then return end
    if attempt then notify(who, "busy"); return end
    owner = actor(who)
    attempt = {nonce = nonce, initiator = initiator, furniture = furniture,
        phase = "preflight", deadline = os.time() + 45, walks = {}, dialogue = {}}
    guarded(function()
        assert(owner and eligible(owner), "The initiator is unavailable")
        request("features", "get_version")
    end)
end

local function tickAttempt()
    if attempt.phase == "playing" or attempt.phase == "picking" then return end
    if os.time() >= attempt.deadline then fail("Timed out", "timeout"); return end
    if attempt.phase == "conversation" then
        local first, second = attempt.initiator, attempt.partner
        if not attempt.conversationDispatched or attempt.dialogue[first] ~= "finished"
            or attempt.dialogue[second] ~= "finished" then return end
        local initiator, partner = confirmPair()
        if interaction(initiator):IsCurrentInteractionCoop() or interaction(partner):IsCurrentInteractionCoop() then return end
        if attempt.branch == "refuse" then
            log("refused")
            attempt = nil
        else
            log("accepted")
            beginWalking()
        end
        return
    end
    if attempt.phase ~= "walking" then return end
    confirmPair()
    for _, who in ipairs({attempt.initiator, attempt.partner}) do
        local walk = attempt.walks[who]
        if not walk or not walk.finished then return end
        local person = assert(actor(who), "Participant unloaded during arrival")
        local position = person:GetLocation()
        local horizontal = math.sqrt((position.X - walk.point.X)^2 + (position.Y - walk.point.Y)^2)
        -- ClickMove takes a floor point, while GetLocation includes the Zoi's capsule height.
        local height = math.abs(position.Z - walk.point.Z)
        assert(horizontal <= 80 and height <= 125,
            string.format("Walk ended away from the target for %s (%.1f cm across, %.1f cm in height)", who, horizontal, height))
        if not walk.reported then
            walk.reported = true
            log("walk_arrived", {participant = who, horizontal_cm = horizontal, height_cm = height})
        end
    end
    log("both_arrived")
    attempt.phase, attempt.deadline = "arrival", os.time() + 30
    validation("arrival")
end

function M.on_tick(self, component, dt)
    if not attempt or id(component:GetOwnerEntityId()) ~= attempt.initiator then return end
    owner = actor(attempt.initiator)
    guarded(function()
        assert(owner, "Initiator unloaded")
        client:tick(dt, owner)
        if attempt then tickAttempt() end
    end)
end

function M.on_end(self, component)
    if attempt and id(component:GetOwnerEntityId()) == attempt.initiator then
        guarded(function() fail("Initiator unloaded") end)
    end
end

function M.shutdown()
    for name, handle in pairs(subscriptions) do
        if handle and handle ~= 0 then inzoi.event.off(name, handle) end
    end
    subscriptions, client, attempt, owner = {}, nil, nil, nil
end

return M
