# Invitations at beds, sofas, and on the ground

With a Zoi selected, click a supported bed, sofa, or a walkable spot on the ground and choose **Have Sex Here**.
The same picker as SceneZOI debug start opens. Choose one partner and click
**Invite**. Your controlled Zoi is included automatically. The game uses the social
conditions and odds from **Set the Mood Next to Bed**. If the pair can talk
but has less than 30 Romance and isn't an official couple, the partner
refuses through the native conversation. If the answer is yes, both Zois walk to the venue
you clicked. SceneZOI starts once both arrive and the selected spot is still
available.

On beds, both Zois use native walks to separate standing spots. HZoi checks
each Zoi's route inside the venue and uses nearby native bed slots as
landmarks when the usual spots are blocked. The two Zois can approach along
one open side, including the aisle between single beds.

On a sofa, the invitation uses an available adjacent seat pair with room for
both Zois to approach. If someone takes those seats while they are walking,
the attempt ends with a sofa availability message. SceneZOI reserves the
two selected spots for playback. Other seats can still be used.

For the included standing scenes, the Zoi playing the male role walks to the
clicked spot. The other Zoi walks to a separate spot on the same floor.
If the game cancels a walk because two Zois overlap, HZoi waits for the other
walk and the game's recovery movement, then retries once. On a player-selected
queen bed it can choose another spot beside the same bed. The ground anchor
and the selected sofa seats stay fixed. A player cancellation, another walk
failure, or an unavailable spot ends the attempt.

## Test in game

Load the usual test household at Normal speed. Try a free-standing queen bed
and a queen bed with one side against a wall.

1. Compare two uncommitted pairs at Romance 29 and 30. The first pair is
   ineligible. The second pair qualifies if it passes the native eligibility
   checks. For refusal, use an eligible uncommitted pair at Romance 30–60
   with a negative target mood for a 70% chance, or spouses at Family −30
   to below 30 for a 30% chance.
2. On refusal, verify the conversation finishes, neither Zoi is sent to the
   bed, and both can start another game interaction.
3. On acceptance, verify both Zois reach separate points on the same floor
   beside the selected bed. At the wall-side bed, observe where each Zoi
   approaches. Exit SceneZOI and check that both can move again.
4. Repeat both outcomes on the other queen bed and a supported single bed.
   Try a pair of single beds with one narrow aisle between them. Both Zois
   should reach the selected bed when two spots along the aisle are reachable.
   An ordinary object should have no HZoi option. A bed without a compatible
   SceneZOI route should report the problem before bringing anyone over.
5. Try a same-sex pair with a pack that supports both goals and again without
   it. On a supported bed, try with and without Ace Animations Library (AAL).
   Without AAL, HZoi’s own bed scenes should still play.

For sofas, use a three-seat sofa or a four-seat corner sofa.

1. Have another Zoi sit on one end before selecting the pair. Accept the
   invitation and verify the scene plays at the two seats that are free.
2. On a three-seat sofa, have a Zoi outside the pair sit in the middle. Check
   that the invitation shows the sofa availability message even if an end seat
   is open.
3. Start with the sofa empty. During playback, try **Sit Down** and **Sit and
   Relax** with another Zoi. In the three-seat test, **Sit and Relax** worked
   on the spare seat. **Sit Down** failed during playback and worked after Exit.
   Check that Exit releases the two reserved spots and both participants can walk.
4. Take one of the chosen seats with a third Zoi while the pair is on the way.
   Check that the invitation stops with a sofa availability message. The pair
   should only use the seats selected before the invitation.
5. Refuse an invitation. Verify neither Zoi is sent to the sofa.

On the ground, test refusal and acceptance from an open spot with the two
Zois starting elsewhere. On refusal, neither should walk to the spot. On
acceptance, watch each walk to a different spot before playback starts. Try
again near a wall or on another floor, and try canceling the second walk
while the first Zoi is already there.

[HZoiGameplay] records the participants, chosen furniture and sofa pair, outcome and arrival
points in the inZOI Lua log. Look for `refused` or `accepted`. On acceptance,
`both_arrived` should precede `session_started`. `session_ended` records SceneZOI's
cleanup result. Each verified Excitement completion is recorded once by
session, Zoi and completion index. If a notification is missed, the add-on
checks the original start request and reads SceneZOI's retained result.
A missing result leaves unobserved completions unknown. A normal result can
apply an outcome after confirmed cleanup and after the final completion
counts are available for both Zois. Technical or lifecycle interruptions
preserve verified completions without applying a final moodlet.

