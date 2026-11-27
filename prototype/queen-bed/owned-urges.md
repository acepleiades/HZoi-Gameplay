# HZoi-owned partner Urges

The fallback follows the native Emotionally Needy Urge and offers one specific
target. The pair must pass the game's `IsLovable` check. The owner needs the
Emotionally Needy characteristic and an established lover whose Romance score
from the owner is below 30. Sleep, prison, rabbit holes, site events,
and the Cahaya desert island block new Urges. When multiple eligible named
lovers are loaded, the mod picks the one with the highest Romance and uses
their entity ID to break ties.

The Urge lasts for 12 in-game hours. The two-day cooldown starts when the
Urge is offered and lasts through fulfillment or expiry. If the controlled
Zoi receives or fulfills an Urge, the toast identifies their selected partner.

Only that owner's Excitement completion with the selected partner fulfills
the Urge. The mod consumes it before calling inZOI's original reward commands
to grant the moodlet, 5 Meow Coins and 15 Admit. A repeated completion
cannot grant a second reward.

This fallback stores the temporary Urge and cooldown in the running world.
A new world, mod unload, or backward simulation-time jump clears both. The
reward uses the game's ordinary save data. The fallback does not write a
separate save or add a native Hope slot.

## Integration

Use the same Urge module in the NPC scheduler and in the verified SceneZOI
completion handler. Call the module reset function in the gameplay world
shutdown hook. The scheduler can call requestEligible with a lookup for
loaded actors. For a pending NPC Urge, canInvite rechecks whether the
pair matches the game's ordinary relationship and city rules. Leave the
Urge pending when the venue is unavailable or when either Zoi needs to wait.

Verify this path with a fresh launch and a test save. Check the offer and
fulfillment toasts, correct partner, expiry, one-time reward, and a repeated
invitation during cooldown.
