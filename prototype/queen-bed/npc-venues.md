# Private rooms for NPC invitations

The venue prototype only considers rooms at residential sites. In Build Mode,
use the native **Room Purpose** menu to mark an enclosed room as **Bedroom**
or **Study**. Those options are added by HZoi Gameplay and use inZOI's room
labels. A room with no purpose stays out of the NPC search. Player invitations
are available on supported furniture and walkable ground as before.

The search prefers a free bed or sofa with a compatible scene. A sofa must
have a free pair of adjacent seats. Within that group, bedrooms take priority
and the nearest reachable venue wins. A room without supported furniture can
offer a standing scene if there are two clear arrival points. A room with
occupied furniture stays out of the floor fallback.

Each NPC pair needs permission to enter the room and a path for both Zois.
A bystander in the room makes it unavailable. Once reserved, the room stays
claimed by that pair through approach. Recheck vacancy as they walk and before
playback. Release the room on cancellation or cleanup, including when a
bystander walks in during the approach.

## Test the venue prototype

Choose two private rooms in a residence. Place a supported queen bed in the
first, and leave a clear walkable area in the second. Leave the living room
without a private room purpose.

1. Ask for a venue with both Zois elsewhere in the same residence. The bed
   should rank first if both Zois can reach it and the room is empty.
2. Have a third Zoi occupy the bedroom and repeat. The bedroom should be
   excluded. If the other marked room has no supported furniture and both
   destinations are walkable, a ground candidate can be selected there.
3. Have a bystander enter while a pair is walking. The venue check should
   stop the attempt with the room occupied, and the room claim should release.
4. Try a second pair in a separate private room. The claims should coexist.
   In the same room, only the first pair should get a claim.
5. Try a locked door or a room without a supported purpose. The venue check
   should exclude it. A player-directed invitation should use its usual rules.

The Lua fixture in the invitation prototype directory covers ranking, access,
occupancy, competing rooms, and the floor fallback. Verify the Room Purpose
menu and native path queries in game before enabling NPC initiative.
