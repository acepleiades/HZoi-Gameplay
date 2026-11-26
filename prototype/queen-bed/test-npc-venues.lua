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
local ownership = {}
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
    GetRoomPurposeIdByLocation = function(_, p) return purposes[roomAt(p)] or "None" end,
    GetOwnerHouseholdId = function() return {Value = 200} end,
    IsCharacterAllowedInRoom = function(_, who, purpose, household)
        assert(who.Value > 0 and household.Value == 200 and type(purpose) == "string")
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
            GetComponent = function(_, component)
                assert(component == 4)
                return {GetSlotOwnershipInfos = function() return ownership[id.Value] or {} end}
            end,
        } end
    end,
}
local sites = {
    FindClosestSite = function() return site end,
    IsIndoor = function(_, p) return indoor and roomAt(p) ~= 8 end,
}

inzoi = {
    EB1SiteType = {Residence = 1}, EB2EntityType = {Character = 3}, EB2ComponentType = {Slot = 4},
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
    row(50, "bed.single", true),
    row(70, "bed.queen", true),
}
local anchors = {point(4200), point(6200)}
local function arrivalPoints(candidate)
    local p = candidate.point
    local width = candidate.kind == "sofa.pair" and 110 or 150
    return {p, point(p.X + width, p.Y, p.Z)}
end
local function rank()
    return Venue.candidates(initiator, partner, furniture, anchors, arrivalPoints)
end

local ranked = rank()
assert(#ranked == 6 and ranked[1].kind == "bed.queen" and ranked[1].furniture_id == "20")
assert(ranked[2].kind == "bed.single" and ranked[2].furniture_id == "50")
assert(ranked[3].furniture_pair_id == "left" and ranked[4].furniture_pair_id == "right")
assert(ranked[5].kind == "ground" and roomAt(ranked[5].point) == 4 and not ranked[5].occupied)
assert(assigned[1] == 1 and assigned[2] == 2, "Check each Zoi's permissions and path")
ownership[50] = {ToTable = function() return {[{Value = 1}] = "BedSlot_Single"} end}
assert(rank()[1].furniture_id == "50" and rank()[1].priority == 1, "An assigned single bed outranks a double")
ownership[50] = {[{Value = 2}] = "BedSlot_Single"}
assert(rank()[1].furniture_id == "20", "Only the initiator's assignment grants top priority")
ownership[50] = nil

assert(Venue.claim("first", ranked[1], initiator, partner))
local claimed, reason = Venue.claim("second", ranked[1], secondInitiator, secondPartner)
assert(not claimed and reason == "room_claimed")
claimed, reason = Venue.claim("duplicate", ranked[3], initiator, partner)
assert(not claimed and reason == "participant_busy", "One Zoi cannot hold two venue claims")
assert(Venue.claim("second", ranked[3], secondInitiator, secondPartner))
claimed, reason = Venue.claim("third", ranked[4], initiator, partner)
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
assert(rank()[1].kind == "bed.single")
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
assert(#rank() == 0, "No indoor room leaves no autonomous destination")

indoor, roomAccess = true, true
purposes[2], purposes[3], purposes[4] = nil, nil, nil
ownership[20] = {[{Value = 1}] = "BedSlot_Left"}
assert(rank()[1].furniture_id == "20" and rank()[1].assigned, "Unlabelled bedrooms qualify")
bystanderLocation.X = 2200
local fallback = rank()
assert(fallback[1].furniture_id == "50" and not fallback[1].occupied, "A vacant single bed beats an occupied assigned bedroom")
assert(fallback[2].kind == "sofa.pair", "An unlabelled living room qualifies")
assert(fallback[4].kind == "ground" and fallback[6].furniture_id == "20" and fallback[6].occupied,
    "Exhaust all vacant rooms, including standing, before the occupied assigned bedroom")
local nowOccupied, code = Venue.claim("new-occupant", ranked[1], initiator, partner)
assert(not nowOccupied and code == "room_occupied", "A first-pass claim rechecks vacancy")
assert(Venue.claim("fallback", fallback[6], initiator, partner), "The fallback can claim a free bed in an occupied room")
assert(Venue.recheck("fallback", initiator, partner), "Arrival privacy is handled separately")
assert(not Venue.claim("same-room", fallback[6], secondInitiator, secondPartner), "Fallback never overrides a room claim")
Venue.release("fallback")
roomAccess = false
local denied, reason = Venue.claim("no-access", fallback[6], initiator, partner)
assert(not denied and reason == "room_access_denied", "Fallback still requires access for both Zois")
roomAccess = true
furniture[2].available = false
for _, candidate in ipairs(rank()) do
    assert(candidate.furniture_id ~= "20", "Fallback never uses unavailable furniture")
end
furniture[2].available = true
active = {initiator, partner, bystander, secondInitiator, secondPartner, character(6, point(3400)), character(7, point(4450))}
secondInitiator.GetLocation = function() return point(5400) end
secondPartner.GetLocation = function() return point(6200) end
local occupied = rank()
for _, candidate in ipairs(occupied) do assert(candidate.occupied) end
assert(occupied[1].assigned and occupied[2].kind == "bed.single" and occupied[3].kind == "sofa.pair",
    "When every room is occupied, apply the same priorities from the start")
print("NPC venue checks passed: assigned beds, vacant-first ranking, occupied fallback, access, reservations and standing.")
