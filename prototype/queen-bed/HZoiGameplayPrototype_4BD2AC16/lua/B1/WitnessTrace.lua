local M = {}

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

local function clearTrace(witness, start, target, participants)
    local hit = UE.FHitResult()
    local ignore = {witness}
    for _, actor in ipairs(participants) do ignore[#ignore + 1] = actor end
    local blocked = inzoi.UB1FunctionLibrary.B1LineTraceSingle(
        hit, witness, start, target, true, ignore, UE.ECollisionChannel.ECC_Visibility)
    assert(type(blocked) == "boolean", "Sight trace did not return a result")
    return not blocked
end

-- Run in B1. The caller must correlate this response with the requesting
-- session and node revision before attaching B2 relationship information.
function M.sample(characters, participantIds, revision)
    local roster, targets, actors = {}, {}, {}
    for _, id in ipairs(participantIds) do
        local actor = characters[id]
        local target = headPoint(actor)
        if not target then return {}, "participant_view_unavailable" end
        roster[id], targets[id] = true, target
        actors[#actors + 1] = actor
    end
    if #actors < 2 then return {}, "encounter_roster_missing" end

    local origin = targets[participantIds[1]]
    local nearby = {}
    for id, actor in pairs(characters) do
        if not roster[id] then
            local distance = distanceSquared(actor:K2_GetActorLocation(), origin)
            if distance <= 900^2 then nearby[#nearby + 1] = {id = id, actor = actor, distance = distance} end
        end
    end
    table.sort(nearby, function(a, b)
        if a.distance == b.distance then return a.id < b.id end
        return a.distance < b.distance
    end)

    local observations = {}
    for i = 1, math.min(#nearby, 24) do
        local row = nearby[i]
        local eye = viewpoint(row.actor)
        if eye then
            local visible = {}
            for id, target in pairs(targets) do
                if clearTrace(row.actor, eye, target, actors) then visible[id] = true end
            end
            if next(visible) then
                observations[#observations + 1] = {id = row.id, visible = visible, revision = revision}
            end
        end
    end
    return observations
end

return M
