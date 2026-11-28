local M = {}
local MOOD_TAGS = {"Positive_Talk"}

local function check(context, predicate, command, subject, comparison, reference)
    local condition = inzoi.FB1Condition()
    condition.Command = inzoi.EB1ConditionType[command]
    condition.BaseObject = subject
    condition.CompareType = comparison
    condition.UseHand = inzoi.EB1UseHandType.Default
    condition.S1, condition.S2 = reference or "None", "None"
    condition.F1, condition.F2 = 0, 0
    return predicate(context, condition) == true
end

local function atLeast(relationships, partnerId, stat, minimum)
    local score = relationships:FindRelationshipStatData(partnerId, stat)
    return score and type(score.Value) == "number" and score.Value >= minimum
end

function M.moodAllowsInvitation(owner)
    local emotion = owner and owner:GetComponent(inzoi.EB2ComponentType.Emotion)
    return emotion ~= nil and emotion:IsEmotionAvailableForInteraction(MOOD_TAGS) == true
end

-- Use the same directional scores and compatibility as Set the Mood.
function M.canSelect(owner, partner)
    if not owner or not partner then return false end
    local ownerId, partnerId = owner:GetEntityId(), partner:GetEntityId()
    if ownerId.Value == partnerId.Value then return false end
    local relationships = owner:GetComponent(inzoi.EB2ComponentType.Relationship)
    local data = relationships and relationships:FindRelationshipData(partnerId)
    if not data then return false end

    local context = inzoi.FB2ScriptContext(ownerId, partnerId, inzoi.EB1ScriptReason.Coop)
    local base, compare = inzoi.EB1BaseObject, inzoi.EB1CompareType
    if data.bIsFamilyRelationship then
        if not atLeast(relationships, partnerId, "Family", -30)
            or not check(context, inzoi.FB2Script_Family.Condition_IsFamilyRelationship,
                "IsFamilyRelationship", base.Target, compare.Equal, "Spouse") then return false end
    else
        local minimum = 30
        for _, relation in ipairs(data.RelationshipInfoList or {}) do
            local name = tostring(relation.Id):lower()
            if name == "youth_lover" or name == "engagement" then
                minimum = -30
                break
            end
        end
        if not atLeast(relationships, partnerId, "Romance", minimum) then return false end
    end

    local remote = inzoi.FB2Script_City.Condition_IsFromRemoteCity
    return check(context, inzoi.FB2Script_Relationship.Condition_IsLovable, "IsLovable", base.Self, compare.Equal)
        and check(context, remote, "IsFromRemoteCity", base.Self, compare.NotEqual)
        and check(context, remote, "IsFromRemoteCity", base.Target, compare.NotEqual)
end

function M.canInvite(owner, partner)
    return M.moodAllowsInvitation(owner) and M.canSelect(owner, partner)
end

return M
