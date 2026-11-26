local FurnitureKind = require("VenueFurnitureKind")
local M = {}
local ranks = {["bed.queen"] = 2, ["bed.single"] = 3, ["sofa.pair"] = 4, ground = 5}

-- Discover each room once. Placing occupied candidates after all vacant
-- candidates lets invitations exhaust the first pass before trying the second.
function M.candidates(furniture, anchors, inspect)
    local ranked = {}
    local function consider(option)
        local occupied, distance, points = inspect(option)
        if type(occupied) == "boolean" and type(distance) == "number" and distance >= 0 and distance < math.huge
            and type(points) == "table" and #points == 2 then
            option.occupied, option.distance, option.arrival_points = occupied, distance, points
            option.priority = option.assigned and 1 or ranks[option.kind]
            ranked[#ranked + 1] = option
        end
    end
    for _, option in ipairs(furniture) do
        if FurnitureKind.supported(option.kind) and option.point and option.available == true
            and (option.kind ~= "sofa.pair" or option.furniture_pair_id) then
            consider(option)
        end
    end
    for _, point in ipairs(anchors or {}) do consider({kind = "ground", point = point}) end

    table.sort(ranked, function(first, second)
        if first.occupied ~= second.occupied then return not first.occupied end
        if first.priority ~= second.priority then return first.priority < second.priority end
        if first.distance ~= second.distance then return first.distance < second.distance end
        if first.furniture_id ~= second.furniture_id then
            return (first.furniture_id or "") < (second.furniture_id or "")
        end
        return (first.furniture_pair_id or "") < (second.furniture_pair_id or "")
    end)
    return ranked
end

return M
