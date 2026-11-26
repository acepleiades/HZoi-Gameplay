local Planner = require("NpcVenuePlanner")
local FurnitureKind = require("VenueFurnitureKind")
local M = {}
local claims = {}
local function distanceSquared(first, second)
    return (first.X - second.X)^2 + (first.Y - second.Y)^2 + (first.Z - second.Z)^2
end

local function scope(initiator, partner, checkVacancy)
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
    local occupants = {}
    if checkVacancy then
        local firstId, secondId = initiator:GetEntityId().Value, partner:GetEntityId().Value
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
    end
    return {
        manager = entityManager, sites = siteManager, floor = pathFinder, site = site,
        site_id = siteId, participants = {initiator, partner}, occupants = occupants,
    }
end

local function accessibleRoom(world, point)
    if world.site:IsIn(point) ~= true or world.sites:IsIndoor(point) ~= true
        or world.site:IsSameRoom(point, point) ~= true then
        return false, "room_unavailable"
    end
    local purpose = world.site:GetRoomPurposeIdByLocation(point)
    local household = world.site:GetOwnerHouseholdId()
    for _, person in ipairs(world.participants) do
        if world.site:IsCharacterAllowedInRoom(person:GetEntityId(), purpose, household) ~= true then
            return false, "room_access_denied"
        end
    end
    return true, purpose
end

local function occupiedRoom(world, point)
    for _, occupant in ipairs(world.occupants) do
        local inside = world.site:IsSameRoom(point, occupant)
        if inside == true then return true end
        if inside ~= false then return nil end
    end
    return false
end

local function unclaimedRoom(world, point)
    for _, claim in pairs(claims) do
        if claim.site_id == world.site_id and world.site:IsSameRoom(point, claim.point) ~= false then
            return false
        end
    end
    return true
end

local function assignedTo(object, initiatorId)
    local slot = object:GetComponent(inzoi.EB2ComponentType.Slot)
    if not slot then return false end
    local owners = slot:GetSlotOwnershipInfos()
    if not owners then return false end
    if type(owners.ToTable) == "function" then owners = owners:ToTable() end
    for owner, tag in pairs(owners) do
        if owner.Value == initiatorId and tag ~= "" and tag ~= "None" then return true end
    end
    return false
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
    local world = scope(initiator, partner, true)
    if not world then return {}, "site_unavailable" end
    local furniture = {}
    local initiatorId = initiator:GetEntityId().Value
    for _, row in ipairs(rows) do
        local kind = row.profile.kind
        if FurnitureKind.supported(kind) then
            local nativeId = inzoi.FB1EntityId()
            nativeId.Value = tonumber(row.furniture_id)
            local object = world.manager:FindGameObject(nativeId)
            if not object then return {}, "furniture_unverified" end
            local location = object:GetLocation()
            if world.site:IsIn(location) then
                furniture[#furniture + 1] = {
                    kind = kind, point = location, furniture_id = row.furniture_id,
                    furniture_pair_id = row.furniture_pair_id, row = row, available = row.available,
                    assigned = FurnitureKind.isBed(kind) and assignedTo(object, initiatorId),
                }
            end
        end
    end

    local ranked = Planner.candidates(furniture, groundAnchors, function(option)
        local accessible, purpose = accessibleRoom(world, option.point)
        if not accessible or not unclaimedRoom(world, option.point) then return end
        local occupied = occupiedRoom(world, option.point)
        if occupied == nil then return end
        local points = arrivalPoints(option, roomFloor(world, option.point))
        if not eligiblePoints(world, option, points) then return end
        option.site_id = world.site_id
        option.room_purpose = purpose
        return occupied, distanceSquared(initiator:GetLocation(), option.point), points
    end)
    return ranked
end

function M.claim(key, candidate, initiator, partner)
    if claims[key] then return false, "room_claimed" end
    local world = scope(initiator, partner, true)
    if not world or world.site_id ~= candidate.site_id then return false, "site_unavailable" end
    local accessible, reason = accessibleRoom(world, candidate.point)
    if not accessible then return false, reason end
    if not unclaimedRoom(world, candidate.point) then return false, "room_claimed" end
    local occupied = occupiedRoom(world, candidate.point)
    if occupied == nil then return false, "room_unknown" end
    if occupied and not candidate.occupied then return false, "room_occupied" end
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
    -- Vacancy and competing claims were checked when this room was claimed.
    -- Judge anyone who enters afterward by sight once the pair arrives.
    local accessible, reason = accessibleRoom(world, claim.point)
    if not accessible then return false, reason end
    if destinations and not eligiblePoints(world, claim, destinations) then return false, "walk_failed" end
    return true
end

function M.release(key)
    claims[key] = nil
end

return M
