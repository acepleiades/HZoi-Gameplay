-- Edit this list to configure the life stages eligible for HZoi invitations.
-- Values are the positive one-bit EB1GrowthStep values used in native bag rows.
local stages = {
    Youth = 32,
    Adult = 64,
    Old = 128,
    Elderly = 256,
}

local allowed = {}
for _, stage in pairs(stages) do allowed[stage] = true end

local M = {}

function M.allows(stage)
    return allowed[stage] == true
end

function M.allowsCharacter(character)
    return character ~= nil and M.allows(character:GetGrowthStep())
end

return M
