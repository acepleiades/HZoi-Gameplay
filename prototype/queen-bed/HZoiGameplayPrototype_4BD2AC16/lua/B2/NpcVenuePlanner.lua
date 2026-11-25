local FurnitureKind = require("VenueFurnitureKind")
local M = {}

local function privateKind(kind)
    return kind == "bedroom" or kind == "private"
end

-- Metadata and world checks are supplied by the caller. A failed or unknown
-- observation deliberately excludes the room.
function M.candidates(furniture, anchors, inspect, sameRoom)
    local accepted = {}
    local supported = {}
    for _, option in ipairs(furniture) do
        if FurnitureKind.supported(option.kind) and option.point then
            supported[#supported + 1] = option
            if option.available == true and (option.kind ~= "sofa.pair" or option.furniture_pair_id) then
                accepted[#accepted + 1] = option
            end
        end
    end
    -- An occupied or temporarily unavailable supported item still makes this
    -- a furniture room. Do not route the pair around it onto the floor.
    for _, point in ipairs(anchors or {}) do
        local containsFurniture = false
        for _, option in ipairs(supported) do
            if sameRoom(point, option.point) ~= false then
                containsFurniture = true
                break
            end
        end
        if not containsFurniture then accepted[#accepted + 1] = {kind = "ground", point = point} end
    end

    local ranked = {}
    for _, option in ipairs(accepted) do
        local room, distance, points = inspect(option)
        if privateKind(room) and type(distance) == "number" and distance >= 0 and distance < math.huge
            and type(points) == "table" and #points == 2 then
            option.room_class, option.distance, option.arrival_points = room, distance, points
            ranked[#ranked + 1] = option
        end
    end
    table.sort(ranked, function(first, second)
        if (first.kind == "ground") ~= (second.kind == "ground") then return first.kind ~= "ground" end
        if first.room_class ~= second.room_class then return first.room_class == "bedroom" end
        if first.distance ~= second.distance then return first.distance < second.distance end
        return (first.furniture_id or "") .. (first.furniture_pair_id or "")
            < (second.furniture_id or "") .. (second.furniture_pair_id or "")
    end)
    return ranked
end

return M
