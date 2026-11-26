# How NPCs choose a venue

For an autonomous invitation, HZoi looks for an indoor room at the residence
where both Zois are located. The room can have any purpose or no assigned
purpose. The search first looks for rooms with no other Zois. If every
vacant option fails, it considers occupied rooms.

In each pass, HZoi looks for the initiator's assigned bed first, then a double
bed, a single bed, a sofa with two free adjacent seats, or two walkable
standing spots in the same room. Within each tier, it uses the nearest
eligible venue. A standing scene can use clear floor space in a room whose
furniture is unavailable. Both Zois must be able to reach their spots and
have permission to enter the room. The venue must support their scene and
be free to reserve.

The pair claims the room until the attempt is canceled or the session ends.
When they arrive, HZoi rechecks furniture availability and applies the
[arrival privacy rules](../../docs/encounter-design.md#arrival-privacy-check)
to anyone who can see either arrival point. An observer who fails the check
causes both Zois to call off the encounter.

## Test the venue search

Use a disposable household with several indoor rooms at the same residence.
Include free compatible single and double beds, a sofa and clear floor space.
Leave at least one room without an assigned purpose.

| Setup | Expected result |
| --- | --- |
| Assign a free, compatible single bed to the initiator through the game's bed assignment. Offer a nearer double bed in the same search pass. | The initiator's assigned bed wins. |
| Clear the initiator's assignment. Repeat with a free double and single bed. Then make each superior option unavailable in order. | The search falls back to double bed, single bed, sofa pair and standing. Put two usable beds in one tier to verify nearest wins. |
| Put another Zoi in the room with the free bed. Leave an unassigned room with two reachable standing spots vacant. | The vacant standing venue wins in the first pass. |
| Leave no vacant venue. Keep the free furniture in an occupied room, or offer enough clear floor space there when the furniture is unavailable. | The occupied room can qualify in the second pass. A blocked sightline or qualifying observer allows the start. A visible observer who fails the check cancels it and releases the claim. |
| Take one seat of an adjacent sofa pair, occupy a bed, or block a path. Then free the seat or clear the route and try again. | Only free furniture and paths both Zois can use qualify. Standing requires two separate reachable spots inside one room. Repeat by occupying the chosen furniture during the walk to check arrival revalidation. |
| Invite two disjoint pairs in separate rooms and try competing starts with a shared room or participant. | Separate sessions can overlap. A conflicting start leaves the existing claim and session intact. |

Check that each canceled attempt leaves the Urge pending. Confirm that both
walk routes respect locked doors and floor boundaries, and that outdoor
spots and nonresidential sites stay outside the NPC search.
