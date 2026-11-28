local M = {}
local MAX_HORIZONTAL_CM = 75
local MAX_VERTICAL_CM = 35

local function finite(value)
    return type(value) == "number" and math.abs(value) < math.huge
end

local function nearbyGridOrigin(site, sites, floor, person, origin)
    local halfHeight = person:GetHalfHeight()
    if not finite(halfHeight) or halfHeight <= 0 or not (finite(origin.X) and finite(origin.Y) and finite(origin.Z)) then return end
    local foot = UE.FVector(origin.X, origin.Y, origin.Z - halfHeight)
    if floor:IsOnWalkableGrid(foot) ~= false or site:IsIn(foot) ~= true then return end

    -- The Lua binding returns the projected location as its second result.
    local found, point = sites:GetSiteNearGridLocation(site:GetEntityId(), foot, UE.FVector(0, 0, 0), foot, true)
    if found ~= true or not point or not (finite(point.X) and finite(point.Y) and finite(point.Z)) then return end
    local planarDistanceSq = (point.X - foot.X)^2 + (point.Y - foot.Y)^2
    if planarDistanceSq > MAX_HORIZONTAL_CM^2 or math.abs(point.Z - foot.Z) > MAX_VERTICAL_CM
        or site:IsIn(point) ~= true or site:IsSameRoom(foot, point) ~= true
        or floor:IsOnWalkableGrid(point) ~= true then return end
    return point
end

-- A native route can reject the raw origin beside furniture. Try a nearby
-- grid origin only when the feet are off-grid. The native route still checks
-- the Zoi's access permissions for every destination.
function M.query(site, sites, floor, person)
    local ready, origin, params = pcall(function()
        local entityId = person:GetEntityId()
        if not entityId then return end
        local query = inzoi.FB1NavigationQueryParams()
        query.EntityId = entityId
        query.bIgnorePermission = false
        return person:GetLocation(), query
    end)
    local projected, checkedProjection
    local sourceInSite = origin and site and site:IsIn(origin) == true
    local function pathFrom(source, destination)
        if sourceInSite then return site:IsExistInternalPath(source, destination, params) end
        return sites:QuerySiteAreaPath(inzoi.FB1NavigationPath(), source, destination, params)
    end
    return function(destination)
        if not (ready and origin and destination) then return false end
        local ok, reachable = pcall(pathFrom, origin, destination)
        if not ok or reachable ~= false then return ok and reachable == true end
        if not checkedProjection then
            checkedProjection = true
            local mapped, point = pcall(function()
                local sourceSite = sourceInSite and site or sites:FindClosestSite(origin, false)
                if sourceSite and (sourceInSite or sourceSite:IsFakeSite() == false) then
                    return nearbyGridOrigin(sourceSite, sites, floor, person, origin)
                end
            end)
            if mapped then projected = point end
        end
        if not projected then return false end
        local routed, canReach = pcall(pathFrom, projected, destination)
        return routed and canReach == true
    end
end

return M
