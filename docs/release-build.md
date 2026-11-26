# Build HZoi Gameplay

Use a fresh isolated Windows ModKit project and the SceneZOI checkout used to
build the framework package you will test with. HZoi Gameplay 1.0.0 requires
SceneZOI 1.7.0 or later. Use the `v1.7.0` checkout to build and verify against
the minimum supported version. [Installation instructions](../README.md#install)

## Stage and cook

From `prototype/queen-bed`, run the following. Set the three paths to your
matching SceneZOI checkout, isolated ModKit installation and isolated project.
Use a fresh path for `$exportRoot`.

```powershell
$sceneZOI = "C:/repos/SceneZOI"
$modkitRoot = "C:/isolated-build/inZOIModKit"
$project = Join-Path $modkitRoot "inZOIModKit/inZOIModKit.uproject"
$exportRoot = "C:/isolated-build/HZoiGameplay-export"
$modId = "HZoiGameplayPrototype_4BD2AC16"
$staged = Join-Path (Split-Path $project -Parent) "Mods/$modId"

python prepare-localization.py --check
if ($LASTEXITCODE -ne 0) { throw "Localization verification failed." }

python prepare-release.py stage --scenezoi $sceneZOI --project $project
if ($LASTEXITCODE -ne 0) { throw "Staging failed." }

& "$modkitRoot/Engine/Build/BatchFiles/RunUAT.bat" PackageUGC `
  "-Project=$project" "-StagingDirectory=$staged" "-ExportToGameMods=$exportRoot" `
  -TargetPlatform=Windows -ugc_cook -nocompile -nocompileuat -nop4 -NoSubmit `
  -unattended -noturnkeyvariables -ddc=NoZenLocalFallback
if ($LASTEXITCODE -ne 0) { throw "ModKit packaging failed." }

python prepare-release.py archive --scenezoi $sceneZOI --prepared $staged `
  --exported (Join-Path $exportRoot $modId) --output "HZoiGameplay-1.0.0.zip"
if ($LASTEXITCODE -ne 0) { throw "Package verification failed." }
```

The script copies the matching SceneZOI SDK into the staged mod and regenerates
the invitation and localization files. It verifies the two native StringTables,
14 non-English translation files, protected Lua, encoded UI and native patches
against the prepared inventory. It preserves ModKit's asset hash and generated
checksums, sets both package dependencies, includes the SceneZOI SDK's GPLv3
license and prints the finished ZIP's SHA-256.

The English text for native moodlets and speech bubbles lives in
`moodlet-text.csv` and `speech-text.csv`. Reimport changes to the corresponding
StringTable and verify its keys and source strings in the editor before cooking.
The 15 [translation catalogs](../prototype/queen-bed/localization/) generate
the menu strings, ending reasons and non-English native language files.

## Verify the release ZIP

Install the exact ZIP with SceneZOI 1.7.0 and HZoi 1.4.1.
Start a fresh inZOI process, load a disposable save at Normal speed, and use
ordinary interactions for these checks.

1. Confirm all three mods appear enabled. A compatible pair should see
   **Have Sex Here** with a burning heart on beds, sofas and walkable ground. Confirm the
   action has no gold **MOD** badge and other mod actions keep their badges.
   Confirm each opens the native one-partner picker.
2. Run one refusal and one acceptance. Make sure both queues clear after
   refusal. After acceptance, watch both Zois walk to the venue and verify
   **Exit** restores normal movement. Repeat on a bed, sofa and walkable ground.
3. With autonomy enabled, run the [NPC venue checks](../prototype/queen-bed/npc-venues.md#test-the-venue-search).
   Verify a native bed assignment, the fallback without an assignment, both
   search passes, and independent claims. The controlled Zoi should stay
   available during background playback.
4. Switch to a non-English modded language and repeat after a fresh launch.
   Check the menu and picker, one moodlet, an overhead line and the
   session-ending reason.
5. Check one ordinary witness exit and an interruption. The normal gameplay
   ending should count down to auto-dismiss. A technical ending should remain
   available to read.
   Check an observer within range across a solid wall and through a closed
   doorway. Before playback, an obstruction should let the pair start even
   when the observer's relationship scores are too low. During playback, the
   observer reacts once both Zois are visible. Repeat with the camera cutting
   away the wall.
   Run the doorway check again while a permitted Zoi walks through it and the
   door swings open. A sightline through the gap should count. Move the
   observer to an angle where the leaf or a wall farther back crosses the
   sightline and verify that the geometry blocks it again.
6. Let a married pair finish both goals. Verify the game receives one +10
   Family request after cleanup and no Romance reward. Check Family in both
   directions and account for inZOI's relationship limits.
7. Use a neutral movement test with the installed witness code. Check that a
   Child, an Adolescent and a Teenager can walk away and clear the movement
   queue. Only the Teenager should display a speech bubble. For the arrival
   score check, supply a visible observer with Friendship 50 toward the
   same-sex participant and Romance 0 toward both. The observer should fail
   the check.

Use the [iteration 1 acceptance matrix](encounter-design.md#acceptance-checks)
and the [full invitation test notes](../prototype/queen-bed/README.md#test-in-game)
for detailed cases. Record the exact package versions and hash alongside the
test results.
