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

- **[Build a gameplay mod with SceneZOI](docs/gameplay-authoring.md).** Follow a
  real invitation into the code. Find the native interaction rows, partner
  picker, venue checks, witness reactions and tests.
- **[Start a goal-driven session](docs/autonomous-scene-start.md).** Build the
  Lua request, choose stage preferences and handle packs with fewer scenes
  or no compatible route.
- **[See how an HZoi Gameplay encounter works](docs/encounter-design.md).**
  Read the full flow from eligibility to cleanup, cooldowns and rewards.
- **[Look up inZOI's romance rules](docs/inzoi-romance.md).** See what
  **Set the Mood** checks, how the game distinguishes a score from a
  partnership, and which native rows handle cheating.
- **[Set up a new add-on in SceneZOI](https://github.com/acepleiades/SceneZOI/blob/main/docs/addon-authoring.md).**
  Install the SDK, send your first request and see how to use the replies.

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
