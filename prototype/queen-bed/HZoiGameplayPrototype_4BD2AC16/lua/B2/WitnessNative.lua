local M = {}

local function id(actor)
    local value = actor:GetEntityId()
    return tostring(type(value) == "number" and value or value.Value)
end

function M.isOfficialPartner(witness, participant)
    local components = inzoi.EB2ComponentType
    local bio = witness:GetComponent(components.Bio)
    local spouse = bio and bio:GetSpouseCharacter()
    if spouse and id(spouse) == id(participant) then return true end
    local relation = witness:GetComponent(components.Relationship)
    local data = relation and relation:FindRelationshipData(participant:GetEntityId())
    if not data then return false end
    for _, entry in ipairs(data.RelationshipInfoList or {}) do
        local name = tostring(entry.Id):lower()
        if name == "youth_lover" or name == "engagement" then return true end
    end
    return false
end

function M.hasTrait(character, trait)
    local view = character:GetComponent(inzoi.EB2ComponentType.Trait)
    return view and view:HasTrait(trait) == true
end

-- Let an idle, non-possessed bystander move out of the encounter's way.
function M.walkAway(witness, near)
    if not witness or not near or id(witness) == tostring(inzoi.FB2ControllerSystem.GetPossessEntityId().Value) then
        return
    end
    local interaction = witness:GetComponent(inzoi.EB2ComponentType.Interaction)
    if not interaction or interaction:IsQueueEmpty() ~= true or interaction:IsPlayingInteraction() ~= false then return end

    local here, scene = witness:GetLocation(), near:GetLocation()
    local dx, dy = here.X - scene.X, here.Y - scene.Y
    if dx * dx + dy * dy < 1 then return end
    local siteManager = inzoi.getB2Manager("FB2SiteManager")
    local site = siteManager and siteManager:FindClosestSite(here, false)
    local grid = inzoi.getB2Subsystem("FB2PathFindSystem")
    if not site or not grid or not siteManager:IsLocatedInSite(site:GetSiteId(), here) then return end

    local query = inzoi.FB1NavigationQueryParams()
    query.EntityId = witness:GetEntityId()
    query.bIgnorePermission = false
    local away = math.atan(dy, dx)
    for _, offset in ipairs({0, .4, -.4, .8, -.8}) do
        local angle = away + offset
        local point = UE.FVector(here.X + math.cos(angle) * 180, here.Y + math.sin(angle) * 180, here.Z)
        if grid:IsOnWalkableGrid(point) and site:CheckReachablePoint(point) and site:IsExistInternalPath(here, point, query) then
            return interaction:AddInteractionQueueByParam(
                inzoi.FB1EntityId(), point, "HZoiGameplay_Walk", inzoi.EB1InteractionPlayReason.Reaction,
                false, false, "HZoi Gameplay witness", true, false)
        end
    end
end

-- Let the native localized line explain why the NPC dropped the approach.
function M.privacyComplaint(initiator, partner)
    local context = inzoi.FB2ScriptContext(initiator:GetEntityId(), partner:GetEntityId(), inzoi.EB1ScriptReason.Howling)
    local command = inzoi.FB1Execute()
    command.BaseObject = inzoi.EB1BaseObject.Self
    command.Command = inzoi.EB1ExecuteType.AddSpeechBubble
    command.S1, command.S2, command.Prob = "SpeechBubble_Hope_Solitude_HaveAloneTime", "None", 1
    inzoi.FB2Script_SpeechBubble.Execute_AddSpeechBubble(context, command)
end

return M
