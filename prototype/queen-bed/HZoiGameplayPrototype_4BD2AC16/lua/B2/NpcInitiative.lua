local M = {}
local TICKS_PER_MINUTE = 600000000
local SCAN_INTERVAL_SECONDS = 5
local MIN_COOLDOWN_MINUTES = 32 * 60
local COOLDOWN_HALF_SPREAD_MINUTES = 8 * 60
local RETRY_DELAY = 15 * TICKS_PER_MINUTE
-- DA_Interaction.AutonomyMaxTalkDistance in the retail game (centimeters).
local DEFAULT_TALK_RANGE_CM = 10000
local FINISHING_SECONDS = 5
local OPPORTUNITY_ROLL = 12

local function distanceSquared(first, second)
    return (first.X - second.X)^2 + (first.Y - second.Y)^2 + (first.Z - second.Z)^2
end

function M.isPresent(person)
    return person and person:IsSpawned() == true
        and person:IsDeath() == false and person:IsInRabbitHole() == false
end

-- An autonomous task near its end can be considered during preflight.
-- Dispatch still waits for it to finish, without clearing either queue.
function M.readiness(person)
    local interaction = person:GetComponent(inzoi.EB2ComponentType.Interaction)
    if not interaction or interaction:IsQueueEmpty() ~= true or interaction:IsPendingCoop()
        or interaction:IsCurrentInteractionCoop() or interaction:IsInteractionEnabled() ~= true then return end
    if interaction:IsPlayingInteraction() == false then return "ready" end
    if interaction:GetCurrentInteractionPlayReason() == inzoi.EB1InteractionPlayReason.Autonomy
        and interaction:IsCurrentInteractionInfinite() == false
        and interaction:IsCurrentInteractionAlmostFinished(FINISHING_SECONDS) == true then
        return "finishing"
    end
end

local function autonomyManager()
    local autonomy = inzoi.getB2Manager("FB2AutonomyOptionManager")
    local global = autonomy and autonomy:GetGlobalOption()
    if global and global.AutonomyEnable and global.AutonomyEnable.Value == true then return autonomy end
end

function M.canAct(person, autonomy)
    autonomy = autonomy or autonomyManager()
    -- A running native action can temporarily suspend autonomy without
    -- changing the player's actual autonomy preference.
    return autonomy and autonomy:ResolveToggleOption(person, inzoi.EB1AutonomyOptionType.AutonomyEnable) == true
end

function M.isSimulationRunning()
    local controller = inzoi.FB2ControllerSystem
    if controller.IsBuildMode() ~= false then return false end
    local time = inzoi.getB2Manager("FB2TimeManager")
    return time ~= nil and (time:GetTimeScaleValue(false) or 0) > 0
end

local function world()
    if not M.isSimulationRunning() then return end
    local autonomy = autonomyManager()
    if not autonomy then return end
    local playerId = inzoi.FB2ControllerSystem.GetPossessEntityId()
    local entities = inzoi.getB2Manager("FB2EntityManager")
    local player = entities and playerId and entities:FindCharacter(playerId)
    if not player then return end
    return {entities = entities, autonomy = autonomy}
end

local function candidates(current, isReserved)
    local members = {}
    for _, entity in pairs(current.entities:GetAllEntities(inzoi.EB2EntityType.Character)) do
        local nativeId = entity:GetEntityId()
        if nativeId.Value > 0 and entity:IsSpawned() == true then
            local person = current.entities:FindCharacter(nativeId)
            local location = M.isPresent(person) and person:GetLocation()
            if location then
                local id = tostring(nativeId.Value)
                members[#members + 1] = {id = id, person = person, location = location,
                    available = not isReserved(id) and M.readiness(person) ~= nil}
            end
        end
    end
    table.sort(members, function(a, b) return a.id < b.id end)
    return members
end

local function closeEnough(first, second)
    return distanceSquared(first.location, second.location) <= DEFAULT_TALK_RANGE_CM^2
end

-- The controlled Zoi supplies the message endpoint.
-- Candidate distance is measured between the pair.
function M.new(beginNpc, canInvite, isReserved)
    local lastPoll, lastGameTick, lastError, hasScanned
    local retries, cooldowns = {}, {}

    local function scan(now, current)
        if not hasScanned then
            hasScanned = true
            print("[HZoiGameplay] NPC initiative is scanning loaded Zois")
        end
        for key, deadline in pairs(retries) do
            if deadline <= now then retries[key] = nil end
        end
        for id, deadline in pairs(cooldowns) do
            if deadline <= now then cooldowns[id] = nil end
        end

        local ready = {}
        for _, candidate in ipairs(candidates(current, isReserved)) do
            if candidate.available then
                candidate.canInitiate = not cooldowns[candidate.id] and M.canAct(candidate.person, current.autonomy)
                ready[#ready + 1] = candidate
            end
        end

        local pool = {}
        -- The sorted roster gives each unordered pair one stable key and one roll.
        for index, first in ipairs(ready) do
            for other = index + 1, #ready do
                local second = ready[other]
                local key = first.id .. "|" .. second.id
                if not retries[key] and closeEnough(first, second) then
                    local firstAllowed = first.canInitiate and canInvite(first.person, second.person)
                    local secondAllowed = second.canInitiate and canInvite(second.person, first.person)
                    if (firstAllowed or secondAllowed) and math.random(OPPORTUNITY_ROLL) == 1 then
                        pool[#pool + 1] = {
                            first = first, second = second, key = key,
                            firstAllowed = firstAllowed, secondAllowed = secondAllowed,
                        }
                    end
                end
            end
        end

        if #pool == 0 then return end
        local choice = pool[#pool > 1 and math.random(#pool) or 1]
        local first, second = choice.first, choice.second
        if not choice.firstAllowed or (choice.secondAllowed and math.random(2) == 2) then
            first, second = second, first
        end
        retries[choice.key] = now + RETRY_DELAY

        local attemptWorld, started = retries, false
        local function onPlaybackStarted()
            if started or attemptWorld ~= retries then return end
            local startedAt = inzoi.FB2TimeManager.StaticGetCurrentTicks()
            if type(startedAt) ~= "number" or not (startedAt >= lastGameTick and startedAt < math.huge) then return end
            started = true
            -- The sum of two uniform draws gives a triangular distribution.
            local minutes = MIN_COOLDOWN_MINUTES + math.random(COOLDOWN_HALF_SPREAD_MINUTES + 1)
                + math.random(COOLDOWN_HALF_SPREAD_MINUTES + 1) - 2
            local deadline = startedAt + minutes * TICKS_PER_MINUTE
            cooldowns[first.id] = deadline
            return {started_tick = startedAt, until_tick = deadline, duration_minutes = minutes}
        end

        return beginNpc(first.id, second.id, onPlaybackStarted)
    end

    return function()
        local now = inzoi.FB2TimeManager.StaticGetCurrentTicks()
        if type(now) ~= "number" or not (now > 0 and now < math.huge) then return end
        -- Observe rewinds between polls so stale callbacks and game-time deadlines
        -- cannot survive a world reload even when the real-time throttle is active.
        if lastGameTick and now < lastGameTick then
            retries, cooldowns, lastPoll = {}, {}, nil
        end
        lastGameTick = now

        -- The game's day-length setting may make its clock as slow as real time.
        -- Use wall time for opportunities and game time for the cooldowns.
        local realTime = os.time()
        if lastPoll and realTime >= lastPoll and realTime - lastPoll < SCAN_INTERVAL_SECONDS then return end
        lastPoll = realTime
        local ok, started, reason = pcall(function()
            local current = world()
            if not current then return end
            return scan(now, current)
        end)
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
