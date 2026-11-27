local Planner = require("NpcVenuePlanner")
local FurnitureKind = require("VenueFurnitureKind")
local VenuePath = require("VenuePath")
local Standing = require("NpcStandingAnchors")
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
    local occupants = {}
    if checkVacancy then
        local firstId, secondId = initiator:GetEntityId().Value, partner:GetEntityId().Value
        for _, entity in pairs(entityManager:GetAllEntities(inzoi.EB2EntityType.Character)) do
            local entityId = entity:GetEntityId()
            if entityId.Value ~= firstId and entityId.Value ~= secondId and entity:IsSpawned() then
                local character = entityManager:FindCharacter(entityId)
                -- Without a location, vacancy cannot be confirmed.
                if not character then return end
                occupants[#occupants + 1] = character:GetLocation()
            end
        end
    end
    return {
        manager = entityManager, sites = siteManager, floor = pathFinder,
        participants = {initiator, partner}, occupants = occupants,
    }
end

local function siteId(site)
    if not site or site:IsFakeSite() ~= false then return end
    local id = tostring(site:GetSiteId())
    if id ~= "" and id ~= "None" then return id end
end

local function siteAt(world, point)
    local site = world.sites:FindClosestSite(point, false)
    if siteId(site) and site:IsIn(point) == true then return site end
end

local function privateResidence(site)
    return site:GetSiteType() == inzoi.EB1SiteType.Residence and site:IsPublicSite() == false
end

local function bookedForPair(world, site, purpose)
    if type(purpose) ~= "string" or purpose == "" or purpose == "None" or purpose == "EntireSite" then
        return false
    end
    local ok, booked = pcall(function()
        local manager = inzoi.getB2Manager("FB2HouseholdBizManager")
        local biz = manager and manager:FindHouseholdBizBySiteEntityIdPtr(site:GetEntityId())
        if not biz then return false end
        local tick = inzoi.FB2TimeManager.StaticGetCurrentTicks()
        local first = world.participants[1]:GetEntityId().Value
        local second = world.participants[2]:GetEntityId().Value
        local id = site:GetSiteId()
        for _, room in pairs(biz.BizInfoData.AccommodationInfoList.Infos) do
            local key = room.RoomKey
            if key.AccommodationDtId == id and key.RoomPurposeId == purpose
                and room.StartTicks >= 0 and room.StartTicks <= tick and tick < room.EndTicks then
                local firstGuest, secondGuest
                for _, guest in pairs(room.GuestEntityIds) do
                    firstGuest = firstGuest or guest.Value == first
                    secondGuest = secondGuest or guest.Value == second
                end
                if firstGuest and secondGuest then return true end
            end
        end
        return false
    end)
    return ok and booked == true
end

local function accessibleRoom(world, site, point)
    if site:IsIn(point) ~= true or world.sites:IsIndoor(point) ~= true
        or site:IsSameRoom(point, point) ~= true then
        return false, "room_unavailable"
    end
    local purpose = site:GetRoomPurposeIdByLocation(point)
    if not privateResidence(site) and not bookedForPair(world, site, purpose) then
        return false, "room_privacy_unverified"
    end
    local household = site:GetOwnerHouseholdId()
    for _, person in ipairs(world.participants) do
        if site:IsCharacterAllowedInRoom(person:GetEntityId(), purpose, household) ~= true then
            return false, "room_access_denied"
        end
    end
    return true, purpose
end

local function occupiedRoom(world, site, point)
    for _, occupant in ipairs(world.occupants) do
        if site:IsIn(occupant) == true then
            local inside = site:IsSameRoom(point, occupant)
            if inside == true then return true end
            if inside ~= false then return nil end
        end
    end
    return false
end

local function unclaimedRoom(site, id, point)
    for _, claim in pairs(claims) do
        if claim.site_id == id and site:IsSameRoom(point, claim.point) ~= false then
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

local function roomFloor(world, site, point)
    return {
        IsOnWalkableGrid = function(_, destination)
            return site:IsSameRoom(point, destination) == true
                and world.floor:IsOnWalkableGrid(destination) == true
        end,
    }
end

local function routesFrom(world, site)
    return {
        VenuePath.query(site, world.sites, world.floor, world.participants[1]),
        VenuePath.query(site, world.sites, world.floor, world.participants[2]),
    }
end

local function eligiblePoints(world, site, option, arrivalPoints, routes)
    local minimumSeparation = option.kind == "sofa.pair" and 100 or 150
    if type(arrivalPoints) ~= "table" or #arrivalPoints ~= 2
        or distanceSquared(arrivalPoints[1], arrivalPoints[2]) < minimumSeparation^2 then
        return false, "arrival_points_unavailable"
    end
    for index, destination in ipairs(arrivalPoints) do
        if site:IsIn(destination) ~= true or site:IsSameRoom(option.point, destination) ~= true
            or world.floor:IsOnWalkableGrid(destination) ~= true then return false, "arrival_outside_room" end
        if not routes[index](destination) then return false, "route_" .. index .. "_unavailable" end
    end
    return true
end

local function standingPoints(world)
    local points, visited = {}, {}
    -- Check the party's two locations and the nearest neighboring sites.
    -- Each ground search independently bounds its samples around the pair.
    for _, person in ipairs(world.participants) do
        local position = person:GetLocation()
        for _, skipLocatedSite in ipairs({false, true}) do
            local site = world.sites:FindClosestSite(position, skipLocatedSite)
            local id = siteId(site)
            if id and not visited[id] then
                visited[id] = true
                local allowed
                if not privateResidence(site) then
                    local checked = {}
                    allowed = function(point)
                        local purpose = site:GetRoomPurposeIdByLocation(point)
                        if not purpose then return false end
                        if checked[purpose] == nil then
                            checked[purpose] = bookedForPair(world, site, purpose)
                        end
                        return checked[purpose]
                    end
                end
                for _, point in ipairs(Standing.find(site, world.participants[1], world.participants[2], allowed)) do
                    points[#points + 1] = point
                end
            end
        end
    end
    return points
end

-- The adapters are intentionally read-only. Confirm playback compatibility
-- with SceneZOI before claiming one of the ranked candidates.
function M.candidates(initiator, partner, rows, groundAnchors, arrivalPoints)
    local world = scope(initiator, partner, true)
    if not world then return {}, "site_unavailable" end
    local furniture = {}
    local siteByPoint, routesBySite = {}, {}
    local initiatorId = initiator:GetEntityId().Value
    for _, row in ipairs(rows) do
        local kind = row.profile.kind
        if FurnitureKind.supported(kind) then
            local nativeId = inzoi.FB1EntityId()
            nativeId.Value = tonumber(row.furniture_id)
            local object = world.manager:FindGameObject(nativeId)
            if object then
                local location = object:GetLocation()
                furniture[#furniture + 1] = {
                    kind = kind, point = location, furniture_id = row.furniture_id,
                    furniture_pair_id = row.furniture_pair_id, row = row, available = row.available,
                    assigned = FurnitureKind.isBed(kind) and assignedTo(object, initiatorId),
                }
            end
        end
    end

    local rejected = {}
    local function reject(reason)
        rejected[reason] = (rejected[reason] or 0) + 1
    end
    local ranked = Planner.candidates(furniture, groundAnchors or standingPoints(world), function(option)
        local site = siteByPoint[option.point]
        if not site then
            site = siteAt(world, option.point)
            siteByPoint[option.point] = site
        end
        if not site then return reject("site_unavailable") end
        local id = siteId(site)
        local accessible, purpose = accessibleRoom(world, site, option.point)
        if not accessible then return reject(purpose) end
        if not unclaimedRoom(site, id, option.point) then return reject("room_claimed") end
        local occupied = occupiedRoom(world, site, option.point)
        if occupied == nil then return reject("room_unknown") end
        local points = arrivalPoints(option, roomFloor(world, site, option.point))
        routesBySite[id] = routesBySite[id] or routesFrom(world, site)
        local canArrive, reason = eligiblePoints(world, site, option, points, routesBySite[id])
        if not canArrive then return reject(reason) end
        option.site_id = id
        option.room_purpose = purpose
        return occupied, distanceSquared(initiator:GetLocation(), option.point), points
    end)
    return ranked, nil, #ranked == 0 and rejected or nil
end

function M.claim(key, candidate, initiator, partner)
    if claims[key] then return false, "room_claimed" end
    local world = scope(initiator, partner, true)
    local site = world and siteAt(world, candidate.point)
    local id = siteId(site)
    if not id or id ~= candidate.site_id then return false, "site_unavailable" end
    local accessible, reason = accessibleRoom(world, site, candidate.point)
    if not accessible then return false, reason end
    if not unclaimedRoom(site, id, candidate.point) then return false, "room_claimed" end
    local occupied = occupiedRoom(world, site, candidate.point)
    if occupied == nil then return false, "room_unknown" end
    if occupied and not candidate.occupied then return false, "room_occupied" end
    local initiatorId, partnerId = initiator:GetEntityId().Value, partner:GetEntityId().Value
    for _, claim in pairs(claims) do
        if claim.initiator == initiatorId or claim.partner == initiatorId
            or claim.initiator == partnerId or claim.partner == partnerId then
            return false, "participant_busy"
        end
    end
    if not eligiblePoints(world, site, candidate, candidate.arrival_points, routesFrom(world, site)) then
        return false, "walk_failed"
    end
    claims[key] = {
        site_id = id, point = candidate.point, kind = candidate.kind,
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
    local site = world and siteAt(world, claim.point)
    if not site or siteId(site) ~= claim.site_id then return false, "site_unavailable" end
    -- Vacancy and competing claims were checked when this room was claimed.
    -- Judge anyone who enters afterward by sight once the pair arrives.
    local accessible, reason = accessibleRoom(world, site, claim.point)
    if not accessible then return false, reason end
    if destinations and not eligiblePoints(world, site, claim, destinations, routesFrom(world, site)) then
        return false, "walk_failed"
    end
    return true
end

function M.release(key)
    claims[key] = nil
end

return M
