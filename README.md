# HZoi Gameplay

Invite another Zoi to have sex through inZOI's Romance menu, pick a bed, sofa
or spot on the ground, or let your Zois look for somewhere on their own.
HZoi Gameplay uses SceneZOI to play the encounter and inZOI's systems for
invitations, moodlets and relationship changes.

## For players

### Install

**[Download HZoi Gameplay and follow the install guide](https://acepleiades.github.io/HZoi-Gameplay/).**
Use the [latest SceneZOI release](https://github.com/acepleiades/SceneZOI/releases/latest)
and a compatible content pack. I recommend HZoi. See
[GitHub releases](https://github.com/acepleiades/HZoi-Gameplay/releases/latest)
for the ZIP and update notes.

For help or to share what happens in your game, join the
[OStim/SceneZOI Community Discord](https://discord.gg/RECvhVaRcU).
If you enjoy my mods, you can [support my work on Patreon](https://www.patreon.com/skyrimaceanimations).

### Play in another language

HZoi Gameplay supports all 15 inZOI languages. Menus, toasts and session-ending
reasons follow the game language. For translated native speech, moodlets and
the invitation title in the action queue, select the corresponding modded
language entry in Game Options. English uses the standard English entry.

## For mod authors

- **[Make your first SceneZOI gameplay add-on](https://github.com/acepleiades/SceneZOI/blob/main/docs/first-gameplay-addon.md).**
  Create a ModKit project, package it, and verify your first request in game.
- **[Read HZoi Gameplay's implementation](docs/gameplay-authoring.md).** Follow
  [an invitation](docs/gameplay-authoring.md#add-the-interaction-and-get-an-answer)
  to see how a session starts, or go straight to
  [witnesses and interruptions](docs/gameplay-authoring.md#handle-witnesses-and-interruptions)
  to see how the mod reacts during playback.
- **[Start a goal-driven session](docs/autonomous-scene-start.md).** Build the
  Lua request, choose stage preferences and handle packs with fewer scenes
  or no compatible route.
- **[See how an HZoi Gameplay encounter works](docs/encounter-design.md).**
  Read the full flow from eligibility to cleanup, cooldowns and rewards.
- **[Look up inZOI's romance rules](docs/inzoi-romance.md).** See what
  **Set the Mood** checks, how the game distinguishes a score from a
  partnership, and which native rows handle cheating.

## For contributors

Want to improve this mod or its docs? Start with
[Contributing](CONTRIBUTING.md) and the [build and test guide](docs/release-build.md).
Fork the repository and open a pull request with what you changed and how you
checked it.

### Report a problem

Check the [existing issues](https://github.com/acepleiades/HZoi-Gameplay/issues)
and then [open an issue](https://github.com/acepleiades/HZoi-Gameplay/issues/new/choose).
Include your versions, what you clicked and how far the encounter got.
[What to include in a report](CONTRIBUTING.md#report-a-problem)

## License

HZoi Gameplay is licensed under [GPL-3.0-only](LICENSE). The player package
includes a separate license notice for the bundled SceneZOI SDK. The inZOI
game, ModKit and HZoi content pack retain their own terms.
