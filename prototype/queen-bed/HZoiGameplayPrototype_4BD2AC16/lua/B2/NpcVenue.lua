local Planner = require("NpcVenuePlanner")
local M = {}
local claims = {}
local privatePurposes = {
    HZoiGameplay_PrivateBedroom = "bedroom",
    HZoiGameplay_PrivateStudy = "private",
}

local function distanceSquared(first, second)
    return (first.X - second.X)^2 + (first.Y - second.Y)^2 + (first.Z - second.Z)^2
end

local function scope(initiator, partner)
    local entityManager = inzoi.getB2Manager("FB2EntityManager")
    local siteManager = inzoi.getB2Manager("FB2SiteManager")
    local pathFinder = inzoi.getB2Subsystem("FB2PathFindSystem")
    if not entityManager or not siteManager or not pathFinder then return end
    local firstPosition, secondPosition = initiator:GetLocation(), partner:GetLocation()
    local site = siteManager:FindClosestSite(firstPosition, false)
    if not site or site:GetSiteType() ~= inzoi.EB1SiteType.Residence or site:IsPublicSite() ~= false
        or site:IsFakeSite() ~= false or site:IsIn(firstPosition) ~= true or site:IsIn(secondPosition) ~= true then
        return
    end

    local siteId = tostring(site:GetSiteId())
    if siteId == "" or siteId == "None" then return end
    local firstId, secondId = initiator:GetEntityId().Value, partner:GetEntityId().Value
    local occupants = {}
    for _, entity in pairs(entityManager:GetAllEntities(inzoi.EB2EntityType.Character)) do
        local entityId = entity:GetEntityId()
        if entityId.Value ~= firstId and entityId.Value ~= secondId and entity:IsSpawned() then
            local character = entityManager:FindCharacter(entityId)
            -- Without a location, vacancy cannot be confirmed.
            if not character then return end
            local location = character:GetLocation()
            if site:IsIn(location) then occupants[#occupants + 1] = location end
        end
    end
    return {
        manager = entityManager, sites = siteManager, floor = pathFinder, site = site,
        site_id = siteId, participants = {initiator, partner}, occupants = occupants,
    }
end

function M.roomClass(site, point)
    local purpose = site:GetRoomPurposeIdByLocation(point)
    return privatePurposes[purpose], purpose
end

local function privateRoom(world, point)
    if world.site:IsIn(point) ~= true or world.sites:IsIndoor(point) ~= true
        or world.site:IsSameRoom(point, point) ~= true then
        return
    end
    local room, purpose = M.roomClass(world.site, point)
    if not room then return end
    local household = world.site:GetOwnerHouseholdId()
    for _, person in ipairs(world.participants) do
        if world.site:IsCharacterAllowedInRoom(person:GetEntityId(), purpose, household) ~= true then
            return nil, "room_access_denied"
        end
    end
    return room
end

local function availableRoom(world, point, claimId)
    local room, reason = privateRoom(world, point)
    if not room then return nil, reason or "room_unclassified" end
    for _, occupant in ipairs(world.occupants) do
        local inside = world.site:IsSameRoom(point, occupant)
        if inside ~= false then return nil, inside and "room_occupied" or "room_unknown" end
    end
    for key, claim in pairs(claims) do
        if key ~= claimId and claim.site_id == world.site_id
            and world.site:IsSameRoom(point, claim.point) ~= false then
            return nil, "room_claimed"
        end
    end
    return room
end

local function roomFloor(world, point)
    return {
        IsOnWalkableGrid = function(_, destination)
            return world.site:IsSameRoom(point, destination) == true
                and world.floor:IsOnWalkableGrid(destination) == true
        end,
    }
end

local function eligiblePoints(world, option, arrivalPoints)
    local minimumSeparation = option.kind == "sofa.pair" and 100 or 150
    if type(arrivalPoints) ~= "table" or #arrivalPoints ~= 2
        or distanceSquared(arrivalPoints[1], arrivalPoints[2]) < minimumSeparation^2 then
        return false
    end
    for index, destination in ipairs(arrivalPoints) do
        if world.site:IsSameRoom(option.point, destination) ~= true
            or world.floor:IsOnWalkableGrid(destination) ~= true then return false end
        local person = world.participants[index]
        local params = inzoi.FB1NavigationQueryParams()
        params.EntityId = person:GetEntityId()
        params.bIgnorePermission = false
        if world.site:IsExistInternalPath(person:GetLocation(), destination, params) ~= true then return false end
    end
    return true
end

-- The adapters are intentionally read-only. Confirm playback compatibility
-- with SceneZOI before claiming one of the ranked candidates.
function M.candidates(initiator, partner, rows, groundAnchors, arrivalPoints)
    local world = scope(initiator, partner)
    if not world then return {}, "site_unavailable" end
    local furniture = {}
    for _, row in ipairs(rows) do
        local kind = row.profile.kind
        if kind == "bed.queen" or kind == "sofa.pair" then
            local nativeId = inzoi.FB1EntityId()
            nativeId.Value = tonumber(row.furniture_id)
            local object = world.manager:FindGameObject(nativeId)
            if not object then return {}, "furniture_unverified" end
            local location = object:GetLocation()
            if world.site:IsIn(location) then
                furniture[#furniture + 1] = {
                    kind = kind, point = location, furniture_id = row.furniture_id,
                    furniture_pair_id = row.furniture_pair_id, row = row, available = row.available,
                }
            end
        end
    end

    local ranked = Planner.candidates(furniture, groundAnchors, function(option)
        local room = availableRoom(world, option.point)
        if not room then return end
        local points = arrivalPoints(option, roomFloor(world, option.point))
        if not eligiblePoints(world, option, points) then return end
        option.site_id = world.site_id
        return room, distanceSquared(initiator:GetLocation(), option.point), points
    end, function(first, second) return world.site:IsSameRoom(first, second) end)
    return ranked
end

function M.claim(key, candidate, initiator, partner)
    if claims[key] then return false, "room_claimed" end
    local world = scope(initiator, partner)
    if not world or world.site_id ~= candidate.site_id then return false, "site_unavailable" end
    local room, reason = availableRoom(world, candidate.point)
    if not room then return false, reason end
    local initiatorId, partnerId = initiator:GetEntityId().Value, partner:GetEntityId().Value
    for _, claim in pairs(claims) do
        if claim.initiator == initiatorId or claim.partner == initiatorId
            or claim.initiator == partnerId or claim.partner == partnerId then
            return false, "participant_busy"
        end
    end
    if not eligiblePoints(world, candidate, candidate.arrival_points) then return false, "walk_failed" end
    claims[key] = {
        site_id = world.site_id, point = candidate.point, kind = candidate.kind,
        initiator = initiatorId, partner = partnerId,
    }
    return true
end

-- The caller repeats availability checks for the selected furniture and its
-- exact seat pair through SceneZOI at arrival.
function M.recheck(key, initiator, partner, destinations)
    local claim = claims[key]
    if not claim or claim.initiator ~= initiator:GetEntityId().Value or claim.partner ~= partner:GetEntityId().Value then
        return false, "room_unclaimed"
    end
    local world = scope(initiator, partner)
    if not world or world.site_id ~= claim.site_id then return false, "site_unavailable" end
    local room, reason = availableRoom(world, claim.point, key)
    if not room then return false, reason end
    if destinations and not eligiblePoints(world, claim, destinations) then return false, "walk_failed" end
    return true
end

function M.release(key)
    claims[key] = nil
end

return M
