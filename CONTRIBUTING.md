# Contribute to HZoi Gameplay

Fork the repository, make a branch and open a pull request against `main`.
Explain what changes for players or authors and how you checked it. A small
fix or a correction to the docs is welcome. For authoring help or to talk
through an idea, join the [OStim/SceneZOI Community Discord](https://discord.gg/RECvhVaRcU).

The [authoring walkthrough](docs/gameplay-authoring.md) points to the Lua,
ModKit rows and tests. To run the mod from source, see the
[build and test guide](docs/release-build.md). If you change a native
interaction, test the relevant branch in game and say what happened. If
you change an example, check the request fields and links.

## Report a problem

Search the [open issues](https://github.com/acepleiades/HZoi-Gameplay/issues)
first. Include the inZOI, HZoi Gameplay, SceneZOI and content pack versions.
Say what you clicked, which Zois and venue you chose, what you expected, and
what happened. For example, say whether the picker opened, the invitation
finished, both Zois arrived or playback actually began.

The `[HZoiGameplay]` lines in the inZOI Lua log help with invitations and
venue problems. If playback started or failed to start, include the
`scenezoi_runtime` diagnostics too.
[Where to find SceneZOI's logs](https://github.com/acepleiades/SceneZOI/blob/main/docs/playing.md#report-a-problem)

File issues about invitations, venue choice or gameplay outcomes here. If the
same playback or restoration problem happens from SceneZOI's own manual start,
report that reproduction to [SceneZOI](https://github.com/acepleiades/SceneZOI/issues).
For an issue in one particular animation or asset, give the pack author the
scene name and the steps to reproduce it.
