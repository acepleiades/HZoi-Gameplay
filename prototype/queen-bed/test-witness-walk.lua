local Native = require("WitnessNative")

local queued, speech = {}, {}
local busy, occupiedFloor = false, false
local step
local function vector(x, y, z) return {X = x, Y = y, Z = z} end
UE = {FVector = vector}
local nativeWalk = {
    IsQueueEmpty = function() return not busy end,
    IsPlayingInteraction = function() return busy end,
    AddInteractionQueueByParam = function(_, actor, point, bag, reason)
        assert(actor.Value == -1 and bag == "HZoiGameplay_WitnessWalk" and reason == "reaction")
        queued[#queued + 1] = point
        return 37
    end,
}
local possessed = {Value = 10}
local witnessId = {Value = 20}
local nearId = {Value = 30}
local witness = {
    GetEntityId = function() return witnessId end,
    GetGrowthStep = function() return step end,
    GetComponent = function() return nativeWalk end,
    GetLocation = function() return vector(250, 0, 15) end,
}
local near = {
    GetEntityId = function() return nearId end,
    GetLocation = function() return vector(0, 0, 15) end,
}
local grid = {IsOnWalkableGrid = function(_, spot) return not occupiedFloor and spot.X > 250 and spot.Z == 15 end}
local site = {
    GetSiteId = function() return "some-site" end,
    CheckReachablePoint = function() return true end,
    IsExistInternalPath = function(_, _, point, params)
        assert(point.Z == 15 and params.EntityId == witnessId and not params.bIgnorePermission)
        return true
    end,
}
inzoi = {
    EB1GrowthStep = {Child = 4, LowTeen = 8, HighTeen = 16},
    EB1ScriptReason = {Howling = "howling"},
    EB1BaseObject = {Self = "self"},
    EB1ExecuteType = {AddSpeechBubble = "speech"},
    EB2ComponentType = {Interaction = "interaction"},
    EB1InteractionPlayReason = {Reaction = "reaction"},
    FB2ControllerSystem = {GetPossessEntityId = function() return possessed end},
    FB1Execute = function() return {} end,
    FB2ScriptContext = function(speaker, target) return {speaker = speaker, target = target} end,
    FB2Script_SpeechBubble = {Execute_AddSpeechBubble = function(ctx, command)
        assert(ctx.speaker == witnessId and ctx.target == nearId and command.Command == "speech")
        speech[#speech + 1] = command.S1
    end},
    FB1NavigationQueryParams = function() return {} end,
    FB1EntityId = function() return {Value = -1} end,
    getB2Manager = function() return {
        FindClosestSite = function() return site end,
        IsLocatedInSite = function() return true end,
    } end,
    getB2Subsystem = function() return grid end,
}
for _, age in ipairs({4, 8, 16}) do
    step = age
    local bubble = Native.sayAsWitness(witness, near, "Uncomfortable")
    assert((bubble ~= nil) == (age == 16))
    assert(Native.walkAway(witness, near) == 37)
end
assert(#speech == 1 and #queued == 3, "Speech age and ability to walk are independent")
busy = true
assert(not Native.walkAway(witness, near))
busy, occupiedFloor = false, true
assert(not Native.walkAway(witness, near))
occupiedFloor, possessed = false, witnessId
assert(not Native.walkAway(witness, near) and #queued == 3)
print("Witness walk-away preserved eligible ages, speech timing, busy and controlled actions.")
