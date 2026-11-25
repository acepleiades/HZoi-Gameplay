local Json = require("SceneZOIAddon.Json")
local M = {}

local MINUTE = 600000000
local HOUR = 60 * MINUTE
local LIFETIME = 12 * HOUR
local COOLDOWN = 48 * HOUR
local rows, lastTicks, nextSweep = {}, nil, 0

local function id(entity)
    local value = type(entity) == "number" and entity or (entity and entity.Value)
    return type(value) == "number" and value > 0 and ("%d"):format(value) or nil
end

local function entity(actor)
    return actor and actor:GetEntityId()
end

function M.reset()
    rows, lastTicks, nextSweep = {}, nil, 0
end

local function now()
    local tick = inzoi.FB2TimeManager.StaticGetCurrentTicks()
    if type(tick) ~= "number" or tick <= 0 or tick >= math.huge or tick ~= tick then return end
    if lastTicks and tick < lastTicks then M.reset() end
    lastTicks = tick
    if tick >= nextSweep then
        for key, row in pairs(rows) do
            if tick >= row.cooldown then rows[key] = nil end
        end
        nextSweep = tick + HOUR
    end
    return tick
end

local function adult(actor)
    local growth = actor:GetGrowthStep()
    local steps = inzoi.EB1GrowthStep
    return growth == steps.Youth or growth == steps.Adult or growth == steps.Old or growth == steps.Elderly
end

local function scriptContext(ownerId, partnerId)
    return inzoi.FB2ScriptContext(ownerId, partnerId, inzoi.EB1ScriptReason.Hope)
end

local function check(context, predicate, command, reference, object, compare)
    local condition = inzoi.FB1Condition()
    condition.BaseObject = object
    condition.Command = inzoi.EB1ConditionType[command]
    condition.CompareType = compare
    condition.UseHand = inzoi.EB1UseHandType.Default
    condition.S1, condition.S2 = reference, "None"
    condition.F1, condition.F2 = 0, 0
    return predicate(context, condition) == true
end

local function namedRelationship(data)
    local named, former = false, false
    for _, relation in ipairs(data.RelationshipInfoList or {}) do
        local name = tostring(relation.Id):lower()
        named = named or name == "youth_lover"
        former = former or name == "highteen_lover"
    end
    return named, former
end

local function eligiblePair(owner, partner)
    if not owner or not partner or not adult(owner) or not adult(partner)
        or owner:IsDeath() ~= false or partner:IsDeath() ~= false or owner:IsInRabbitHole() ~= false then return end
    local ownerId, partnerId = entity(owner), entity(partner)
    if not id(ownerId) or not id(partnerId) or ownerId.Value == partnerId.Value then return end

    local kinds = inzoi.EB2ComponentType
    local traits = owner:GetComponent(kinds.Trait)
    local emotion = owner:GetComponent(kinds.Emotion)
    local buffs = owner:GetComponent(kinds.Buff)
    if not (traits and traits:HasTrait("Needy") == true and emotion and emotion:IsCurrentEmotion("Sleep") == false
        and buffs and buffs:HasBuffTag("BuffTag_InPrison") == false) then return end
    if inzoi.FB2SiteEventManager.StaticIsPlayingSiteEvent(ownerId) ~= false then return end

    local context = scriptContext(ownerId, partnerId)
    local compare, base = inzoi.EB1CompareType, inzoi.EB1BaseObject
    if not check(context, inzoi.FB2Script_Site.Condition_EnteredSiteHasTag, "EnteredSiteHasTag",
            "Cahaya_DesertIsland", base.Self, compare.NotEqual)
        or not check(context, inzoi.FB2Script_Relationship.Condition_IsLovable, "IsLovable",
            "None", base.Self, compare.Equal) then return end

    local relationships = owner:GetComponent(kinds.Relationship)
    local data = relationships and relationships:FindRelationshipData(partnerId)
    if not data then return end
    local named, former = namedRelationship(data)
    if not named and not former then return end
    local romance = relationships:FindRelationshipStatData(partnerId, "Romance")
    if romance and type(romance.Value) == "number" and math.abs(romance.Value) < math.huge then
        return romance.Value, named, data, context
    end
end

function M.canInvite(owner, partner)
    local romance, named, data, context = eligiblePair(owner, partner)
    if not romance or romance < (named and -30 or 30) or data.bIsFamilyRelationship ~= false then return false end

    local remote = inzoi.FB2Script_City.Condition_IsFromRemoteCity
    local compare, objects = inzoi.EB1CompareType, inzoi.EB1BaseObject
    return check(context, remote, "IsFromRemoteCity", "None", objects.Self, compare.NotEqual)
        and check(context, remote, "IsFromRemoteCity", "None", objects.Target, compare.NotEqual)
