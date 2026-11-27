local M = {}

local GRID_STEP = 200
local GRID_RINGS = 5
local MAX_SEEDS = 160
local MAX_PROJECTIONS = 36
local MAX_POINTS = 12
local MAX_POINTS_PER_ROOM = 3
local HORIZONTAL_TOLERANCE = 65
local VERTICAL_TOLERANCE = 35

local function finite(number)
    return type(number) == "number" and math.abs(number) < math.huge
end

local function coordinates(value)
    local kind = type(value)
    if kind ~= "table" and kind ~= "userdata" then return end
    if finite(value.X) and finite(value.Y) and finite(value.Z) then return value.X, value.Y, value.Z end
end

local function floorOrigin(actor)
    local center = actor:GetLocation()
    local halfHeight = actor:GetHalfHeight()
    local x, y, z = coordinates(center)
    if not x or not finite(halfHeight) or halfHeight <= 0 then return end
    return UE.FVector(x, y, z - halfHeight)
end

local function projectedPoint(sites, siteId, seed)
    -- The native site grid returns its out parameter as the second value.
    local output = UE.FVector(0, 0, 0)
    local ok, found, projected = pcall(sites.GetSiteNearGridLocation, sites, siteId, seed, output, seed, true)
    if not ok or found ~= true then return end
    local x, y, z = coordinates(projected)
    if x == nil or math.abs(x - seed.X) > HORIZONTAL_TOLERANCE or math.abs(y - seed.Y) > HORIZONTAL_TOLERANCE
        or math.abs(z - seed.Z) > VERTICAL_TOLERANCE then return end
    return UE.FVector(x, y, z)
end

local function key(point, scale)
    return table.concat({
        math.floor(point.X / scale + .5),
        math.floor(point.Y / scale + .5),
        math.floor(point.Z / 75 + .5),
    }, ":")
end

local function roomHasSpace(site, points, position)
    local count = 0
    for _, point in ipairs(points) do
        if site:IsSameRoom(point, position) == true then
            count = count + 1
            if count >= MAX_POINTS_PER_ROOM then return false end
        end
    end
    return true
end

-- Find possible anchors inside actual rooms. NpcVenue checks vacancy,
-- access, and the separate arrival paths for both Zois.
function M.find(site, initiator, partner, isAllowedRoom)
    local floor = inzoi.getB2Subsystem("FB2PathFindSystem")
    local sites = inzoi.getB2Manager("FB2SiteManager")
    if not floor or not sites or type(sites.GetSiteNearGridLocation) ~= "function" then
        return {}, "projection_unavailable"
    end
    if not site or site:IsFakeSite() ~= false then
        return {}, "site_unavailable"
    end

    local points, tested, accepted = {}, {}, {}
    local first, second = floorOrigin(initiator), floorOrigin(partner)
    if not first or not second then return {}, "floor_origin_unavailable" end
    local siteId = site:GetEntityId()
    local origins = {first, second}
    local seeds, projections = 0, 0
    local function sample(origin, dx, dy)
        local seed = UE.FVector(origin.X + dx * GRID_STEP, origin.Y + dy * GRID_STEP, origin.Z)
        local index = key(seed, GRID_STEP / 2)
        if tested[index] then return end
        tested[index] = true
        seeds = seeds + 1

        if site:IsIn(seed) ~= true or sites:IsIndoor(seed) ~= true or site:IsSameRoom(seed, seed) ~= true then return end
        if isAllowedRoom and not isAllowedRoom(seed) then return end
        if not roomHasSpace(site, points, seed) then return end

        projections = projections + 1
        local point = projectedPoint(sites, siteId, seed)
        if not point or site:IsIn(point) ~= true or site:IsSameRoom(seed, point) ~= true
            or sites:IsIndoor(point) ~= true or floor:IsOnWalkableGrid(point) ~= true then return end
        local spot = key(point, 50)
        if not accepted[spot] then
            accepted[spot] = true
            points[#points + 1] = point
        end
    end

    for ring = 0, GRID_RINGS do
        for dx = -ring, ring do
            for dy = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring then
                    for _, origin in ipairs(origins) do
                        sample(origin, dx, dy)
                        if seeds >= MAX_SEEDS or projections >= MAX_PROJECTIONS or #points >= MAX_POINTS then
                            return points
                        end
                    end
                end
            end
        end
    end
    return points
end

return M
