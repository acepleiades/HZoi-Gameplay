local Json = require("SceneZOIAddon.Json")
local Urges = require("OwnedEncounterUrges")
local hour = 36000000000
local ticks, controlled, rewards, notices = 80 * hour, 14, {}, {}
local models = {}
local kinds = {Trait = "Trait", Emotion = "Emotion", Buff = "Buff", Relationship = "Relationship"}
local function entity(value) return {Value = value or -1} end
local function actor(id, rules)
    local person = {
        GetEntityId = function() return entity(id) end,
        GetGrowthStep = function() return rules.growth or 32 end,
        GetFirstName = function() return rules.name or "Zoi" end,
        GetLastName = function() return "Test" end,
        IsDeath = function() return rules.dead == true end,
        IsInRabbitHole = function() return rules.rabbit == true end,
    }
    local components = {
        Trait = {HasTrait = function(_, name) return name == "Needy" and rules.needy == true end},
        Emotion = {IsCurrentEmotion = function(_, name) return name == "Sleep" and rules.sleeping == true end},
        Buff = {HasBuffTag = function(_, name) return name == "BuffTag_InPrison" and rules.prison == true end},
        Relationship = {
            FindRelationshipData = function(_, target)
                local relationship = rules.relationships and rules.relationships[target.Value]
                if not relationship then return end
                return {bIsFamilyRelationship = rules.family == true,
                    RelationshipInfoList = {{Id = relationship.name or "Youth_Lover"}}}
            end,
            GetRelationshipDataMap = function()
                local result = {}
                for partner, relationship in pairs(rules.relationships or {}) do
                    result[entity(partner)] = {RelationshipInfoList = {{Id = relationship.name or "Youth_Lover"}}}
                end
                return result
            end,
            FindRelationshipStatData = function(_, target, stat)
                assert(stat == "Romance")
                return {Value = rules.relationships[target.Value].score}
            end,
        },
    }
    person.GetComponent = function(_, kind) return components[kind] end
    models[id] = rules
    return person
