local M = {}

local function validCount(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

function M.new(requestId, clientId, attempt)
    return {
        request_id = requestId,
        client_id = clientId,
        initiator = attempt.initiator,
        partner = attempt.partner,
        participants = {attempt.initiator, attempt.partner},
        furniture = attempt.furniture,
        furniture_pair = attempt.seats and attempt.seats.id,
        kind = attempt.kind,
        completions = {[attempt.initiator] = {}, [attempt.partner] = {}},
    }
end

local function sessionMatches(encounter, snapshot)
    local sessionId = snapshot.session_id or snapshot.id
    if type(sessionId) ~= "string" or sessionId == ""
        or snapshot.request_id ~= encounter.request_id or snapshot.addon_id ~= "hzoi.gameplay"
        or snapshot.addon_client_id ~= encounter.client_id
        or (encounter.session_id and encounter.session_id ~= sessionId) then
        return false
    end

    local roster = snapshot.participants
    if type(roster) ~= "table" or #roster ~= #encounter.participants then return false end
    local seen = {}
    for _, person in ipairs(roster) do
        if not encounter.completions[person.id] or seen[person.id] then return false end
        seen[person.id] = true
    end
    return true
end

local function countEvidence(encounter, snapshot)
    local counts = {}
    local function record(participantId, taskId, count)
        if not encounter.completions[participantId] or taskId ~= "excitement" or not validCount(count) then
            return
        end
        counts[participantId] = math.max(counts[participantId] or 0, count)
    end
    local facts = snapshot.result_facts or {}
    for _, row in ipairs(facts.task_state or snapshot.task_state or {}) do
        record(row.participant_id, row.task_id, row.completions)
    end
    for _, goal in ipairs(snapshot.plan and snapshot.plan.goals or {}) do
        record(goal.participant_id, goal.task_id, goal.completed)
    end
    if snapshot.name == "task_completed" and snapshot.task then
        record(snapshot.participant_id, snapshot.task.id, snapshot.task.completion_index)
    end
    return counts
end

function M.observe(encounter, snapshot, onCompletion)
    if encounter.ended or not sessionMatches(encounter, snapshot) then return false end
    encounter.session_id = snapshot.session_id or snapshot.id
    if not encounter.snapshot or (snapshot.event_index or 0) >= (encounter.snapshot.event_index or 0) then
        encounter.snapshot = snapshot
    end
    local facts = snapshot.result_facts or {}
    if snapshot.name == "session_started" or snapshot.phase == "playing" or (facts.playing_seconds or 0) > 0 then
        encounter.started = true
    end

    local counts = countEvidence(encounter, snapshot)
    local complete = true
    for _, participantId in ipairs(encounter.participants) do
        local finalCount = counts[participantId]
        if finalCount == nil then
            complete = false
        else
            local entry = encounter.completions[participantId]
            local previous = entry.excitement or 0
            entry.excitement = math.max(previous, finalCount)
            for index = previous + 1, finalCount do
                onCompletion(encounter, participantId, "excitement", index)
            end
        end
    end
    return true, complete
end

function M.finish(encounter, snapshot, taskCountsComplete)
    encounter.ended = true
    local facts = snapshot.result_facts or {}
    local origin = facts.stop_origin or {}
    local witness = facts.stop_reason == "addon_requested" and origin.addon_id == "hzoi.gameplay"
        and origin.client_id == encounter.client_id
        and (origin.reason == "witness_sighting" or origin.reason == "caught_by_partner")
    local ordinary = (facts.stop_reason == "ok" and origin.source == "framework") or witness
    return {
        stop_reason = facts.stop_reason,
        stop_origin = facts.stop_origin,
        cleanup_code = facts.cleanup_code,
        cleanup_complete = facts.cleanup_complete == true,
        task_counts_complete = taskCountsComplete,
        plan = snapshot.plan,
        playing_seconds = facts.playing_seconds,
        apply_outcome = encounter.started == true and ordinary == true and facts.cleanup_complete == true
            and taskCountsComplete == true,
    }
end

return M
