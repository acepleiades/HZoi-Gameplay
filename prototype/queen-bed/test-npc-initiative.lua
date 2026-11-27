local minute = 600000000
local ticks, wallTime, speed, globalAutonomy, building = minute, 1000, 1, true, false
local scans = 0
local urges = {}
local offered = {}
local urgeSource = {
    pending = function(person) return urges[person.id] end,
    requestEligible = function(person) offered[#offered+1] = person.id end,
}

local function candidate(id, x)
    local person = {id = id, x = x, spawned = true, dead = false, busy = false,
        rabbitHole = false, localAutonomy = true}
    function person:GetEntityId() return {Value = self.id} end
    function person:GetLocation() return {X = self.x, Y = 0, Z = 0} end
    function person:IsSpawned() return self.spawned end
    function person:IsDeath() return self.dead end
    function person:IsInRabbitHole() return self.rabbitHole end
    function person:GetComponent(name)
        assert(name == "Interaction")
        return {
            IsQueueEmpty = function() return not self.queued end,
            IsPlayingInteraction = function() return self.busy end,
            IsInteractionEnabled = function() return not self.blocked end,
            IsPendingCoop = function() return self.pendingCoop end,
            IsCurrentInteractionCoop = function() return self.currentCoop end,
            GetCurrentInteractionPlayReason = function() return self.reason end,
            IsCurrentInteractionInfinite = function() return false end,
            IsCurrentInteractionAlmostFinished = function() return self.finishing end,
        }
    end
    return person
end

local people = {candidate(1, 0), candidate(2, 200), candidate(3, 400), candidate(4, 12000)}
local reserved = {}
local managers = {
    FB2TimeManager = {GetTimeScaleValue = function(_, ignorePause) assert(not ignorePause); return speed end},
    FB2AutonomyOptionManager = {
        GetGlobalOption = function() return {AutonomyEnable = {Value = globalAutonomy}} end,
        ResolveToggleOption = function(_, person, toggle) assert(toggle == "AutonomyEnable"); return person.localAutonomy end,
    },
    FB2EntityManager = {
        FindCharacter = function(_, id) return people[id.Value] end,
        GetAllEntities = function(_, kind) assert(kind == "Character"); scans = scans + 1; return people end,
    },
}
inzoi = {
    FB2TimeManager = {StaticGetCurrentTicks = function() return ticks end},
    FB2ControllerSystem = {GetPossessEntityId = function() return {Value = 1} end,
        IsBuildMode = function() return building end},
    getB2Manager = function(name) return managers[name] end,
    EB2ComponentType = {Interaction = "Interaction"},
    EB2EntityType = {Character = "Character"},
    EB1InteractionPlayReason = {Autonomy = "Autonomy", User = "User"},
    EB1AutonomyOptionType = {AutonomyEnable = "AutonomyEnable"},
}

local calls, mayStart, allowed = {}, true, {}
local function allow(first, second)
    allowed[first .. "|" .. second] = true
end
local function scheduler()
    return require("NpcInitiative").new(function(first, second, started)
        assert(type(started) == "function")
        calls[#calls + 1] = {first, second, started = started}
        return mayStart, mayStart and "npc-test" or "busy"
    end, urgeSource, function(first, second)
        return allowed[first.id .. "|" .. second.id] == true
    end, function(id)
        return reserved[id] == true
    end)
end

local realRandom, realTime, expected, seen = math.random, os.time, {}, {}
os.time = function() return wallTime end
math.random = function(limit)
    seen[#seen + 1] = limit
    return expected[#seen] and expected[#seen][2] or limit
end
local start = scheduler()
local function scan(realSeconds, gameMinutes, ...)
    wallTime = wallTime + realSeconds
    ticks = ticks + gameMinutes * minute
    expected, seen = {...}, {}
    local ok, reason = start()
    assert(#seen == #expected, ("Unexpected number of random draws: %d, expected %d"):format(#seen, #expected))
    for i, roll in ipairs(expected) do assert(seen[i] == roll[1], "Unexpected range for random draw " .. i) end
    return ok, reason
end

local function observeStart(call, firstRoll, secondRoll)
    expected, seen = {{481, firstRoll}, {481, secondRoll}}, {}
    local cooldown = assert(call.started())
    assert(#seen == 2 and seen[1] == 481 and seen[2] == 481, "Use two uniform half-range draws")
    assert(cooldown.started_tick == ticks)
    assert(cooldown.until_tick == ticks + cooldown.duration_minutes * minute)
    return cooldown
end

allow(2, 3)
allow(3, 4)
urges[1] = {partner = "2", expires = 400 * minute}
globalAutonomy = false
scan(0, 0); assert(scans == 0)
globalAutonomy, speed = true, 0
scan(5, 0); assert(scans == 0, "The live clock can be paused while wall time advances")
speed, building = 1, true
scan(5, 5); assert(scans == 0)
building, people[3].busy = false, true
scan(5, 5); assert(scans == 1 and #calls == 0)
people[3].busy, people[3].queued = false, true
scan(5, 5); assert(scans == 2 and #calls == 0)
people[3].queued, people[3].spawned = false, false
scan(5, 5); assert(scans == 3 and #calls == 0)
people[3].spawned, people[3].x = true, people[4].x
people[4].busy = true
scan(5, 5); assert(scans == 4 and #calls == 0)
people[3].x, reserved["3"] = 400, true
scan(5, 5); assert(scans == 5 and #calls == 0)
reserved["3"], people[4].busy = nil, false
scan(4, 20); assert(scans == 5, "Advancing the game clock cannot trigger an early opportunity")
scan(1, 1 / 60, {12, 2})
assert(scans == 6 and #calls == 0, "A regular eligible pair must pass the one-in-12 draw")

mayStart = false
local ok, reason = scan(5, 5 / 60, {12, 1})
assert(ok == false and reason == "busy" and #calls == 1)
scan(5, 5 / 60)
scan(5, 5 / 60)
mayStart = true
ok, reason = scan(5, 15, {12, 1})
assert(ok and reason == "npc-test" and #calls == 2, "Retry the same pair after a temporary failure")
scan(5, 5)
scan(5, 5)
scan(5, 5, {12, 1})
assert(#calls == 3, "Starting asynchronous venue setup does not consume the long cooldown")

scan(3, 3)
local cooldown = observeStart(calls[3], 241, 241)
assert(cooldown.duration_minutes == 40 * 60, "The two central draws give a 40-hour sender cooldown")
assert(calls[3].started() == nil and #seen == 2, "Duplicate start observations do not extend or reroll")
allow(3, 2)
scan(5, 11)
assert(#calls == 3, "The brief unordered retry still blocks reversing the same pending pair")
scan(5, 1, {12, 1})
assert(#calls == 4 and calls[4][1] == "3" and calls[4][2] == "2",
    "The invited partner is free to initiate and the cooled sender can receive")
allowed["3|2"], allowed["3|4"] = nil, nil
people[4].x = 650
allow(2, 4)
local scansBeforeClockJump = scans
scan(-100, 0)
assert(scans == scansBeforeClockJump + 1 and #calls == 4, "A backward wall-clock adjustment keeps game cooldowns")
ticks = cooldown.until_tick - minute
scan(5, 0)
assert(#calls == 4, "A cooled sender cannot start with any partner")
scan(5, 1, {12, 12}, {12, 1})
assert(#calls == 5 and calls[5][1] == "2" and calls[5][2] == "4",
    "At the deadline the sender can start with a different partner")

local obsolete = calls[5].started
scan(1, 10)
ticks = ticks - 5 * minute
assert(obsolete() == nil and #seen == 0, "Reject an old-world start arriving before the rewind poll")
scan(1, 0, {12, 12}, {12, 1})
assert(#calls == 6 and calls[6][2] == "4", "Read game-clock rewinds even between real-time scans")
ticks = ticks + 1000 * minute
assert(obsolete() == nil)
local beforeForwardJump = scans
scan(300, 0, {12, 1}, {12, 12})
assert(scans == beforeForwardJump + 1 and #calls == 7 and calls[7][2] == "3",
    "A forward wall-clock jump samples once, and an obsolete start callback cannot affect the new world")

for _, boundary in ipairs({{1, 32}, {481, 48}}) do
    start = scheduler()
    calls, allowed = {}, {}
    allow(2, 3)
    scan(5, 0, {12, 1})
    local sampled = observeStart(calls[1], boundary[1], boundary[1])
    assert(sampled.duration_minutes == boundary[2] * 60, "The cooldown includes both 32- and 48-hour endpoints")
end

start = scheduler()
calls, allowed = {}, {}
allow(2, 3)
allow(3, 2)
allow(4, 3)
urges[4] = {partner = "2", expires = ticks + 60 * minute}
scan(0, 0, {12, 2}, {12, 2})
assert(#calls == 0, "An Urge with a different partner does not increase the odds")
urges[4] = {partner = "3", expires = ticks}
scan(5, 5, {12, 2}, {12, 2})
assert(#calls == 0, "An expired Urge does not increase the odds")
urges[4].expires = ticks + 60 * minute
allowed["4|3"] = nil
allow(3, 4)
scan(5, 5, {12, 2}, {12, 2})
assert(#calls == 0, "An Urge cannot improve the odds when its owner cannot start the invitation")
allow(4, 3)
scan(5, 5, {12, 1}, {12, 2})
assert(#calls == 1 and calls[1][1] == "4" and calls[1][2] == "3",
    "A passing Urge pair takes priority and queues the Urge owner's valid direction")

start = scheduler()
urges[4] = nil
scan(5, 5, {12, 1}, {12, 1}, {2, 2}, {2, 2})
assert(#calls == 2 and calls[2][1] == "4" and calls[2][2] == "3",
    "Choose a random passing pair, then a random eligible direction. A bidirectional pair gets only one opportunity")
urges[1] = nil
local count = #offered
globalAutonomy = false
scan(5, 5); assert(#offered == count + 1 and offered[#offered] == 1)

globalAutonomy = true
start = scheduler()
calls, allowed = {}, {}
allow(1, 2)
allow(2, 1)
people[2].localAutonomy = false
people[2].x = 8500
people[2].busy, people[2].reason, people[2].finishing = true, "User", true
scan(5, 5)
assert(#calls == 0, "A finishing player action should be preserved")
people[2].reason, people[2].pendingCoop = "Autonomy", true
scan(5, 5)
assert(#calls == 0, "Someone already in a cooperative action is unavailable")
people[2].pendingCoop = false
scan(5, 5, {12, 1})
assert(#calls == 1 and calls[1][1] == "1" and calls[1][2] == "2",
    "The controlled Zoi can initiate for an available autonomy-off partner finishing a routine task")

start = scheduler()
calls, allowed = {}, {}
people[2].busy, people[2].localAutonomy = false, true
people[1].localAutonomy = false
allow(1, 2)
allow(2, 1)
scan(5, 5, {12, 1})
assert(#calls == 1 and calls[1][1] == "2" and calls[1][2] == "1",
    "The controlled Zoi can be the invited partner with autonomy off")

start = scheduler()
calls, allowed = {}, {}
people[2].x, people[3].x = 11000, 15000
allow(2, 3)
scan(5, 5, {12, 1})
assert(#calls == 1 and calls[1][1] == "2" and calls[1][2] == "3",
    "A local pair can start well away from the controlled Zoi")
math.random, os.time = realRandom, realTime

print("NPC initiative passed: eligibility, cadence, directed fairness, Urges, sender-only playback cooldown, pair retry and world rewind.")
