# Queen-bed invitations

With a Zoi selected, click a supported queen bed and choose **Have sex here**.
The same picker as SceneZOI debug start opens. Keep your controlled Zoi
selected, choose one partner, then click **Invite**. The game uses the same social
conditions and odds as **Set the Mood Next to Bed**. A refusal finishes with
the native conversation. If the answer is yes, both Zois walk to the bed you
clicked. SceneZOI starts once both arrive and the bed is still available.

## Test in game

Load the usual test household at Normal speed. Try a free-standing queen bed
and a queen bed with one side against a wall.

1. Use a pair that can refuse under the native rules. A married pair with
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

[HZoiGameplay] records the participants, chosen bed, outcome and arrival
points in the inZOI Lua log. Look for `refused` or `accepted`. On acceptance,
`both_arrived` should precede `scene_started`. `scene_ended` records SceneZOI's
cleanup result.

## Implementation

The menu action is available for the models in SceneZOI's built-in queen-bed
profiles. It opens the native picker through SceneZOI's `open_partner_picker`
operation. The sim checks the chosen entity against SceneZOI's live furniture
list and validates the requested encounter before queuing the invitation.

The new interaction rows use the game’s lover and spouse conditions, branch
order and weights. The exact venue check replaces the generic vanilla
site-has-a-double-bed condition. The two Coop rows use the game's approach and
dialogue. The game finishes the parent RequestCoop action before the dialogue
ends, so the add-on waits for both conversation roles and the end of the Coop.

## Build

Use the `HZoiGameplayPrototype_4BD2AC16` staging source. Copy
`sdk/lua/SceneZOIAddon` from the SceneZOI checkout into `lua/B2/` before
running ModKit PackageUGC. The SceneZOI SDK keeps its GPLv3 license. Install
SceneZOI with the four-stage API and native partner-picker operation, plus HZoi,
alongside the test package.

The Lua smoke test runs with that B2 source directory on Lua's module search
path. It simulates both answers, an obstruction on one side, cancellation,
occupied furniture, arrival on the wrong floor, native eligibility rejection
and the end of SceneZOI playback.

Run `node test-picker.js` from this directory to check that the menu
forwards the clicked bed and opens a single picker request.
