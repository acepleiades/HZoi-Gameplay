local M = {}
local REQUIREMENT = 30

local function validGender(value)
    local types = inzoi.EB1GenderType
    return value ~= nil and (value == types.Male or value == types.Female)
end

local function qualifies(observer, roster, readScore)
    local romance = {}
    local allRomantic = true
    for index, participant in ipairs(roster) do
        local score = readScore(observer, participant, "Romance")
        if score == nil then return nil, "romance_unavailable" end
        romance[index] = score
        if score < REQUIREMENT then allRomantic = false end
    end
    if allRomantic then return true end

    local observerGender = observer:GetGenderType()
    if not validGender(observerGender) then return nil, "observer_gender_unavailable" end
    local oppositeSex = false
    for index, participant in ipairs(roster) do
        local gender = participant:GetGenderType()
        if not validGender(gender) then return nil, "participant_gender_unavailable" end
        if gender ~= observerGender then
            oppositeSex = true
            if romance[index] < REQUIREMENT then return false end
        else
            local score = readScore(observer, participant, "Friendship")
            if score == nil then return nil, "friendship_unavailable" end
            if score < REQUIREMENT then return false end
        end
    end
    return oppositeSex
end

-- Return the continuity baseline, a social denial with its witness, or a
-- technical failure that the caller can retry. A native missing score is zero.
function M.evaluate(participantIds, observations, findActor, readScore)
    if type(observations) ~= "table" or #observations > 128 then return nil, "observations_invalid" end
    local roster, participants, qualified = {}, {}, {}
    for _, id in ipairs(participantIds) do
        local person = findActor(id)
        if not person then return nil, "participant_unavailable" end
        roster[#roster + 1], participants[id] = person, true
    end

    local count = 0
    for index, row in pairs(observations) do
        local id = type(row) == "table" and row.id
        if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or index > #observations
            or type(id) ~= "string" or #id > 20 or not id:match("^[1-9]%d*$")
            or participants[id] or qualified[id] then return nil, "observation_invalid" end
        count = count + 1
        local observer = findActor(id)
        if not observer then return nil, "observer_unavailable", id end
        local allowed, reason = qualifies(observer, roster, readScore)
        if allowed == nil then return nil, reason, id end
        if not allowed then return false, "observer_not_qualified", id end
        qualified[id] = true
    end
    if count ~= #observations then return nil, "observations_invalid" end
    return qualified
end

return M
