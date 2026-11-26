local M = {}
local MAX_ARRIVAL_WITNESSES = 128
local MAX_DOORS_PER_TRACE = 8

local function headPoint(actor)
    local mesh = actor and actor.Mesh
    if mesh and mesh:GetBoneIndex("head") >= 0 then
        return mesh:GetSocketTransform("head", 0).Translation
    end
end

local function viewpoint(actor)
    for _, component in ipairs(actor:K2_GetComponentsByClass(UE.USkeletalMeshComponent:StaticClass())) do
        if component:GetName() == "Head"
            and component:GetBoneIndex("FACIAL_L_Eye") >= 0
            and component:GetBoneIndex("FACIAL_R_Eye") >= 0 then
            local left = component:GetSocketTransform("FACIAL_L_Eye", 0).Translation
            local right = component:GetSocketTransform("FACIAL_R_Eye", 0).Translation
            return UE.FVector((left.X + right.X) / 2, (left.Y + right.Y) / 2, (left.Z + right.Z) / 2)
        end
    end
end

local function distanceSquared(a, b)
    return (a.X - b.X)^2 + (a.Y - b.Y)^2 + (a.Z - b.Z)^2
end

local function lineTrace(witness, start, target, ignore, channel)
    local hit = UE.FHitResult()
    local blocked, result = inzoi.UB1FunctionLibrary.B1LineTraceSingle(
        hit, witness, start, target, true, ignore, UE.ECollisionChannel[channel])
    assert(type(blocked) == "boolean", "Sight trace did not return a result for " .. channel)
    return blocked, result or hit
end

local function clearDoorGeometry(hit, start, target)
    local _, _, _, _, _, _, _, _, _, actor, blocker = UE.UGameplayStatics.BreakHitResult(hit)
    if not actor or not blocker then return end
    local readable, proxy, leaf, otherLeaf = pcall(function()
        return actor.InvisibleBlockingWallComponent, actor.DoorMeshComponent, actor.SecondDoorMeshComponent
    end)
    if not readable or not proxy or not leaf then return end
    local proxyName = blocker:GetName()
    if proxyName ~= proxy:GetName() then return end

    -- The door's movement blocker stays in the doorway even as the leaf swings.
    -- Keep all real geometry on the door in the sight test before skipping it.
    local firstLeaf = leaf:GetName()
    local secondLeaf = otherLeaf and otherLeaf:GetName()
    local foundFirst, foundSecond = false, not secondLeaf
    for _, component in ipairs(actor:K2_GetComponentsByClass(UE.UPrimitiveComponent:StaticClass())) do
        local name = component:GetName()
        local isLeaf = name == firstLeaf or name == secondLeaf
        if name ~= proxyName and (isLeaf or (component:K2_IsQueryCollisionEnabled()
            and component:GetCollisionResponseToChannel(UE.ECollisionChannel.ECC_Visibility)
                == UE.ECollisionResponse.ECR_Block)) then
            local blocked = component:K2_LineTraceComponent(start, target, true, false, false,
                UE.FVector(), UE.FVector(), "", UE.FHitResult())
            if blocked ~= false then return end
            foundFirst = foundFirst or name == firstLeaf
            foundSecond = foundSecond or name == secondLeaf
        end
    end
    if foundFirst and foundSecond then return actor end
end

local function clearTrace(witness, start, target, participants)
    local ignore = {witness}
    for _, actor in ipairs(participants) do ignore[#ignore + 1] = actor end
    local visibilityIgnore = ignore
    for attempt = 0, MAX_DOORS_PER_TRACE do
        local blocked, hit = lineTrace(witness, start, target, visibilityIgnore, "ECC_Visibility")
        if not blocked then
            -- Camera cutaways can leave walls that only block WorldStatic.
            local wallBlocked = lineTrace(witness, start, target, ignore, "ECC_WorldStatic")
            return not wallBlocked
        end
        if attempt == MAX_DOORS_PER_TRACE then return false end
        local clearDoor = clearDoorGeometry(hit, start, target)
        if not clearDoor then return false end
        if visibilityIgnore == ignore then
            visibilityIgnore = {table.unpack(ignore)}
        end
        visibilityIgnore[#visibilityIgnore + 1] = clearDoor
    end
    return false
end

-- Run in B1. The caller must correlate this response with the requesting
-- session and node revision before attaching B2 relationship information.
function M.sample(characters, participantIds, revision, arrivalPoints, baseline)
    local roster, targets, actors = {}, {}, {}
    for _, id in ipairs(participantIds) do
        local actor = characters[id]
        local target = headPoint(actor)
        if not target then return {}, "participant_view_unavailable" end
        if arrivalPoints then
            local point = arrivalPoints[id]
            -- Use each prepared spot at its participant's current eye-level
            -- height so sight is tested across walls, not into the walkable floor.
            target = UE.FVector(point.x, point.y, target.Z)
        end
        roster[id], targets[id] = true, target
        actors[#actors + 1] = actor
    end
    if #actors < 2 then return {}, "encounter_roster_missing" end

    local nearby = {}
    for id, actor in pairs(characters) do
        if not roster[id] then
            local origin = actor:K2_GetActorLocation()
            local distance = math.huge
            for _, target in pairs(targets) do
                distance = math.min(distance, distanceSquared(origin, target))
            end
            if distance <= 900^2 then nearby[#nearby + 1] = {id = id, actor = actor, distance = distance} end
        end
    end
    table.sort(nearby, function(a, b)
        if a.distance == b.distance then return a.id < b.id end
        return a.distance < b.distance
    end)

    local observations, baselineAbsent = {}, {}
    for i, row in ipairs(nearby) do
        local trackBaseline = baseline and baseline[row.id]
        if arrivalPoints or i <= 24 or trackBaseline then
            local eye = viewpoint(row.actor)
            if arrivalPoints then
                eye = eye or headPoint(row.actor)
                if not eye then return {}, "observer_view_unavailable" end
            end
            if eye then
                local visible = {}
                for id, target in pairs(targets) do
                    if clearTrace(row.actor, eye, target, actors) then
                        visible[id] = true
                        if arrivalPoints then break end
                    end
                end
                if next(visible) then
                    if arrivalPoints then
                        if #observations == MAX_ARRIVAL_WITNESSES then return {}, "observer_limit" end
                        observations[#observations + 1] = {id = row.id}
                    elseif i <= 24 then
                        observations[#observations + 1] = {id = row.id, visible = visible, revision = revision}
                    end
                elseif trackBaseline then
                    baselineAbsent[#baselineAbsent + 1] = row.id
                end
            end
        end
    end
    if baseline then
        local nearbyIds = {}
        for _, row in ipairs(nearby) do nearbyIds[row.id] = true end
        for id in pairs(baseline) do
            if not nearbyIds[id] then baselineAbsent[#baselineAbsent + 1] = id end
        end
        table.sort(baselineAbsent)
    end
    return observations, nil, baselineAbsent
end

return M
