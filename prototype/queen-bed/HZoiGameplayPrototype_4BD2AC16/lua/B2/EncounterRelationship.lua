local M = {}

-- Set the Mood's native relationship amounts. Partial completion earns half the full bonus.
local CHANGES = {refusal = -5, partial = 5, full = 10}

local function familyMatches(context, reference, comparison)
    local condition = inzoi.FB1Condition()
    condition.BaseObject = inzoi.EB1BaseObject.Target
    condition.Command = inzoi.EB1ConditionType.IsFamilyRelationship
    condition.CompareType = comparison
    condition.S1, condition.S2 = reference, "None"
    return inzoi.FB2Script_Family.Condition_IsFamilyRelationship(context, condition) == true
end

local function relationshipStat(context, outcome)
    local compare = inzoi.EB1CompareType
    if outcome == "refusal" and familyMatches(context, "Spouse", compare.Equal) then return "Family" end
    if familyMatches(context, "None", compare.NotEqual) then return "Romance" end
    if outcome ~= "refusal" and familyMatches(context, "None", compare.Equal) then return "Family" end
end

local function score(person, target, stat)
    local relationships = person:GetComponent(inzoi.EB2ComponentType.Relationship)
    local data = relationships and relationships:FindRelationshipStatData(target, stat)
    return data and data.Value
end

local function settle(attempt, initiator, partner, outcome)
    if attempt.relationshipSettled then return end
    attempt.relationshipSettled = true
    local effect = {outcome = outcome}
    if not initiator or not partner then
        effect.skipped = "participant_unavailable"
        return effect
    end

    local initiatorId, partnerId = initiator:GetEntityId(), partner:GetEntityId()
    local context = inzoi.FB2ScriptContext(initiatorId, partnerId, inzoi.EB1ScriptReason.Coop)
    local stat = relationshipStat(context, outcome)
    if not stat then
        effect.skipped = "no_native_relationship_branch"
        return effect
    end

    local command = inzoi.FB1Execute()
    command.BaseObject = inzoi.EB1BaseObject.Self
    command.Command = inzoi.EB1ExecuteType.AddRelationship
    command.S1, command.S2, command.F1, command.Prob = stat, "None", CHANGES[outcome], 1
    effect.stat, effect.requested_delta = stat, command.F1
    effect.initiator_before = score(initiator, partnerId, stat)
    effect.partner_before = score(partner, initiatorId, stat)
    inzoi.FB2Script_Relationship.Execute_AddRelationship(context, command)
    effect.initiator_after = score(initiator, partnerId, stat)
    effect.partner_after = score(partner, initiatorId, stat)
    return effect
end

function M.onRefusal(attempt, initiator, partner)
    return settle(attempt, initiator, partner, "refusal")
end

function M.onResult(attempt, encounter, result, initiator, partner)
    -- A native relationship reward is bilateral. Group settlement is a separate policy.
    if not result.apply_outcome or #encounter.participants ~= 2 then return end
    local completed = 0
    for _, who in ipairs(encounter.participants) do
        local counts = encounter.completions[who]
        if counts and (counts.excitement or 0) > 0 then completed = completed + 1 end
    end
    if completed > 0 then
        return settle(attempt, initiator, partner, completed == #encounter.participants and "full" or "partial")
    end
end

return M
