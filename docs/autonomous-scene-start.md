# Starting a SceneZOI session

HZoi Gameplay decides who to invite, whether they accept, and where they go.
SceneZOI chooses compatible animations, runs Auto mode, tracks Excitement and
restores the Zois when the session ends. Animation packs supply the scenes.

This example follows HZoi Gameplay's two-Zoi invitation. The request builder
accepts a roster and gives every participant a goal; the invitation and venue
code currently handle two Zois.

## Before starting playback

1. Check that the installed content can support the selected Zois and venue.
2. Let the native invitation finish. SceneZOI accepting a request does not mean
   the other Zoi accepted the invitation.
3. Walk both Zois to the venue, then check the content and placement again.
4. Confirm privacy at arrival, then ask SceneZOI to start.

Preflight does not reserve Zois or furniture. A valid request can still fail
during preparation if a participant becomes busy or the furniture changes.
The [invitation and arrival rules](encounter-design.md#content-check-and-invitation)
explain the gameplay checks before this handoff.

## Start request

Set up the [SceneZOI SDK](https://github.com/acepleiades/SceneZOI/blob/main/docs/addon-authoring.md#wire-the-sdk)
and negotiate `get_version` first. Use a matching SceneZOI build with the
[autonomous plan features](https://github.com/acepleiades/SceneZOI/blob/main/docs/addons.md#autonomous-scenes).
Call `get_definitions` to read its registered actions and tasks.

The [request builder](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/EncounterArguments.lua)
is HZoi Gameplay code, separate from the SDK. Copy or adapt that module into
your B2 scripts to use this example. It builds the action filters and the
goal-driven plan from the host's definitions, without naming a content pack's
scene IDs.

Here, `client` is your SDK client and `definitions` is the successful
`get_definitions` result. Use the selected Zois' decimal string IDs and a new
`nonce` for each attempt. The native `carrier` owns the SDK messages; it does
not have to be one of the participants.
Set `allowAnalIntercourse` from the selected pair's male/male eligibility.
The example uses a `phase` of `"before_walk"` or `"arrival"` so that each
preflight has its own request ID. A reused request ID would ask for the
original reply again.

```lua
local makeArguments = require("EncounterArguments")
local arguments, reason = makeArguments(
    definitions.actions, initiatorId, {initiatorId, partnerId},
    furnitureId, furniturePairId, allowAnalIntercourse
)
if not arguments then return nil, reason end

local validateId = "encounter." .. nonce .. ".validate." .. phase
local startId = "encounter." .. nonce .. ".start"
local preflight = {start_mode = "start_autonomous_scene"}
for key, value in pairs(arguments) do preflight[key] = value end
if phase == "before_walk" then preflight.check_start_distance = false end
client:request(carrier, validateId, "validate_start", preflight)
```

For a bed, pass its `furniture_id`. For a sofa, also pass the
`furniture_pair_id` returned by `find_furniture`. Omit both for ground scenes.
Use preflight's role bindings when placing the Zois. A role name such as
`male` does not mean the initiator or the message carrier. For a standing
scene, keep the planned scene, bindings and anchor Zoi as the pair walks,
then verify them again at arrival.

Before inviting, skip the start distance check because both Zois still have to
walk. The content and venue checks still run. In your response handler, keep
the successful result for planning that walk. Use a fresh arrival preflight
and leave the distance check enabled. Once its response arrives and the
[privacy check](encounter-design.md#arrival-privacy-check) passes, call the
following helper with the arrival reply. It pins the returned scene and
roles before requesting playback.

```lua
local function startAfterPrivacy(reply)
    if phase ~= "arrival" or reply.request_id ~= validateId then return end
    local ready = reply.result
    if not reply.ok or not ready or not ready.valid or ready.route_uncertain then
        print("SceneZOI preflight failed: " .. tostring(
            reply.code or (ready and ready.code) or "route_unconfirmed"))
        return
    end
    arguments.scene_id = ready.scene_id
    arguments.bindings = ready.bindings
    arguments.furniture_pair_id = ready.furniture_pair_id or arguments.furniture_pair_id
    client:request(carrier, startId, "start_autonomous_scene", arguments)
end
```

`validate_start` reports an unavailable route as `result.valid == false`, with
`result.code`. `route_uncertain` means the bounded planner could not prove the
route; HZoi Gameplay does not treat that as confirmed content availability.

Check the start reply for `ok` and `result.accepted`. Then wait for
`session_started` or `session_start_failed`, matched to `startId`. Acceptance
means preparation was queued. Keep the resulting `session_id` for controls,
observations and cleanup. See the real
[invitation handler](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/Components/VenueInvite.lua)
for retries, uncertain acknowledgements and cancellation.

## What Auto mode does

The builder requests one new `excitement` completion for every Zoi, with
`end_policy = {type = "goals"}`. One Zoi finishing is not enough to end the
encounter.

`stages = 4` and `stage_progress = "fastest"` make the leading goal's progress
advance the plan. They do not require four different animations.

| Stage | Becomes due | Preferred activity | Playback preset |
| --- | --- | --- | --- |
| 1 | Entry | Opening activity, then intercourse | 1.0× |
| 2 | Leading goal reaches 25% | Opening activity, then intercourse | 1.0× |
| 3 | Leading goal reaches 50% | Intercourse, then opening activity | 1.5× |
| 4 | Leading goal reaches 75% | Intercourse, then opening activity | 2.0× |

The speed request is `auto_speed = {start = 0.5, finish = 2, minimum = 1}`.
SceneZOI selects the nearest preset at each stage. Task progress uses game
time, separately from this animation-speed ramp.

Within the best available activity tier, Auto prefers a scene that has not
played yet. Each scene ID counts separately in HZoi Gameplay's request.
SceneZOI follows the pack's navigation, plays one-shot transitions on the way,
and skips idle loops used only to connect the route.

After all goals complete, Auto waits six seconds at Normal game speed and lets
authored completion effects finish. The wait follows the game's speed controls
and pauses with the game. Turning Auto off lets the player navigate manually
and pauses planned Exit. If the last outstanding goal completes in manual
mode, turning Auto back on skips that extra wait; completion effects can still
finish before Exit.

## When fewer scenes are available

The activity tiers are preferences. A route must still fit the fixed roster,
venue and restrictions, and be able to complete every goal.

- **No opening activity:** Auto can start with intercourse if that is a viable
  route for the selected Zois.
- **No intercourse:** A compatible opening activity can carry the encounter
  if it can complete every goal. An activity capped below completion may need
  another reachable scene.
- **Only one useful loop:** Auto can keep that loop through the stages. It does
  not need to invent another clip or replay a transition just to fill a slot.
- **All goals finish early:** A goals-driven session can finish before stage
  four. Four stages are not four mandatory visits.
- **No compatible activity:** Report `no_matching_scenes`. If activities match
  but no route can complete all goals, report `goal_unreachable` instead of
  starting a session that cannot finish.

This also applies to packs that support different body combinations. A
registered action is not proof that a matching animation exists. Let SceneZOI
check the actual scenes; do not assume support from the Zois' genders alone.

## Automatic action policy

The builder reads each registered action's `sexual_activity` and
`content_rating`, then applies these HZoi Gameplay rules.

| Role in the encounter | Approved actions |
| --- | --- |
| Opening activity | `handjob`, `fellatio`, `cunnilingus`, `vaginal_fingering`, `vulval_rubbing`, `penile_licking`, `vulval_licking` |
| Intercourse | `vaginal_sex`; `anal_sex` only for the current male/male invitation rule |
| Supporting activity | `holding_penis_at_base`, `groping_breast`, `groping_butt`, `licking_nipple`, `sucking_nipple` |

Opening actions must also have the expected non-penetrative or penetrative
non-coital classification. Classification alone does not approve an action.
Supporting actions may accompany an eligible activity; they do not qualify a
scene as an entry by themselves.

Other explicit actions, plus the listed companion exclusions in the builder,
are excluded through `auto_restrictions`. Turning Auto off removes that
Auto-only filter. Manual navigation still respects SceneZOI's technical
compatibility and any session-wide restrictions. The
[metadata guide](https://github.com/acepleiades/SceneZOI/blob/main/docs/scene-metadata.md)
explains action definitions and calculated ratings.

## Read what actually happened

Use `task_completed` for effects earned during playback. Count each
participant's completion once. On `session_ended`, inspect the final goal
counts, `plan.outcome`, and `result_facts.cleanup_complete` before applying an
outcome that requires restoration. A request being accepted is not an earned
completion. The [encounter ledger](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/EncounterLedger.lua)
shows how HZoi Gameplay correlates the owner, roster and session and reconciles
events with task counts from later snapshots.

If an acknowledgement or event is missed, query `get_request_status` with the
original start request ID, or `get_session_result` with the known session ID.
Do not assume a transport timeout means playback never started. Retry the
same request with the same ID; use a new ID for a new attempt.

HZoi Gameplay can also ask SceneZOI to stop after a walk-in. That sends an
owned `request_stop`, with a machine-readable reason and a localized
`display_reason`. The [witness rules](encounter-design.md#witnesses-and-cheating)
decide when to stop; SceneZOI handles playback cleanup and the ending panel.