end

local function notify(owner, kind, partnerName)
    local ownerId = entity(owner)
    if id(inzoi.FB2ControllerSystem.GetPossessEntityId()) ~= id(ownerId) then return end
    inzoi.message.send_to_client(ownerId, "HZoiGameplay.Urge", Json.encode({kind = kind, partner = partnerName}))
end

local function displayName(person)
    local first, last = person:GetFirstName(), person:GetLastName()
    local full = ((first or "") .. " " .. (last or "")):match("^%s*(.-)%s*$")
    return full ~= "" and full or "their partner"
end

function M.pending(owner)
    local key, tick = id(entity(owner)), now()
    local row = key and rows[key]
    if not tick or not row or not row.expires or tick >= row.expires then return end
    return {partner = row.partner, expires = row.expires}
end

function M.request(owner, partner)
    local key, partnerId, tick = id(entity(owner)), id(entity(partner)), now()
    if not tick or not key or not partnerId or key == partnerId then return false, "invalid_pair" end
    if rows[key] and rows[key].cooldown > tick then return false, "cooldown" end
    local romance = eligiblePair(owner, partner)
    if not romance or romance >= 30 then return false, "ineligible" end

    local name = displayName(partner)
    rows[key] = {partner = partnerId, partnerName = name, expires = tick + LIFETIME, cooldown = tick + COOLDOWN}
    pcall(notify, owner, "selected", name)
    print("[HZoiGameplay] urge_offered " .. Json.encode({participant = key, partner = partnerId}))
    return true
end

-- Use the relationship index to find named lovers among available actors.
-- If more than one qualifies, prefer the highest Romance and break ties by ID.
function M.requestEligible(owner, lookupActorById)
    local key, tick = id(entity(owner)), now()
    if not tick or not key or (rows[key] and rows[key].cooldown > tick) then return end
    local kinds = inzoi.EB2ComponentType
    local traits = owner:GetComponent(kinds.Trait)
    local relationships = owner:GetComponent(kinds.Relationship)
    if not traits or traits:HasTrait("Needy") ~= true or not relationships then return end

    local best, bestId, bestRomance
    for nativeTarget, data in pairs(relationships:GetRelationshipDataMap() or {}) do
        local named, former = namedRelationship(data)
        if named or former then
            local targetId = id(nativeTarget)
            local partner = targetId and lookupActorById(targetId)
            local romance = partner and eligiblePair(owner, partner)
            if romance and romance < 30
                and (not best or romance > bestRomance or (romance == bestRomance and targetId < bestId)) then
                best, bestId, bestRomance = partner, targetId, romance
            end
        end
    end
    if best and M.request(owner, best) then return M.pending(owner) end
end

local function applyReward(context, domain, command, value, amount)
    local execute = inzoi.FB1Execute()
    execute.BaseObject = inzoi.EB1BaseObject.Self
    execute.Command = inzoi.EB1ExecuteType[command]
    execute.S1, execute.S2 = value, "None"
    execute.F1, execute.F2, execute.Prob = amount, 0, 1
    inzoi[domain]["Execute_" .. command](context, execute)
end

function M.onCompletion(encounter, owner, taskId)
    if taskId ~= "excitement" then return false end
    local key, tick = id(entity(owner)), now()
    if not key or not tick or (key ~= encounter.initiator and key ~= encounter.partner) then return false end
    local partner = key == encounter.initiator and encounter.partner or encounter.initiator
    local row = rows[key]
    if not row or not row.expires or tick >= row.expires or row.partner ~= partner then return false end

    local target = inzoi.FB1EntityId()
    target.Value = tonumber(partner)
    local context = scriptContext(entity(owner), target)
    -- Consume before calling native scripts. A partially applied reward must
    -- not be submitted again on a repeated event.
    row.expires = nil
    local rewards = {
        {"FB2Script_Buff", "AddBuff", "Buff_Needy_LoveLover", 0},
        {"FB2Script_Currency", "AddCurrency", "CatShopPoint", 5},
        {"FB2Script_Stat", "AddStat", "Admit", 15},
    }
    for _, reward in ipairs(rewards) do
        local ok, problem = pcall(applyReward, context, table.unpack(reward))
        if not ok then print("[HZoiGameplay] Urge reward " .. reward[2] .. " failed: " .. tostring(problem)) end
    end
    pcall(notify, owner, "fulfilled", row.partnerName)
    return true
end

return M
