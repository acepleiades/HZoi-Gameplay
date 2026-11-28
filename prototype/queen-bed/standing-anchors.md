# Find standing spots inside a room

If beds and sofas are unavailable, HZoi Gameplay can use a clear area of
floor. It looks farther into each room so the Zois don't start in the
doorway just because that was the first reachable point. If the center
is blocked, it tries other spots with room to stand.

[`NpcStandingAnchors.lua`](HZoiGameplay_4BD2AC16/lua/B2/NpcStandingAnchors.lua)
samples floor points near both Zois, groups them by room and gives each room
a chance before trying more points in the same room. It scores the available
space toward the walls and how close each candidate is to the sampled center.
It then projects the best candidates onto the native walkable floor. A
projection has to stay in the same room and at roughly the same height.
The venue code still needs two separate spots with routes the Zois can use.
The room can have any purpose that passes the venue rules.
[How NPCs choose a venue](npc-venues.md)

The search uses a two-metre grid up to ten metres in each horizontal
direction from a Zoi. Across the search it checks at most 160 seeds and
36 native projections, keeping up to 12 points overall and three per room.
If you're adapting this for your mod, keep a bound on native projections and
test that one cluttered room can't use the whole search budget.

Try a clear room where both Zois start outside the door, a room with furniture
at its center, and a split-level or L-shaped room. Check that both Zois enter
and reach different points on the same floor.
[Standing spot tests](test-npc-standing-anchors.lua)
