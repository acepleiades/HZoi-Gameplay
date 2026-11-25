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
If either walk fails or a spot becomes unavailable, the scene stops preparing
and shows a message.

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
cleanup result.

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

## Build

Use the `HZoiGameplayPrototype_4BD2AC16` staging source. Copy
`sdk/lua/SceneZOIAddon` from the SceneZOI checkout into `lua/B2/`, and copy its `Json.lua`
into `lua/B1/SceneZOIAddon/` before running ModKit PackageUGC. The SceneZOI
SDK keeps its GPLv3 license. Install SceneZOI with the four-stage API and native
partner-picker operation, plus HZoi, alongside the test package.

The Lua smoke test runs with that B2 source directory on Lua's module search
path. It simulates both answers, an obstruction on one side, cancellation,
occupied furniture, arrival on the wrong floor, native eligibility rejection
and the end of SceneZOI playback. The sofa cases cover a seat taken during the
walk, a sofa moved before arrival, and the approach to a rotated corner sofa.
The ground cases cover blocked floor, a missing second spot, and a Zoi leaving
their arrival point while SceneZOI validates the start.

Run `node test-picker.js` from this directory to check that the menu
forwards the clicked furniture and opens a single picker request.
