# Invitations at queen beds, sofas, and on the ground

With a Zoi selected, click a supported queen bed, sofa, or a walkable spot on the ground and choose **Have sex here**.
The same picker as SceneZOI debug start opens. Keep your controlled Zoi
selected, choose one partner, then click **Invite**. The game uses the social
conditions and odds from **Set the Mood Next to Bed**. If the pair can talk
but has less than 30 Romance and isn't an official couple, the partner
refuses through the native conversation. If the answer is yes, both Zois walk to the venue
you clicked. SceneZOI starts once both arrive and the selected spot is still
available.

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

1. Use two friends with Romance 0. They should play the refusal conversation
   every time. To test the existing invitation odds, a married pair with
   Family below 30 but at least -30 has a 30% refusal chance. An eligible
   unnamed romantic pair at Romance 30–60 has a 70% refusal chance when the
   target's emotion tendency is Negative.
2. On refusal, verify the conversation finishes, neither Zoi is sent to the
   bed, and both can start another game interaction.
3. On acceptance, verify both Zois reach separate points on the same floor
   beside the selected bed. At the wall-side bed, observe where each Zoi
   approaches. Exit SceneZOI and check that both can move again.
4. Repeat both outcomes using the other bed. Check that a single bed and
   ordinary furniture have no HZoi menu option.

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
`both_arrived` should precede `scene_started`. `scene_ended` records SceneZOI's
cleanup result. Each verified Excitement completion is recorded once by
session, Zoi and completion index. If a notification is missed, the add-on
checks the original start request and reads SceneZOI's retained result.
A missing result leaves unobserved completions unknown. A normal result can
apply an outcome after confirmed cleanup and after the final completion
counts are available for both Zois. Technical or lifecycle interruptions
preserve verified completions without applying a final moodlet.

## Implementation

The menu action uses SceneZOI's built-in queen-bed model IDs and native sofa
tags and categories. It calls SceneZOI's `open_partner_picker` operation. The sim checks the chosen entity against SceneZOI's live furniture
list and validates the requested encounter before queuing the invitation. For
sofas, it queries availability again with the two chosen participants and
passes the same `furniture_pair_id` to preflight, arrival validation, and
playback. The ground option is appended to the game's Click selection set.
The invitation reads the clicked world point from its native queue entry
before the game makes that entry current. The menu action itself has no
movement target. After acceptance, both walks are checked against the scene
and role bindings selected before the invitation.

The new interaction rows use the game’s lover and spouse conditions, branch
order and weights. A separate branch lets an otherwise eligible pair below
the ordinary Romance threshold reach the existing refusal dialogue. The exact
venue check replaces the generic vanilla
site-has-a-double-bed condition. The two Coop rows use the game's approach and
dialogue. The game finishes the parent RequestCoop action before the dialogue
ends, so the add-on waits for both conversation roles and the end of the Coop.

## Autonomous invitations

With inZOI autonomy enabled, HZoi periodically checks nearby idle NPCs for
a partner-specific [Urge](owned-urges.md). Both Zois need to be free to
participate. The game uses its normal invitation rules, so an Urge still
allows the partner to refuse. HZoi searches [private rooms](npc-venues.md)
and checks that both Zois can reach the same venue without a bystander using
the room. Each pair keeps its own room and SceneZOI request. If someone
enters during the approach, the room is released and the Urge stays pending.
The controlled Zoi carries the message to SceneZOI and can keep playing.

## Build

Use the `HZoiGameplayPrototype_4BD2AC16` staging source. Copy
`sdk/lua/SceneZOIAddon` from the SceneZOI checkout into `lua/B2/`, and copy its `Json.lua`
into `lua/B1/SceneZOIAddon/` before running ModKit PackageUGC. The SceneZOI
SDK keeps its GPLv3 license. Include that license with the packaged SDK. Install SceneZOI with the four-stage API and native
partner-picker operation, plus HZoi, alongside the development package.

Cook `Content/String/mod_ST_Buff_4bd2ac16.uasset` with the mod. The included
`moodlet-text.csv` is the authoring source for the English moodlet names and
descriptions. To change those strings, update the CSV and reimport it into
the native StringTable asset before packaging.

The Lua smoke test runs with that B2 source directory on Lua's module search
path. It simulates both answers, an obstruction on one side, cancellation,
occupied furniture, arrival on the wrong floor, native eligibility rejection
and the end of SceneZOI playback. The sofa cases cover a seat taken during the
walk, a sofa moved before arrival, and the approach to a rotated corner sofa.
The ground cases cover blocked floor, a missing second spot, and a Zoi leaving
their arrival point while SceneZOI validates the start.

Run `node test-picker.js` from this directory to check that the menu
forwards the clicked furniture and opens a single picker request.

## Witnesses

HZoi watches nearby Zois while a directed intimate action plays. A Zoi must
have a clear line from their eyes to both participants. A closed wall or an
unavailable trace leaves the encounter unwitnessed. Ordinary NPC bystanders gain the short Unexpected Company moodlet the first
time they see an encounter. An idle bystander can also walk away when a
nearby reachable spot is available.

One vote out of two keeps the scene going. Two stop votes request SceneZOI
Exit. An established partner's sighting is recorded with all three Zoi IDs
even when the vote does not stop playback. Once SceneZOI restores the
participants, HZoi passes the three recorded roles to inZOI's native affair
reaction. The game controls the dialogue and relationship effects.

Each participant can receive a completion moodlet and a separate sighting
moodlet. If traits compete for the same slot, the more specific rule wins.
Ties prefer core personality, then characteristics, then aptitudes.
Charmer adds one point to a positive completion moodlet and keeps its title
and duration. A Rulebreaker or a Flirt votes to continue if someone sees the
encounter, including an established partner.

## Iteration 1 test evidence

**In game.** The native picker reached acceptance and refusal on both freestanding and wall-side queen beds. On the ground, a Romance 0 pair finished the refusal and cleared both queues. Acceptance sent them to separate points and ran all four stages through cleanup. The three-seat sofa passed the adjacent-seat availability checks. In a separate wall-side bed run, a bystander stopped the encounter and both participants returned to normal gameplay.

At Normal speed, an NPC Urge selected Jaewoo and Xinyu while Seoyun carried on with her own actions. A third Zoi entering the claimed room canceled the first approach. A later native invitation reached the queen bed and completed all four stages. The log recorded one Excitement completion per participant. The need changes included Hunger stopping at −34, no further Hygiene cost where it was already low, and Fun reaching 100. The Urge owner received the standard reward moodlet, 5 Meow Coins and 15 Admit before normal stat decay. The partner received no coins. Both Zois resumed native conversation after cleanup.

The fresh development package showed both HZoi floor actions. Marking a room and removing its mark from a different point in the same room each showed the expected toast. The scheduler also found a standing venue after the queen bed was temporarily removed, chose separate floor points, and completed a background scene after both Zois arrived.

In a ground invitation, an established partner saw both participants. HZoi stopped the scene, confirmed restoration, then passed the three identities to inZOI. The expected native confrontation actions played for all three Zois.

**Automated coverage.** The Lua fixtures exercise exact room and floor selection, marks resetting on unload, seat and room contention, door permissions, revalidation at arrival, overlap retry, duplicate completions, and recovery from missed SceneZOI notifications. The overlap regression recreates displacement after one Zoi already reached the bed.
