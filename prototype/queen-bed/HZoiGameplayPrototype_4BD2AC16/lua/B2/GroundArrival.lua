local M = {}

function M.walkable(floor, point)
    return floor ~= nil and floor:IsOnWalkableGrid(point) == true
end

function M.partnerPoint(floor, anchor, partner)
    if not M.walkable(floor, anchor) then return end
    local facing = math.atan(partner.Y - anchor.Y, partner.X - anchor.X)
    for _, distance in ipairs({150, 200}) do
        for _, step in ipairs({0, 1, -1, 2, -2, 3, -3, 4}) do
            local angle = facing + step * math.pi / 4
            local x, y = distance * math.cos(angle), distance * math.sin(angle)
            local function offset(factor)
                return UE.FVector(anchor.X + x * factor, anchor.Y + y * factor, anchor.Z)
            end
            local spot = offset(1)
            if M.walkable(floor, spot) and M.walkable(floor, offset(.5)) then
                return spot
            end
        end
    end
end

return M
