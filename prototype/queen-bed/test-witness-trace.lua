-- Run from prototype/queen-bed with the SceneZOI SDK on the Lua module search path.
package.path = "HZoiGameplayPrototype_4BD2AC16/lua/B1/?.lua;" .. package.path
local Json = require("SceneZOIAddon.Json")
package.loaded.Localization = {culture = function() return "fr-fr" end}
local TraceBridge = require("WitnessTraceBridge")

local function vec(x, y, z) return {X = x, Y = y or 0, Z = z or 0} end
local function actor(id, x, participant)
    local mesh = {
        GetBoneIndex = function() return 1 end,
        GetSocketTransform = function() return {Translation = vec(x)} end,
    }
    local head = {
        GetName = function() return "Head" end,
        GetBoneIndex = function() return 1 end,
        GetSocketTransform = function() return {Translation = vec(x)} end,
    }
    return {
        id = id,
        Mesh = participant and mesh or nil,
        K2_GetActorLocation = function() return vec(x) end,
        K2_GetComponentsByClass = function() return {head} end,
    }
end
local characters = {
    [1] = actor("1", 0, true), [2] = actor("2", 30, true), [3] = actor("3", 2000, true),
    [4] = actor("4", 2020), [5] = actor("5", 3000),
}
local traced, replies, participantCount, replySize = {}, {}, 3, 0
UE = {
    FVector = vec, FHitResult = function() return {} end,
    USkeletalMeshComponent = {StaticClass = function() return true end},
    ECollisionChannel = {ECC_Visibility = 7},
}
inzoi = {
    EB1ManagerType = {Entity = "entity"},
    UB1System = {Get = function()
        return {ManagerMap = {Find = function()
            return {CharacterMap = {ToTable = function() return characters end}}
        end}}
    end},
    UB1FunctionLibrary = {B1LineTraceSingle = function(_, witness, _, target, _, ignored, channel)
        assert(witness == ignored[1] and #ignored == participantCount + 1 and channel == 7)
        traced[#traced + 1] = witness.id
        return target.X == 30
    end},
    message = {send_to_sim = function(id, kind, content)
        assert(id == "owner" and kind == "HZoiGameplay.WitnessResult")
        replySize = #content
        replies[#replies + 1] = Json.decode(content)
    end},
}
local owner = {GetEntityId = function() return "owner" end}
local function request(ids, extra)
    local message = {token = "session.1", revision = 2, participants = ids}
    for key, value in pairs(extra or {}) do message[key] = value end
    TraceBridge.reply(owner, Json.encode(message))
end

request({"1", "2", "3"})
assert(#replies == 1 and #traced == 3, "Only the witness near the third participant should be traced")
for _, id in ipairs(traced) do assert(id == "4") end
local reply = replies[1]
assert(reply.token == "session.1" and reply.revision == 2 and reply.language == "fr-fr")
assert(#reply.observations == 1)
local witness = reply.observations[1]
assert(witness.id == "4" and witness.visible["1"] and witness.visible["3"] and not witness.visible["2"])

local wholeRoster = {}
characters = {}
for id = 1, 33 do
    wholeRoster[id] = tostring(id)
    characters[id] = actor(wholeRoster[id], id, true)
end
request({"1"})
request({"1", "2", "1"})
request({"1", "01"})
request({"1", "a"})
request({"1", "111111111111111111111"})
request(wholeRoster)
assert(#replies == 1, "Invalid requests must not invoke the native witness trace")

wholeRoster[33] = nil
characters[33] = actor("33", 40)
participantCount = 32
request(wholeRoster)
assert(#replies == 2 and #replies[2].observations == 1)
assert(replies[2].observations[1].visible["32"], "Support the largest SceneZOI roster")

participantCount = 2
characters = {[1] = actor("1", 0, true), [2] = actor("2", 30, true), [4] = actor("4", 50)}
request({"1", "2"})
assert(#replies == 3 and replies[3].observations[1].visible["1"] and not replies[3].observations[1].visible["2"])
characters, wholeRoster, participantCount = {}, {}, 32
for index = 1, 57 do
    local id = "123456789012345678" .. ("%02d"):format(index)
    characters[{Value = id}] = actor(id, 100 + index, index <= participantCount)
    if index <= participantCount then wholeRoster[index] = id end
end
request(wholeRoster)
assert(#replies == 4 and #replies[4].observations == 24, "Keep the nearby witness cap")
assert(replySize > 8192 and replySize <= 32768, "A full trace must fit the B2 decoder budget")
local fullReplySize = replySize
local points = {["1"] = {x = 30, y = 0, z = -100}, ["2"] = {x = 30, y = 10, z = -100}}
participantCount = 2
characters = {[1] = actor("1", 2, true), [2] = actor("2", 10, true), [4] = actor("4", 50)}
request({"1", "2"}, {kind = "arrival", points = points})
assert(replies[5].kind == "arrival" and replies[5].token == "session.1"
    and #replies[5].observations == 0, "Trace to the exact prepared X/Y, and stop at blocking geometry")
points["1"].x = 20
for id = 5, 32 do characters[id] = actor(tostring(id), 55 + id) end
request({"1", "2"}, {kind = "arrival", points = points})
assert(#replies[6].observations == 29, "Do not drop arrival observers at the playback limit")
characters[33] = actor("33", 70)
characters[33].K2_GetComponentsByClass = function() return {} end
request({"1", "2"}, {kind = "arrival", points = points})
assert(replies[7].diagnostic == "observer_view_unavailable", "Unresolved viewpoint cannot prove privacy")
request({"1", "2"}, {kind = "arrival", points = {}})
assert(#replies == 7, "Reject a malformed arrival point before native calls")

request({"1", "2"}, {baseline = {"32", "33", "34"}})
local baselineAbsent = replies[8].baseline_absent
assert(#baselineAbsent == 1 and baselineAbsent[1] == "34",
    "Track continuity even over the playback limit, without clearing an unknown eye position")
characters[32] = actor("32", 6000)
request({"1", "2"}, {baseline = {"32", "33", "34"}})
baselineAbsent = replies[9].baseline_absent
assert(#baselineAbsent == 2 and baselineAbsent[1] == "32" and baselineAbsent[2] == "34")

print(("Witness trace bridge: bounded rosters, nearest participant, blocked trace, correlation, pairs and %d-byte full response passed."):format(fullReplySize))
