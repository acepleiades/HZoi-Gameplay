-- Run with B2 Lua and this file's adjacent module on package.path.
local Approach = require("VenueApproach")

local function point(x, y, z)
    return {X = x, Y = y, Z = z}
end
UE = {FVector = point}

local inside = function() return true end
local room = function() return true end
local walkable = function() return true end
local reachable = function() return true end
local calls = {paths = 0}
local id = {Value = 22}
local actorLocation = point(100, 100, 90)
local actor = {
    GetEntityId = function() return id end,
    GetLocation = function() return actorLocation end,
    GetHalfHeight = function() return 90 end,
}
local site = {
    IsIn = function(_, target) return inside(target) end,
    IsSameRoom = function(_, first, second) return room(first, second) end,
    IsExistInternalPath = function(_, origin, target, query)
        assert(origin == actorLocation and query.EntityId == id and query.bIgnorePermission == false)
        calls.paths = calls.paths + 1
        return reachable(target)
    end,
}
local floor = {IsOnWalkableGrid = function(_, target) return walkable(target) end}
local sites = {FindClosestSite = function() return site end}
inzoi = {
    getB2Manager = function(name)
        assert(name == "FB2SiteManager")
        return sites
    end,
    FB1NavigationQueryParams = function() return {} end,
}

local bed = {GetLocation = function() return point(40, 0, 0) end}
local original, partner = point(150, 0, 0), point(0, 0, 0)
for _, kind in ipairs({"bed.queen", "bed.single"}) do
    local alternate = Approach.retryPoint(original, partner, partner, bed, floor, actor, kind)
    assert(alternate.X == 260 and alternate.Y == 0 and alternate.Z == 0, "Keep the tested bed alternatives")
end

inside = function(target) return target.X < 250 end
local alternate = Approach.retryPoint(original, partner, partner, bed, floor, actor, "bed.single")
assert(alternate ~= original and alternate.X < 250, "Skip a nearby spot outside the site's boundary")
inside = function() return true end

room = function(first, second) return (first.X < 250) == (second.X < 250) end
alternate = Approach.retryPoint(original, partner, partner, bed, floor, actor, "bed.queen")
assert(alternate ~= original and alternate.X < 250, "Skip a nearby spot across the venue's wall")
room = function() return true end

walkable = function(target) return target.X ~= 205 end
alternate = Approach.retryPoint(original, partner, partner, bed, floor, actor, "bed.queen")
assert(alternate ~= original and alternate.X ~= 260, "Both the alternate and its midpoint must be walkable")
walkable = function() return true end

reachable = function(target) return target.X < 240 end
alternate = Approach.retryPoint(original, partner, partner, bed, floor, actor, "bed.queen")
assert(alternate ~= original and alternate.X < 240 and calls.paths > 0,
    "Skip an alternate that the selected Zoi cannot reach with normal permissions")
reachable = function() return false end
assert(Approach.retryPoint(original, partner, partner, bed, floor, actor, "bed.queen") == original,
    "Keep the original target when no safe alternative is reachable")
reachable = function() return true end

local sofaApproach, sofaPartner = point(1000, 1000, 0), point(1100, 1000, 0)
for _, kind in ipairs({"sofa.pair", "test.future_venue"}) do
    alternate = Approach.retryPoint(sofaApproach, sofaPartner, sofaPartner, {}, floor, actor, kind)
    assert(alternate.X == 890 and alternate.Y == 1000,
        "Stay near the chosen approach without requiring a venue-specific recovery rule")
end

local groundAnchor, anotherVector = point(0, 0, 0), point(0, 0, 0)
local companion = point(200, 0, 0)
assert(Approach.retryPoint(anotherVector, companion, companion, nil, floor, actor, "ground", groundAnchor)
    == anotherVector, "Keep the designated anchor exactly at the clicked ground point")
alternate = Approach.retryPoint(companion, groundAnchor, groundAnchor, nil, floor, actor, "ground", groundAnchor)
local radius = math.sqrt(alternate.X^2 + alternate.Y^2)
assert(alternate ~= companion and radius >= 150 and radius <= 250 and alternate.Z == 0,
    "Find a separate companion point near the selected ground point")

local conversationPartner = {GetLocation = function() return point(65, 100, 90) end}
local reposition = Approach.conversationPoint(actor, conversationPartner, floor)
assert(reposition and reposition.X == 240 and reposition.Y == 100 and reposition.Z == 0,
    "Make a short same-floor move away from a close partner")

room = function(first, second) return (first.X < 220) == (second.X < 220) end
reposition = Approach.conversationPoint(actor, conversationPartner, floor)
assert(reposition and reposition.X < 220 and reposition.Z == 0,
    "Skip a conversation reposition that would cross into a different room")
room = function() return true end

reachable = function() return false end
assert(not Approach.conversationPoint(actor, conversationPartner, floor),
    "Keep the ordinary native invitation retry without a permission-checked local path")
reachable = function() return true end

walkable = function(target) return target == actorLocation end
assert(not Approach.conversationPoint(actor, conversationPartner, floor),
    "Skip conversation reposition when the floor grid cannot support the move")

print("Venue and invitation retry approaches passed: fixed anchor and seat pair, walkable grid, room and permission checks.")
