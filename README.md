# HZoi Gameplay

The companion gameplay integration for [HZoi](https://github.com/acepleiades/HZoi) and [SceneZOI](https://github.com/acepleiades/SceneZOI) in inZOI.

HZoi Gameplay decides when a scene should be requested, which eligible participants and content to use, and what the result means for gameplay. SceneZOI executes the scene; HZoi supplies assets and declarative data.

## Project status

Development is deferred. This repository documents the intended delegation of responsibilities. No gameplay rules, acceptance formulas, interactions, or runtime code have been implemented. The required inZOI APIs remain to be validated. SceneZOI's first release retains its own Start SceneZOI buttons on the controlled Zoi and supported furniture; this gameplay integration is not required.

## The three projects

| Project | Responsibility |
| --- | --- |
| **[SceneZOI](https://github.com/acepleiades/SceneZOI)** | Runs scene sessions, animations, outfits, and optional subsystems. |
| **[HZoi](https://github.com/acepleiades/HZoi)** | Supplies animation assets and declarative scene data. Contains no executable code. |
| **HZoi Gameplay** | Connects those systems to inZOI interactions, decisions, and consequences. |

## HZoi Gameplay owns

- The gameplay entry points through which a player or supported autonomous behavior can request a scene.
- Adult participant eligibility, consensual participation, willingness, and acceptance or rejection checks.
- Relevant relationship, personality, availability, location, privacy, and other context checks, as the gameplay design and available APIs require.
- Selecting compatible scenes and participants using SceneZOI's registered content and metadata.
- Requesting a SceneZOI session only after gameplay conditions are satisfied.
- Observing lifecycle events to handle success, refusal, interruption, cancellation, completion, and runtime failure appropriately.
- Applying gameplay consequences, relationship effects, notifications, and other integration-specific outcomes.
- Configuration for this integration's behavior and balance.

The exact rules and formulas are future design decisions. This document assigns responsibility; it does not prescribe a particular relationship model or acceptance formula.

## SceneZOI boundary

Animation playback, participant alignment, scene-mode transitions, scene controls, outfit changes and restoration, navigation, voice, SFX, expressions, and optional excitement behavior belong to SceneZOI.

HZoi Gameplay should use the public SceneZOI API and lifecycle events rather than reach into framework internals or duplicate its runtime systems. SceneZOI owns temporary participant control during the session; this integration owns the surrounding gameplay decision and response.

Willingness to begin a scene is distinct from excitement during a scene. This integration decides the former; SceneZOI can implement the latter as an optional capability requested by scene data.

The current scene determines the task definition, including when this
integration starts the session. HZoi uses SceneZOI’s shared Excitement task.
An integration can read the active definition with `get_task_state`.
[SceneZOI task provider rules](https://github.com/acepleiades/SceneZOI/blob/v1.3.12/docs/scene-tasks.md#choose-which-definition-a-scene-uses)

## HZoi boundary

Animations, media assets, scene graphs, transitions, outfit directives, and scene-specific subsystem configuration belong to HZoi's declarative content.

HZoi must remain code-free. New reusable scene behavior belongs in SceneZOI; new gameplay policy belongs in this repository. Do not add executable callbacks or gameplay checks to HZoi scene definitions.

## Relationship to inZOI

The intended emphasis is deciding when adult scenes can become available within inZOI's existing social gameplay. The integration should build on the game's relationship and romance systems where practical rather than require a replacement courtship system.

## Dependencies and alternatives

This integration requires a compatible SceneZOI version and is designed around HZoi as its companion content pack. Support for additional compatible packs can be added through registered metadata and capability queries.

HZoi and SceneZOI do not depend on this integration. Other authors can implement different gameplay rules or a posing interface using the same framework and compatible content. Their integrations should not need to depend on HZoi Gameplay.

## Compatibility

Releases will declare the supported SceneZOI API version and required content versions. Changes to gameplay balance should be releasable independently from framework fixes and animation additions.
