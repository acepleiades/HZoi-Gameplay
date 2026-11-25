local Venue = require("NpcVenue")

local function point(x, y, z)
    return {X = x, Y = y or 0, Z = z or 0}
end

local function roomAt(position)
    return math.floor(position.X / 1000)
end

local firstPosition = point(200)
local bedroom = "HZoiGameplay_PrivateBedroom"
local study = "HZoiGameplay_PrivateStudy"
local purposes = {[1] = study, [2] = bedroom, [3] = study, [4] = study, [7] = study, [8] = study}
local nativeObjects, metadata = {}, {}
local active, public, bedAccess, indoor, roomAccess = {}, false, true, true, true
local function character(id, location)
    return {
        GetEntityId = function() return {Value = id} end,
        IsSpawned = function() return true end,
        GetLocation = function() return location end,
    }
end
local initiator = character(1, firstPosition)
local partner = character(2, point(500))
local bystanderLocation = point(700)
local bystander = character(3, bystanderLocation)
local secondInitiator = character(4, point(350))
local secondPartner = character(5, point(600))
active = {initiator, partner, bystander, secondInitiator, secondPartner}
local assigned = {}
local site = {
    GetSiteType = function() return public and 2 or 1 end,
    GetSiteId = function() return "site" end,
    IsPublicSite = function() return public end,
    IsFakeSite = function() return false end,
    IsIn = function(_, position) return position.X >= 0 and position.X < 9000 end,
    IsSameRoom = function(_, a, b) return roomAt(a) == roomAt(b) and a.Z == b.Z end,
    GetObjects = function() return nativeObjects end,
    GetRoomPurposeIdByLocation = function(_, p) return purposes[roomAt(p)] or "None" end,
    GetOwnerHouseholdId = function() return {Value = 200} end,
    IsCharacterAllowedInRoom = function(_, who, purpose, household)
        assert(who.Value > 0 and household.Value == 200 and (purpose == bedroom or purpose == study or purpose == "None"))
        return purpose == study or roomAccess
    end,
    IsExistInternalPath = function(_, source, destination, params)
        assert(params.bIgnorePermission == false and params.EntityId.Value > 0)
        assigned[#assigned + 1] = params.EntityId.Value
        return roomAt(destination) ~= 2 or bedAccess
    end,
}
local objects = {[10] = point(1200), [20] = point(2220), [30] = point(3300), [50] = point(5400), [70] = point(7500)}
local entities = {
    GetAllEntities = function() return active end,
    FindCharacter = function(_, id) return active[id.Value] end,
    FindGameObject = function(_, id)
        local location = objects[id.Value]
        if location then return {
            GetLocation = function() return location end,
            GetObjectTableRow = function() return metadata[id.Value] end,
        } end
    end,
}
local sites = {
    FindClosestSite = function() return site end,
    IsIndoor = function(_, p) return indoor and roomAt(p) ~= 8 end,
}

inzoi = {
    EB1SiteType = {Residence = 1}, EB2EntityType = {Character = 3},
    FB1EntityId = function() return {} end, FB1NavigationQueryParams = function() return {} end,
    getB2Manager = function(name) return name == "FB2EntityManager" and entities or sites end,
    getB2Subsystem = function()
        return {IsOnWalkableGrid = function(_, p) return p.X < 7500 end}
    end,
}
local function row(id, kind, available, selected)
    return {furniture_id = tostring(id), profile = {kind = kind}, available = available, furniture_pair_id = selected}
end
local furniture = {
    row(10, "bed.queen", false),
    row(20, "bed.queen", true),
    row(30, "sofa.pair", true, "left"),
    row(30, "sofa.pair", true, "right"),
    row(50, "bed.queen", true),
    row(70, "bed.queen", true),
}
local anchors = {point(1450), point(4200), point(5400), point(6200), point(8300)}
local function arrivalPoints(candidate)
    local p = candidate.point
    local width = candidate.kind == "sofa.pair" and 110 or 150
    return {p, point(p.X + width, p.Y, p.Z)}
end
local function rank()
    return Venue.candidates(initiator, partner, furniture, anchors, arrivalPoints)
end

local ranked = rank()
assert(#ranked == 4 and ranked[1].kind == "bed.queen" and ranked[1].furniture_id == "20")
assert(ranked[2].kind == "sofa.pair" and ranked[2].furniture_pair_id == "left")
assert(ranked[3].furniture_pair_id == "right" and ranked[4].kind == "ground" and roomAt(ranked[4].point) == 4)
assert(assigned[1] == 1 and assigned[2] == 2, "Check each Zoi's permissions and path")
for _, row in ipairs(furniture) do
    if row.furniture_id == "20" then row.profile.kind = "bed.single" end
end
assert(rank()[1].kind == "bed.single", "A compatible single bed must also rank ahead of ground.")
for _, row in ipairs(furniture) do
    if row.furniture_id == "20" then row.profile.kind = "bed.queen" end
end

assert(Venue.claim("first", ranked[1], initiator, partner))
local claimed, reason = Venue.claim("second", ranked[1], secondInitiator, secondPartner)
assert(not claimed and reason == "room_claimed")
claimed, reason = Venue.claim("duplicate", ranked[2], initiator, partner)
assert(not claimed and reason == "participant_busy", "One Zoi cannot hold two venue claims")
assert(Venue.claim("second", ranked[2], secondInitiator, secondPartner))
claimed, reason = Venue.claim("third", ranked[3], initiator, partner)
assert(not claimed and reason == "room_claimed", "One autonomous pair claims a room even on a four-seat sofa")
assert(Venue.recheck("first", initiator, partner))
assert(not Venue.recheck("first", partner, bystander), "Only the selected participants can recheck")
bystanderLocation.X = 2100
assert(Venue.recheck("first", initiator, partner) and Venue.recheck("second", secondInitiator, secondPartner),
    "A new observer is evaluated by sight on arrival, independently of other attempts")

Venue.release("first")
Venue.release("second")
bystanderLocation.X = 700
assert(Venue.claim("third", ranked[1], initiator, partner))
Venue.release("third")
bedAccess = false
assert(rank()[1].kind == "sofa.pair")
local canReach, reason = Venue.claim("blocked", ranked[1], initiator, partner)
assert(not canReach and reason == "walk_failed")
bedAccess, roomAccess = true, false
assert(rank()[1].kind == "sofa.pair")
local access, reason = Venue.claim("private", ranked[1], initiator, partner)
assert(not access and reason == "room_access_denied")
public = true
local none, reason = rank()
assert(#none == 0 and reason == "site_unavailable")
public, indoor = false, false
assert(#rank() == 0, "No classified interior leaves no autonomous destination")

local function contains(option, value)
    for _, candidate in ipairs(rank()) do
        if candidate[option] == value then return candidate end
    end
end

indoor, roomAccess, purposes[2], purposes[4] = true, true, nil, nil
metadata[20] = {FilterCategory = "Bed", ObjectTags = {"Seat", "Bed"}}
metadata[21] = {FilterCategory = "Closet"}
metadata[22] = {FilterCategory = "DiningRoom_Table", ObjectTags = {"Food_Table"}}
objects[21], objects[22] = point(2300), point(2420, 0, 300)
nativeObjects = {{Value = 20}, {Value = 21}, {Value = 22}}
assert(contains("furniture_id", "20"), "A native bed classifies its exact unlabeled bedroom")
assert(not contains("kind", "ground"), "Unclassified clear rooms never become a ground fallback")
assert(not contains("furniture_id", "50"), "A selected furniture profile alone cannot establish an unlabeled bedroom")

local inferred = contains("furniture_id", "20")
assert(Venue.claim("inferred", inferred, initiator, partner))
assert(Venue.recheck("inferred", initiator, partner))
objects[22].Z = 0
local valid, changedReason = Venue.recheck("inferred", initiator, partner)
assert(not valid and changedReason == "room_unclassified", "A dining table entering the room invalidates an inferred bedroom")
assert(not contains("furniture_id", "20"), "A mixed-use room cannot be inferred")
objects[22].Z = 300
metadata[21] = {FilterCategory = "SmallAppliances", ObjectFilterTags = {"Cook"}}
assert(not contains("furniture_id", "20"), "Native cooking fixtures veto bedroom inference")
metadata[21] = {FilterCategory = "Bath"}
assert(not contains("furniture_id", "20"), "Native bathroom fixtures veto bedroom inference")
metadata[21] = nil
assert(not contains("furniture_id", "20"), "Unresolved room fixture metadata fails closed")
metadata[21] = {FilterCategory = "Closet"}
assert(Venue.recheck("inferred", initiator, partner))

roomAccess = false
valid, changedReason = Venue.recheck("inferred", initiator, partner)
assert(not valid and changedReason == "room_access_denied", "Inferred bedrooms retain native permission checks")
roomAccess, purposes[2] = true, "PublicPurpose"
assert(not contains("furniture_id", "20"), "An explicit incompatible purpose takes priority over furniture")
assert(not Venue.recheck("inferred", initiator, partner))
purposes[2], metadata[20].ObjectTags = nil, {"Seat"}
assert(not Venue.recheck("inferred", initiator, partner), "Removing the qualifying bed invalidates the claim")
Venue.release("inferred")
print("NPC venue checks passed: ranking, exact seats, private-room inference, permissions, ground fallback, competing claims, and intrusion.")
