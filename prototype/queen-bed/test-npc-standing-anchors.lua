local Anchors = require("NpcStandingAnchors")
local function point(x, y, z) return {X = x, Y = y, Z = z} end
local function actor(x, y, z, halfHeight)
    return {
        GetLocation = function() return point(x, y, z) end,
        GetHalfHeight = function() return halfHeight end,
    }
end
local siteType, callCount, readCount = 1, 0, 0
local function floorAt(p) return math.floor(p.Z / 300) end
local function roomAt(p)
    if p.X < 400 then return "living" end
    if p.X < 800 then return "bedroom" end
    if p.X < 1200 then return "private" end
    return "hall"
end
local site = {
    GetSiteType = function() return siteType end,
    GetEntityId = function() return 8123 end,
    IsPublicSite = function() return siteType ~= 1 end,
    IsFakeSite = function() return false end,
    IsIn = function(_, p) return p.X >= -2000 and p.X <= 1500 and math.abs(p.Y) <= 1100 end,
    IsSameRoom = function(_, first, second)
        return floorAt(first) == floorAt(second) and roomAt(first) == roomAt(second)
    end,
}
local mode = "ok"
local isIndoor = function() return true end
local floor = {
    IsOnWalkableGrid = function(_, p) return mode ~= "blocked" and p.Z % 300 == 0 end,
}
local sites = {
    IsIndoor = function(_, p) readCount = readCount + 1; return isIndoor(p) end,
    GetSiteNearGridLocation = function(_, siteId, seed, unusedOutput, priority, checkWall)
        callCount = callCount + 1
        assert(siteId == 8123 and unusedOutput.Z == 0 and priority == seed and checkWall == true)
        assert(math.abs(seed.Z - 300 * floorAt(seed)) < 1, "Use the measured capsule half height")
        if mode == "mutated" then
            unusedOutput.X, unusedOutput.Y, unusedOutput.Z = seed.X, seed.Y, 300 * floorAt(seed)
            return true
        end
        if mode == "unknown" then return false, point(0, 0, 0) end
        if mode == "non_finite" then return true, point(seed.X, seed.Y, 0 / 0) end
        if mode == "upper" then return true, point(seed.X, seed.Y, 300 * (floorAt(seed) + 1)) end
        if mode == "lower" then return true, point(seed.X, seed.Y, 300 * (floorAt(seed) - 1)) end
        if mode == "outside" then return true, point(seed.X + 300, seed.Y, 300 * floorAt(seed)) end
        if mode == "across_wall" then return true, point(seed.X + 50, seed.Y, 300 * floorAt(seed)) end
        return true, point(seed.X, seed.Y, 300 * floorAt(seed))
    end,
}
UE = {FVector = point}
inzoi = {
    EB1SiteType = {Residence = 1},
    getB2Subsystem = function() return floor end,
    getB2Manager = function() return sites end,
}

local a, b = actor(0, 0, 90.15, 90), actor(0, 0, 395.15, 95)
local points = Anchors.find(site, a, b)
assert(#points == 12, "Three samples per room on either source floor")
assert(callCount <= 36 and readCount <= 196)
local same, different = false, false
for _, projected in ipairs(points) do
    assert(site:IsIn(projected) and projected.Z % 300 == 0)
    same = same or projected.Z == 0
    different = different or projected.Z == 300
end
assert(same and different, "Use actual projection on both candidate floors")

for _, invalid in ipairs({"mutated", "unknown", "non_finite", "upper", "lower", "outside", "blocked"}) do
    mode = invalid
    callCount = 0
    assert(#Anchors.find(site, a, b) == 0, invalid)
    assert(callCount <= 36)
end
mode, callCount, readCount = "unknown", 0, 0
Anchors.find(site, a, b)
assert(callCount == 36 and readCount <= 160, "Bound the scan even where every projection fails")
isIndoor = function() return false end
local none = Anchors.find(site, a, b)
assert(#none == 0 and callCount == 36, "Skip projections outdoors")
mode = "across_wall"
-- A valid point projected 50 cm past a wall is still a different room.
isIndoor = function(p) return p.X == 750 or p.X == 800 end
local onlyBoundary = Anchors.find(site, actor(750, 0, 90.15, 90), actor(750, 0, 90.15, 90))
assert(#onlyBoundary == 0)
siteType, callCount = 2, 0
local none, status = Anchors.find(site, a, b, function() return false end)
assert(#none == 0 and callCount == 0)
mode, isIndoor = "ok", function() return true end
local rented = Anchors.find(site, actor(900, 0, 90.15, 90), actor(1510, 0, 90.15, 90),
    function(seed) return roomAt(seed) == "private" end)
assert(#rented > 0, "A partner just across the lot line can consider the booked room")
for _, point in ipairs(rented) do assert(roomAt(point) == "private") end
siteType, mode = 1, "ok"
local none, status = Anchors.find(site, actor(0, 0, 0), b)
assert(#none == 0 and status == "floor_origin_unavailable")
sites = {}
local none, status = Anchors.find(site, a, b)
assert(#none == 0 and status == "projection_unavailable")

-- Start at the doorway of an L-shaped room. The doorway is walkable,
-- the inner corner is furnished and the wider arm offers a better anchor.
roomAt = function(p)
    if p.Y < 0 or p.Y >= 600 or p.X < -200 or p.X >= 800 then return end
    if p.X < 0 then return "hall" end
    if p.X >= 400 or p.Y < 200 then return "living" end
end
site.IsSameRoom = function(_, a, b)
    return roomAt(a) ~= nil and roomAt(a) == roomAt(b) and floorAt(a) == floorAt(b)
end
floor.IsOnWalkableGrid = function(_, p)
    return roomAt(p) ~= nil and not (p.X >= 390 and p.X < 550 and p.Y >= 180 and p.Y < 350)
end
sites.GetSiteNearGridLocation = function(_, _, p) return true, p end
sites.IsIndoor = function(_, p) return roomAt(p) ~= nil end
local inset, _, preferences = Anchors.find(site, actor(20, 100, 90, 90), actor(-20, 100, 90, 90))
local living, hall
for _, p in ipairs(inset) do
    if roomAt(p) == "living" then living = living or p else hall = hall or p end
end
assert(living and living.X >= 550 and living.Y >= 180 and living.Y < 500,
    "A walkable doorway and a furnished center should favor the open arm")
assert(preferences[living].order == 1 and hall and preferences[living].room ~= preferences[hall].room)
assert(floor:IsOnWalkableGrid(living))

local rejected = 0
local remaining = Anchors.find(site, actor(20, 100, 90, 90), actor(-20, 100, 90, 90), nil,
    function(p)
        if roomAt(p) == "living" and p.X >= 200 then rejected = rejected + 1 end
        return roomAt(p) == "living" and p.X < 200
    end)
assert(rejected >= 3 and #remaining > 0 and remaining[1].X < 200,
    "An anchor that fits both arrival routes must survive multiple unusable center candidates")

roomAt = function(p)
    return p.X >= 0 and p.X < 180 and p.Y >= 0 and p.Y < 260 and "narrow" or nil
end
local narrow = Anchors.find(site, actor(40, 40, 90, 90), actor(40, 40, 90, 90))
assert(#narrow > 0, "A small room can still supply a valid anchor")
print("Standing anchors pass bounded scanning, native out-value handling, indoor checks, and stacked floor rejection.")
