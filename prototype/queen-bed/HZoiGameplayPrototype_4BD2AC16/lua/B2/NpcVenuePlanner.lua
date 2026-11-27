local FurnitureKind = require("VenueFurnitureKind")
local M = {}
local ranks = {["bed.queen"] = 2, ["bed.single"] = 3, ["sofa.pair"] = 4, ground = 5}

-- Placing occupied candidates after all vacant candidates lets invitations
-- exhaust the first pass before trying the second.
function M.candidates(furniture, anchors, inspect, standingPreferences)
    local ranked, roomDistances = {}, {}
    local function consider(option)
        local occupied, distance, points = inspect(option)
        if type(occupied) == "boolean" and type(distance) == "number" and distance >= 0 and distance < math.huge
            and type(points) == "table" and #points == 2 then
            option.occupied, option.distance, option.arrival_points = occupied, distance, points
            option.priority = option.assigned and 1 or ranks[option.kind]
            local preference = standingPreferences and standingPreferences[option.point]
            if preference then
                option.standing_preference = preference
                local room = preference.room
                roomDistances[room] = math.min(roomDistances[room] or distance, distance)
            end
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
        local a, b = first.standing_preference, second.standing_preference
        local firstRoom = a and roomDistances[a.room] or first.distance
        local secondRoom = b and roomDistances[b.room] or second.distance
        if firstRoom ~= secondRoom then return firstRoom < secondRoom end
        local firstOrder, secondOrder = a and a.order or 0, b and b.order or 0
        if firstOrder ~= secondOrder then return firstOrder < secondOrder end
        if first.distance ~= second.distance then return first.distance < second.distance end
        if first.furniture_id ~= second.furniture_id then
            return (first.furniture_id or "") < (second.furniture_id or "")
        end
        return (first.furniture_pair_id or "") < (second.furniture_pair_id or "")
    end)
    return ranked
end

return M
