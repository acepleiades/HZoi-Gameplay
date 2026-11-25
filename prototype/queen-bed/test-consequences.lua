local effects = require("EncounterConsequences")

local needs = {
    Hunger = -36,
    Cleanliness = -34,
    Energy = -32,
    Fun = 98,
    Society = 85,
}
local bounds = {
    Hunger = {-100, 100},
    Cleanliness = {-100, 100},
    Energy = {-100, 100},
    Fun = {-100, 100},
    Society = {0, 100},
}
local statWrites, moodlets = {}, {}
local stats = {
    HasStat = function(_, name) return needs[name] ~= nil end,
    GetStat = function(_, name) return needs[name] end,
    SetStat = function(_, name, value, reason)
        assert(reason == "interaction")
        needs[name] = value
        statWrites[#statWrites + 1] = name
    end,
}
local statSystem = {
    Clamp = function(_, name, value)
        return math.max(bounds[name][1], math.min(bounds[name][2], value))
    end,
}
local people, traits = {}, {}
for _, who in ipairs({101, 102}) do
    local buffs = {AddBuff = function(_, id) moodlets[who] = id end}
    people[who] = {GetComponent = function(_, component)
        if component == "Buff" then return buffs end
        if component == "Trait" then return {HasTrait = function(_, trait)
            return traits[who] and traits[who][trait] == true
        end} end
        if who == 101 and component == "Stat" then return stats end
    end}
end

inzoi = {
    FB1EntityId = function() return {} end,
    getB2Manager = function(name)
        assert(name == "FB2EntityManager")
        return {FindCharacter = function(_, id) return people[id.Value] end}
    end,
    getB2Subsystem = function(name)
        assert(name == "FB2StatSystem")
        return statSystem
    end,
    EB2ComponentType = {Stat = "Stat", Buff = "Buff", Trait = "Trait"},
    EB1ScriptReason = {Interaction = "interaction"},
}

local encounter = {session_id = "test", participants = {"101", "102"}, completions = {}}
effects.onCompletion(encounter, "101", "unrelated", 1)
assert(#statWrites == 0)
effects.onCompletion(encounter, "101", "excitement", 1)
assert(needs.Hunger == -36 and needs.Cleanliness == -34 and needs.Energy == -34)
assert(needs.Fun == 100 and needs.Society == 90 and #statWrites == 3)
effects.onCompletion(encounter, "102", "excitement", 1)
assert(#statWrites == 3)
needs.Hunger = 10
needs.Energy = 5
needs.Society = nil
effects.onCompletion(encounter, "101", "excitement", 2)
assert(needs.Hunger == -2.5 and needs.Energy == -7.5 and #statWrites == 5)

local manualExit = {stop_reason = "ok", stop_origin = {source = "framework"}}
effects.onResult(encounter, manualExit)
assert(moodlets[101] == "HZoiGameplay_UnfinishedMoment" and moodlets[102] == moodlets[101])
encounter.completions["101"] = {excitement = 2}
effects.onResult(encounter, manualExit)
assert(moodlets[101] == "HZoiGameplay_Satisfied" and moodlets[102] == "HZoiGameplay_OutOfSync")
encounter.completions["102"] = {excitement = 1}
effects.onResult(encounter, manualExit)
assert(moodlets[101] == "HZoiGameplay_InSync" and moodlets[102] == moodlets[101])

encounter.completions = {}
effects.onResult(encounter, {stop_reason = "addon_requested", stop_origin = {reason = "witness_sighting"}})
assert(moodlets[101] == "HZoiGameplay_AwkwardTiming" and moodlets[102] == moodlets[101])
encounter.witnessPolicy = {incidents = {{witness_id = "103", cheater_id = "101"}}}
moodlets = {}
effects.onResult(encounter, manualExit)
assert(next(moodlets) == nil)
traits[101] = {Cooperator = true}
effects.onResult(encounter, manualExit)
assert(moodlets[101] == "HZoiGameplay_ThrillOfBeingCaught" and not moodlets[102])

encounter.witnessPolicy = nil
encounter.completions = {["101"] = {excitement = 1}, ["102"] = {excitement = 1}}
traits[101] = {Romantic = true}
traits[102] = {Romantic = true, Aptitude_Casanova = true}
effects.onResult(encounter, manualExit)
assert(moodlets[101] == "HZoiGameplay_InSync_Romantic")
assert(moodlets[102] == "HZoiGameplay_AGoodImpression_Romantic")

traits[101] = {CleanFreak = true, Artist = true}
effects.onResult(encounter, manualExit)
assert(moodlets[101] == "HZoiGameplay_CouldUseAShower")
needs.Cleanliness = 10
effects.onResult(encounter, manualExit)
assert(moodlets[101] == "HZoiGameplay_PerfectImprovisation")
print("Encounter consequences and trait moodlets passed")
