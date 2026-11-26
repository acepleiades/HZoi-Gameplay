local M = {}
local MIN_SEPARATION_SQ = 150 ^ 2

local function distanceSquared(a, b)
    return (a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2
end

function M.points(bed, floor, initiator, partner)
    local center = bed:GetLocation()
    local yaw = math.rad(bed:GetRotation().Yaw)
    local sites = inzoi.getB2Manager("FB2SiteManager")
    local site = sites and sites:FindClosestSite(center, false)
    if site and not site:IsIn(center) then site = nil end
    local indoor = site and site:IsSameRoom(center, center) == true
    local origins = {initiator:GetLocation(), partner:GetLocation()}
    local filters = {}
    for i, person in ipairs({initiator, partner}) do
        if site and site:IsIn(origins[i]) then
            local params = inzoi.FB1NavigationQueryParams()
            params.EntityId = person:GetEntityId()
            params.bIgnorePermission = false
            filters[i] = params
        end
    end

    local candidates = {}
    local function reachable(candidate, person)
        if candidate.paths[person] == nil then
            local params = filters[person]
            -- The site query covers internal routes. A Zoi outside the site
            -- is still routed by the native walk when queued.
            candidate.paths[person] = not params
                or site:IsExistInternalPath(origins[person], candidate.point, params) == true
        end
        return candidate.paths[person]
    end

    local function consider(x, y)
        local spot = UE.FVector(x, y, center.Z)
        if floor:IsOnWalkableGrid(spot) ~= true
            or (indoor and site:IsSameRoom(center, spot) ~= true) then return end
        local nextPoint = {point = spot, paths = {}}
        for _, candidate in ipairs(candidates) do
            local point = candidate.point
            if distanceSquared(point, spot) >= MIN_SEPARATION_SQ then
                local swap = distanceSquared(origins[1], point) + distanceSquared(origins[2], spot)
                    > distanceSquared(origins[1], spot) + distanceSquared(origins[2], point)
                local first, second = candidate, nextPoint
                if swap then first, second = second, first end
                if reachable(first, 1) and reachable(second, 2) then return {first.point, second.point} end
                if reachable(second, 1) and reachable(first, 2) then return {second.point, first.point} end
            end
        end
        candidates[#candidates + 1] = nextPoint
    end

    -- Prefer the established positions when both paths work.
    for _, radius in ipairs({150, 200, 250}) do
        for direction = 1, 8 do
            local angle = yaw + direction * math.pi / 4
            local pair = consider(center.X + radius * math.cos(angle), center.Y + radius * math.sin(angle))
            if pair then return pair end
        end
    end

    -- A narrow aisle may reach the native slots but not any of the defaults.
    -- Sample along the bed's edge so both Zois can use the same side.
    local slots = bed:GetComponent(inzoi.EB2ComponentType.Slot)
    for _, state in ipairs(slots and slots.SlotStateInfos or {}) do
        local found, slot = slots:GetSlotLocationBySlotStateInfo(state, UE.FVector(0, 0, 0))
        if found and slot then
            local dx, dy = slot.X - center.X, slot.Y - center.Y
            local radius = math.sqrt(dx ^ 2 + dy ^ 2)
            if radius >= 45 and radius <= 190 then
                for _, offset in ipairs({0, 80, -80, 155, -155}) do
                    local pair = consider(slot.X - offset * dy / radius, slot.Y + offset * dx / radius)
                    if pair then return pair end
                end
            end
        end
    end

    -- Custom beds can omit usable approach slots. Search closer to the center
    -- on both axes as a fallback, using the same room, grid and path checks.
    for _, radius in ipairs({85, 115}) do
        for direction = 1, 16 do
            local angle = yaw + direction * math.pi / 8
            local pair = consider(center.X + radius * math.cos(angle), center.Y + radius * math.sin(angle))
            if pair then return pair end
        end
    end
end

return M
