# Build a gameplay mod with SceneZOI

If this is your first ModKit project, start with
[Make your first SceneZOI gameplay add-on](https://github.com/acepleiades/SceneZOI/blob/main/docs/first-gameplay-addon.md).
It takes you from a new project to a working add-on installed in inZOI.
Come back here when you want to see how a released mod handles a particular
part of an encounter.

[`prototype/queen-bed/`](../prototype/queen-bed/) is where HZoi Gameplay's
first queen-bed invitation was built. It still holds the ModKit project source
used for the player release, alongside the tests and build scripts.
[How to build HZoi Gameplay](release-build.md)

- **Start a session.** Read [the invitation code](#add-the-interaction-and-get-an-answer)
  if your mod needs an interaction or picker. If you already have the gameplay
  that leads up to playback, start with [the SceneZOI request](autonomous-scene-start.md).
- **React to a session.** If your mod watches scenes started elsewhere, start
  with [SceneZOI event subscriptions](https://github.com/acepleiades/SceneZOI/blob/main/docs/addons.md#events-and-ownership).
  [The witness code](#handle-witnesses-and-interruptions) shows how HZoi Gameplay
  uses scene snapshots and reacts when a Zoi sees what is happening.

For the full flow from invitation to outcome, read the
[encounter design](encounter-design.md). For help from other authors, ask in
the [OStim/SceneZOI Community Discord](https://discord.gg/RECvhVaRcU).

## Add the interaction and get an answer

Our furniture and ground options open the shared SceneZOI partner picker. The
Romance menu already has a target, so it goes straight to checking the pair.
Autonomous invitations use the same venue search and invitation. The three ways
in meet in one place, [`VenueInvite.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/Components/VenueInvite.lua).
SceneZOI supplies the furniture profiles and shared menu, so an add-on can
support mod-added furniture without maintaining a second list of sofa IDs.
[Shared controls and picker](https://github.com/acepleiades/SceneZOI/blob/main/docs/addon-controls.md)

Start from a native interaction close to what you're making. For HZoi Gameplay
that was **Set the Mood**. We use its conversation and answer rules in our
own `HZoiGameplay_*` rows. When you borrow a sequence, follow it through the
co-op and action rows to see which scripts and effects it runs. The native
bed sequence can change the relationship and trigger an affair event before
bed playback. HZoi keeps the conversation but applies its own consequences
later. The [inZOI romance reference](inzoi-romance.md#set-the-mood-next-to-bed-menu-rules)
shows the original rows and their conditions. Compare them with
[`InteractionBag_patch.json`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/Content/JsonPatch/InteractionBag_patch.json),
[`Coop_patch.json`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/Content/JsonPatch/Coop_patch.json)
and [`InvitationEligibility.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/InvitationEligibility.lua).

**Wait for the conversation to finish.** The opening queue entry can finish
or report a co-op cancellation when the native scheduler takes over. Check
that the expected co-op actually owns both Zois, then wait for its answer
and dialogue to finish. The player might switch to another Zoi during this
time. Keep the participant IDs on the attempt and use the current controlled
Zoi only for things like deciding where to show a toast.
[Invitation fixture](../prototype/queen-bed/test.lua)

## Bring the Zois to the right place

Check that installed content can work for the pair and venue before sending
anyone across the house. With furniture, keep the chosen object ID and, for a
sofa, the exact seat pair ID. With standing scenes, keep the bindings and the
Zoi who anchors the scene at the selected point. Preflight is a check at one
moment in time. After walking, check the same place again before you start.
Another Zoi can take a seat or walk into view in the meantime.
[Venue search and test cases](../prototype/queen-bed/npc-venues.md)

**Let the native game do the walking.** Give the pair separate reachable spots
on the correct floor. Leave enough tolerance for how inZOI ends a walk. For
example, two Zois can reach a single bed from different points along one narrow
aisle. Requiring both to hit exact coordinates would reject a usable bed.
For a walk canceled by overlap, the add-on waits for the native movement to
settle and retries once where it can preserve the same venue. Respect
ordinary player cancellation. See
[`VenuePath.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/VenuePath.lua),
[`BedArrival.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/BedArrival.lua)
and [`VenueApproach.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/VenueApproach.lua).

## Tell SceneZOI how the encounter should progress

Give each participant a scene task and a completion goal. HZoi Gameplay asks
for one Excitement completion per Zoi and lets SceneZOI advance through four
stages as progress builds. For a male and female pair, the early stages
prefer foreplay and the later stages prefer vaginal sex. A pack with limited
variety can still work if its scenes give both Zois a way to finish. Use
`stage_priorities` to express a preference and
`validate_start` to find out whether the installed scenes can satisfy the
whole request. [Worked Lua example and fallback behavior](autonomous-scene-start.md)

A yes from the partner lets you prepare the venue. A successful start reply
means SceneZOI accepted the request. Use `session_started` as evidence of
actual playback. HZoi Gameplay starts the sender's autonomy cooldown at that
point. Once playback ends, use the confirmed result and restored state to
award an outcome. HZoi tracks each task completion by session, participant
and completion index so a repeated message can't award the same effect twice.
[`EncounterLedger.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/EncounterLedger.lua)
· [`EncounterConsequences.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/EncounterConsequences.lua)

## Handle witnesses and interruptions

A Zoi can be nearby and still be behind a wall. HZoi Gameplay requests a
trace in B1 (the presentation environment) and makes the privacy or witness
decision in B2 (the simulation). Before playback, check who can see the
arrival spots. During playback, check who can see both Zois in the current
intimate action. Test an open door, a closed door and the game's cutaway
camera. The on-screen wall is a poor way to infer what the trace hit.
[`WitnessTrace.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B1/WitnessTrace.lua)
· [`ArrivalPrivacy.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/ArrivalPrivacy.lua)
· [`EncounterWitness.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/EncounterWitness.lua)

Keep the reaction to a sighting separate from the decision to stop. A Zoi
can comment even if the other participant votes to continue. If an official
partner catches the pair, remember the witness and both participant IDs.
Start the native confrontation once SceneZOI has restored the Zois so the
game can queue its reactions. For an ordinary stop, your add-on can pass a
localized reason to SceneZOI.
[`WitnessPolicy.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/WitnessPolicy.lua)
· [`NativeAffair.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/NativeAffair.lua)
· [SceneZOI stop and witness examples](https://github.com/acepleiades/SceneZOI/blob/main/docs/addon-authoring.md#a-romantic-partner-catches-the-encounter)

## Give an AI agent the part you want to work on

Point it to the relevant code and its test. Ask it to check the current
SceneZOI SDK and the game's native conditions before proposing new APIs or
duplicating a game interaction. Give it the expected behavior and a save
where it can try the change in game.

| To work on | Read first |
| --- | --- |
| Menu entries and partner eligibility | [Native interaction tests](../prototype/queen-bed/test-invitation-rules.js) and [picker tests](../prototype/queen-bed/test-furniture-click.lua) |
| Venue search and native movement | [Venue tests](../prototype/queen-bed/test-npc-venues.lua) and [approach tests](../prototype/queen-bed/test-venue-approach.lua) |
| Stage selection, interruptions and recovery | [Invitation and playback fixture](../prototype/queen-bed/test.lua) and [SceneZOI API reference](https://github.com/acepleiades/SceneZOI/blob/main/docs/addons.md) |
| Witnesses and relationship changes | [Witness tests](../prototype/queen-bed/test-witness.lua), [trace tests](../prototype/queen-bed/test-witness-trace.lua) and [relationship tests](../prototype/queen-bed/test-relationship.lua) |
| Game text or packaging | [Source and localization notes](../prototype/queen-bed/README.md) and [build guide](release-build.md) |

Try refusal, acceptance, a failed start and an immediate retry. Switch control
during the approach, then Exit a running session and check that both Zois can
take ordinary game actions. Use the automated tests for decisions and repeat
the relevant case in game when it depends on native queues, routing or UI.
