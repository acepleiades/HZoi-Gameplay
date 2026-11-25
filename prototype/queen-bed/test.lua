local callbacks, clientCallbacks, pending, queued, logs = {}, nil, {}, {}, {}
local clock, ownerId, partnerId, bedId, alternateBedId = 100, 20522, 20524, 21166, 21167
local sofaId, sofaLocation = 21168, {X = 900, Y = 500, Z = 0}
local controlled, blockedSide, queueResult = ownerId, false, "Success"
local notices = {}
local walkable = function() return true end
local function entity(i) return {Value = i or -1} end
local function point(x, y, z) return {X = x, Y = y, Z = z} end
local function actor(i)
    local pos = point(0, 0, 0)
    local clickPosition
    local component = {
        IsCurrentInteractionCoop = function() return false end,
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
        GetGrowthStep = function() return 32 end,
        GetGenderType = function() return i == ownerId and 1 or 2 end,
        GetLocation = function() return pos end,
        ClickGround = function(_, location, inQueue, bag)
            clickPosition = location
            bag = bag or "HZoiGameplay_GroundInvite"
            -- The real start event arrived before the current bag and ID changed.
            component.GetCurrentInteractionBagId = function() return inQueue and "None" or bag end
            component.GetCurrentInteractionQueueId = function() return inQueue and -1 or 40 end
            component.InteractionQueue = {
                {InteractionQueueId = 39, InteractionBagId = "Other", ImpactPoint = point(1, 2, 3)},
            }
            if inQueue then
                component.InteractionQueue[2] = {InteractionQueueId = 40,
                    InteractionBagId = bag, ImpactPoint = location}
            end
            component.GetCurrentAction = function()
                return {NonTargetLocation = clickPosition}
            end
        end,
        MoveTo = function(_, p) pos = p end,
    }
end
local owner, partner = actor(ownerId), actor(partnerId)
local bed = {
    GetLocation = function() return point(300, 300, 0) end,
    GetRotation = function() return {Yaw = 90} end,
}
local manager = {
    FindCharacter = function(_, i)
        if i.Value == ownerId then return owner end
        if i.Value == partnerId then return partner end
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
    EB1GrowthStep = {Youth = 32, Adult = 64, Old = 128, Elderly = 256}, EB1GenderType = {Male = 1},
    message = {send_to_client = function(_, kind, value)
        assert(kind == "HZoiGameplay.Notice")
        notices[#notices + 1] = value
    end},
    EB1ActionType = {Delay = 33},
    EB2ComponentType = {Interaction = 1}, EB1InteractionPlayReason = {User = 1},
    EB1InteractionCancelReason = {User = 1, CharacterOverlap = 77}, EB1AddInteractionQueueResult = {Success = "Success", EnqueueConditionCheckFail = "EnqueueConditionCheckFail"},
    FB2ControllerSystem = {GetPossessEntityId = function() return entity(controlled) end},
    event = {
        on = function(key, func) callbacks[key] = func; return 1 end,
        off = function(key) callbacks[key] = nil end,
    },
}
local completions, outcomes = {}, {}
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
            request = function(_, _, key, op, args) pending[#pending + 1] = {key = key, op = op, args = args} end,
        }
    end,
}
package.loaded.NpcInitiative = {new = function() end}
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
local function fire(kind, player, bag, victim, reason)
    callbacks["interaction." .. kind]({
        entity_id = entity(player), target_entity_id = entity(victim), interaction_bag_id = bag, reason = reason,
    })
