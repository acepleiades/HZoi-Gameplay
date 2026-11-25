local Ledger = require("EncounterLedger")
local Relationship = require("EncounterRelationship")

local commands, family = {}, "None"
local values = {[1] = {Romance = 20, Family = 45}, [2] = {Romance = 40, Family = 55}}

inzoi = {
    EB1ScriptReason = {Coop = "Coop"}, EB1BaseObject = {Self = "Self", Target = "Target"},
    EB1ConditionType = {IsFamilyRelationship = "IsFamilyRelationship"},
    EB1CompareType = {Equal = "Equal", NotEqual = "NotEqual"},
    EB1ExecuteType = {AddRelationship = "AddRelationship"},
    EB2ComponentType = {Relationship = "Relationship"},
    FB1Condition = function() return {} end,
    FB1Execute = function() return {} end,
    FB2ScriptContext = function(initiator, partner, reason)
        assert(initiator.Value == 1 and partner.Value == 2 and reason == "Coop")
        return {initiator = initiator, partner = partner}
    end,
    FB2Script_Family = {Condition_IsFamilyRelationship = function(_, condition)
        assert(condition.BaseObject == "Target" and condition.Command == "IsFamilyRelationship")
        assert(condition.S2 == "None")
        local matches = condition.S1 == "None" and family ~= "None" or family == condition.S1 and family ~= "None"
        if condition.CompareType == "Equal" then return matches end
        assert(condition.CompareType == "NotEqual")
        return not matches
    end},
    FB2Script_Relationship = {Execute_AddRelationship = function(context, command)
        assert(command.BaseObject == "Self" and command.Command == "AddRelationship")
        assert(command.S2 == "None" and command.Prob == 1)
        commands[#commands + 1] = command
        for _, person in ipairs({context.initiator, context.partner}) do
            local score = values[person.Value]
            score[command.S1] = math.max(-100, math.min(100, score[command.S1] + command.F1))
        end
    end},
}

local function character(id, other)
    return {
        GetEntityId = function() return {Value = id} end,
        GetComponent = function(_, kind)
            assert(kind == "Relationship")
            return {FindRelationshipStatData = function(_, target, stat)
                assert(target.Value == other)
                return {Value = values[id][stat]}
            end}
        end,
    }
end

local initiator, partner = character(1, 2), character(2, 1)
local refusal = {}
local effect = Relationship.onRefusal(refusal, initiator, partner)
assert(effect.stat == "Romance" and effect.requested_delta == -5 and effect.outcome == "refusal")
assert(effect.initiator_before == 20 and effect.initiator_after == 15)
assert(effect.partner_before == 40 and effect.partner_after == 35)
assert(Relationship.onRefusal(refusal, initiator, partner) == nil and #commands == 1)

family = "Spouse"
effect = Relationship.onRefusal({}, initiator, partner)
assert(effect.stat == "Family" and effect.requested_delta == -5 and #commands == 2)
family = "Parent"
assert(Relationship.onRefusal({}, initiator, partner).skipped == "no_native_relationship_branch")
family = "None"

local function normalEnd()
    return {cleanup_complete = true, stop_reason = "ok", stop_origin = {source = "framework"}}
end

local function result(attempt, first, second, facts, countsKnown, started)
    attempt.initiator, attempt.partner = "1", "2"
    local encounter = Ledger.new("route", "test.client", attempt, {"1", "2"})
    encounter.started = started == true
    encounter.completions["1"].excitement = first
    encounter.completions["2"].excitement = second
    local outcome = Ledger.finish(encounter, {result_facts = facts}, countsKnown)
    return Relationship.onResult(attempt, encounter, outcome, initiator, partner)
end

assert(not result({}, 0, 0, normalEnd(), true, true))
assert(not result({}, 1, 1, normalEnd(), true, false))
assert(not result({}, 1, 1, normalEnd(), false, true))
for _, reason in ipairs({"restore_timeout", "runtime_error", "save_requested", "unknown"}) do
    local termination = normalEnd()
    if reason == "restore_timeout" then
        termination.cleanup_complete = false
        termination.cleanup_code = reason
    else
        termination.stop_reason = reason
    end
    assert(not result({}, 1, 1, termination, true, true))
end
assert(#commands == 2, "Ends without a verified eligible outcome leave the relationship alone")

local partial = {}
effect = result(partial, 3, 0, normalEnd(), true, true)
assert(effect.outcome == "partial" and effect.requested_delta == 5 and #commands == 3)
assert(not result(partial, 3, 1, normalEnd(), true, true), "Do not settle a duplicate terminal result")
assert(not result(refusal, 1, 1, normalEnd(), true, true), "One relationship effect per invitation")

values[1].Romance = 96
effect = result({}, 1, 2, normalEnd(), true, true)
assert(effect.outcome == "full" and effect.stat == "Romance" and effect.requested_delta == 10)
assert(effect.initiator_after == 100 and effect.partner_after == 50 and #commands == 4)

family = "Spouse"
local witnessExit = {cleanup_complete = true, stop_reason = "addon_requested",
    stop_origin = {addon_id = "hzoi.gameplay", client_id = "test.client", reason = "caught_by_partner"}}
effect = result({}, 0, 1, witnessExit, true, true)
assert(effect.outcome == "partial" and effect.stat == "Family" and effect.requested_delta == 5)
effect = result({}, 1, 1, witnessExit, true, true)
assert(effect.outcome == "full" and effect.stat == "Family" and effect.requested_delta == 10)
witnessExit.stop_origin.client_id = "foreign"
assert(not result({}, 1, 1, witnessExit, true, true) and #commands == 6)

assert(not Relationship.onResult({}, {participants = {"1", "2", "3"}, completions = {
    ["1"] = {excitement = 1}, ["2"] = {excitement = 1}, ["3"] = {excitement = 1},
}}, {apply_outcome = true}, initiator, partner) and #commands == 6,
    "The two-Zoi reward must not settle a group encounter")

local roster = {"1", "2", "3"}
local route = require("EncounterArguments")({handjob = {sexual_activity = "non_penetrative"}}, "1", roster)
assert(#route.participants == 3 and #route.goals == 3 and route.goals[3].participant_id == "3")
local group = Ledger.new("group", "test.client", {initiator = "1", partner = "2"}, route.participants)
roster[3] = "4"
assert(group.participants[3] == "3", "The ledger owns the roster it validated")
local startedEvent = {name = "session_started", session_id = "group-session", request_id = "group",
    addon_id = "hzoi.gameplay", addon_client_id = "test.client", phase = "playing"}
local observedCompletions = 0
local function checkCompletion(_, id, task, index)
    assert(id == "3" and task == "excitement" and index == 1)
    observedCompletions = observedCompletions + 1
end
startedEvent.participants = {{id = "1"}, {id = "2"}, {id = "2"}}
assert(not Ledger.observe(group, startedEvent, checkCompletion))
startedEvent.participants = {{id = "2"}, {id = "3"}, {id = "1"}}
startedEvent.task_state = {
    {participant_id = "1", task_id = "excitement", completions = 0},
    {participant_id = "2", task_id = "excitement", completions = 0},
    {participant_id = "3", task_id = "excitement", completions = 1},
}
local observed, complete = Ledger.observe(group, startedEvent, checkCompletion)
assert(observed and complete and group.completions["3"].excitement == 1)
assert(Ledger.observe(group, startedEvent, checkCompletion) and observedCompletions == 1)

print("Relationship effects passed native stat selection, refusal, unique participant goals, cleanup, and deduplication.")
