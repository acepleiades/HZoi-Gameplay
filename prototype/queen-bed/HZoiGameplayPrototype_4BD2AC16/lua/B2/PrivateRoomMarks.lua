local M = {}
local marksBySite = {}

local function positiveId(entityId)
    local value = entityId and entityId.Value
    if type(value) == "number" and value > 0 then return value end
end

local function siteKey(site)
    local key = site and site:GetSiteId()
    if key and key ~= "" and key ~= "None" then return key end
end

local function privateResidence(site)
    return site and site:GetSiteType() == inzoi.EB1SiteType.Residence
        and site:IsPublicSite() == false and site:IsFakeSite() == false
end

local function markerInRoom(site, point)
    local marks = marksBySite[siteKey(site)]
    if not marks then return end
    local household = positiveId(site:GetOwnerHouseholdId())
    for index, mark in ipairs(marks) do
        if household == mark.household and site:IsIn(mark.point) == true
            and site:IsSameRoom(mark.point, point) == true then
            return index, marks
        end
    end
end

function M.isMarked(site, point)
    return privateResidence(site) and point ~= nil and site:IsIn(point) == true and markerInRoom(site, point) ~= nil
end

function M.toggle(owner, point)
    local controller = inzoi.FB2ControllerSystem
    local ownerId = owner and positiveId(owner:GetEntityId())
    if not ownerId or ownerId ~= positiveId(controller.GetPossessEntityId()) then return "private_room_unavailable" end
    local household = positiveId(controller.GetPossessedHouseholdId())
    local sites = inzoi.getB2Manager("FB2SiteManager")
    local floor = inzoi.getB2Subsystem("FB2PathFindSystem")
    if not household or not sites or not floor or not point or floor:IsOnWalkableGrid(point) ~= true then
        return "private_room_unavailable"
    end
    local here = owner:GetLocation()
    local site = sites:FindClosestSite(here, false)
    local key = siteKey(site)
    if not key or not privateResidence(site) or positiveId(site:GetOwnerHouseholdId()) ~= household
        or site:IsIn(here) ~= true or site:IsIn(point) ~= true or sites:IsIndoor(here) ~= true
        or sites:IsIndoor(point) ~= true or site:IsSameRoom(here, point) ~= true then
        return "private_room_unavailable"
    end

    local index, marks = markerInRoom(site, point)
    if index then
        table.remove(marks, index)
        if #marks == 0 then marksBySite[key] = nil end
        return "private_room_unmarked"
    end
    if site:GetRoomPurposeIdByLocation(point) ~= "None" then return "private_room_purpose_defined" end
    marks = marksBySite[key] or {}
    marks[#marks + 1] = {household = household, point = UE.FVector(point.X, point.Y, point.Z)}
    marksBySite[key] = marks
    return "private_room_marked"
end

function M.reset()
    marksBySite = {}
end

return M