## Implementation

The ground menu uses the native `HZoiGameplay_SelectVenue` interaction to
capture the exact clicked world point. The furniture menu uses SceneZOI's
shared `scenezoi_furniture` trigger filter. Any sofa SceneZOI recognizes from
its seating slots and any bed covered by a SceneZOI furniture profile can
offer **Have Sex Here**, including furniture from other mods. Both menus
show the burning heart and the game's ModKit marker.

The furniture trigger forwards the exact object ID to the same invitation
flow as the ground menu. The initiator's native mood restriction applies
before the picker opens. The action checks for eligible partners using the
same Romance and Family thresholds, `IsLovable`, and remote-city checks as
the directed **Have Sex** entry. The native picker uses the game’s roster.
**Invite** blocks ineligible partners and rechecks the selected pair.
Content and furniture checks run before the invitation. The placement distance
check runs after both Zois arrive. For
sofas, it queries availability again with the two chosen participants and
passes the same `furniture_pair_id` to preflight, arrival validation, and
playback. The menu action neither moves a Zoi nor takes a furniture
slot. After acceptance, both walks are checked against the scene
and role bindings selected before the invitation.

The new interaction rows use the game’s lover and spouse score thresholds,
branch order and weights. HZoi uses native compatibility and those thresholds
for the encounter entries. HZoi checks the selected venue directly. The two
Coop rows use the game's approach and
dialogue. The game finishes the parent RequestCoop action before the dialogue
ends, so the add-on waits for both conversation roles and the end of the Coop.
If the game cancels a player's approach to the conversation spot because a Zoi
couldn't move out of the way, HZoi retries the native invitation once both
queues are clear. A second failure, an expired retry, or a new player action
ends the attempt. The log records the native cancellation and any retry.

## Autonomous invitations

With inZOI autonomy enabled, HZoi periodically checks nearby idle NPCs for
a partner-specific [Urge](owned-urges.md). Both Zois need to be free to
participate. The game uses its normal invitation rules, so an Urge still
allows the partner to refuse. HZoi searches [indoor venues](npc-venues.md)
with a walking route for both Zois. It checks vacant rooms first, then
considers occupied rooms if none qualifies. Each pair keeps its own room
claim and SceneZOI request. The arrival privacy check still decides whether
the pair can start. If the attempt is canceled, HZoi releases the room and
keeps the Urge pending. A background encounter leaves the controlled Zoi
available.

## Build

