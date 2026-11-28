# HZoi Gameplay source and tests

This directory holds the shipped HZoi Gameplay project, including ground,
bed and sofa invitations, the Romance menu and autonomous invitations.
The directory name comes from the first queen-bed test.

- [Follow an encounter through the source](../../docs/gameplay-authoring.md).
- [Build and verify the install ZIP](../../docs/release-build.md).
- [See what players should experience](../../docs/encounter-design.md).

## Where to edit

| Change | Files |
| --- | --- |
| Invitations, movement and SceneZOI requests | [B2 Lua](HZoiGameplay_4BD2AC16/lua/B2/) |
| Picker messages, toasts and visibility traces | [B1 Lua](HZoiGameplay_4BD2AC16/lua/B1/) |
| Native interactions, co-ops, moodlets and speech | [ModKit row patches](HZoiGameplay_4BD2AC16/Content/JsonPatch/) |
| Add-on text and its translations | [Language catalogs](localization/) and the source CSVs below |
| Prepare and verify a release | [`prepare-release.py`](prepare-release.py) and [`prepare-localization.py`](prepare-localization.py) |

## Update player text

Edit the [translation catalogs](localization/) together. Keep placeholders
such as `{partner}`, `{first}` and `{second}`. Translators can put names in
the order that fits their language. The catalogs generate the shared menus,
toasts, ending reasons and native translation files.

For native text, update the matching source CSV and reimport it into the
StringTable in ModKit. The tables live in [`Content/String/`](HZoiGameplay_4BD2AC16/Content/String/).

| Text shown in game | English source |
| --- | --- |
| Moodlet name and description | [`moodlet-text.csv`](moodlet-text.csv) |
| Overhead speech | [`speech-text.csv`](speech-text.csv) |
| Invitation in the action queue | [`interaction-text.csv`](interaction-text.csv) |

Run `python prepare-localization.py --check` from this directory to verify
the generated text files. Before release, use the
[build steps](../../docs/release-build.md#stage-and-cook) to stage the mod
with the SDK and package the native StringTables.

Menus, toasts and the reason shown at session end follow the selected game
language. For translated native moodlets, overhead speech and the action queue
title, choose the corresponding modded language entry in Game Options. English
uses the source StringTables. Base-game dialogue keeps inZOI's translations.

## Run the source checks

From this directory, check the native interaction rows and witness movement patch.

```powershell
node test-invitation-rules.js
node test-witness-walk.js
python prepare-localization.py --check
```

The Lua fixtures need the mod's Lua folder and SceneZOI's `sdk/lua/` on the
Lua search path. For example, with a Lua interpreter and a SceneZOI checkout
at `C:/repos/SceneZOI`, run the invitation fixture like this.

```powershell
$env:LUA_PATH = "./HZoiGameplay_4BD2AC16/lua/B2/?.lua;C:/repos/SceneZOI/sdk/lua/?.lua;;"
lua test.lua
```

Use the [authoring walkthrough](../../docs/gameplay-authoring.md#give-an-ai-agent-the-part-you-want-to-work-on)
to find a fixture for the code you're changing. For native behavior, repeat the
relevant case in the game.

## Test in game

Use a disposable household at Normal speed. Start at the actual interaction menu.
Try refusal and acceptance, then check movement after Exit. A good routing
check is a bed flush against a wall and a pair of single beds with only one
narrow aisle. For a sofa, take one of the selected seats while the Zois walk
over and confirm the invitation ends without leaving anyone stuck. Try
switching the controlled Zoi during a conversation and again while the pair
walks to the venue.

For an eligible refusal case, use an uncommitted pair with Romance 30–60 and
a target with a negative emotional tendency. The native branch refuses about
70% of the time. Check that the dialogue finishes and neither Zoi walks to
the venue. Use a qualifying pair with higher Romance for acceptance.
[Native answer rules](../../docs/inzoi-romance.md#set-the-mood-next-to-bed-menu-rules)

Look for `[HZoiGameplay]` in the inZOI Lua log. `accepted` or `refused`
records the finished conversation. `both_arrived` should precede
`session_started`. `session_ended` includes the SceneZOI cleanup result.
Record the two Zois, the venue and the last step that completed when reporting
a failure. [Release checks](../../docs/release-build.md#verify-the-release-zip)
