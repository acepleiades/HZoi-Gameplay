local Affair = require("NativeAffair")
local flags, calls = {}, 0
local function byId(id) return tostring(id.Value) end
local reject, gloat = false, false
local receiveCooldowns, failureCooldowns = {Effect_Affair_Confirmed = 300, OtherEffect = 75}, {}
local CHEATER, OTHER = "Affair_Caught_Cheater", "Affair_Caught_Mistress"

local function makeActor(id, components)
    return {
        GetEntityId = function() return {Value = id} end,
        GetComponent = function(_, kind) return components and components[kind] end,
        HasTag = function() return false end,
    }
end

local witness = makeActor(10, {
    Relationship = {
        GetRelationshipFlagTotalCount = function(_, name)
            local total = 0
            for _, value in pairs(flags) do if value == name then total = total + 1 end end
            return total
        end,
        FindRelationshipData = function(_, who)
            assert(who.Value == 20)
            return {RelationshipInfoList = {{Id = "Youth_Lover"}}}
        end,
        AddRelationshipFlag = function(_, id, name)
            assert(id.Value == 30)
            flags[byId(id)] = name
        end,
    },
    Howling = {
        CooltimeMap = receiveCooldowns,
        FailCooltimeMap = {ToTable = function() return failureCooldowns end},
        OnReceiveHowling = function(_, name, actor)
            assert(name == "Howling_Affair_Confirmed" and actor.Value == 20)
            if not gloat then assert(flags["30"] == OTHER) else assert(not flags["30"]) end
            calls = calls + 1
            if reject then
                failureCooldowns.Effect_Affair_Confirmed = 360
                return false
            end
            flags["20"] = CHEATER
            return true
        end,
    },
    Trait = {HasTrait = function(_, trait) assert(trait == "Flirt"); return gloat end},
})
local cheater, other = makeActor(20), makeActor(30)
inzoi = {
    EB2ComponentType = {Relationship = "Relationship", Howling = "Howling", Trait = "Trait"},
    EB1ScriptReason = {Howling = 1},
    FB2ScriptContext = function(self, target, reason) return {self = self, target = target} end,
    FB1Condition = function() return {} end,
    FB1Execute = function() return {} end,
    EB1BaseObject = {Self = 1},
    EB1ConditionType = {HasRelationshipFlag = 1, IsLovable = 2},
    EB1CompareType = {Equal = 1},
    EB1UseHandType = {Default = 1},
    EB1ExecuteType = {RemoveRelationshipFlag = 1},
    FB2Script_Trait = {Condition_TraitGroup = function(_, param)
        assert(param.S1 == "TraitGroup_Affair_Witness_Gloat"); return gloat
    end},
    FB2Script_Relationship = {
        Condition_HasRelationshipFlag = function(context, param)
            assert(context.self.Value == 10 and param.S2 == "Single")
            return flags[byId(context.target)] == param.S1
        end,
        Condition_IsLovable = function(context) return context.target.Value == 20 end,
        Execute_RemoveRelationshipFlag = function(ctx, param)
            assert(ctx.target.Value == 30 and param.S1 == OTHER)
            flags[byId(ctx.target)] = nil
        end,
    },
}
reject = true
local outcome = Affair.deliver(witness, cheater, other)
assert(outcome.code == "native_witness_declined" and outcome.receiver == false)
assert(outcome.cooldowns.before.receive.Effect_Affair_Confirmed == 300)
assert(outcome.cooldowns.before.receive.OtherEffect == nil)
assert(not next(outcome.cooldowns.before.failure) and outcome.cooldowns.after.failure.Effect_Affair_Confirmed == 360)
assert(next(flags) == nil and calls == 1)
reject = false
outcome = Affair.deliver(witness, cheater, other)
assert(outcome.code == "native_witness_processed" and outcome.primary_flag and outcome.other_flag)
assert(flags["30"] == OTHER and calls == 2)
outcome = Affair.deliver(witness, cheater, other)
assert(outcome.code == "native_confrontation_pending" and calls == 2)
assert(outcome.cooldowns.before.failure.Effect_Affair_Confirmed == 360 and outcome.cooldowns.after == nil)
flags = {}
gloat = true
outcome = Affair.deliver(witness, cheater, other)
assert(outcome.code == "native_witness_processed" and outcome.primary_flag and not outcome.other_flag)
assert(not flags["30"] and calls == 3)
print("Native affair delivery keeps exact roles, cooldown rollback and native trait branches")
