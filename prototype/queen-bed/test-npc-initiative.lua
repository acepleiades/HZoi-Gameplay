local minute = 600000000
local ticks, speed, globalAutonomy, building = minute, 1, true, false
local scans = 0
local urges = {}
local offered = {}
local urgeSource = {
    pending = function(person) return urges[person.id] end,
    requestEligible = function(person) offered[#offered+1] = person.id end,
    canInvite = function(person, partner) return person.id ~= partner.id end,
}

local function candidate(id, x)
    local person = {id = id, x = x, spawned = true, dead = false, busy = false,
        rabbitHole = false, autonomy = true, localAutonomy = true}
    function person:GetEntityId() return {Value = self.id} end
    function person:GetLocation() return {X = self.x, Y = 0, Z = 0} end
    function person:IsSpawned() return self.spawned end
    function person:IsDeath() return self.dead end
    function person:IsInRabbitHole() return self.rabbitHole end
    function person:IsAutonomyEnable() return self.autonomy end
    function person:GetComponent(name)
        assert(name == "Interaction")
        return {IsQueueEmpty = function() return not self.busy end,
            IsPlayingInteraction = function() return self.busy end}
    end
    return person
end

local people = {candidate(1, 0), candidate(2, 200), candidate(3, 400), candidate(4, 3000)}
local public = false
local site = {
    GetSiteType = function() return "Residence" end,
    IsPublicSite = function() return public end,
    IsFakeSite = function() return false end,
    IsIn = function(_, point) return point.X <= 3500 end,
}
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
    FB2SiteManager = {FindClosestSite = function() return site end},
}
inzoi = {
    FB2TimeManager = {StaticGetCurrentTicks = function() return ticks end},
    FB2ControllerSystem = {GetPossessEntityId = function() return {Value = 1} end,
        IsBuildMode = function() return building end},
    getB2Manager = function(name) return managers[name] end,
    EB2ComponentType = {Interaction = "Interaction"},
    EB2EntityType = {Character = "Character"},
    EB1SiteType = {Residence = "Residence"},
    EB1AutonomyOptionType = {AutonomyEnable = "AutonomyEnable"},
}

local calls, mayStart = {}, true
local start = require("NpcInitiative").new(function(first, second, ground)
    assert(ground[1] == "verified floor point")
    calls[#calls + 1] = {first, second}
    return mayStart, mayStart and "npc-test" or "busy"
end, function(nativeSite, first, second)
    assert(nativeSite == site and first.id ~= second.id)
    return {"verified floor point"}
end, urgeSource)

local function scan(delta)
    ticks = ticks + delta * minute
    return start()
end

urges[1] = {partner = "3", expires = 400 * minute}
urges[2] = {partner = "1", expires = 400 * minute}
start(); assert(scans == 1 and #calls == 0)
urges[2].partner = "3"
globalAutonomy = false
scan(5); assert(scans == 1)
globalAutonomy, speed = true, 0
scan(5); assert(scans == 1)
speed, building = 1, true
scan(5); assert(scans == 1)
building, public = false, true
scan(5); assert(scans == 1)
public, people[3].busy = false, true
scan(5); assert(scans == 2 and #calls == 0)
people[3].busy, people[3].localAutonomy = false, false
scan(5); assert(scans == 3 and #calls == 0)
people[3].localAutonomy, people[3].spawned = true, false
scan(5); assert(scans == 4 and #calls == 0)
people[3].spawned, people[3].x = true, people[4].x
scan(5); assert(scans == 5 and #calls == 0)
people[3].x = 400
local ok, reason = scan(5)
assert(ok and reason == "npc-test" and #calls == 1 and calls[1][1] == "2" and calls[1][2] == "3")

urges[3] = {partner = "2", expires = 400 * minute}
scan(4); assert(scans == 6 and #calls == 1)
scan(26); assert(scans == 7 and #calls == 1)
mayStart = false
ok, reason = scan(15)
assert(ok == false and reason == "busy" and #calls == 2)
scan(10); assert(#calls == 2)
scan(5); assert(#calls == 3)
ticks = minute
mayStart = true
start(); assert(#calls == 4)
urges[2], urges[3] = nil, nil
scan(50); assert(#calls == 4)
urges[1] = nil
local count = #offered
globalAutonomy = false
scan(5); assert(#offered == count + 1 and offered[#offered] == 1)

print("NPC initiation gates and retry bounds passed")
