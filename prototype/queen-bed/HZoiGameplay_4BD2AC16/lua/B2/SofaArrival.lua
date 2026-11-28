local M = {}

function M.seats(row)
    local ids = row.sitting_spots
    if not row.furniture_pair_id or not ids or #ids ~= 2 then return nil end
    local profile = row.profile
    local a, b
    for _, spot in ipairs(profile.sitting_spots) do
        if spot.id == ids[1] then a = spot end
        if spot.id == ids[2] then b = spot end
    end
    if not a or not b then return nil end
    local offset = profile.offset_cm or {}
    return {
        id = row.furniture_pair_id,
        x = (a.offset_cm.x + b.offset_cm.x) / 2 + (offset.x or 0),
        y = (a.offset_cm.y + b.offset_cm.y) / 2 + (offset.y or 0),
        z = (a.offset_cm.z + b.offset_cm.z) / 2 + (offset.z or 0),
        yaw = a.yaw_degrees + (profile.yaw_degrees or 0),
    }
end

function M.points(seats, sofa, floor)
    local location = sofa:GetLocation()
    local objectYaw = sofa:GetRotation().Yaw
    local yaw = math.rad(objectYaw)
    local x = location.X + seats.x * math.cos(yaw) - seats.y * math.sin(yaw)
    local y = location.Y + seats.x * math.sin(yaw) + seats.y * math.cos(yaw)
    local z = location.Z + seats.z
    -- The sofa's local +Y faces out from the cushions. Use the chosen run's
    -- yaw so a corner sofa's other arm is never the intended destination.
    local facing = math.rad(objectYaw + seats.yaw)
    local sideX, sideY = math.cos(facing), math.sin(facing)
    local function floorPoint(side, depth)
        return UE.FVector(x + side * sideX - depth * sideY, y + side * sideY + depth * sideX, z)
    end
    for _, depth in ipairs({90, 125, 160}) do
        local a, b = floorPoint(-55, depth), floorPoint(55, depth)
        if floor:IsOnWalkableGrid(a) and floor:IsOnWalkableGrid(b) then return {a, b} end
    end
    -- A table or armrest can block one side. Stagger along an open approach.
    for _, side in ipairs({-55, 55, 0}) do
        local a, b = floorPoint(side, 90), floorPoint(side, 200)
        if floor:IsOnWalkableGrid(a) and floor:IsOnWalkableGrid(b) then return {a, b} end
    end
end

return M