end
local function invite(nonce, partner, bed, bedStatus, rejection, cancelPicker)
    local before = #queued
    module.on_lua_message(state, component, "HZoiGameplay.Invite", table.concat({nonce, controlled, bed}, "|"))
    reply("get_version", {features = setmetatable({}, {__index = function() return 1 end})})
    local venues = reply("find_furniture", {furniture = {
        {furniture_id = tostring(bedId), profile = {kind = "bed.queen"}, status = bedStatus or "available"},
        {furniture_id = tostring(alternateBedId), profile = {kind = "bed.queen"}, status = "available"}
    }})
    assert(venues.args.origin_id == tostring(controlled))

    if bedStatus == "occupied" then return end
    local picker = reply("open_partner_picker", {opened = true})
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
    }})
    queueResult = rejection or "Success"
    local preflight = reply("validate_start", {valid = true})
    queueResult = "Success"
    assert(preflight.args.placement.max_start_distance_m == 100)
    assert(preflight.args.furniture_id == tostring(bed) and preflight.args.stages == 4)
    assert(#preflight.args.goals == 2 and preflight.args.start_mode == "start_autonomous_scene")
end
local INVITE, WALK = "HZoiGameplay_Invite", "HZoiGameplay_Walk"

local function conversation(refusal)
    local first, second = controlled, controlled == ownerId and partnerId or ownerId
    local bag = INVITE
    local action = "Coop_TalkLike_Before_MakeLove" .. (refusal and "_Fail" or "")
    local count = #queued
    fire("started", first, bag, second)
    fire("finished", first, bag, second)
    tick()
    assert(#queued == count and #pending == 0, "RequestCoop alone is not an answer")
    fire("started", first, action, second)
    fire("started", second, action .. "_Feedback", first)
    fire("finished", first, action, second)
    tick()
    assert(#queued == count and #pending == 0, "Wait for the selected partner's response")
    fire("finished", second, action .. "_Feedback", first)
    tick()
end


invite("picker-cancelled", partnerId, bedId, nil, nil, true)
assert(#queued == 0 and #pending == 0 and logs[#logs]:find("picker_cancelled"))
invite("refused", partnerId, bedId)
assert(queued[1].bag == INVITE and queued[1].target == partnerId)
conversation(true)
assert(logs[#logs]:find("refused") and #queued == 1 and #pending == 0)

-- The same action can be used by another selected Zoi, at a different bed.
controlled = partnerId
blockedSide = true
queued = {}
invite("wall", ownerId, alternateBedId)
assert(queued[1].id == partnerId and queued[1].target == ownerId)
conversation(false)
assert(queued[2].bag == WALK and queued[3].bag == WALK and #pending == 0)
local p1, p2 = queued[2].destination, queued[3].destination
assert(p1.X >= 600 and p2.X >= 600, "The wall-side points must be rejected")
assert((p1.X - p2.X)^2 + (p1.Y - p2.Y)^2 >= 150^2)
partner:MoveTo(point(p1.X, p1.Y, p1.Z + 90))
fire("finished", partnerId, WALK, -1)
tick()
assert(#pending == 0, "Start must wait for the second Zoi")
owner:MoveTo(point(p2.X, p2.Y, p2.Z + 90))
fire("finished", ownerId, WALK, -1)
tick()
local arrival = reply("validate_start", {valid = true, scene_id = "hzoi.bed", bindings = {male = "20522", female = "20524"}})
assert(not arrival.args.placement.max_start_distance_m and arrival.args.furniture_id == tostring(alternateBedId))
local start = reply("start_autonomous_scene", {accepted = true, stages = 4})
assert(start.args.scene_id == "hzoi.bed" and start.args.bindings.male == "20522")
assert(logs[#logs]:find("start_accepted") and not logs[#logs]:find("scene_started"))
clientCallbacks.event(snapshot(start, "unrelated", "playing", {name = "session_started",
    addon_client_id = "different.client"}))
clientCallbacks.event(snapshot(start, "unrelated", "playing", {name = "session_started",
    participants = {{id = tostring(ownerId)}, {id = "999"}}}))
assert(not logs[#logs]:find("scene_started"))
clientCallbacks.event(snapshot(start, "test", "playing", {name = "session_started"}))
assert(logs[#logs]:find("scene_started"))
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
assert(outcomes[1].result.task_counts_complete and logs[#logs]:find("scene_ended"))

controlled, blockedSide, queued = ownerId, false, {}
invite("canceled", partnerId, bedId)
fire("canceled", ownerId, INVITE, partnerId)
tick()
assert(#pending == 0 and #queued == 1 and logs[#logs - 1]:find("failed"))
invite("failed-walk", partnerId, bedId)
conversation(false)
fire("failed", partnerId, WALK, -1)
tick()
assert(#pending == 0 and #queued == 4 and notices[#notices] == "walk_failed")

queued = {}
invite("wrong-floor", partnerId, bedId)
conversation(false)
local first, second = queued[2].destination, queued[3].destination
owner:MoveTo(point(first.X, first.Y, first.Z + 300))
partner:MoveTo(point(second.X, second.Y, second.Z + 90))
fire("finished", ownerId, WALK, -1)
fire("finished", partnerId, WALK, -1)
tick()
assert(#pending == 0 and notices[#notices] == "walk_failed", "Reject another floor")

queued = {}
invite("occupied", partnerId, bedId, "occupied")
assert(#queued == 0 and notices[#notices] == "furniture_unavailable")
invite("ineligible", partnerId, bedId, nil, "EnqueueConditionCheckFail")
assert(#queued == 0 and notices[#notices] == "not_eligible")

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
local function sofaInvite(nonce, available)
    queued = {}
    module.on_lua_message(state, component, "HZoiGameplay.Invite", table.concat({nonce, ownerId, sofaId}, "|"))
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
    assert(preflight.args.placement.max_start_distance_m == 100 and #queued == 1)
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

sofaInvite("sofa-occupied", false)
assert(#pending == 0 and #queued == 0 and notices[#notices] == "sofa_unavailable")
sofaInvite("sofa-refused", true)
conversation(true)
assert(#pending == 0 and #queued == 1 and logs[#logs]:find("refused"))
sofaInvite("sofa-taken-during-walk", true)
arriveAtSofa()
local blocked = reply("validate_start", {valid = false, code = "furniture_unavailable"})
assert(blocked.args.furniture_pair_id == "side" and not blocked.args.placement.max_start_distance_m)
assert(#pending == 0 and notices[#notices] == "sofa_unavailable", "An alternate pair must never replace the chosen pair on arrival")
sofaInvite("sofa-changed-pair", true)
arriveAtSofa()
reply("validate_start", {valid = true, furniture_pair_id = "front"})
assert(#pending == 0 and notices[#notices] == "sofa_unavailable")
sofaInvite("sofa-moved", true)
arriveAtSofa()
sofaLocation = point(900, 520, 0)
reply("validate_start", {valid = true, furniture_pair_id = "side"})
assert(#pending == 0 and notices[#notices] == "sofa_unavailable")
sofaLocation = point(900, 500, 0)
sofaInvite("sofa-ready", true)
arriveAtSofa()
local sofaArrival = reply("validate_start", {valid = true, furniture_pair_id = "side", scene_id = "hzoi.sofa",
    bindings = {male = tostring(ownerId), female = tostring(partnerId)}})
assert(sofaArrival.args.furniture_pair_id == "side")
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
assert(recovered.args.session_id == "sofa" and logs[#logs]:find("scene_ended"))
assert(#completions == 4 and #outcomes == 2 and outcomes[2].record.furniture_pair == "side")
line("Sofa invitations passed: actual roster, exact pair across start checks, occupied or moved sofa, refusal, rotated corner sofa approach and cleanup.")


local clickedFloor = point(900, 650, 340)
local standing = {valid = true, scene_id = "hzoi.standing", bindings = {male = tostring(ownerId), female = tostring(partnerId)}}

local markBag = "HZoiGameplay_MarkPrivateRoom"
local marks = require("PrivateRoomMarks")
local originalToggle, markCount = marks.toggle, 0
marks.toggle = function(person, position)
    assert(person == owner and position == clickedFloor)
    markCount = markCount + 1
    return markCount == 1 and "private_room_marked" or "private_room_unmarked"
end
local markQueueCount = #queued
owner:ClickGround(clickedFloor, true, markBag)
fire("started", ownerId, markBag, -1)
fire("finished", ownerId, markBag, -1)
tick()
assert(markCount == 1 and notices[#notices] == "private_room_marked")
owner:ClickGround(clickedFloor, false, markBag)
fire("started", ownerId, markBag, -1)
assert(markCount == 2 and notices[#notices] == "private_room_unmarked")
fire("started", partnerId, markBag, -1)
owner:ClickGround(clickedFloor, false)
fire("started", ownerId, markBag, -1)
fire("finished", ownerId, "HZoiGameplay_GroundInvite", -1)
clock = clock + 3
tick()
assert(markCount == 2 and notices[#notices] == "private_room_unavailable")
assert(#pending == 0 and #queued == markQueueCount, "Toggling a room never starts a picker, walk, or scene.")
marks.toggle = originalToggle

local function selectGround(inQueue)
    queued = {}
    local selector = controlled == ownerId and owner or partner
    selector:ClickGround(clickedFloor, inQueue)
    fire("started", controlled, "HZoiGameplay_GroundInvite", -1)
end

local function groundInvite()
    selectGround(controlled == ownerId)
    reply("get_version", {features = setmetatable({}, {__index = function() return 1 end})})
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
fire("started", ownerId, "HZoiGameplay_GroundInvite", -1)
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
assert(not arrivalCheck.args.placement.max_start_distance_m)
assert(arrivalCheck.args.scene_id == standing.scene_id and arrivalCheck.args.bindings == standing.bindings)
local groundStart = reply("start_autonomous_scene", {accepted = true})
assert(groundStart.args.scene_id == standing.scene_id and groundStart.args.bindings == standing.bindings)
assert(not groundStart.args.furniture_id and not groundStart.args.furniture_pair_id)
clientCallbacks.event(snapshot(groundStart, "ground", "playing", {name = "session_started"}))
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
assert(logs[#logs]:find("scene_ended") and #completions == 5 and #outcomes == 2)
line("Ground invitations passed: native click handoff, both answers, separate destinations, blocked ground, wrong floor, departure and revalidation.")

arriveAtGround(false)
reply("validate_start", standing)
local startFailed = reply("start_autonomous_scene", {accepted = true})
clientCallbacks.event({name = "session_start_failed", request_id = startFailed.key, addon_id = "hzoi.gameplay",
    code = "start_failed"})
assert(notices[#notices] == "start_failed" and #completions == 5 and #outcomes == 2)

arriveAtGround(false)
reply("validate_start", standing)
local interrupted = reply("start_autonomous_scene", {accepted = true})
clientCallbacks.event(snapshot(interrupted, "interrupted", "playing", {name = "session_started"}))
clientCallbacks.event(snapshot(interrupted, "interrupted", "ended", {name = "session_ended",
    result_facts = {stop_reason = "runtime_error", cleanup_code = "runtime_error", cleanup_complete = true},
    task_state = taskCounts(0, 1)}))
assert(#completions == 6 and #outcomes == 2, "An interruption preserves confirmed completions")

arriveAtGround(false)
reply("validate_start", standing)
local missing = reply("start_autonomous_scene", {accepted = true})
clientCallbacks.event(snapshot(missing, "missing", "playing", {name = "session_started"}))
clock = clock + 9
tick()
current = request("get_session")
clientCallbacks.response({request_id = current.key, ok = false, code = "session_not_found"})
reply("get_session_result", {result = require("SceneZOIAddon.Json").null})
assert(logs[#logs]:find("No verified ended result") and #completions == 6 and #outcomes == 2)

line("Encounter results passed: request and roster matching, deduplication, lost notifications, cleanup, and unknown outcomes.")

local RETRY = "HZoiGameplay_WalkRetry"
local function recoveryAction(who, bag, reason)
    local actions = who:GetComponent()
    actions.GetCurrentInteractionQueueId = function() return bag and 76 or -1 end
    actions.GetCurrentInteractionBagId = function() return bag or "None" end
    actions.GetCurrentInteractionPlayReason = function() return reason end
    actions.InteractionQueue = {}
end

local function prepareOverlap(nonce)
    controlled, queued = ownerId, {}
    owner:MoveTo(point(0, 0, 0))
    partner:MoveTo(point(0, 0, 0))
    recoveryAction(owner)
    recoveryAction(partner)
    invite(nonce, partnerId, bedId)
    conversation(false)
    assert(#queued == 3 and #pending == 0)
    return queued[2].destination, queued[3].destination
end

local function finishWalk(who, id, position, bag)
    who:MoveTo(point(position.X, position.Y, position.Z + 90))
    fire("finished", id, bag or WALK, -1)
end

local ownerSpot, overlapSpot = prepareOverlap("recover-overlap")
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

ownerSpot = prepareOverlap("user-cancel-during-recovery")
fire("canceled", partnerId, WALK, -1, 77)
fire("canceled", partnerId, "ClickMove_Self", -1, "User")
tick()
assert(#queued == 3 and #pending == 0 and notices[#notices] == "walk_failed")

ownerSpot = prepareOverlap("new-task-supersedes-recovery")
fire("canceled", partnerId, WALK, -1, "CharacterOverlap")
finishWalk(owner, ownerId, ownerSpot)
recoveryAction(partner, "Eat", "User")
tick()
assert(#queued == 3 and #pending == 0 and notices[#notices] == "walk_failed")

prepareOverlap("both-overlap")
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

prepareOverlap("user-cancels-original")
fire("canceled", partnerId, WALK, -1, 1)
tick()
assert(#queued == 3 and #pending == 0 and notices[#notices] == "walk_failed")
line("Arrival overlap checks passed: serial retry, stale events, current native recovery, superseding actions, cancellation, and final revalidation.")
