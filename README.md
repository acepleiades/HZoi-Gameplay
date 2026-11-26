# HZoi Gameplay

HZoi Gameplay adds invitations and autonomous encounters to inZOI. Click a
supported bed, a sofa or a clear spot on the ground and choose **Have Sex Here**.
Pick one partner. The Zois use the game's **Set the Mood** rules, so the answer
depends on their relationship and mood. If the partner accepts, both Zois walk
to the chosen spot before the scene begins.

**[OStim/SceneZOI Community Discord](https://discord.gg/RECvhVaRcU)** ·
**[Encounter design](docs/encounter-design.md)**

## Install

Download the Windows ZIP for HZoi Gameplay and install these dependencies.

- **The matching SceneZOI development build.** HZoi Gameplay uses the native
  partner picker and four-stage Auto-mode with per-Zoi goals and a 1.0×
  minimum speed. Check for `features.autonomous_auto_speed_minimum` when
  testing against a different SceneZOI build.
- **HZoi 1.4.1.** Install the player animation pack. It supplies routes for
  supported beds, sofas and standing scenes. Other compatible packs can add
  choices. [HZoi downloads](https://www.patreon.com/skyrimaceanimations/posts/hzoi-public-174452155)
- **Ace Animations Library (AAL) is optional.** Compatible AAL animations add
  variety when enabled. HZoi's own scenes can play without it.

Close inZOI and extract the three packages to `Documents\inZOI\Mods`. When
updating, replace each old mod folder with the matching new one. Check that the
gameplay package has this layout:

```text
Documents\inZOI\Mods\HZoiGameplayPrototype_4BD2AC16\mod_manifest.json
```

Enable **SceneZOI**, **HZoi** and **HZoi Gameplay** in the game's mod menu, then
load your household. The game displays the mod as **HZoi Gameplay**.

## Play

- **Invite a partner.** Choose **Have Sex Here**, select a partner and click
  **Invite**. A refusal ends the invitation. An acceptance sends both Zois to
  the spot. The scene can still be called off if the spot becomes unavailable
  or someone nearby can see the pair and they decide to wait for privacy.
- **Let Zois initiate.** With autonomy enabled for both Zois, an NPC with a
  relevant Urge can invite their chosen partner. They look for a reachable
  spot indoors, starting with rooms that have no other Zois. If they need to
  use an occupied room, the usual arrival privacy check still applies.
  [How Zois choose a venue](prototype/queen-bed/npc-venues.md)
- **Control playback.** Auto mode progresses through the encounter. Turn Auto
  off to choose from the available scenes. **Exit** restores both Zois to
  normal gameplay. Their outcome can affect Romance, needs and moodlets.
- **Getting caught.** Zois react to what they can see. Familiarity and
  personality affect whether the participants stop. An official partner who
  catches the encounter can trigger inZOI's cheating reactions.

This version supports two-Zoi invitations. Which pairs and venues can play
depends on the scenes and goals supplied by the installed packs.

## Play in another language

HZoi Gameplay supports all 15 inZOI languages. Menus and session-ending reasons
follow the selected language. For translated overhead speech bubbles and
moodlet tooltips, select your language's **modded** entry in Game Options.
English works with the standard English entry.

## Report a problem

Include the versions of inZOI, HZoi Gameplay, SceneZOI and your animation packs.
Say where you clicked, which two Zois you chose, and how far the invitation got.
The `[HZoiGameplay]` entries in the inZOI Lua log and the SceneZOI runtime folder
can help when playback fails. [SceneZOI logs and support](https://github.com/acepleiades/SceneZOI/blob/main/docs/playing.md#report-a-problem)

## Develop

[Build and verify a package](docs/release-build.md) ·
[Invitation tests](prototype/queen-bed/README.md) ·
[inZOI romance reference](docs/inzoi-romance.md) ·
[HZoi content pack examples](https://github.com/acepleiades/HZoi-Reference)

## License

HZoi Gameplay is licensed under [GPL-3.0-only](LICENSE). The player package
includes a separate license notice for the bundled SceneZOI SDK. The inZOI
game, ModKit and HZoi animation pack retain their own terms.
