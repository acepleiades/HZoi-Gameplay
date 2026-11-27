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
local tick, booking, crossSiteAllowed, crossSiteChecks = 400, nil, true, 0
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
    GetEntityId = function() return {Value = 900} end,
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
    QuerySiteAreaPath = function(_, output, source, destination, params)
        assert(type(output) == "table" and source.X < 0 and site:IsIn(destination))
        assert(params.bIgnorePermission == false and params.EntityId.Value == 2)
        crossSiteChecks = crossSiteChecks + 1
        return crossSiteAllowed
    end,
}

inzoi = {
    EB1SiteType = {Residence = 1}, EB2EntityType = {Character = 3}, EB2ComponentType = {Slot = 4},
    FB1EntityId = function() return {} end, FB1NavigationQueryParams = function() return {} end,
    FB1NavigationPath = function() return {} end,
    FB2TimeManager = {StaticGetCurrentTicks = function() return tick end},
    getB2Manager = function(name)
        if name == "FB2EntityManager" then return entities end
        if name == "FB2SiteManager" then return sites end
        if name == "FB2HouseholdBizManager" and booking then
            return {FindHouseholdBizBySiteEntityIdPtr = function(_, id)
                assert(id.Value == 900)
                return {BizInfoData = {AccommodationInfoList = {Infos = booking}}}
            end}
        end
    end,
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

local Planner = require("NpcVenuePlanner")
local nearDoor, nearCenter, farCenter = point(210), point(520), point(430)
local placementOrder = {
    [nearCenter] = {room = nearDoor, order = 1},
    [nearDoor] = {room = nearDoor, order = 2},
    [farCenter] = {room = farCenter, order = 1},
}
local allowCenter = true
local function standingOrder()
    return Planner.candidates({}, {nearDoor, nearCenter, farCenter}, function(option)
        if option.point ~= nearCenter or allowCenter then
            return false, option.point.X, arrivalPoints(option)
        end
    end, placementOrder)
end
local standingRanked = standingOrder()
assert(standingRanked[1].point == nearCenter and standingRanked[2].point == nearDoor
    and standingRanked[3].point == farCenter, "Choose the room, then favor its interior over the doorway")
allowCenter = false
assert(standingOrder()[1].point == nearDoor, "Keep a reachable alternative if the center cannot be used")

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
local none, _, rejected = rank()
assert(#none == 0 and rejected.room_privacy_unverified, "A public common room cannot qualify on vacancy alone")
roomAccess = true
booking = {{RoomKey = {AccommodationDtId = "site", RoomPurposeId = bedroom},
    StartTicks = 100, EndTicks = 500, GuestEntityIds = {{Value = 1}}}}
assert(#rank() == 0, "Both Zois must be included in the active room booking")
booking[1].GuestEntityIds[2] = {Value = 2}
booking[1].RoomKey.AccommodationDtId = "other_site"
assert(#rank() == 0, "A booking elsewhere cannot authorize this room")
booking[1].RoomKey.AccommodationDtId = "site"
booking[1].RoomKey.RoomPurposeId = "EntireSite"
assert(#rank() == 0, "A whole-site booking does not prove that a particular room is private")
booking[1].RoomKey.RoomPurposeId = bedroom
roomAccess = false
local booked = rank()
assert(#booked == 1 and booked[1].furniture_id == "20",
    "An active booking authorizes the guest pair even when the residence permission does not")
bedAccess = false
assert(#rank() == 0, "Room authorization never bypasses the permission-aware native route")
bedAccess = true
local standing = Venue.candidates(initiator, partner, {}, {point(2220), point(4200)}, arrivalPoints)
assert(#standing == 1 and standing[1].kind == "ground" and standing[1].room_purpose == bedroom,
    "A booked room without compatible furniture can serve as a standing venue")
assert(Venue.claim("booked", standing[1], initiator, partner))
tick = 500
local stillBooked, reason = Venue.recheck("booked", initiator, partner)
assert(not stillBooked and reason == "room_privacy_unverified", "Booking expiry invalidates the claim")
Venue.release("booked")
booking = nil
public, indoor = false, false
assert(#rank() == 0, "No indoor room leaves no autonomous destination")

indoor, roomAccess = true, true
local originalPartnerPosition = partner.GetLocation
partner.GetLocation = function() return point(-40) end
local acrossLotLine = rank()
assert(#acrossLotLine == 6 and crossSiteChecks > 0, "Reachable partners may start on opposite sides of a lot line")
assert(Venue.claim("cross-site", acrossLotLine[1], initiator, partner))
crossSiteAllowed = false
local reachable, routeReason = Venue.recheck("cross-site", initiator, partner, acrossLotLine[1].arrival_points)
assert(not reachable and routeReason == "walk_failed", "The native approach remains required from outside a venue lot")
Venue.release("cross-site")
assert(#rank() == 0, "Unavailable cross-site routes cannot use geometrically near venues")
crossSiteAllowed, partner.GetLocation = true, originalPartnerPosition
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

objects[15], objects[80] = point(6550), point(1400)
ownership[20] = nil
ownership[50] = {[{Value = 1}] = "BedSlot_Single"}
local expectedOrder = {
    {kind = "bed.single", id = "50", priority = 1},
    {kind = "bed.queen", id = "20", priority = 2},
    {kind = "bed.queen", id = "15", priority = 2},
    {kind = "bed.single", id = "80", priority = 3},
    {kind = "sofa.pair", id = "30", pair = "left", priority = 4},
    {kind = "sofa.pair", id = "30", pair = "right", priority = 4},
    {kind = "ground", priority = 5},
}

for _, occupiedPass in ipairs({false, true}) do
    active = {initiator, partner}
    if occupiedPass then
        -- These observers occupy the rooms without using the selected furniture.
        for room = 1, 6 do active[#active + 1] = character(room + 2, point(room * 1000 + 100)) end
    end
    local options = {
        row(30, "sofa.pair", true, "right"), row(15, "bed.queen", true),
        row(80, "bed.single", true), row(50, "bed.single", true),
        row(20, "bed.queen", true), row(30, "sofa.pair", true, "left"),
        row(30, "sofa.pair", true), -- A sofa row must name an exact pair.
    }
    local standing = {point(4200)}
    for index, expected in ipairs(expectedOrder) do
        local ranked = Venue.candidates(initiator, partner, options, standing, arrivalPoints)
        assert(#ranked == #expectedOrder - index + 1, "A blocked candidate leaves the remaining venue tiers available")
        local winner = ranked[1]
        assert(winner.kind == expected.kind and winner.furniture_id == expected.id
            and winner.furniture_pair_id == expected.pair and winner.priority == expected.priority
            and winner.occupied == occupiedPass,
            ("Tier %d, occupied pass %s, ranked %s/%s/%s with priority %s and occupied=%s")
                :format(index, tostring(occupiedPass), winner.kind, tostring(winner.furniture_id),
                    tostring(winner.furniture_pair_id), tostring(winner.priority), tostring(winner.occupied)))
        if expected.id then
            for _, option in ipairs(options) do
                if option.furniture_id == expected.id and option.furniture_pair_id == expected.pair then
                    option.available = false
                end
            end
        else
            assert(Venue.claim("last-stand", winner, initiator, partner))
            assert(Venue.recheck("last-stand", initiator, partner, winner.arrival_points))
            Venue.release("last-stand")
            standing = {}
        end
    end
    local none = Venue.candidates(initiator, partner, options, standing, arrivalPoints)
    assert(#none == 0, "No available furniture, exact sofa pair or standing spot leaves no venue")
end

print("NPC venue checks passed: all venue tiers in both passes, nearest double bed, exact sofa pairs, no venue, access and reservations.")
