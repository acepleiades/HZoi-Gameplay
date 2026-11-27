local now = 100
local controlled = 1
local callbacks, wire, queued, canceled, completed, terminal = {}, {}, {}, {}, {}, {}
local observers, tickCount
local standing
local privacyQueries, speech = {}, {}
local schedulers, notices = {}, {}
local Json = require("SceneZOIAddon.Json")
local function entity(value) return {Value = value or -1} end
local function point(x, y, z) return {X = x, Y = y or 0, Z = z or 0} end
local function roomAt(p) return math.floor(p.X / 1000) end

local actors = {}
for _, number in ipairs({1, 11, 12, 21, 22, 31}) do
    local location = point(300)
    local busy, currentBag, currentReason, currentTarget, autonomy = false, nil, nil, nil, true
    local finishing = false
    local interaction = {
        GetCurrentInteractionQueueId = function() return currentBag and 42 or -1 end,
        GetCurrentInteractionBagId = function() return currentBag or "None" end,
        GetCurrentInteractionTargetEntityId = function() return entity(currentTarget) end,
        GetCurrentInteractionPlayReason = function() return currentReason end,
        IsQueueEmpty = function() return not busy end,
        IsPlayingInteraction = function() return busy or finishing end,
        IsInteractionEnabled = function() return true end,
        IsCurrentInteractionInfinite = function() return false end,
        IsCurrentInteractionAlmostFinished = function() return finishing end,
        IsCurrentInteractionCoop = function() return false end,
        IsPendingCoop = function() return false end,
        AddInteractionQueueByParam = function(_, target, destination, bag, reason)
            queued[#queued + 1] = {who = number, target = target.Value, point = destination, bag = bag, reason = reason}
            return 1
        end,
        TryCancelInteractionByBagId = function(_, bag)
            canceled[#canceled + 1] = {who = number, bag = bag}
        end,
        TryCancelInteraction = function(_, queueId)
            canceled[#canceled + 1] = {who = number, queue = queueId}
        end,
    }
    actors[number] = {
        GetEntityId = function() return entity(number) end,
        GetGrowthStep = function() return 32 end,
        GetGenderType = function() return number % 2 == 0 and 2 or 1 end,
        GetComponent = function(_, kind) if kind == 1 then return interaction end end,
        IsSpawned = function() return true end,
        IsDeath = function() return false end,
        IsInRabbitHole = function() return false end,
        IsAutonomyEnable = function() return not busy end,
        GetLocation = function() return location end,
        move = function(_, p) location = p end,
        busy = function(_, state) busy = state end,
        finishSoon = function(_, state) finishing = state end,
        setRunning = function(_, bag, reason, target) currentBag, currentReason, currentTarget = bag, reason, target end,
        autonomyAllowed = function(_, value)
            if value ~= nil then autonomy = value end
            return autonomy
        end,
    }
end

local privateBedrooms = {[1] = true, [2] = true}
local privateStudy = {[3] = true}
local site = {
    GetSiteType = function() return 1 end,
    GetSiteId = function() return "test-residence" end,
    IsPublicSite = function() return false end,
    IsFakeSite = function() return false end,
    IsIn = function(_, p) return p.X > 0 and p.X < 4000 end,
    GetRoomPurposeIdByLocation = function(_, p)
        if privateBedrooms[roomAt(p)] then return "HZoiGameplay_PrivateBedroom" end
        if privateStudy[roomAt(p)] then return "HZoiGameplay_PrivateStudy" end
        return "None"
    end,
    GetOwnerHouseholdId = function() return entity(500) end,
    IsCharacterAllowedInRoom = function(_, person) return person.Value ~= 1 end,
    IsSameRoom = function(_, first, second) return roomAt(first) == roomAt(second) and first.Z == second.Z end,
    IsExistInternalPath = function(_, _, _, params)
        assert(params.bIgnorePermission == false and actors[params.EntityId.Value] and params.EntityId.Value ~= 1)
        return true
    end,
}
local function furniture(x)
    return {GetLocation = function() return point(x) end, GetRotation = function() return {Yaw = 0} end,
        GetComponent = function() end}
end
local objects = {[411] = furniture(1425), [421] = furniture(2425)}
local manager = {
    GetAllEntities = function(_, kind) return kind == 4 and schedulers or actors end,
    FindCharacter = function(_, who) return actors[who.Value] end,
    FindGameObject = function(_, object) return objects[object.Value] end,
}
local sites = {
    FindClosestSite = function() return site end,
    IsIndoor = function(_, p) return site:IsIn(p) and roomAt(p) > 0 end,
}

inzoi = {
    FB1EntityId = entity, FB1NavigationQueryParams = function() return {} end,
    getB2Manager = function(name) return name == "FB2EntityManager" and manager or sites end,
    getB2Subsystem = function()
        return {IsOnWalkableGrid = function(_, p) return site:IsIn(p) and p.Y >= -800 and p.Y <= 800 end}
    end,
    EB1GrowthStep = {Youth = 32, Adult = 64, Old = 128, Elderly = 256}, EB1GenderType = {Male = 1, Female = 2},
    EB1SiteType = {Residence = 1}, EB2EntityType = {Character = 3, CoopScheduler = 4},
    EB2ComponentType = {Interaction = 1},
    EB1InteractionPlayReason = {User = 3, Autonomy = 8}, EB1InteractionCancelReason = {User = 1},
    EB1AddInteractionQueueResult = {Success = 1, EnqueueConditionCheckFail = 17},
    FB2ControllerSystem = {GetPossessEntityId = function() return entity(controlled) end},
    event = {
        on = function(name, callback) callbacks[name] = callback; return 1 end,
        off = function(name) callbacks[name] = nil end,
    },
    message = {send_to_client = function(owner, kind, payload)
        if kind == "HZoiGameplay.Notice" then
            notices[#notices + 1] = {owner = owner.Value, code = payload}
            return
        end
        assert(owner.Value == controlled and kind == "HZoiGameplay.WitnessTrace",
            "NPC failures should stay in the diagnostics")
        local query = Json.decode(payload)
        if query.kind == "arrival" then privacyQueries[#privacyQueries + 1] = query end
    end},
}
UE = {FVector = point}
local emit = print
print = function() end
os.time = function() return now end
tickCount = 0
package.loaded["SceneZOIAddon.Client"] = {
    new = function(_, handlers)
        observers = handlers
        return {
            client_id = "client.npc-test",
            tick = function(_, _, owner)
                assert(owner:GetEntityId().Value == controlled)
                tickCount = tickCount + 1
            end,
            request = function(_, owner, key, op, args)
                assert(owner:GetEntityId().Value == controlled)
                assert(not wire[key])
                wire[key] = {op = op, args = args or {}}
            end,
        }
    end,
}
package.loaded["EncounterConsequences"] = {
    onCompletion = function(encounter, who, task)
        assert(task == "excitement")
        completed[#completed + 1] = {session = encounter.session_id, who = who}
    end,
    onResult = function(encounter)
        terminal[#terminal + 1] = encounter.session_id
    end,
}

local Initiative = require("NpcInitiative")
Initiative.new = function() end
Initiative.canAct = function(person) return person:autonomyAllowed() end
Initiative.isSimulationRunning = function() return true end
package.loaded.InvitationEligibility = {
    canInvite = function() return true end,
    canSelect = function() return true end,
}
package.loaded.NpcStandingAnchors = {find = function() return standing or {} end}
package.loaded.WitnessNative = {
    relationshipScore = function(observer)
        assert(observer == actors[31], "Read the observer's side")
        return 0
    end,
    say = function(...) speech[#speech + 1] = {...} end,
    tickSpeech = function() end,
}
local invite = require("Components.VenueInvite")
local main = require("Main")
main.on_begin()
local function expect(nonce, step, op)
    assert(nonce)
    local key = "encounter." .. nonce .. "." .. step
    local wanted = assert(wire[key], key)
    assert(wanted.op == op, wanted.op)
    return key, wanted.args
end
local function reply(nonce, step, op, data)
    local key, args = expect(nonce, step, op)
    wire[key] = nil
    observers.response({request_id = key, result = data, ok = true})
    return args
end
local function confirmPrivacy(nonce, visible)
    local wire = assert(table.remove(privacyQueries, 1))
    assert(wire.token:find(nonce, 1, true) and wire.points[wire.participants[1]])
    invite.on_lua_message({}, {GetOwnerEntityId = function() return entity(controlled) end},
        "HZoiGameplay.WitnessResult", Json.encode({
            kind = "arrival", token = wire.token, revision = wire.revision,
            observations = Json.array(visible or {}),
        }))
end
local function tick()
    local before = tickCount
    main.on_tick(0.05)
    assert(tickCount == before + 1, "Tick the shared SDK once per frame")
end
local function event(name, who, target, bag, reason)
    callbacks["interaction." .. name]({entity_id = entity(who), target_entity_id = entity(target),
        interaction_bag_id = bag, reason = reason})
end

local sofaprofile = {kind = "sofa.pair", sitting_spots = {
    {id = "left", offset_cm = {x = -40, y = 0, z = 0}, yaw_degrees = 0},
    {id = "right", offset_cm = {x = 40, y = 0, z = 0}, yaw_degrees = 0},
}}
local rows = {
    {furniture_id = "411", profile = {kind = "bed.queen"}, available = true},
    {furniture_id = "421", profile = sofaprofile, available = true, furniture_pair_id = "center",
        sitting_spots = {"left", "right"}},
}
local knownFeatures = setmetatable({}, {__index = function() return 1 end})
local definitions = {actions = {handjob = {sexual_activity = "non_penetrative", content_rating = "EXPLICIT"}}}
local function preflight(nonce, first, second, furniture)
    reply(nonce, "features", "get_version", {features = knownFeatures})
    local search = reply(nonce, "venues", "find_furniture", {furniture = furniture or rows})
    assert(search.include_unavailable and search.origin_id == tostring(first))
    assert(search.participants[1] == tostring(first) and search.participants[2] == tostring(second))
    reply(nonce, "definitions", "get_definitions", definitions)
end
local function nativeConversation(first, second, refused)
    event("started", first, second, "HZoiGameplay_Invite")
    event("finished", first, second, "HZoiGameplay_Invite")
    local branch = "Coop_TalkLike_Before_MakeLove" .. (refused and "_Fail" or "")
    event("started", first, second, branch)
    event("started", second, first, branch .. "_Feedback")
    event("finished", first, second, branch)
    event("finished", second, first, branch .. "_Feedback")
end
local function walkFor(who, bag)
    for i = #queued, 1, -1 do
        local walk = queued[i]
        if walk.who == who and walk.bag == (bag or "HZoiGameplay_Walk") then return walk end
    end
end
local function arrived(who, bag, playReason)
    local walk = assert(walkFor(who, bag))
    assert(walk.reason == (playReason or inzoi.EB1InteractionPlayReason.Autonomy))
    actors[who]:move(walk.point)
    event("finished", who, -1, walk.bag)
end
local function valid(first, second, pair)
    return {valid = true, scene_id = "hzoi.scene", anchor_participant_id = tostring(first),
        bindings = {male = tostring(first), female = tostring(second)},
        furniture_pair_id = pair}
end
local function snapshot(nonce, session, first, second, phase, name, facts)
    return {
        request_id = "encounter." .. nonce .. ".start", id = session, session_id = session,
        addon_id = "hzoi.gameplay", addon_client_id = "client.npc-test", phase = phase, name = name,
        participants = {{id = tostring(first)}, {id = tostring(second)}}, result_facts = facts,
    }
end

actors[1]:autonomyAllowed(false)
assert(not invite.beginNpc(1, 11), "A controlled initiator must have effective autonomy")
actors[1]:autonomyAllowed(true)
actors[11]:busy(true)
assert(not invite.beginNpc(11, 12))
actors[11]:busy(false)
local starts, deniedStarts = 0, 0
controlled = 11
actors[12]:autonomyAllowed(false)
local success, a = invite.beginNpc(11, 12, function() starts = starts + 1 end)
assert(success, "A controlled initiator can invite an available partner with autonomy off")
local success, b = invite.beginNpc(21, 22, function() deniedStarts = deniedStarts + 1 end)
assert(success and a ~= b)
assert(not invite.beginNpc(11, 22) and not invite.beginNpc(31, 12), "No overlapping roster")
preflight(b, 21, 22)
preflight(a, 11, 12)
assert(starts == 0, "Preparation does not start the invitation cooldown")
local denied = reply(b, "venue-1", "validate_start", {valid = false, code = "no_matching_scenes"})
assert(denied.background and denied.furniture_id == "411")
local selected = reply(b, "venue-2", "validate_start", valid(21, 22, "center"))
assert(selected.background and selected.furniture_id == "421" and selected.furniture_pair_id == "center")
actors[12]:setRunning("ordinary_task", inzoi.EB1InteractionPlayReason.Autonomy)
actors[12]:finishSoon(true)
reply(a, "venue-1", "validate_start", valid(11, 12))
assert(starts == 0 and #queued == 1, "Let the partner finish the ordinary task before asking")
actors[12]:finishSoon(false)
actors[12]:setRunning()
tick()
assert(starts == 0 and deniedStarts == 0, "Successful native invitation enqueue does not start the cooldown")
assert(queued[1].who == 21 and queued[2].who == 11 and queued[1].reason == inzoi.EB1InteractionPlayReason.Autonomy)
controlled = 11
nativeConversation(11, 12)
nativeConversation(21, 22)
tick()
actors[12]:autonomyAllowed(true)
arrived(11)
arrived(12)
arrived(21)
controlled = 1
tick()
reply(a, "arrival", "validate_start", valid(11, 12))
confirmPrivacy(a)
local args = reply(a, "start", "start_autonomous_scene", {accepted = true})
assert(args.background and args.furniture_id == "411" and args.initiator == "11")
assert(starts == 0, "Acceptance, arrival and the SDK's accepted start request do not start the cooldown")
observers.event(snapshot(a, "session-a", 11, 12, "preparing", "session_preparing"))
assert(starts == 0, "Preparing playback does not start the cooldown")
observers.event(snapshot(a, "session-a", 11, 12, "playing", "session_started"))
assert(starts == 1, "Observed playback starts the autonomous sender's cooldown")
observers.event(snapshot(a, "session-a", 11, 12, "playing", "session_started"))
assert(starts == 1, "A duplicate event cannot spend another cooldown")

actors[31]:move(point(2450))
now = now + 1
tick()
assert(#canceled == 0, "Room occupancy alone cannot cancel a still-pending walk")
arrived(22)
controlled = 22
tick()
reply(b, "arrival", "validate_start", valid(21, 22, "center"))
confirmPrivacy(b, {{id = "31"}})
assert(not wire["encounter." .. b .. ".start"] and #speech == 0 and #canceled == 0 and deniedStarts == 0,
    "A visible unqualified observer ends the invitation quietly while the invited partner is controlled")
controlled = 1

actors[31]:move(point(300))
actors[21]:move(point(300))
actors[22]:move(point(300))
local recoveredStarts = 0
local success, retry = invite.beginNpc(21, 22, function() recoveredStarts = recoveredStarts + 1 end)
assert(success, "A confirmed privacy denial releases the participants and room")
standing = {point(3320)}
preflight(retry, 21, 22, rows)
standing = nil
-- The active encounter claims the first room. Try standing after the sofa fails preflight.
local sofa = reply(retry, "venue-1", "validate_start", {valid = false, code = "no_matching_scenes"})
assert(sofa.furniture_id == "421")
local ground = reply(retry, "venue-2", "validate_start", valid(21, 22))
assert(not ground.furniture_id and ground.background)
nativeConversation(21, 22)
tick()
assert(walkFor(21).point.X == 3320 and walkFor(22).point.X ~= 0, "Keep the ground role on the anchor")
arrived(21)
arrived(22)
tick()
reply(retry, "arrival", "validate_start", valid(21, 22))
confirmPrivacy(retry)
reply(retry, "start", "start_autonomous_scene", {accepted = true})
observers.event(snapshot(retry, "session-b", 21, 22, "preparing", "session_preparing"))
assert(recoveredStarts == 0)
now = now + 8
tick()
reply(retry, "observe-1", "get_session", {session = snapshot(retry, "session-b", 21, 22, "playing")})
assert(recoveredStarts == 1, "A recovered playing snapshot can establish a missed playback start")
observers.event(snapshot(retry, "session-b", 21, 22, "playing", "session_started"))
assert(recoveredStarts == 1, "The delayed original event cannot spend another cooldown")

local task = snapshot(retry, "session-b", 21, 22, "playing", "task_completed")
task.task, task.participant_id = {id = "excitement", completion_index = 1}, "21"
observers.event(task)
local finishA = snapshot(a, "session-a", 11, 12, "ended", "session_ended",
    {cleanup_complete = true, stop_reason = "ok", stop_origin = {source = "framework"}, playing_seconds = 3})
finishA.task_state = {
    {participant_id = "11", task_id = "excitement", completions = 0},
    {participant_id = "12", task_id = "excitement", completions = 0},
}
observers.event(finishA)
assert(#terminal == 1 and terminal[1] == "session-a")
observers.event(task)
assert(#completed == 1 and completed[1].session == "session-b" and completed[1].who == "21")
assert(not invite.beginNpc(11, 21), "Ending the first session does not release the second roster")
invite.shutdown()

local WALK, RETRY = "HZoiGameplay_Walk", "HZoiGameplay_WalkRetry"
local function prepareApproach()
    for _, person in pairs(actors) do
        person:move(point(300))
        person:setRunning()
    end
    now = now + 1
    queued = {}
    local accepted, nonce = invite.beginNpc(11, 12)
    assert(accepted, nonce)
    preflight(nonce, 11, 12, rows)
    reply(nonce, "venue-1", "validate_start", valid(11, 12))
    nativeConversation(11, 12)
    tick()
    assert(#queued == 3)
    return nonce, assert(walkFor(11)).point
end

local function pushAside(spot, height)
    actors[11]:move(point(spot.X + 111, spot.Y, spot.Z + (height or 90)))
end

local function runPartnerRetry()
    actors[12]:setRunning()
    tick()
    assert(#queued == 4 and queued[4].who == 12 and queued[4].bag == RETRY)
    arrived(12, RETRY)
end

invite.on_begin()
local nonce, destination = prepareApproach()
event("canceled", 12, -1, WALK, "CharacterOverlap")
actors[12]:setRunning("ClickMove_Self", "MoveOver")
arrived(11)
tick()
pushAside(destination)
tick()
assert(#queued == 3, "Do not fail the first arrival while the partner's native overlap is still active")
runPartnerRetry()
actors[11]:setRunning("ClickMove_Self", "MoveOver")
tick()
assert(#queued == 4, "Wait for the first actor's native recovery before returning")
actors[11]:setRunning()
tick()
assert(#queued == 5 and queued[5].who == 11 and queued[5].bag == RETRY)
assert(queued[5].point == destination, "Return to the original verified destination")
arrived(11, RETRY)
tick()
reply(nonce, "arrival", "validate_start", {valid = false, code = "furniture_unavailable"})

nonce, destination = prepareApproach()
arrived(11)
tick()
pushAside(destination)
arrived(12)
tick()
assert(#queued == 3 and not wire["encounter." .. nonce .. ".arrival"], "No reapproach without a native overlap")

nonce, destination = prepareApproach()
event("canceled", 12, -1, WALK, "CharacterOverlap")
arrived(11)
tick()
pushAside(destination)
arrived(12, RETRY)
event("started", 11, -1, "ClickMove_Self", "User")
tick()
assert(#queued == 4 and not wire["encounter." .. nonce .. ".arrival"], "A player action takes priority")

nonce, destination = prepareApproach()
event("canceled", 12, -1, WALK, "CharacterOverlap")
arrived(11)
tick()
pushAside(destination)
arrived(12, RETRY)
actors[11]:setRunning("Eat", "Autonomy")
tick()
assert(#queued == 4 and not wire["encounter." .. nonce .. ".arrival"], "Preserve unrelated native activity")

nonce, destination = prepareApproach()
event("canceled", 12, -1, WALK, "CharacterOverlap")
arrived(11)
tick()
pushAside(destination, 300)
arrived(12, RETRY)
tick()
assert(#queued == 4 and not wire["encounter." .. nonce .. ".arrival"], "A different floor is never a displaced arrival")

nonce, destination = prepareApproach()
event("canceled", 12, -1, WALK, "CharacterOverlap")
arrived(11)
tick()
pushAside(destination)
arrived(12, RETRY)
actors[31]:move(destination)
tick()
assert(#queued == 5 and not wire["encounter." .. nonce .. ".arrival"], "A new occupant does not block a return walk")
arrived(11, RETRY)
tick()
reply(nonce, "arrival", "validate_start", valid(11, 12))
confirmPrivacy(nonce)
reply(nonce, "start", "start_autonomous_scene", {accepted = true})
observers.event({name = "session_start_failed", request_id = "encounter." .. nonce .. ".start",
    addon_id = "hzoi.gameplay", code = "start_failed"})

nonce, destination = prepareApproach()
event("canceled", 12, -1, WALK, "CharacterOverlap")
arrived(11)
tick()
pushAside(destination)
arrived(12, RETRY)
tick()
assert(#queued == 5)
event("finished", 11, -1, RETRY)
tick()
assert(#queued == 5 and not wire["encounter." .. nonce .. ".arrival"], "Allow only one return")
invite.shutdown()

invite.on_begin()
for _, person in pairs(actors) do person:move(point(300)); person:setRunning() end
local ready, pauseConversation = invite.beginNpc(11, 12)
assert(ready, pauseConversation)
preflight(pauseConversation, 11, 12)
reply(pauseConversation, "venue-1", "validate_start", valid(11, 12))
local branch = "Coop_TalkLike_Before_MakeLove"
event("started", 11, 12, "HZoiGameplay_Invite")
event("finished", 11, 12, "HZoiGameplay_Invite")
event("started", 11, 12, branch)
actors[11]:setRunning(branch, "Autonomy", 12)
local actions = actors[12]:GetComponent(1)
actions.InteractionQueue = {
    {InteractionQueueId = 51, InteractionBagId = branch .. "_Feedback", PickedEntityId = entity(11)},
    {InteractionQueueId = 52, InteractionBagId = branch .. "_Feedback", PickedEntityId = entity(31)},
}
local canceledBefore, queuedBefore = #canceled, #queued
actors[11]:autonomyAllowed(false)
tick()
assert(#canceled == canceledBefore + 3 and canceled[canceledBefore + 1].bag == "HZoiGameplay_Invite")
assert(canceled[canceledBefore + 2].who == 11 and canceled[canceledBefore + 2].queue == 42)
assert(canceled[canceledBefore + 3].who == 12 and canceled[canceledBefore + 3].queue == 51,
    "Cancel only the matching conversation roles when the initiator's autonomy changes")
actors[11]:autonomyAllowed(true)
nativeConversation(11, 12)
assert(#queued == queuedBefore, "Late canceled conversation events must not start the approach")
actions.InteractionQueue = nil

nonce = prepareApproach()
arrived(11)
arrived(12)
tick()
reply(nonce, "arrival", "validate_start", valid(11, 12))
confirmPrivacy(nonce)
reply(nonce, "start", "start_autonomous_scene", {accepted = true})
now = now + 1
actors[11]:autonomyAllowed(false)
tick()
assert(not wire["encounter." .. nonce .. ".cancel-start"],
    "SceneZOI can temporarily disable autonomy between the start reply and playback")
now = now + 60
tick()
local cancelArgs = reply(nonce, "cancel-start", "cancel_start", {accepted = true})
assert(cancelArgs.start_request_id == "encounter." .. nonce .. ".start")
reply(nonce, "observe-1", "get_request_status", {phase = "failed", code = "start_failed"})
actors[11]:autonomyAllowed(true)

nonce = prepareApproach()
arrived(11)
arrived(12)
tick()
reply(nonce, "arrival", "validate_start", valid(11, 12))
confirmPrivacy(nonce)
reply(nonce, "start", "start_autonomous_scene", {accepted = true})
observers.event(snapshot(nonce, "keep-playing", 11, 12, "playing", "session_started"))
now = now + 1
actors[11]:autonomyAllowed(false)
tick()
assert(not wire["encounter." .. nonce .. ".cancel-start"], "An already-playing session can finish")
actors[11]:autonomyAllowed(true)
invite.shutdown()

invite.on_begin()
for _, pair in ipairs({{11, 12}, {12, 11}}) do
    local first, second = table.unpack(pair)
    controlled, wire = first, {}
    actors[first]:autonomyAllowed(false)
    actors[second]:autonomyAllowed(false)
    local queuedBefore = #queued
    local menu = "HZoiGameplay_FindVenue"
    local actions = actors[first]:GetComponent(1)
    actions.InteractionQueue = {{InteractionBagId = menu, PickedEntityId = entity(second),
        PlayReason = inzoi.EB1InteractionPlayReason.User}}
    event("started", first, -1, menu)
    event("canceled", first, -1, menu)
    event("finished", first, second, menu)
    assert(next(wire) == nil, "A canceled Romance interaction must not start a search")
    event("started", first, -1, menu)
    assert(next(wire) == nil, "Wait until the native menu action finishes")
    actions.InteractionQueue = nil
    controlled = 1
    event("finished", first, -1, menu)
    local key = assert(next(wire), "Use the clicked partner across possession changes")
    local nonce = assert(key:match("^encounter%.(romance%-[^.]+)%.features$"))
    preflight(nonce, first, second)
    local args = reply(nonce, "venue-1", "validate_start", valid(first, second))
    assert(not args.background and args.furniture_id == "411", "Use the shared venue ranking for player starts")
    local invitation = assert(queued[#queued])
    assert(invitation.reason == inzoi.EB1InteractionPlayReason.User
        and invitation.who == first and invitation.target == second)
    nativeConversation(first, second, true)
    assert(#queued == queuedBefore + 1, "Refusal does not walk to the venue or start a session")
end

controlled, wire, queued = 11, {}, {}
for _, person in pairs(actors) do
    person:move(point(300))
    person:setRunning()
end
event("started", 11, 12, "HZoiGameplay_FindVenue")
event("finished", 11, 12, "HZoiGameplay_FindVenue")
local romance = assert(assert(next(wire)):match("^encounter%.(romance%-[^.]+)%.features$"))
preflight(romance, 11, 12)
reply(romance, "venue-1", "validate_start", valid(11, 12))
nativeConversation(11, 12)
tick()
assert(#queued == 3)
event("canceled", 12, -1, WALK, "CharacterOverlap")
arrived(11, WALK, inzoi.EB1InteractionPlayReason.User)
tick()
pushAside(walkFor(11).point)
arrived(12, RETRY, inzoi.EB1InteractionPlayReason.User)
event("started", 11, -1, "ClickMove_Self", "User")
tick()
assert(#queued == 4 and not wire["encounter." .. romance .. ".arrival"],
    "A player action after a Romance invitation supersedes an automatic return walk")
invite.shutdown()

invite.on_begin()
local function prepareRomanceHandoff()
    controlled, wire, queued, notices, schedulers = 11, {}, {}, {}, {}
    for _, person in pairs(actors) do
        person:move(point(300))
        person:setRunning()
    end
    event("started", 11, 12, "HZoiGameplay_FindVenue")
    event("finished", 11, 12, "HZoiGameplay_FindVenue")
    local key = assert(assert(next(wire)):match("^encounter%.(romance%-[^.]+)%.features$"))
    preflight(key, 11, 12)
    reply(key, "venue-1", "validate_start", valid(11, 12))
    event("started", 11, 12, "HZoiGameplay_Invite")
end
local relationship = require("EncounterRelationship")
local onRefusal = relationship.onRefusal
local refusalCount = 0
relationship.onRefusal = function()
    refusalCount = refusalCount + 1
end
local coop = {GetEntityId = function() return entity(900) end, HostId = entity(11), MainTargetId = entity(12),
    OriginInteractionBagId = "Co_TryTo_Mood_Lover", CoopId = "HZoiGameplay_Coop_Refuse", CurrentResult = "None"}
prepareRomanceHandoff()
schedulers = {coop}
event("canceled", 11, 12, "HZoiGameplay_Invite", "Coop")
tick()
assert(#notices == 0 and refusalCount == 0)
coop.OriginInteractionBagId = "HZoiGameplay_Invite"
tick()
local refusal = "Coop_TalkLike_Before_MakeLove_Fail"
event("started", 11, 12, refusal)
event("started", 12, 11, refusal .. "_Feedback")
event("finished", 11, 12, refusal)
assert(refusalCount == 0, "Wait for both Zois to finish the native refusal")
event("finished", 12, 11, refusal .. "_Feedback")
event("finished", 12, 11, refusal .. "_Feedback")
assert(refusalCount == 1 and #queued == 1 and #notices == 0, "Complete the refusal once without walking")

prepareRomanceHandoff()
coop.MainTargetId = entity(21)
schedulers = {coop}
event("canceled", 11, 12, "HZoiGameplay_Invite", "Coop")
now = now + 2
tick()
assert(refusalCount == 1 and #queued == 1 and #notices == 1 and notices[1].code == "failed",
    "An unrelated scheduler must not turn a real cancellation into a dispatch")
relationship.onRefusal = onRefusal
invite.shutdown()

invite.on_begin()
controlled, wire, queued, schedulers = 11, {}, {}, {}
for _, person in pairs(actors) do
    person:move(point(300))
    person:setRunning()
end
actors[11]:autonomyAllowed(true)
local ready, interrupted = invite.beginNpc(11, 12)
assert(ready)
preflight(interrupted, 11, 12)
actors[12]:setRunning("ordinary_task", inzoi.EB1InteractionPlayReason.Autonomy)
actors[12]:finishSoon(true)
reply(interrupted, "venue-1", "validate_start", valid(11, 12))
assert(#queued == 0)
actors[12]:finishSoon(false)
actors[12]:setRunning()
actors[11]:busy(true)
local canceledBefore = #canceled
tick()
assert(#queued == 0 and #canceled == canceledBefore,
    "A player action queued while waiting supersedes the invitation without being canceled")
actors[11]:busy(false)
assert(invite.beginNpc(11, 12), "A superseded invitation releases both Zois")
invite.shutdown()

emit("NPC invitation checks passed: concurrent sessions, privacy, venue fallback, and one-time return after native overlap.")
