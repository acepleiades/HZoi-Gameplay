# How HZoi Gameplay encounters work

HZoi Gameplay lets two Zois propose sex, find a place to go, and react to what
happens. Try **Have Sex Here** if you already have a spot in mind. Use **Have Sex**
from the Romance menu if you want the pair to find a place. A Zoi with autonomy
enabled can also make an invitation independently.

HZoi Gameplay handles the invitation, walk, privacy checks, and consequences.
SceneZOI chooses and plays compatible animations, tracks goals, and restores
the Zois when the session ends. A session can play several scenes in sequence.
Animation packs supply the scenes for each pair and venue.

## Player interaction

Click a supported bed, sofa, or clear spot on the ground and choose **Have Sex
Here**. Select one partner in the game's picker and click **Invite**. If nobody
qualifies, the picker stays closed. If the selected Zoi becomes ineligible
while the picker is open, the invitation stops there. The game also requires
the initiator to leave their group and close any other open picker first.

To invite a specific Zoi and let the pair choose the location, click that Zoi
and choose **Romance → Have Sex**. This uses the same venue search as an
autonomous invitation. Both menu options use the burning heart icon.

### Who can invite whom

HZoi Gameplay uses inZOI's **Set the Mood** relationship and mood rules. The
score is read from the initiator toward the partner.

| Relationship | Minimum score |
| --- | --- |
| Uncommitted pair | Romance 30 |
| Committed lovers or fiancés | Romance −30 |
| Spouses | Family −30 |

