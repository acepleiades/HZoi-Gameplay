local VenuePath = require("VenuePath")

local function point(x, y, z)
    return {X = x, Y = y, Z = z}
end

UE = {FVector = point}
inzoi = {FB1NavigationQueryParams = function() return {} end}

local actorOrigin = point(10, 20, 105)
local actorId = {Value = 42}
local floorOrigin = point(10, 20, 15)
local pathOK, permissionDenied = point(350, 100, 15), point(450, 100, 15)

local function fixture(options)
    local projected = options.projected or point(58, 68, 25)
    local calls = {paths = {}, projections = 0}
    local person = {
        GetEntityId = function() return actorId end,
        GetLocation = function() return actorOrigin end,
        GetHalfHeight = function() return 90 end,
    }
    local floor = {IsOnWalkableGrid = function(_, origin)
        if origin == projected then return options.unwalkableProjection ~= true end
        assert(origin.X == floorOrigin.X and origin.Y == floorOrigin.Y and origin.Z == floorOrigin.Z)
        return options.walkableOrigin == true
    end}
    local site = {
        GetEntityId = function() return 809 end,
        IsIn = function(_, origin) return origin ~= projected or options.outside ~= true end,
        IsSameRoom = function(_, origin, candidate)
            assert(origin.Z == floorOrigin.Z and candidate == projected)
            return options.crossesWall ~= true
        end,
        IsExistInternalPath = function(_, origin, destination, params)
            assert(params.EntityId == actorId and params.bIgnorePermission == false)
            calls.paths[#calls.paths + 1] = origin
            if origin == actorOrigin then
                if options.rawPathError then error("No native route query") end
                return options.rawRoute == true and destination == pathOK
            end
            assert(origin == projected)
            return destination == pathOK
        end,
    }
    local sites = {}
    if not options.missingProjection then
        function sites:GetSiteNearGridLocation(siteId, seed, output, priority, checkWall)
            assert(siteId == 809 and priority == seed and checkWall == true)
            assert(seed.X == floorOrigin.X and seed.Y == floorOrigin.Y and seed.Z == floorOrigin.Z)
            assert(output.X == 0 and output.Y == 0 and output.Z == 0)
            calls.projections = calls.projections + 1
            if options.failedProjection then return false end
            return true, projected
        end
    end
    return VenuePath.query(site, sites, floor, person), calls
end

local rawQuery, rawCalls = fixture({rawRoute = true, missingProjection = true})
assert(rawQuery(pathOK) and #rawCalls.paths == 1 and rawCalls.projections == 0,
    "Prefer a valid raw path even if no projection is available")

local query, calls = fixture({})
assert(query(pathOK) and #calls.paths == 2 and calls.paths[1] == actorOrigin and calls.projections == 1,
    "Recover an off-grid origin through a nearby native grid point")
assert(not query(permissionDenied) and #calls.paths == 4 and calls.projections == 1,
    "Each destination still passes the permission-respecting path test with the cached origin")

for _, options in ipairs({{walkableOrigin = true}, {missingProjection = true}, {rawPathError = true}}) do
    local unavailable, reads = fixture(options)
    assert(not unavailable(pathOK) and reads.projections == 0 and #reads.paths == 1,
        "A blocked on-grid path or unavailable API does not authorize a projection")
end

for _, options in ipairs({{failedProjection = true}, {crossesWall = true}, {outside = true},
    {unwalkableProjection = true}, {projected = point(70, 80, 15)}, {projected = point(10, 20, 51)},
    {projected = point(10, 20, -21)}, {projected = point(10, 20, 0 / 0)}}) do
    local rejected, reads = fixture(options)
    assert(not rejected(pathOK) and not rejected(pathOK) and reads.projections == 1 and #reads.paths == 2,
        "Invalid projections are rejected once and never passed to the native route query")
end

local missing = VenuePath.query(nil, nil, nil, nil)
assert(not missing(pathOK))
print("Venue path passed: raw route priority, bounded same-room recovery, blocked routes, permission checks and safe fallback.")
