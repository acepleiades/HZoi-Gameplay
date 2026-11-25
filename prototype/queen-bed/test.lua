local callbacks, clientCallbacks, pending, queued, logs = {}, nil, {}, {}, {}
local clock, ownerId, partnerId, bedId, alternateBedId = 100, 20522, 20524, 21166, 21167
local sofaId, sofaLocation = 21168, {X = 900, Y = 500, Z = 0}
local controlled, blockedSide, queueResult = ownerId, false, "Success"
local notices = {}
local function entity(i) return {Value = i or -1} end
local function point(x, y, z) return {X = x, Y = y, Z = z} end
local function actor(i)
    local pos = point(0, 0, 0)
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
        return {IsOnWalkableGrid = function(_, p) return not blockedSide or p.X >= 600 end}
    end,
    EB1GrowthStep = {Youth = 32, Adult = 64, Old = 128, Elderly = 256}, EB1GenderType = {Male = 1},
    message = {send_to_client = function(_, kind, value)
        assert(kind == "HZoiGameplay.Notice")
        notices[#notices + 1] = value
    end},
    EB2ComponentType = {Interaction = 1}, EB1InteractionPlayReason = {User = 1},
    EB1InteractionCancelReason = {User = 1}, EB1AddInteractionQueueResult = {Success = "Success", EnqueueConditionCheckFail = "EnqueueConditionCheckFail"},
    FB2ControllerSystem = {GetPossessEntityId = function() return entity(controlled) end},
    event = {
        on = function(key, func) callbacks[key] = func; return 1 end,
        off = function(key) callbacks[key] = nil end,
    },
}
package.loaded["SceneZOIAddon.Client"] = {
    new = function(_, observers)
        clientCallbacks = observers
        return {
            refresh_owner = function() end,
            tick = function() end,
            request = function(_, _, key, op, args) pending[#pending + 1] = {key = key, op = op, args = args} end,
        }
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
local function fire(kind, player, bag, victim)
    callbacks["interaction." .. kind]({
        entity_id = entity(player), target_entity_id = entity(victim), interaction_bag_id = bag,
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
clientCallbacks.event({name = "session_started", request_id = start.key, session_id = "test"})
clientCallbacks.event({name = "session_ended", request_id = start.key, session_id = "test",
    result_facts = {cleanup_complete = true, cleanup_code = "ok"}})
assert(logs[#logs]:find("scene_ended"))

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
clientCallbacks.event({name = "session_started", request_id = sofaStart.key, session_id = "sofa"})
clientCallbacks.event({name = "session_ended", request_id = sofaStart.key, session_id = "sofa",
    result_facts = {cleanup_complete = true, cleanup_code = "ok"}})
assert(logs[#logs]:find("scene_ended"))
line("Sofa invitations passed: actual roster, exact pair across start checks, occupied or moved sofa, refusal, rotated corner sofa approach and cleanup.")
