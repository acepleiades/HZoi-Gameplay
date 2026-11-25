local now = 100
local controlled = 1
local callbacks, wire, queued, canceled, completed, terminal = {}, {}, {}, {}, {}, {}
local observers, tickCount
local function entity(value) return {Value = value or -1} end
local function point(x, y, z) return {X = x, Y = y or 0, Z = z or 0} end
local function roomAt(p) return math.floor(p.X / 1000) end

local actors = {}
for _, number in ipairs({1, 11, 12, 21, 22, 31}) do
    local location = point(300)
    local busy, currentBag, currentReason = false, nil, nil
    local interaction = {
        GetCurrentInteractionQueueId = function() return currentBag and 42 or -1 end,
        GetCurrentInteractionBagId = function() return currentBag or "None" end,
        GetCurrentInteractionPlayReason = function() return currentReason end,
        IsQueueEmpty = function() return not busy end,
        IsPlayingInteraction = function() return busy end,
        IsCurrentInteractionCoop = function() return false end,
        AddInteractionQueueByParam = function(_, target, destination, bag, reason)
            queued[#queued + 1] = {who = number, target = target.Value, point = destination, bag = bag, reason = reason}
            return 1
        end,
        TryCancelInteractionByBagId = function(_, bag)
            canceled[#canceled + 1] = {who = number, bag = bag}
        end,
    }
    actors[number] = {
        GetEntityId = function() return entity(number) end,
        GetGrowthStep = function() return 32 end,
        GetGenderType = function() return number % 2 == 0 and 2 or 1 end,
        GetComponent = function(_, kind) if kind == 1 then return interaction end end,
        IsSpawned = function() return true end,
        IsAutonomyEnable = function() return not busy end,
        GetLocation = function() return location end,
        move = function(_, p) location = p end,
        busy = function(_, state) busy = state end,
        setRunning = function(_, bag, reason) currentBag, currentReason = bag, reason end,
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
        assert(params.bIgnorePermission == false and params.EntityId.Value ~= controlled)
        return true
    end,
}
local function furniture(x)
    return {GetLocation = function() return point(x) end, GetRotation = function() return {Yaw = 0} end}
end
local objects = {[411] = furniture(1425), [421] = furniture(2425)}
local manager = {
    GetAllEntities = function() return actors end,
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
    EB1GrowthStep = {Youth = 32, Adult = 64, Old = 128, Elderly = 256}, EB1GenderType = {Male = 1},
    EB1SiteType = {Residence = 1}, EB2EntityType = {Character = 3},
    EB2ComponentType = {Interaction = 1, Hope = 2, Mission = 3},
    EB1InteractionPlayReason = {User = 3, Autonomy = 8}, EB1InteractionCancelReason = {User = 1},
    EB1AddInteractionQueueResult = {Success = 1, EnqueueConditionCheckFail = 17},
    FB2ControllerSystem = {GetPossessEntityId = function() return entity(controlled) end},
    event = {
        on = function(name, callback) callbacks[name] = callback; return 1 end,
        off = function(name) callbacks[name] = nil end,
    },
    message = {send_to_client = function() error("NPC failures should stay in the diagnostics") end},
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

package.loaded.NpcInitiative = {new = function() end, canAct = function(person) return person:IsAutonomyEnable() end}
package.loaded.OwnedEncounterUrges = {
    pending = function(owner) return {partner = tostring(owner:GetEntityId().Value + 1)} end,
    canInvite = function() return true end,
    onCompletion = function() return false end,
    reset = function() end,
}
local invite = require("Components.VenueInvite")
invite.on_begin()
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
local function tick()
    local before = tickCount
    for whom in pairs(actors) do
        invite.on_tick({}, {GetOwnerEntityId = function() return entity(whom) end}, 0.05)
    end
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
    local search = reply(nonce, "npc_venues", "find_furniture", {furniture = furniture or rows})
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
local function arrived(who, bag)
    local walk = assert(walkFor(who, bag))
    assert(walk.reason == inzoi.EB1InteractionPlayReason.Autonomy)
    actors[who]:move(walk.point)
    event("finished", who, -1, walk.bag)
end
local function valid(first, second, pair)
    return {valid = true, scene_id = "hzoi.scene", bindings = {male = tostring(first), female = tostring(second)},
        furniture_pair_id = pair}
end
local function snapshot(nonce, session, first, second, phase, name, facts)
    return {
        request_id = "encounter." .. nonce .. ".start", id = session, session_id = session,
        addon_id = "hzoi.gameplay", addon_client_id = "client.npc-test", phase = phase, name = name,
        participants = {{id = tostring(first)}, {id = tostring(second)}}, result_facts = facts,
    }
end

assert(not invite.beginNpc(1, 11), "Do not initiate for the controlled Zoi")
actors[11]:busy(true)
assert(not invite.beginNpc(11, 12))
actors[11]:busy(false)
local success, a = invite.beginNpc(11, 12)
assert(success)
local success, b = invite.beginNpc(21, 22)
assert(success and a ~= b)
assert(not invite.beginNpc(11, 22) and not invite.beginNpc(31, 12), "No overlapping roster")
preflight(b, 21, 22)
preflight(a, 11, 12)
local denied = reply(b, "venue-1", "validate_start", {valid = false, code = "no_matching_scenes"})
assert(denied.background and denied.furniture_id == "411")
local selected = reply(b, "venue-2", "validate_start", valid(21, 22, "center"))
assert(selected.background and selected.furniture_id == "421" and selected.furniture_pair_id == "center")
reply(a, "venue-1", "validate_start", valid(11, 12))
assert(queued[1].who == 21 and queued[2].who == 11 and queued[1].reason == inzoi.EB1InteractionPlayReason.Autonomy)
nativeConversation(11, 12)
nativeConversation(21, 22)
tick()
arrived(11)
arrived(12)
arrived(21)
tick()
reply(a, "arrival", "validate_start", valid(11, 12))
local args = reply(a, "start", "start_autonomous_scene", {accepted = true})
assert(args.background and args.furniture_id == "411" and args.initiator == "11")
observers.event(snapshot(a, "session-a", 11, 12, "playing", "session_started"))

actors[31]:move(point(2450))
now = now + 1
tick()
assert(#canceled == 1 and canceled[1].who == 22,
    "An intrusion cancels the still-pending walk only, leaving the independent scene running")

actors[31]:move(point(300))
actors[21]:move(point(300))
local success, retry = invite.beginNpc(21, 22, {point(3320)})
assert(success, "Intrusion releases the participants and room")
preflight(retry, 21, 22, rows)
-- The occupied first room is filtered. Fall back after the second room fails content preflight.
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
reply(retry, "start", "start_autonomous_scene", {accepted = true})
observers.event(snapshot(retry, "session-b", 21, 22, "playing", "session_started"))

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
assert(#queued == 4 and not wire["encounter." .. nonce .. ".arrival"], "Recheck privacy before returning")

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

emit("NPC invitation checks passed: concurrent sessions, privacy, venue fallback, and one-time return after native overlap.")
