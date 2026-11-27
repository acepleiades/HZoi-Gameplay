local VenuePath = require("VenuePath")
local FurnitureKind = require("VenueFurnitureKind")
local M = {}

local RETRY_OFFSET_CM = 110
local BED_RANGE_CM = 290
local GROUND_RANGE_CM = 250
local MIN_SEPARATION_CM = 150
local CONVERSATION_OFFSET_CM = 140
local CONVERSATION_MIN_SEPARATION_CM = 125
local CONVERSATION_RANGE_CM = 250
local alternatives = {0, .25, -.25, .5, -.5, .75, -.75}

local function horizontalSquared(a, b)
    return (a.X - b.X)^2 + (a.Y - b.Y)^2
end

local function venueCheck(reference, floor, person)
    local sites = inzoi.getB2Manager("FB2SiteManager")
    local site = sites and sites:FindClosestSite(reference, false)
    if not site or site:IsIn(reference) ~= true then return function() return true end end
    local indoor = site:IsSameRoom(reference, reference) == true
    local canReach
    if type(site.IsExistInternalPath) == "function" then
        canReach = VenuePath.query(site, sites, floor, person)
    end
    local function inVenue(point)
        return site:IsIn(point) == true and (not indoor or site:IsSameRoom(reference, point) == true)
    end
    return function(point, midpoint)
        return inVenue(point) and inVenue(midpoint) and (not canReach or canReach(point))
    end
end

-- Retry a native walk near the chosen approach, without changing the bed,
-- seat pair or clicked ground anchor. The ordinary walk still owns arrival.
function M.retryPoint(original, partnerPoint, partnerLocation, furniture, floor, person, kind, groundAnchor)
    if groundAnchor and horizontalSquared(original, groundAnchor) == 0 and original.Z == groundAnchor.Z then
        return original
    end
    local bed = furniture and FurnitureKind.isBed(kind)
    local center = bed and furniture:GetLocation() or groundAnchor
    local range = bed and BED_RANGE_CM or GROUND_RANGE_CM
    local validVenue = venueCheck(groundAnchor or original, floor, person)
    local angle = math.atan(original.Y - partnerPoint.Y, original.X - partnerPoint.X)
    for _, turn in ipairs(alternatives) do
        local yaw = angle + turn * math.pi
        local dx, dy = math.cos(yaw) * RETRY_OFFSET_CM, math.sin(yaw) * RETRY_OFFSET_CM
        local point = UE.FVector(original.X + dx, original.Y + dy, original.Z)
        local midpoint = UE.FVector(original.X + dx / 2, original.Y + dy / 2, original.Z)
        if (not center or horizontalSquared(point, center) + (point.Z - center.Z)^2 <= range^2)
            and horizontalSquared(point, partnerPoint) >= MIN_SEPARATION_CM^2
            and horizontalSquared(point, partnerLocation) >= MIN_SEPARATION_CM^2
            and floor:IsOnWalkableGrid(point) == true and floor:IsOnWalkableGrid(midpoint) == true
            and validVenue(point, midpoint) then
            return point
        end
    end
    return original
end

-- Change the failed walker's starting position before the native conversation
-- picks its positions again. Leave this to the native retry if no small,
-- permission-checked move in the same room and on the same floor is available.
function M.conversationPoint(person, partner, floor)
    local sites = inzoi.getB2Manager("FB2SiteManager")
    local location, other = person:GetLocation(), partner:GetLocation()
    local height = person:GetHalfHeight()
    if not (floor and sites and height and height > 0 and height < math.huge) then return end
    local origin = UE.FVector(location.X, location.Y, location.Z - height)
    local site = sites:FindClosestSite(origin, false)
    if not site or site:IsIn(origin) ~= true or site:IsSameRoom(origin, origin) ~= true
        or type(site.IsExistInternalPath) ~= "function" then return end

    local canReach = VenuePath.query(site, sites, floor, person)
    local separation = horizontalSquared(origin, other)
    local maxSeparation = math.max(CONVERSATION_RANGE_CM^2, separation)
    local angle = math.atan(origin.Y - other.Y, origin.X - other.X)
    if separation > CONVERSATION_RANGE_CM^2 then angle = angle + math.pi end
    for _, turn in ipairs(alternatives) do
        local yaw = angle + turn * math.pi
        local dx, dy = math.cos(yaw) * CONVERSATION_OFFSET_CM, math.sin(yaw) * CONVERSATION_OFFSET_CM
        local point = UE.FVector(origin.X + dx, origin.Y + dy, origin.Z)
        local distance = horizontalSquared(point, other)
        if distance >= CONVERSATION_MIN_SEPARATION_CM^2 and distance <= maxSeparation then
            local midpoint = UE.FVector(origin.X + dx / 2, origin.Y + dy / 2, origin.Z)
            if floor:IsOnWalkableGrid(point) == true and floor:IsOnWalkableGrid(midpoint) == true
                and site:IsSameRoom(origin, point) == true and site:IsSameRoom(origin, midpoint) == true
                and canReach(point) then
                return point
            end
        end
    end
end

return M
