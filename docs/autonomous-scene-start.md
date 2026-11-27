# Autonomous SceneZOI encounters

This document describes how HZoi Gameplay starts an autonomous encounter through SceneZOI. It includes the exact Lua request, explains how action metadata guides clip selection and how the four stages set playback speed, and outlines the in-game checks from validating the pair and venue to reading the result after exit.

## Start request

Call `get_version` with empty arguments and require value `1` in `reply.result.features` for `autonomous_scenes`, `autonomous_stages`, `autonomous_stage_progress`, `autonomous_stage_priorities`, `autonomous_auto_restrictions`, `autonomous_joint_goal_routes`, `autonomous_post_completion_stay`, `autonomous_manual_completion_exit`, and `autonomous_auto_speed_minimum`. Call `get_definitions` with empty arguments and use `reply.result.actions`, a map keyed by registered action ID. Use successful replies for both operations.

SceneZOI's `sexual_activity` categories are `non_penetrative` (external stimulation), `penetrative_non_coital` (penetration other than vaginal intercourse), and `coital` (vaginal intercourse). The optional field is independent of `content_rating`. Verify that the host returns `handjob`, `fellatio`, and `vaginal_sex` in those respective categories before testing the bundled HZoi clips. HZoi uses the first two categories for initial sexual activity. Anal intercourse belongs to the intercourse tier and is eligible only for a male/male pair. The scene queries take the resulting action IDs.

```lua
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
        auto_speed = {start = 0.5, finish = 2, minimum = 1},
        post_completion_stay_seconds = 6,
        skip_post_completion_stay_after_manual = true,
        placement = {exit = "restore"},
    }
end
```

Pass the full roster as decimal strings. For the iteration 1 invitation, set `allowAnalIntercourse` from the selected pair's male/male eligibility. SceneZOI checks the authored roles and body requirements. For ground, omit both furniture IDs and send the anchor-role Zoi to the selected point. The current HZoi ground clips use the `male` role, so read that participant ID from the preflight's `bindings.male`. For furniture, use the selected ID and pass the slot-pair ID returned by `find_furniture` for sofas.

Before the invitation, call `validate_start` with a shallow copy of the arguments and `start_mode = "start_autonomous_scene"`. Stage 1 ranks a viable opening activity first and can select intercourse when that is the best available entry. Check `reply.ok`, `reply.result.valid`, and whether `route_uncertain` is true. An uncertain route needs further verification before treating the content as available. A proven route covers every goal across reachable clips. Asset loading and placement are checked again at startup.

```lua
local arguments, reason = makeEncounterArguments(
    definitionsReply.result.actions, initiatorId, {initiatorId, partnerId},
    furnitureId, furniturePairId, allowAnalIntercourse
)
if not arguments then return nil, reason end

local preflight = {start_mode = "start_autonomous_scene"}
for key, value in pairs(arguments) do preflight[key] = value end
client:request(owner, preflightRequestId, "validate_start", preflight)
```

After the iteration 1 partner accepts the [two-Zoi invitation](encounter-design.md#content-check-and-invitation) and both Zois arrive, repeat `validate_start` with a new request ID. Pin the initial scene, roles, and slot pair from that successful response. Run the [arrival sight check](encounter-design.md#arrival-privacy-check) before sending `start_autonomous_scene` with a distinct request ID. Check `reply.ok` and `reply.result.accepted`, then wait for `session_started` or `session_start_failed`.

```lua
local ready = arrivalReply.result
arguments.scene_id = ready.scene_id
arguments.bindings = ready.bindings
arguments.furniture_pair_id = ready.furniture_pair_id or arguments.furniture_pair_id
client:request(owner, startRequestId, "start_autonomous_scene", arguments)
```

The leading participant's progress makes stages 2–4 due at 25%, 50%, and 75%. Auto selects a speed preset at each stage, with a 1× minimum and a 2× final preset. Stages 1–2 favor opening activities and stages 3–4 favor intercourse. Within a tier, SceneZOI prefers an eligible clip whose activity group has yet to play. Each scene ID is its own group in this request. The planner can switch clips if progress stalls or keep the current clip if it is the best reachable choice. All goals can be met before stage 4. The bundled HZoi intercourse clips support both roles reaching completion in the same loop.

| Venue | Current HZoi intercourse clips for a supported pair |
| --- | --- |
| Queen bed and single bed | Two positions when the optional AAL tracks are available, otherwise one. |
| Sofa and ground | One position. |

Use `session_ended` and its task counts to evaluate final outcomes. `task_completed` supports need changes during playback, including repeated completions.

If more than half of the roster votes to stop after a witness sees the encounter, HZoi calls `request_stop` for the session. It sends `witness_sighting` or `caught_by_partner` as the machine-readable `reason`. With SceneZOI's `stop_session_display_reason` feature, HZoi also sends a short `display_reason` explaining why the session ended. SceneZOI displays it with the session result and dismisses the panel automatically after normal cleanup.

## Automatic action policy

HZoi builds an Auto-only exclusion list from all registered explicit actions outside the approved sets. Manual navigation follows ordinary SceneZOI compatibility. An action's classification alone does not approve it for automatic selection. Adult surveys informed the broad defaults. A U.S. probability survey found widespread lifetime participation in oral and vaginal sex. A separate study of male-partnered encounters reported oral sex and partnered masturbation more frequently than anal sex. The male-pair anal exception follows the HZoi design rule. [U.S. probability survey](https://pubmed.ncbi.nlm.nih.gov/28727762/) · [Male-partnered encounter study](https://onlinelibrary.wiley.com/doi/10.1111/j.1743-6109.2011.02438.x).

| Automatic eligibility | SceneZOI explicit action IDs |
| --- | --- |
| Opening activity, non-penetrative | `handjob`, `cunnilingus`, `vulval_rubbing`, `penile_licking`, `vulval_licking` |
| Opening activity, penetrative non-coital | `fellatio`, `vaginal_fingering` |
| Supporting actions | `holding_penis_at_base`, `groping_breast`, `groping_butt`, `licking_nipple`, `sucking_nipple` |
| Intercourse | `vaginal_sex` and, for a male/male pair only, `anal_sex` |
| Manual, specialty actions or specific variants | `anal_fingering`, `anal_fisting`, `anal_licking`, `anal_toying`, `anilingus`, `breast_job`, `breast_slapping`, `breast_sliding`, `breast_smothering`, `butt_smothering`, `buttjob`, `deep_throating`, `oral_fingering`, `oral_toying`, `rubbing_penis_against_face`, `scrotal_licking`, `ejaculation_on_butt`, `ejaculation_on_chest`, `ejaculation_on_face`, `ejaculation_on_vulva`, `footjob`, `grinding_foot`, `grinding_object`, `grinding_penis`, `grinding_thigh`, `thighjob`, `groping_testicles`, `vaginal_fisting`, `vaginal_toying` |
| Manual, pending clearer participant metadata or a specific preference | `penile_masturbation`, `vulval_masturbation`, `tribadism`, `unspecified_action` |

The companion exclusions in the request also cover five suggestive-rated actions that could otherwise appear alongside an allowed action. The current HZoi loops remain eligible under both filters.