Use the [release build instructions](../../docs/release-build.md) to stage the
matching SceneZOI SDK, cook the ModKit package, and verify the resulting ZIP.
See [installation](../../README.md#install) for the SceneZOI and HZoi
dependencies.

Cook `Content/String/mod_ST_Buff_4bd2ac16.uasset` with the mod. The included
`moodlet-text.csv` is the authoring source for the English moodlet names and
descriptions. Also cook `Content/String/mod_ST_SpeechBubble_4bd2ac16.uasset`
for the walk-in reactions. Its English source lines are
in `speech-text.csv`. To change either set of strings, update its CSV and
reimport it into the corresponding native StringTable asset before packaging.
Native speech rows use `LifeTime` in game time. HZoi also clears its own
lines after about five seconds of real time while the simulation is ticking,
which keeps reactions short even with longer in-game days.

Translations live in [localization](localization/), one catalog per inZOI
language. Update the English source and the other catalogs together. Keep
placeholders such as `{partner}`, `{first}` and `{second}`; translators can put
the names in the order that reads naturally. Run
`python prepare-localization.py <staged-mod-directory>` before packaging and
`python prepare-localization.py --check` to check the committed generated files.

The encounter menus, notifications and ending reasons follow the selected
game language. For native moodlet tooltips and speech bubbles, select the
modded entry for your language in Game Options so inZOI loads the mod's native
translations. English is present in the source StringTables. The PO files use
only HZoi Gameplay’s own text keys. Base-game dialogue and the picker’s built-in
controls keep the translations shipped with inZOI and SceneZOI.

The Lua smoke test runs with that B2 source directory on Lua's module search
path. It simulates both answers, an obstruction on one side, cancellation,
occupied furniture, arrival on the wrong floor, native eligibility rejection
and the end of SceneZOI playback. The sofa cases cover a seat taken during the
walk, a sofa moved before arrival, and the approach to a rotated corner sofa.
The ground cases cover blocked floor, a missing second spot, and a Zoi leaving
their arrival point while SceneZOI validates the start.

Run `node test-invitation-rules.js` to check the native menu registration.
The Lua invitation test checks that menu clicks pass the original furniture
or ground point through to one picker request.

## Witnesses

HZoi watches nearby Zois while a directed intimate action plays. A witness must
have a clear sightline to both participants. A wall hit on either of the two
game collision channels blocks the sightline. A closed door or a leaf that
crosses the sightline also blocks it. Zois can see through an open gap even if
inZOI leaves an invisible door access blocker there. An unavailable trace
cannot confirm a sighting. An ordinary first-time witness can gain **Unexpected
Company**. The highest Romance score from the witness toward any participant
sets the speech pool and whether the witness prefers to leave. At 60 or higher,
keep the witness's current action. Younger witnesses below the Teenager stage react without an
overhead line. An idle NPC who prefers to leave can take a nearby reachable
walk-away route.

More than half of the roster must vote to stop over the same sighting. In
iteration 1, that requires both participants. For ordinary witnesses, Romance
of at least 30 toward a participant suppresses that participant's stop vote
and negative sighting reactions. HZoi requests SceneZOI Exit on a majority. An established partner's sighting is recorded with all three Zoi IDs
even when the vote does not stop playback. Once SceneZOI restores the
participants, HZoi passes the three recorded roles to inZOI's native affair
reaction. The game controls the dialogue and relationship effects.

Each participant can receive a completion moodlet and a separate sighting
moodlet. If traits compete for the same slot, the more specific rule wins.
Ties prefer core personality, then characteristics, then aptitudes.
Charmer adds one point to a positive completion moodlet and keeps its title
and duration. A Rulebreaker or a Flirt votes to continue if someone sees the
encounter, including an established partner. On an eligible sighting, a Perfectionist can ask the witness to knock next
time and a Recluse can ask for privacy. Both lines use the native overhead
bubble. Check the [arrival and witness rules](../../docs/encounter-design.md#arrival-privacy-check)
for the score thresholds and the full test matrix.

## Iteration 1 test evidence

**In game.** The native picker reached acceptance and refusal on both freestanding and wall-side queen beds. A separate ground acceptance sent the pair to separate points and ran all four stages through cleanup. The three-seat sofa passed the adjacent-seat availability checks. In a separate wall-side bed run, a bystander stopped the encounter and both participants returned to normal gameplay.

At Normal speed, an NPC Urge selected Jaewoo and Xinyu while Seoyun carried on with her own actions. A third Zoi entering the claimed room canceled the first approach. A later native invitation reached the queen bed and completed all four stages. The log recorded one Excitement completion per participant. The need changes included Hunger stopping at −34, no further Hygiene cost where it was already low, and Fun reaching 100. The Urge owner received the standard reward moodlet, 5 Meow Coins and 15 Admit before normal stat decay. The partner received no coins. Both Zois resumed native conversation after cleanup.

In a ground invitation, an established partner saw both participants. HZoi stopped the scene, confirmed restoration, then passed the three identities to inZOI. The expected native confrontation actions played for all three Zois.

**Native trait checks.** A test-only probe changed traits on a Zoi in a disposable
save and passed controlled outcome facts through the gameplay code. All 48
trait, characteristic, and aptitude cases produced the expected native moodlet
and stop vote. The probe checks how the game applies those decisions. In a separate
single-bed invitation, a late bystander triggered the Perfectionist dialogue
command and two stop votes. The game applied Too Many Eyes and Kept It
Together to the participants and Unexpected Company to the bystander.
Both participants were restored. Neither reached their goal, so Romance
stayed at its starting score in both directions.

**Relationship checks.** An unmarried pair's native refusal completed before
either Zoi walked to the bed. HZoi requested −5 Romance and inZOI applied
about −5.3 in both directions. In a separate single-bed run both goals
completed and HZoi requested +10 after cleanup. InZOI's own modifiers
produced different gains in the two directions. That run also selected the
optional AAL scene. Exiting a separate run after just one goal completed
requested +5 after both Zois were restored.

**Automated coverage.** The Lua fixtures exercise automatic room classification, exact room and floor selection, seat and room contention, door permissions, revalidation at arrival, overlap retry, duplicate completions, and recovery from missed SceneZOI notifications. The overlap regression recreates displacement after one Zoi already reached the bed.
