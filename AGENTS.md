# Working on HZoi Gameplay

Start with the [encounter proposal](docs/encounter-design.md) and follow its
implementation priorities. Use the [SceneZOI request](docs/autonomous-scene-start.md)
for playback and the [vanilla romance reference](docs/inzoi-romance.md) for native
interaction rules. Prove each native handoff in game before building features that
depend on it.

- HZoi Gameplay owns invitations, venue selection, witnesses and gameplay
  consequences. SceneZOI owns animation selection, placement, playback, scene
  tasks and cleanup. Content packs supply the scenes and their assets.
- Keep iteration 1's two-Zoi rules at the invitation, venue approach, and
  native relationship boundaries. Shared playback and outcome handling use a
  roster, and shared player text works for larger groups.
- Use the public SceneZOI SDK and check for the features the add-on needs. Keep
  invitation acceptance, SceneZOI request acceptance and actual playback start
  separate. Recheck the participants and venue after walking. Send gameplay consequences
  from observed events or results.
- Start with the exposed ModKit data and Lua APIs. Compare the relevant inZOI rows
  before recreating an interaction. Give new rows IDs unique to this mod and
  verify which scripts and effects a reused sequence runs. Keep project changes
  in HZoi Gameplay.
- Keep temporary entry points and test data separate from player-facing content.
  Test both answers to an invitation, normal Exit and recovery after an
  interruption. Confirm every participant can return to ordinary gameplay. For
  concurrent encounters, verify that each has its own participants, venue and
  outcome.
- Reproduce a reported issue when possible and test the fix against that case.
  When it cannot be reproduced, add a diagnostic if it can distinguish the
  likely causes. Keep raw logs, local packages and machine-specific paths out of
  commits.

Preserve working changes and existing attribution. Commit, push, tag or publish
when asked.
