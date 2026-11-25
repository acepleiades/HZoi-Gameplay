local M = {}
local TICKS_PER_MINUTE = 600000000
local SCAN_INTERVAL = 5 * TICKS_PER_MINUTE
local ATTEMPT_COOLDOWN = 45 * TICKS_PER_MINUTE
local RETRY_DELAY = 15 * TICKS_PER_MINUTE
local NEAR_PLAYER_CM = 4000
local NEAR_PARTNER_CM = 2000

local function distanceSquared(first, second)
    return (first.X - second.X)^2 + (first.Y - second.Y)^2 + (first.Z - second.Z)^2
end

local function idle(person, autonomy)
    if not person or person:IsSpawned() ~= true or person:IsDeath() ~= false
        or person:IsInRabbitHole() ~= false or person:IsAutonomyEnable() ~= true then
        return false
    end
    if autonomy:ResolveToggleOption(person, inzoi.EB1AutonomyOptionType.AutonomyEnable) ~= true then
        return false
    end
    local interaction = person:GetComponent(inzoi.EB2ComponentType.Interaction)
    return interaction and interaction:IsQueueEmpty() == true
        and interaction:IsPlayingInteraction() == false
end

local function autonomyManager()
    local autonomy = inzoi.getB2Manager("FB2AutonomyOptionManager")
    local global = autonomy and autonomy:GetGlobalOption()
    if global and global.AutonomyEnable and global.AutonomyEnable.Value == true then return autonomy end
end

function M.canAct(person)
    local autonomy = autonomyManager()
    return autonomy and person:IsAutonomyEnable() == true
        and autonomy:ResolveToggleOption(person, inzoi.EB1AutonomyOptionType.AutonomyEnable) == true
end

local function world()
    local controller = inzoi.FB2ControllerSystem
    if controller.IsBuildMode() ~= false then return end
    local time = inzoi.getB2Manager("FB2TimeManager")
    if not time or (time:GetTimeScaleValue(false) or 0) <= 0 then return end
    local autonomy = autonomyManager()
    local playerId = controller.GetPossessEntityId()
    local entities = inzoi.getB2Manager("FB2EntityManager")
    local sites = inzoi.getB2Manager("FB2SiteManager")
    local player = entities and playerId and entities:FindCharacter(playerId)
    if not (player and sites) then return end
    local center = player:GetLocation()
    local site = sites:FindClosestSite(center, false)
    if not site or site:GetSiteType() ~= inzoi.EB1SiteType.Residence
        or site:IsFakeSite() ~= false or site:IsPublicSite() ~= false or site:IsIn(center) ~= true then
        site = nil
    end
    return {entities = entities, autonomy = autonomy, site = site, center = center, playerId = playerId.Value, player = player}
end

local function candidates(current)
    local members, byId = {}, {}
    for _, entity in pairs(current.entities:GetAllEntities(inzoi.EB2EntityType.Character)) do
        local nativeId = entity:GetEntityId()
        if nativeId.Value > 0 and nativeId.Value ~= current.playerId and entity:IsSpawned() == true then
            local person = current.entities:FindCharacter(nativeId)
            local location = person and person:GetLocation()
            if location and distanceSquared(location, current.center) <= NEAR_PLAYER_CM^2
                and current.site:IsIn(location) == true and idle(person, current.autonomy) then
                local id = tostring(nativeId.Value)
                local candidate = {id = id, person = person, location = location}
                members[#members + 1], byId[id] = candidate, candidate
            end
        end
    end
    table.sort(members, function(a, b) return a.id < b.id end)
    return members, byId
end

local function pairKey(first, second)
    if first < second then return first .. "|" .. second end
    return second .. "|" .. first
end

-- Run once per simulation frame from the possessed character. Only idle,
-- nearby NPCs on the same residential site may start a background invitation.
function M.new(beginNpc, groundAnchors, urges)
    local nextScan, lastScan, lastError = 0, nil, nil
    local retries = {}

    local function scan(now)
        local current = world()
        if not current then return end
        if not urges.pending(current.player) then
            urges.requestEligible(current.player, function(key)
                local target = inzoi.FB1EntityId()
                target.Value = tonumber(key)
                return current.entities:FindCharacter(target)
            end)
        end
        if not (current.autonomy and current.site) then return end
        for key, deadline in pairs(retries) do
            if deadline <= now then retries[key] = nil end
        end
        local members, byId = candidates(current)
        for _, owner in ipairs(members) do
            local function nearbyPartner(key)
                local partner = byId[key]
                if partner and partner ~= owner
                    and distanceSquared(owner.location, partner.location) <= NEAR_PARTNER_CM^2 then return partner end
            end
            local urge = urges.pending(owner.person) or urges.requestEligible(owner.person, function(key)
                local partner = nearbyPartner(key)
                return partner and partner.person
            end)
            local partner = urge and nearbyPartner(urge.partner)
            if partner and urge.expires > now and urges.canInvite(owner.person, partner.person) then
                local key = pairKey(owner.id, partner.id)
                if not retries[key] then
                    retries[key] = now + RETRY_DELAY
                    local anchors = groundAnchors and groundAnchors(current.site, owner.person, partner.person)
                    local started, reason = beginNpc(owner.id, partner.id, anchors)
                    if started then retries[key] = now + ATTEMPT_COOLDOWN end
                    return started, reason
                end
            end
        end
    end

    return function()
        local now = inzoi.FB2TimeManager.StaticGetCurrentTicks()
        if type(now) ~= "number" or now <= 0 then return end
        if lastScan and now < lastScan then
            retries, nextScan = {}, 0
        end
        if now < nextScan then return end
        lastScan, nextScan = now, now + SCAN_INTERVAL
        local ok, started, reason = pcall(scan, now)
        if ok then
            lastError = nil
            return started, reason
        end
        if started ~= lastError then
            lastError = started
            print("[HZoiGameplay] NPC initiative scan failed: " .. tostring(started))
        end
    end
end

return M
