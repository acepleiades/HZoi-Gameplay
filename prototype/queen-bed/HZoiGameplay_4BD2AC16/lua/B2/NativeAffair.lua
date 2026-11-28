local NativeWitness = require("WitnessNative")

local M = {}
local CHEATER = "Affair_Caught_Cheater"
local OTHER = "Affair_Caught_Mistress"
local HOWLING = "Howling_Affair_Confirmed"

local function cooldownEntries(howling, field)
    local ok, entries = pcall(function()
        local map = howling[field]
        if not map then return end
        -- ModKit exposes native maps as Lua tables or native map wrappers.
        if type(map) ~= "table" or type(map.ToTable) == "function" then map = map:ToTable() end
        local affair = {}
        for id, value in pairs(map) do
            local key, time = tostring(id), tonumber(value)
            if key:lower():find("affair", 1, true) and time and math.abs(time) < math.huge then
                affair[key] = time
            end
        end
        return affair
    end)
    -- false indicates that this map could not be read on the running build.
    return ok and entries or false
end

local function cooldowns(howling)
    return {
        receive = cooldownEntries(howling, "CooltimeMap"),
        failure = cooldownEntries(howling, "FailCooltimeMap"),
    }
end

local function component(actor, name)
    return actor:GetComponent(inzoi.EB2ComponentType[name])
end

local function context(self, target)
    return inzoi.FB2ScriptContext(self:GetEntityId(), target:GetEntityId(), inzoi.EB1ScriptReason.Howling)
end

local function condition(name, first, second)
    local param = inzoi.FB1Condition()
    param.BaseObject = inzoi.EB1BaseObject.Self
    param.Command = inzoi.EB1ConditionType[name]
    param.CompareType = inzoi.EB1CompareType.Equal
    param.UseHand = inzoi.EB1UseHandType.Default
    param.S1, param.S2 = first or "None", second or "None"
    return param
end

local function hasFlag(ctx, flag)
    return inzoi.FB2Script_Relationship.Condition_HasRelationshipFlag(
        ctx, condition("HasRelationshipFlag", flag, "Single")) == true
end

local function removeOtherFlag(ctx)
    local param = inzoi.FB1Execute()
    param.BaseObject = inzoi.EB1BaseObject.Self
    param.Command = inzoi.EB1ExecuteType.RemoveRelationshipFlag
    param.S1, param.S2 = OTHER, "None"
    param.Prob = 1
    inzoi.FB2Script_Relationship.Execute_RemoveRelationshipFlag(ctx, param)
end

function M.deliver(witness, cheater, other)
    if not (witness and cheater and other) then return {code = "participant_unavailable"} end
    local relationships = component(witness, "Relationship")
    local howling = component(witness, "Howling")
    if not (relationships and howling) then return {code = "native_components_unavailable"} end

    local pair = context(witness, cheater)
    if not NativeWitness.isOfficialPartner(witness, cheater) or witness:HasTag("Exclude_Cheat")
        or not inzoi.FB2Script_Relationship.Condition_IsLovable(pair, condition("IsLovable")) then
        return {code = "native_witness_ineligible"}
    end
    local companion = context(witness, other)
    if relationships:GetRelationshipFlagTotalCount(CHEATER) ~= 0
        or relationships:GetRelationshipFlagTotalCount(OTHER) ~= 0
        or hasFlag(pair, CHEATER) or hasFlag(companion, OTHER) then
        return {code = "native_confrontation_pending", cooldowns = {before = cooldowns(howling)}}
    end
    local gloating = inzoi.FB2Script_Trait.Condition_TraitGroup(
        pair, condition("TraitGroup", "TraitGroup_Affair_Witness_Gloat"))

    -- The native effect adds the cheater role. Its Coop uses a second flag to
    -- recruit the recorded other Zoi when the original native activity is absent.
    local before = cooldowns(howling)
    local ok, processed, primary = pcall(function()
        if not gloating then
            relationships:AddRelationshipFlag(other:GetEntityId(), OTHER)
            assert(hasFlag(companion, OTHER), "Native other-participant binding unavailable")
        end
        local accepted = howling:OnReceiveHowling(HOWLING, cheater:GetEntityId())
        return accepted == true, hasFlag(pair, CHEATER)
    end)

    if not ok or not primary then
        local trace = {before = before, after = cooldowns(howling)}
        if not gloating and hasFlag(companion, OTHER) then
            removeOtherFlag(companion)
            if hasFlag(companion, OTHER) then return {code = "native_role_rollback_failed", cooldowns = trace} end
        end
        if not ok then
            return {code = "native_delivery_failed", error = tostring(processed), cooldowns = trace}
        end
        return {code = "native_witness_declined", receiver = processed, primary_flag = false, other_flag = false,
            cooldowns = trace}
    end
    return {code = "native_witness_processed", receiver = processed, primary_flag = true, other_flag = not gloating}
end

return M
