local model = {romance = 30, family = 30, named = {}}
local firstId, secondId = {Value = 1}, {Value = 2}
local relationships = {
    FindRelationshipData = function(_, id)
        assert(id == secondId)
        return {bIsFamilyRelationship = model.isFamily, RelationshipInfoList = model.named}
    end,
    FindRelationshipStatData = function(_, id, stat)
        assert(id == secondId)
        return {Value = model[stat:lower()]}
    end,
}
local emotion = {
    IsEmotionAvailableForInteraction = function(_, tags)
        assert(#tags == 1 and tags[1] == "Positive_Talk")
        return not model.moodBlocked
    end,
}
local first = {
    GetEntityId = function() return firstId end,
    GetComponent = function(_, kind)
        if kind == "Emotion" then return emotion end
        assert(kind == "Relationship")
        return relationships
    end,
}
local second = {
    GetEntityId = function() return secondId end,
}

inzoi = {
    EB2ComponentType = {Relationship = "Relationship", Emotion = "Emotion"},
    EB1ScriptReason = {Coop = "Coop"},
    EB1ConditionType = {
        IsLovable = "IsLovable", IsFamilyRelationship = "IsFamilyRelationship", IsFromRemoteCity = "IsFromRemoteCity",
    },
    EB1BaseObject = {Self = "Self", Target = "Target"},
    EB1CompareType = {Equal = "Equal", NotEqual = "NotEqual"},
    EB1UseHandType = {Default = "Default"},
    FB1Condition = function() return {} end,
    FB2ScriptContext = function(owner, partner, reason)
        assert(owner == firstId and partner == secondId and reason == "Coop")
        return reason
    end,
    FB2Script_Relationship = {
        Condition_IsLovable = function(_, condition)
            assert(condition.BaseObject == "Self" and condition.Command == "IsLovable")
            return not model.incompatible
        end,
    },
    FB2Script_Family = {
        Condition_IsFamilyRelationship = function(_, condition)
            assert(condition.BaseObject == "Target" and condition.S1 == "Spouse")
            return model.spouse
        end,
    },
    FB2Script_City = {
        Condition_IsFromRemoteCity = function(_, condition)
            assert(condition.CompareType == "NotEqual")
            return model.remote ~= condition.BaseObject
        end,
    },
}

local eligibility = require("InvitationEligibility")
local canInvite = eligibility.canInvite
assert(canInvite(first, second), "An ordinary pair at Romance 30 can initiate")
model.moodBlocked = true
assert(eligibility.canSelect(first, second) and not canInvite(first, second),
    "Only the initiator's native mood blocks a compatible invitation")
model.moodBlocked = false
model.romance = 29
assert(not canInvite(first, second))
for _, named in ipairs({"Youth_Lover", "engagement"}) do
    model.named, model.romance = {{Id = named}}, -30
    assert(canInvite(first, second), "A named partner can ask even when refusal is likely")
    model.romance = -31
    assert(not canInvite(first, second))
end
model.isFamily, model.spouse = true, false
assert(not canInvite(first, second), "Only spouses qualify through the family branch")
model.spouse, model.family = true, -30
assert(canInvite(first, second))
model.family = -31
assert(not canInvite(first, second))
model.family, model.remote = 30, "Target"
assert(not canInvite(first, second))
model.remote = "Self"
assert(not canInvite(first, second))
model.remote, model.incompatible = nil, true
assert(not canInvite(first, second))
model.incompatible = false
assert(canInvite(first, second), "The current native relationship checks supply eligibility without a separate life-stage rule")