end
local ownerRules = {name = "Eli", needy = true, relationships = {[23] = {score = 14}, [42] = {score = 12}}}
local owner, partner = actor(14, ownerRules), actor(23, {name = 'Alex "Jr."' })
local third = actor(42, {name = "Sam"})
local function reward(command, id, amount)
    return function(ctx, param)
        assert(ctx.owner.Value == 14 and ctx.target.Value == 23)
        assert(param.Command == command and param.BaseObject == 1 and param.S1 == id and param.F1 == amount)
        rewards[#rewards + 1] = command
    end
end

inzoi = {
    EB2ComponentType = kinds,
    EB1GrowthStep = {Youth = 32, Adult = 64, Old = 128, Elderly = 256},
    EB1ScriptReason = {Hope = 23},
    EB1BaseObject = {Self = 1, Target = 2},
    EB1CompareType = {Equal = 1, NotEqual = 2},
    EB1ConditionType = {IsLovable = 58, EnteredSiteHasTag = 181, IsFromRemoteCity = 162},
    EB1UseHandType = {Default = 0},
    EB1ExecuteType = {AddBuff = 1, AddCurrency = 2, AddStat = 3},
    FB1Condition = function() return {} end,
    FB1Execute = function() return {} end,
    FB1EntityId = entity,
    FB2ScriptContext = function(first, second, reason)
        assert(reason == 23 and first.Value > 0 and second.Value > 0)
        return {owner = first, target = second}
    end,
    FB2TimeManager = {StaticGetCurrentTicks = function() return ticks end},
    FB2SiteEventManager = {StaticIsPlayingSiteEvent = function(who) return models[who.Value].siteEvent == true end},
    FB2ControllerSystem = {GetPossessEntityId = function() return entity(controlled) end},
    FB2Script_Relationship = {
        Condition_IsLovable = function(ctx, condition)
            assert(condition.BaseObject == 1 and condition.CompareType == 1 and condition.Command == 58)
            return not models[ctx.target.Value].notLovable
        end,
    },
    FB2Script_Site = {
        Condition_EnteredSiteHasTag = function(ctx, condition)
            assert(condition.BaseObject == 1 and condition.CompareType == 2 and condition.S1 == "Cahaya_DesertIsland")
            return not models[ctx.owner.Value].desertIsland
        end,
    },
    FB2Script_City = {
        Condition_IsFromRemoteCity = function(ctx, condition)
            assert(condition.CompareType == 2 and condition.Command == 162)
            local who = condition.BaseObject == 1 and ctx.owner or ctx.target
            return not models[who.Value].remote
        end,
    },
    FB2Script_Buff = {Execute_AddBuff = reward(1, "Buff_Needy_LoveLover", 0)},
    FB2Script_Currency = {Execute_AddCurrency = reward(2, "CatShopPoint", 5)},
    FB2Script_Stat = {Execute_AddStat = reward(3, "Admit", 15)},
    message = {send_to_client = function(who, kind, content)
        assert(kind == "HZoiGameplay.Urge" and who.Value == controlled)
        notices[#notices + 1] = Json.decode(content)
    end},
}

for _, state in ipairs({"sleeping", "siteEvent", "desertIsland", "dead", "prison", "rabbit"}) do
    ownerRules[state] = true
    assert(not Urges.request(owner, partner), state)
    ownerRules[state] = false
end
models[23].notLovable = true
assert(not Urges.request(owner, partner))
models[23].notLovable = false
ownerRules.relationships[23].score = 30
assert(not Urges.request(owner, partner) and Urges.canInvite(owner, partner), "A high Romance partner can invite")
ownerRules.relationships[23].score = -31
assert(not Urges.canInvite(owner, partner), "Keep very low Romance Urges pending")
ownerRules.relationships[23].score = 14
models[23].remote = true
assert(not Urges.canInvite(owner, partner))
models[23].remote = false
assert(Urges.canInvite(owner, partner))

assert(Urges.request(owner, partner))
local pending = assert(Urges.pending(owner))
assert(pending.partner == "23" and pending.expires == ticks + 12 * hour)
assert(#notices == 1 and notices[1].kind == "selected" and notices[1].partner == 'Alex "Jr." Test')
assert(not Urges.request(owner, third), "A later eligible partner cannot replace the ongoing Urge")

local encounter = {initiator = "23", partner = "14", session_id = "first"}
assert(not Urges.onCompletion(encounter, partner, "excitement"))
assert(not Urges.onCompletion(encounter, owner, "other_task"))
assert(not Urges.onCompletion({initiator = "14", partner = "42"}, owner, "excitement"))
assert(Urges.pending(owner) and #rewards == 0)
assert(Urges.onCompletion(encounter, owner, "excitement"))
assert(not Urges.pending(owner) and #rewards == 3 and #notices == 2)
assert(notices[2].kind == "fulfilled")
assert(not Urges.onCompletion(encounter, owner, "excitement") and #rewards == 3)

ticks = ticks + 48 * hour - 1
assert(not Urges.request(owner, partner), "Cooldown is based on game time")
ticks = ticks + 1
controlled = 99
assert(Urges.request(owner, partner) and #notices == 2, "Background Urges do not interrupt the player's UI")
ticks = ticks + 12 * hour
assert(not Urges.pending(owner) and not Urges.onCompletion(encounter, owner, "excitement"))
assert(not Urges.request(owner, partner), "Expiration does not reset the cooldown")
ticks = 14 * hour
assert(Urges.request(owner, partner), "A backward game-time jump clears old world state")
Urges.reset()
assert(not Urges.pending(owner), "World teardown clears the fallback")
local found = Urges.requestEligible(owner, function(id)
    return ({["23"] = partner, ["42"] = third})[id]
end)
assert(found.partner == "23", "Select the eligible named lover with the highest Romance")
Urges.reset()
ownerRules.relationships[23].name = "romance5"
found = Urges.requestEligible(owner, function(id)
    return ({["23"] = partner, ["42"] = third})[id]
end)
assert(found.partner == "42", "A score band is not a named lover")
print("Owned Urges passed: exact target, native eligibility, same-game-time cooldown/expiry, reward once, and world reset.")
