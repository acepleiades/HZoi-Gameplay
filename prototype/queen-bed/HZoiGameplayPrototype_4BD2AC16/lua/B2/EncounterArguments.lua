local openingPolicy = {
    handjob = true, fellatio = true, cunnilingus = true,
    vaginal_fingering = true, vulval_rubbing = true,
    penile_licking = true, vulval_licking = true,
}
local supportingPolicy = {
    holding_penis_at_base = true, groping_breast = true, groping_butt = true,
    licking_nipple = true, sucking_nipple = true,
}
local excludedPolicy = {
    choking = true, kissing_foot = true, pulling_hair = true,
    spanking = true, tickling_foot = true,
}

local function matchesInOrder(first, second)
    local matches = {}
    if first then matches[#matches + 1] = first end
    if second then matches[#matches + 1] = second end
    return matches
end

local function makeEncounterArguments(actions, initiatorId, participantIds, furnitureId, furniturePairId, allowAnalIntercourse)
    local opening, intercourse, entry, excluded, intercourseOnly = {}, {}, {}, {}, {}
    for id, action in pairs(actions) do
        local activity = action.sexual_activity
        local isOpening = openingPolicy[id] and (
            activity == "non_penetrative" or activity == "penetrative_non_coital"
        )
        local isIntercourse = (id == "vaginal_sex" and activity == "coital")
            or (allowAnalIntercourse and id == "anal_sex" and activity == "penetrative_non_coital")
        if isOpening then opening[#opening + 1] = id end
        if isIntercourse then intercourse[#intercourse + 1] = id end
        if isOpening or isIntercourse then entry[#entry + 1] = id end
        if activity == "coital" or id == "anal_sex" then
            intercourseOnly[#intercourseOnly + 1] = id
        end
        if excludedPolicy[id] or (action.content_rating == "EXPLICIT"
            and not (isOpening or isIntercourse or supportingPolicy[id])) then
            excluded[#excluded + 1] = id
        end
    end
    if #entry == 0 then return nil, "no_matching_scenes" end
    for _, ids in ipairs({opening, intercourse, entry, excluded, intercourseOnly}) do
        table.sort(ids)
    end

    local openingMatch = #opening > 0 and {any_actions = opening} or nil
    if openingMatch and #intercourseOnly > 0 then
        openingMatch.excluded_actions = intercourseOnly
    end
    local intercourseMatch = #intercourse > 0 and {any_actions = intercourse} or nil
    local openingFirst = matchesInOrder(openingMatch, intercourseMatch)
    local intercourseFirst = matchesInOrder(intercourseMatch, openingMatch)
    local goals = {}
    for _, id in ipairs(participantIds) do
        goals[#goals + 1] = {participant_id = id, task_id = "excitement", completions = 1}
    end
    return {
        initiator = initiatorId,
        participants = participantIds,
        furniture_id = furnitureId,
        furniture_pair_id = furniturePairId,
        search = {any_actions = entry},
        goals = goals,
        end_policy = {type = "goals"},
        stages = 4,
        stage_progress = "fastest",
        stage_priorities = {
            {stage = 1, matches = openingFirst},
            {stage = 2, matches = openingFirst},
            {stage = 3, matches = intercourseFirst},
            {stage = 4, matches = intercourseFirst},
        },
        auto_restrictions = #excluded > 0 and {excluded_actions = excluded} or nil,
        auto_speed = {start = 0.5, finish = 2},
        post_completion_stay_seconds = 6,
        skip_post_completion_stay_after_manual = true,
        placement = {exit = "restore"},
    }
end
return makeEncounterArguments
