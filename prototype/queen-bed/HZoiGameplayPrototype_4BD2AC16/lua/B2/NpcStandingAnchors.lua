local M = {}

local GRID_STEP = 200
local GRID_RINGS = 5
local MAX_SEEDS = 160
local MAX_PROJECTIONS = 36
local MAX_POINTS = 12
local MAX_POINTS_PER_ROOM = 3
local HORIZONTAL_TOLERANCE = 65
local VERTICAL_TOLERANCE = 35
local ROOM_PROBE_STEP = 80
local directions = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

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

local function interiorScore(site, room, point)
    local score = 0
    for _, direction in ipairs(directions) do
        for step = 1, 2 do
            local probe = UE.FVector(point.X + direction[1] * step * ROOM_PROBE_STEP,
                point.Y + direction[2] * step * ROOM_PROBE_STEP, point.Z)
            if site:IsSameRoom(room, probe) ~= true then break end
            score = score + 1
        end
    end
    return score
end

local function orderRoomSeeds(site, room)
    local x, y = 0, 0
    for _, point in ipairs(room.seeds) do x, y = x + point.X, y + point.Y end
    x, y = x / #room.seeds, y / #room.seeds
    local center = UE.FVector(x, y, room.reference.Z)
    if site:IsSameRoom(room.reference, center) == true then
        room.seeds[#room.seeds + 1] = center
    end
    local options = {}
    for index, point in ipairs(room.seeds) do
        options[index] = {point = point, interior = interiorScore(site, room.reference, point),
            distance = (point.X - x)^2 + (point.Y - y)^2, index = index}
    end
    table.sort(options, function(a, b)
        if a.interior ~= b.interior then return a.interior > b.interior end
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.index < b.index
    end)
    return options
end

-- Discover rooms before projecting their best interior spots. NpcVenue
-- checks vacancy, access, and the separate arrival paths for both Zois.
function M.find(site, initiator, partner, isAllowedRoom, canUse)
    local floor = inzoi.getB2Subsystem("FB2PathFindSystem")
    local sites = inzoi.getB2Manager("FB2SiteManager")
    if not floor or not sites or type(sites.GetSiteNearGridLocation) ~= "function" then
        return {}, "projection_unavailable"
    end
    if not site or site:IsFakeSite() ~= false then
        return {}, "site_unavailable"
    end

    local rooms, tested = {}, {}
    local first, second = floorOrigin(initiator), floorOrigin(partner)
    if not first or not second then return {}, "floor_origin_unavailable" end
    local siteId = site:GetEntityId()
    local origins = {first, second}
    local seeds = 0
    local function sample(origin, dx, dy)
        if seeds >= MAX_SEEDS then return end
        local seed = UE.FVector(origin.X + dx * GRID_STEP, origin.Y + dy * GRID_STEP, origin.Z)
        local index = key(seed, GRID_STEP / 2)
        if tested[index] then return end
        tested[index] = true
        seeds = seeds + 1

        if site:IsIn(seed) ~= true or sites:IsIndoor(seed) ~= true or site:IsSameRoom(seed, seed) ~= true then return end
        if isAllowedRoom and not isAllowedRoom(seed) then return end
        for _, room in ipairs(rooms) do
            if site:IsSameRoom(room.reference, seed) == true then
                room.seeds[#room.seeds + 1] = seed
                return
            end
        end
        rooms[#rooms + 1] = {reference = seed, seeds = {seed}, accepted = 0}
    end

    for ring = 0, GRID_RINGS do
        for dx = -ring, ring do
            for dy = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring then
                    for _, origin in ipairs(origins) do
                        sample(origin, dx, dy)
                    end
                end
            end
        end
    end
    for _, room in ipairs(rooms) do room.options = orderRoomSeeds(site, room) end

    local points, accepted, preferences = {}, {}, {}
    local projections, index = 0, 1
    -- Give each discovered room a projection before spending the budget on
    -- alternatives in a single room with blocked floor space.
    while projections < MAX_PROJECTIONS and #points < MAX_POINTS do
        local pending = false
        for _, room in ipairs(rooms) do
            local option = room.options[index]
            if option and room.accepted < MAX_POINTS_PER_ROOM then
                pending = true
                local seed = option.point
                projections = projections + 1
                local point = projectedPoint(sites, siteId, seed)
                if point and site:IsIn(point) == true and site:IsSameRoom(room.reference, point) == true
                    and sites:IsIndoor(point) == true and floor:IsOnWalkableGrid(point) == true then
                    local spot = key(point, 50)
                    if not accepted[spot] and (not canUse or canUse(point)) then
                        accepted[spot] = true
                        room.accepted = room.accepted + 1
                        points[#points + 1] = point
                        preferences[point] = {room = room.reference, order = room.accepted}
                    end
                end
                if projections >= MAX_PROJECTIONS or #points >= MAX_POINTS then break end
            end
        end
        if not pending then break end
        index = index + 1
    end
    return points, nil, preferences
end

return M
