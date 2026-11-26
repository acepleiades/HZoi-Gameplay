# Standing anchor test

A possible ground anchor is sampled from the floors occupied by the two Zois
at a residential site. The scan stays within 10 metres in each horizontal
direction of either Zoi. It considers at most 160 sample points, attempts at
most 36 native projections, and returns up to 3 points in each eligible room.

The scan starts at each Zoi's capsule position minus their native half
height. The sample and its native walkable floor projection must belong to
the same indoor room, regardless of its purpose. If the native projection
returns no point, the candidate is skipped. Venue selection needs two
separate walkable arrival points with paths for both Zois. Furniture in the
room can be unavailable as long as those spots qualify.

Run the standing anchor Lua fixture for split levels, room boundaries, missing
projection results and scan limits. A live apartment probe confirmed that
the native site grid returned the same floor height as a picked floor point.
Verify the standing fallback in a room without an assigned purpose. Repeat
with unavailable furniture and enough clear floor space for both arrivals.
