# HZoi Gameplay

HZoi Gameplay brings sexual scenes and non-sexual affectionate scenes into inZOI's everyday gameplay. It integrates HZoi and other compatible content packs for [SceneZOI](https://github.com/acepleiades/SceneZOI). Depending on the installed packs, a scene might involve sex or something as simple as resting a Zoi's head on their partner's lap.

## Pre-production

Development is in pre-production. Current work focuses on understanding inZOI's romance system and deciding how SceneZOI scenes can fit into it. Romance progression will be one of the main factors in which interactions become available. The research also looks at which relationship states the game tracks separately, when partners react to other romances, and how a partner could agree to a nonexclusive relationship.

The [inZOI romance reference](docs/inzoi-romance.md) documents the vanilla relationship tiers, courtship, marriage, having children, and cheating detection. The [interaction catalog](docs/inzoi-romance-interactions.csv) lists the game's romance-related interactions and their conditions.

## Gameplay direction

The goal is to connect scenes to the systems Zois already use to express and develop relationships:

- **Interactions and autonomy.** A player can invite another Zoi into a scene, and Zois can initiate scenes through their own social behavior.
- **Urges and moods.** A Zoi's current mood or urges can influence what they seek out or how they respond.
- **Relationships and memories.** An encounter can affect the relationship or leave a memory that matters in later interactions.

HZoi Gameplay will decide when to offer or request a scene and how the encounter affects gameplay. SceneZOI will handle playback through its public API. HZoi and other compatible packs supply the animations and scene data. [HZoi Reference](https://github.com/acepleiades/HZoi-Reference) provides public examples of how that content is authored.
