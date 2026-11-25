local Marks = require("PrivateRoomMarks")
local Venue = require("NpcVenue")

local function point(x, z)
    return {X = x, Y = 0, Z = z or 0}
end
local function id(value)
    return {Value = value}
end
local location = point(60)
local function character(who, position)
    return {
        GetEntityId = function() return id(who) end,
        GetLocation = function() return position end,
        IsSpawned = function() return true end,
    }
end
local owner, partner, bystander = character(1, location), character(2, point(300)), character(3, point(500))
local controlled, household, siteOwner = 1, 42, 42
local public, fake, indoors, reachable, vacant, roomAccess = false, false, true, true, true, true
local selectedPurpose = "None"
local site = {
    GetSiteId = function() return "residence" end,
    GetSiteType = function() return 1 end,
    GetOwnerHouseholdId = function() return id(siteOwner) end,
    IsPublicSite = function() return public end,
    IsFakeSite = function() return fake end,
    IsIn = function(_, p) return p.X >= 0 and p.X < 2500 end,
    IsSameRoom = function(_, a, b) return math.floor(a.X/1000) == math.floor(b.X/1000) and a.Z == b.Z end,
    GetRoomPurposeIdByLocation = function() return selectedPurpose end,
    GetObjects = function() return {} end,
    IsCharacterAllowedInRoom = function(_, who, purpose)
        assert(who.Value ~= 3 and (purpose == "None" or purpose == "HZoiGameplay_PrivateStudy"))
        return roomAccess
    end,
    IsExistInternalPath = function(_, _, _, params)
        assert(params.EntityId.Value > 0 and params.bIgnorePermission == false)
        return reachable
    end,
}
local siteManager = {
    FindClosestSite = function() return site end,
    IsIndoor = function() return indoors end,
}
local entityManager = {
    GetAllEntities = function() return vacant and {owner, partner} or {owner, partner, bystander} end,
    FindCharacter = function(_, whose) return ({owner, partner, bystander})[whose.Value] end,
    FindGameObject = function(_, whose)
        assert(whose.Value == 200)
        return {GetLocation = function() return point(350) end}
    end,
}
inzoi = {
    EB1SiteType = {Residence = 1}, EB2EntityType = {Character = 3},
    FB2ControllerSystem = {
        GetPossessEntityId = function() return id(controlled) end,
        GetPossessedHouseholdId = function() return id(household) end,
    },
    FB1EntityId = function() return id(0) end,
    FB1NavigationQueryParams = function() return {} end,
    getB2Manager = function(name) return name == "FB2SiteManager" and siteManager or entityManager end,
    getB2Subsystem = function()
        return {IsOnWalkableGrid = function(_, p) return p.X ~= 90 end}
    end,
}
UE = {FVector = function(x, _, z) return point(x, z) end}

for _, outside in ipairs({point(-1), point(1100), point(50, 330), point(90)}) do
    assert(Marks.toggle(owner, outside) == "private_room_unavailable")
end
assert(Marks.toggle(partner, point(120)) == "private_room_unavailable")
household = 43
assert(Marks.toggle(owner, point(120)) == "private_room_unavailable")
household, public = 42, true
assert(Marks.toggle(owner, point(120)) == "private_room_unavailable")
public, fake = false, true
assert(Marks.toggle(owner, point(120)) == "private_room_unavailable")
fake, indoors = false, false
assert(Marks.toggle(owner, point(120)) == "private_room_unavailable")
indoors, selectedPurpose = true, "PublicPurpose"
assert(Marks.toggle(owner, point(120)) == "private_room_purpose_defined")
selectedPurpose = "None"
local markPoint = point(120)
assert(Marks.toggle(owner, markPoint) == "private_room_marked")
markPoint.X = 2100
assert(Marks.isMarked(site, point(500)), "A native wrapper can change after the coordinates are captured.")
assert(not Marks.isMarked(site, point(1100)) and not Marks.isMarked(site, point(50, 330)))
local otherSite = setmetatable({GetSiteId = function() return "other" end}, {__index = site})
assert(not Marks.isMarked(otherSite, point(500)))
siteOwner = 43
assert(not Marks.isMarked(site, point(500)))
siteOwner = 42
public = true
assert(not Marks.isMarked(site, point(500)))
public, fake = false, true
assert(not Marks.isMarked(site, point(500)))
fake = false
location.Z = 330
assert(Marks.toggle(owner, point(500, 330)) == "private_room_marked")
assert(Marks.isMarked(site, point(500, 330)) and Marks.isMarked(site, point(500)))
assert(Marks.toggle(owner, point(130, 330)) == "private_room_unmarked")
assert(not Marks.isMarked(site, point(500, 330)) and Marks.isMarked(site, point(500)))
location.Z = 0

local furniture = {{profile = {kind = "sofa.pair"}, furniture_id = "200", furniture_pair_id = "left", available = true}}
local function candidates(rows)
    return Venue.candidates(owner, partner, rows, {point(120), point(1100)}, function(candidate)
        return {candidate.point, point(candidate.point.X + 150, candidate.point.Z)}
    end)
end
local ranked = candidates(furniture)
assert(#ranked == 1 and ranked[1].kind == "sofa.pair" and ranked[1].furniture_pair_id == "left")
assert(Venue.roomClass(site, point(150)) == "private", "Standing anchor discovery uses this same room classifier.")
ranked = candidates({})
assert(#ranked == 1 and ranked[1].kind == "ground" and ranked[1].point.X < 1000)
assert(Venue.claim("mark", ranked[1], owner, partner))
assert(Venue.recheck("mark", owner, partner))
vacant = false
assert(#candidates({}) == 0 and Venue.recheck("mark", owner, partner),
    "Vacancy gates new claims while sight decides whether the existing invitation can start")
vacant, reachable = true, false
assert(not Venue.recheck("mark", owner, partner, ranked[1].arrival_points))
reachable, roomAccess = true, false
assert(#candidates({}) == 0 and not Venue.recheck("mark", owner, partner))
roomAccess, selectedPurpose = true, "PublicPurpose"
assert(#candidates({}) == 0 and not Venue.recheck("mark", owner, partner))
assert(not Venue.roomClass(site, point(150)))
selectedPurpose = "None"
assert(Marks.toggle(owner, point(500)) == "private_room_unmarked")
assert(not Marks.isMarked(site, point(500)) and not Venue.recheck("mark", owner, partner))
Venue.release("mark")

assert(Marks.toggle(owner, point(120)) == "private_room_marked")
Marks.reset()
assert(not Marks.isMarked(site, point(120)) and #candidates(furniture) == 0)
print("Private-room marks passed: exact room, household, floor, world reset, sofa and ground, occupancy, access and rechecks.")
