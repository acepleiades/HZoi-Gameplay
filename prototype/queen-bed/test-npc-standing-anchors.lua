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
local floor = {
    IsOnWalkableGrid = function(_, p) return mode ~= "blocked" and p.Z % 300 == 0 end,
}
local sites = {
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

local function policy(_, p)
    readCount = readCount + 1
    local room = roomAt(p)
    return (room == "bedroom" or room == "private") and room or nil
end

local a, b = actor(0, 0, 90.15, 90), actor(0, 0, 395.15, 95)
local points = Anchors.find(site, a, b, policy)
assert(#points == 12, "Three samples per private room on either source floor")
assert(callCount <= 36 and readCount <= 196)
local same, different = false, false
for _, projected in ipairs(points) do
    assert(policy(site, projected) and projected.Z % 300 == 0)
    same = same or projected.Z == 0
    different = different or projected.Z == 300
end
assert(same and different, "Use actual projection on both candidate floors")

for _, invalid in ipairs({"mutated", "unknown", "non_finite", "upper", "lower", "outside", "blocked"}) do
    mode = invalid
    callCount = 0
    assert(#Anchors.find(site, a, b, policy) == 0, invalid)
    assert(callCount <= 36)
end
mode, callCount, readCount = "unknown", 0, 0
Anchors.find(site, a, b, function() readCount = readCount + 1; return "private" end)
assert(callCount == 36 and readCount <= 160, "Bound the scan even where every projection fails")
local none = Anchors.find(site, a, b, function() return nil end)
assert(#none == 0 and callCount == 36, "Skip projection for unmarked rooms")
mode = "across_wall"
-- A valid point projected 50 cm past a wall is still a different room.
local onlyBoundary = Anchors.find(site, actor(750, 0, 90.15, 90), actor(750, 0, 90.15, 90), function(_, p)
    if p.X == 750 or p.X == 800 then return "private" end
end)
assert(#onlyBoundary == 0)
siteType, callCount = 2, 0
local none, status = Anchors.find(site, a, b, policy)
assert(#none == 0 and status == "site_unavailable" and callCount == 0)
siteType, mode = 1, "ok"
local none, status = Anchors.find(site, actor(0, 0, 0), b, policy)
assert(#none == 0 and status == "floor_origin_unavailable")
sites = {}
local none, status = Anchors.find(site, a, b, policy)
assert(#none == 0 and status == "projection_unavailable")
print("Standing anchors pass bounded scanning, native out-value handling, marked-room gating, and stacked floor rejection.")