The game also checks whether the pair can use a romantic interaction and
whether either Zoi is from a remote city. The initiator's mood can block the
invitation. The partner's mood and relationship affect the answer. See the
[native Set the Mood rules](inzoi-romance.md#set-the-mood-next-to-bed-menu-rules).

Eligibility follows the game's relationship scores and `IsLovable` check.
That keeps the invitation rules usable for new life stages as long as the
native relationship system supports them. A stage with a new engine flag may
also need to be enabled on the menu entries. HZoi Gameplay can use a sofa,
single bed, or standing spot as well as a double bed.

### Content check and invitation

Before the Zois talk, SceneZOI checks that the installed packs can play scenes
for this pair at this venue and give both Zois a path to completing
**Excitement**. The same check handles mixed-sex and same-sex pairs. A pack can
add support for a pair by supplying a compatible route. The player gets a
message if SceneZOI can't find one. See the
[request and animation requirements](autonomous-scene-start.md).

1. The initiator walks up to the partner and asks using the native **Set the
   Mood** conversation. During the invitation, the action queue shows
   **Invite To Have Sex**.
2. A confirmed refusal ends the attempt and applies the
   [relationship loss](#romance-changes). If the conversation is canceled
   before the answer, the relationship score stays as it was.
3. On acceptance, both Zois walk to separate spots near the venue. HZoi
   Gameplay rechecks the pair, venue, and arrival points, then checks
   [who can see them](#arrival-privacy-check) before asking SceneZOI to play.

Switching the controlled Zoi during the conversation or walk lets the pair
carry on. A temporary path blockage can trigger a short, native walk to a
nearby reachable spot and another invitation attempt. An explicit player
action can take priority during recovery.

### Venue arrival and pathfinding

The single bed in a narrow aisle is the benchmark for every venue. Both Zois
need separate reachable spots near the selected furniture or standing anchor.
They can approach a bed from the same side or use the aisle between two beds.
For player-directed attempts, HZoi Gameplay can try nearby points or send a
Zoi back after being displaced while waiting for a partner. Arrival checks
keep the pair on the intended floor and, indoors, in the intended room.
SceneZOI reserves the selected sofa seat pair and leaves spare seats out of
that reservation. See the [invitation and arrival tests](../prototype/queen-bed/README.md#test-in-game).

## NPC initiative

An autonomous invitation uses the same relationship rules, native conversation,
and playback as a player invitation. A Zoi can initiate while under player
control if their effective autonomy setting is enabled. An available partner
can answer with autonomy disabled. These rules apply to loaded Zois within
100 meters of each other. The pair can be away from the controlled Zoi and
across a lot boundary.

The scheduler checks every five real-time seconds while the simulation runs.
Each eligible pair has a 1 in 12 chance per check, with up to one invitation
started per check. A Zoi near the end of a routine autonomous task can be
considered, and the invitation waits for that task to finish. Existing player
actions, conversations, invitations, and sessions take priority. Turning off
the initiator's autonomy during preparation can cancel the attempt.

An attempted invitation starts a 15-minute in-game retry window for the pair.
Once an autonomous encounter actually starts playing, the sender gets a
randomized 32–48 in-game-hour cooldown, weighted toward 40 hours. That Zoi can
still receive invitations from other eligible Zois. A refusal or failed start
uses the short retry window. Player-directed invitations follow the normal
eligibility rules throughout.

## Automatic venue selection

For autonomous invitations and **Have Sex**, the pair searches reachable indoor
rooms. It checks vacant rooms first, then considers occupied rooms if no vacant
room works. Within each pass, the search prefers the nearest suitable venue in
each tier, in this order.

1. The initiator's assigned bed.
2. A double bed.
3. A single bed.
4. A sofa with two available adjacent seats.
5. Two walkable standing spots, favoring open space near the center of a room.

A vacant room with standing space can win over a free bed in an occupied room.
Residential rooms can have any purpose. At commercial sites, the search needs
a native accommodation booking for both Zois that identifies the room. Both
Zois need permission and a walkable route to the selected spots. The room is
claimed until the attempt is canceled or the session ends. Other pairs can use
their own rooms at the same time. When no venue qualifies, a player-directed
invitation reports the problem. See the [venue rules and test cases](../prototype/queen-bed/npc-venues.md).

## Arrival privacy check

Right before playback, HZoi Gameplay checks any nearby Zoi within nine meters
who can see either of the pair's arrival points. The trace checks both
Visibility and WorldStatic, so a solid wall or closed door can protect the
room even when the game camera cuts the wall away. An open doorway can expose
the spot if the door itself and the rest of the geometry leave a clear view.

Every visible observer must pass one of these checks. The scores run from the
observer toward each participant.

- **Romance 30 or higher with every participant.**
- **Romance 30 or higher with every opposite-sex participant and Friendship 30
  or higher with every same-sex participant.** This route requires at least
  one opposite-sex participant. For a pair of the observer's own sex, only the
  first route applies.

For example, a woman with Friendship 50 toward the woman in a mixed-sex pair
also needs Romance 30 with the man to qualify through the second route. If
anyone fails the check, the encounter is called off before playback and the
venue is released. **They need more privacy.** appears only when the player is
controlling the initiator. The relationship score stays as it was.

### Bystander speech at playback start

A qualifying bystander still in view can make one short comment when playback
begins and then go about their business. The Troublemaker, Charmer, and Recluse
have their own pools of five lines. Other Zois use the general pool. A bystander
who stays in view is treated as already present. If they move away and come
back into view, the walk-in rules apply. An official partner who sees an
intimate action can still trigger the cheating reaction.

## Playback and consequences

Auto mode starts a SceneZOI session with an **Excitement** goal for each Zoi.
The first two stages favor opening activities. The last two favor intercourse.
As the leading Zoi reaches 25%, 50%, and 75%, SceneZOI considers the next stage.
The four playback speeds are 1×, 1×, 1.5×, and 2×. The planner can keep an
eligible loop or use fewer scenes when the pack has fewer choices. It follows
authored transition clips between scenes and switches directly when the route
has none. See the [full Auto action policy](autonomous-scene-start.md#automatic-action-policy).

With Auto on, the session normally ends six seconds after both goals are
complete at Normal simulation speed, once any active completion effects
settle. Turn Auto off to choose scenes and speed manually. Use **Exit**
to finish a manual session. If the last goal completes in manual mode,
turning Auto back on skips the six-second stay once active effects settle.
SceneZOI restores both Zois to their arrival positions.

### Romance changes

HZoi Gameplay uses the native relationship command. It requests changes to
Romance for unmarried pairs and to Family for spouses. The normal inZOI score
limits still apply.

| What happened | Requested change |
| --- | ---: |
| The partner refuses | −5 when the refusal is confirmed |
| The invitation is accepted, canceled, or fails to start | 0 |
| The session ends normally and neither Zoi completes the goal | 0 |
| The session ends normally and one Zoi completes the goal | +5 after cleanup |
| The session ends normally and both Zois complete the goal | +10 after cleanup |

Normal endings include manual Exit and a walk-in stop requested by HZoi
Gameplay. Two completions by one Zoi still count as a partial outcome. A
technical stop or an unknown ending result earns no final relationship bonus.
See the [native relationship effects](inzoi-romance.md#set-the-mood-romance-effects).

### Needs on each Excitement completion

Each time a Zoi completes Excitement, that Zoi loses 12.5 Hunger, Hygiene, and
Energy points and gains 5 Fun and Social points. HZoi's costs stop at 33% of
the need's range. A need already below that point stays where it is when the
cost is applied. Natural decay can continue, and gains stop at the normal
maximum. These changes take effect during playback, even when the encounter
ends early or the other Zoi hasn't finished.

### Player feedback when a session ends

If a walk-in ends the session, SceneZOI can show **Session ended** with a short
localized explanation. The player must control a participant both when HZoi
requests the stop and when cleanup finishes. **Dismiss** counts down from ten
real-time seconds. Switching to an uninvolved Zoi closes the notice and
switching back leaves it closed. Technical error panels stay up for manual
dismissal. See [SceneZOI's session outcome API](https://github.com/acepleiades/SceneZOI/blob/main/docs/addon-controls.md#observation-and-outcomes)
and the [in-game language instructions](../README.md#play-in-another-language).

## Witnesses and cheating

During an intimate action, a walk-in needs a clear view of both Zois in that
action. Zois can enter during playback, and opening a door can change what
they can see.

### What the witness does

An official partner's cheating reaction takes priority. For other witnesses,
use the highest Romance score from the witness toward either participant.

| Witness's highest Romance | Reaction |
| --- | --- |
| Below 30 | Surprised and prefers to leave |
| 30 to below 60 | Surprised, comments with more familiarity, and prefers to leave |
| 60 or higher | Surprised, makes a familiar remark, and can carry on in the room |

A walk-away action is queued for an idle NPC with a reachable place to go.
Controlled Zois and those already busy keep their actions. Overhead witness
dialogue starts at the Teenager stage. Younger witnesses can still react and
walk away. HZoi's overhead lines last five real-time seconds.

### How the participants react

Each participant reacts to an ordinary walk-in according to personality. A
witness with Romance 30 or higher toward a particular participant suppresses
that participant's stop vote and their negative reaction to being seen. For
example, if a stranger walks in on a Perfectionist and a Recluse, both normally
vote to stop. If the witness has Romance 30 with the Recluse, only the
Perfectionist votes to stop. The Perfectionist can still say a line about the
distraction and the session continues after the tied vote.

The session stops if more than half the participants vote to stop over the
same sighting. Each sighting gets its own vote. A Zoi who has a relevant speech
line can say it even when the session continues. Perfectionists express
distraction, Recluses express embarrassment, and the general pool expresses
awkwardness. Each participant speaks at most once per session. See the
[English speech lines](../prototype/queen-bed/speech-text.csv).

An official-partner sighting normally makes each participant vote to stop.
A Rulebreaker or a Zoi with the Flirt characteristic prefers to continue.
The cheating incident still counts even if the vote lets playback continue.

### Native cheating reaction

When a lover, fiancé, or spouse catches their official partner, HZoi Gameplay
records the witness, both involved Zois, and the session. After SceneZOI
confirms restoration, HZoi Gameplay passes those roles to inZOI's native
affair reaction once per witness and involved partner. The game supplies its
normal reaction and relationship consequences. See the
[vanilla cheating test findings](inzoi-romance.md#conclusions-from-the-tests).

## Outcome moodlets and personality

Both Zois reaching their goals can earn **In Sync**. If only one finishes, that
Zoi can get **Satisfied** while the other gets **Out of Sync**. When nobody
finishes, a walk-in stop can lead to **Awkward Timing**, and a manual exit can
lead to **Unfinished Moment**.

Personality, characteristics, and aptitudes can change the moodlet. A
Perfectionist can get **Out of Order** when only one Zoi finishes. A Recluse
can get **Nowhere to Hide** after a stranger walks in. A Zoi can receive a
completion moodlet and a separate witness moodlet from the same session. For
the complete rules, see [`TraitOutcomes.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/TraitOutcomes.lua)
and [`EncounterConsequences.lua`](../prototype/queen-bed/HZoiGameplay_4BD2AC16/lua/B2/EncounterConsequences.lua).
The [English moodlet texts](../prototype/queen-bed/moodlet-text.csv) and
[locale catalogs](../prototype/queen-bed/localization/) contain the wording.

### SceneZOI failure signals

Use `session_started` to confirm playback. A request can be accepted and
still fail during preparation. HZoi Gameplay settles an encounter from
`session_start_failed` or `session_ended`. If it misses the end event, it can
ask `get_session_result`. A missing result leaves unverified outcomes unknown.
A technical stop grants no new outcome moodlet or relationship bonus. Verified
need changes remain, and confirmed sightings can still be handled after
restoration. Read the
[SceneZOI outcomes and cleanup fields](https://github.com/acepleiades/SceneZOI/blob/main/docs/addon-controls.md#observation-and-outcomes)
for the event fields and stop reasons.

## Acceptance checks

Use a disposable save and start with one ordinary invitation. Then vary one
condition at a time so you can tell what caused the result.

1. Try acceptance and refusal from the venue picker and the Romance menu.
   Test a wall-side bed, a narrow single-bed aisle, a sofa with a spare seat,
   and standing on clear ground. Switch control during the conversation and
   again during the walk. Try a pair that has no compatible animation route.
2. Compare a private room with an occupied room, a closed door with an open
   one, and a familiar witness with a stranger. Check a tied walk-in vote
   and confirm that the participant can speak while playback continues.
   Try a verified official-partner sighting and check the native reaction.
3. End an encounter with zero, one, and two completed goals. Check the
   relationship change, needs, moodlets, and return to normal gameplay. For
   a walk-in stop, check the countdown while controlling a participant and
   switch away to verify the notice closes.
4. Let a controlled Zoi with autonomy on invite an available partner. Check
   that the partner can answer with autonomy off. Compare the short retry
   after refusal with the sender cooldown after playback actually starts.

For more cases, see the [in-game invitation tests](../prototype/queen-bed/README.md#test-in-game),
[venue test matrix](../prototype/queen-bed/npc-venues.md#test-the-venue-search),
and [release verification](release-build.md#verify-the-release-zip).
