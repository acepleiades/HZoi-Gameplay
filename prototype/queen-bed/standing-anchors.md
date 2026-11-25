# Standing anchor test

A possible ground anchor is sampled from the floors occupied by the two Zois
at a residential site. The scan stays within 10 metres in each horizontal
direction of either Zoi. It considers at most 160 sample points, attempts at
most 36 native projections, and returns up to 3 points in each marked room.

The scan starts at each Zoi's capsule position minus their native half
height. The sample and its native walkable floor projection must have the same private
room purpose and be in the same native room. If the native projection returns
no point, the candidate is skipped. Venue selection still checks that a room
has no supported furniture and that both Zois have separately reachable
arrival points inside it.

Run the standing anchor Lua fixture for split levels, room boundaries, missing
projection results and scan limits. A live apartment probe confirmed that
the native site grid returned the same floor height as a picked floor point.
Verify selection in an empty marked room before connecting this sampler
to automatic invitations.
