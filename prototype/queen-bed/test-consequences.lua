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
local statWrites, moodlets, buffInitiators = {}, {}, {}
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
for _, who in ipairs({101, 102, 103}) do
    local buffs = {AddBuff = function(_, id, detail, desireBoost)
        assert(detail.Reason == "howling" and people[detail.Initiator.Value])
        assert(desireBoost == "None")
        moodlets[who], buffInitiators[who] = id, detail.Initiator.Value
    end}
    people[who] = {GetEntityId = function() return {Value = who} end, GetComponent = function(_, component)
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
    EB1ScriptReason = {Interaction = "interaction", Howling = "howling"},
    FB1BuffDetail = function() return {} end,
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
assert(buffInitiators[101] == 101 and buffInitiators[102] == 102)
assert(require("WitnessNative").addMoodlet(people[102], "HZoiGameplay_SawEncounter", people[101]))
assert(moodlets[102] == "HZoiGameplay_SawEncounter" and buffInitiators[102] == 101)
encounter.completions["101"] = {excitement = 2}
effects.onResult(encounter, manualExit)
assert(moodlets[101] == "HZoiGameplay_Satisfied" and moodlets[102] == "HZoiGameplay_OutOfSync")
encounter.completions["102"] = {excitement = 1}
effects.onResult(encounter, manualExit)
assert(moodlets[101] == "HZoiGameplay_InSync" and moodlets[102] == moodlets[101])

encounter.completions = {}
local witnessExit = {stop_reason = "addon_requested", stop_origin = {reason = "witness_sighting"}}
local unfamiliarToBoth = {["101"] = true, ["102"] = true}
encounter.witnessPolicy = {
    ordinary_sighting = true, ordinary_unfamiliar = unfamiliarToBoth,
    ordinary_stop_unfamiliar = unfamiliarToBoth,
}
effects.onResult(encounter, witnessExit)
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
-- Exercise each shipped trait through the actual per-Zoi outcome dispatcher.
local traitCases = {
    mismatch = {Perfectionist = "OutOfOrder"},
    both = {Activist = "FoundABetterRhythm", Artist = "PerfectImprovisation",
        Adventurer = "WorthTheRush", Dreamer = "TheWorldWentQuiet", Gloomy = "ALittleLight",
        Bookworm = "AChapterWorthKeeping", Active = "FoundOurPace", Workaholic = "ABreakWellSpent",
        Aptitude_Seeker = "WorthTheDetour", Aptitude_Casanova = "AGoodImpression",
        Aptitude_BakingMaster = "SweetFinish", Aptitude_Collect = "AMemoryToKeep"},
    own = {Independent = "AtMyOwnPace", Observer = "SomethingToThinkAbout",
        Aptitude_Swim = "ASecondWind", Energetic = "StillBuzzing", Lazy = "GoodEnoughForMe",
        Mean = "IGotMine", Aptitude_Wikipedia = "WellNowIKnow", Aptitude_CoffeeMaster = "APleasantBuzz"},
    partner = {Intellect = "AQuestionOfTiming", Peacemaker = "MixedFeelings",
        Cheerful = "ALittleLetDown", Needy = "StayClose", Genius = "MissingPiece"},
    neither = {Achiever = "UnfinishedBusiness", Aptitude_Fishing = "BetterLuckNextTime"},
    furniture = {Snob = "ALittleLuxury", Aptitude_Smith = "FoundTheFit"},
    lowHygiene = {CleanFreak = "CouldUseAShower"},
    seen = {Helper = "NowhereToHide", ["Risk-averse"] = "ExactlyWhatIWorriedAbout",
        Arrogant = "WhoLetThemIn", Introvert = "TooManyEyes"},
    ordinary = {Popular = "PlayedItCool", Entertainer = "WhatAnEntrance", Extrovert = "LetsLaughAboutIt",
        Childish = "CouldntKeepAStraightFace", Flirt = "CoolUnderPressure",
        Aptitude_FirstImpression = "KeptMyComposure"},
    ordinaryStop = {Leader = "KeptItTogether", Clumsy = "ThatWasAwkward",
        Aptitude_Peace = "QuietAgain", Aptitude_BeverageMaster = "TakingItEasy"},
    caught = {Cooperator = "ThrillOfBeingCaught", Faithful = "WhatHaveIDone"},
}
local oneComplete = {excitement = 1}
local ordinarySighting = {
    ordinary_sighting = true, ordinary_unfamiliar = unfamiliarToBoth,
    ordinary_stop_unfamiliar = unfamiliarToBoth,
}
local caughtByPartner = {incidents = {{witness_id = "103", cheater_id = "101"}}}
local automaticExit = {stop_reason = "ok", stop_origin = {source = "auto"}}

local function setOutcome(own, partner, furniture, witnesses, hygiene)
    encounter.completions = {["101"] = own and oneComplete or nil, ["102"] = partner and oneComplete or nil}
    encounter.furniture = furniture
    encounter.witnessPolicy = witnesses
    needs.Cleanliness = hygiene or 10
    moodlets = {}
end

local scenarios = {
    mismatch = function() setOutcome(true, false) end,
    both = function() setOutcome(true, true) end,
    own = function() setOutcome(true, false) end,
    partner = function() setOutcome(false, true) end,
    neither = function() setOutcome(false, false); return manualExit end,
    furniture = function() setOutcome(true, true, "bed") end,
    lowHygiene = function() setOutcome(true, false, nil, nil, -40) end,
    seen = function() setOutcome(false, false, nil, ordinarySighting) end,
    ordinary = function() setOutcome(false, false, nil, ordinarySighting) end,
    ordinaryStop = function() setOutcome(false, false, nil, ordinarySighting); return witnessExit end,
    caught = function() setOutcome(false, false, nil, caughtByPartner) end,
}
local covered = {Romantic = true}  -- The Charmer variants were exercised above.
for scenario, cases in pairs(traitCases) do
    for trait, expected in pairs(cases) do
        assert(not covered[trait], "duplicate case for " .. trait)
        covered[trait] = true
        traits[101], traits[102] = {[trait] = true}, nil
        setOutcome(false, false)
        effects.onResult(encounter, automaticExit)
        assert(not moodlets[101], trait .. " applied without its trigger")
        effects.onResult(encounter, scenarios[scenario]() or automaticExit)
        assert(moodlets[101] == "HZoiGameplay_" .. expected,
            trait .. " in " .. scenario .. ": " .. tostring(moodlets[101]))
    end
end
local count = 0
for _ in pairs(covered) do count = count + 1 end
assert(count == 48, "expected 18 core traits, 18 characteristics and 12 aptitudes")
for _, rule in ipairs(require("TraitOutcomes").catalog()) do
    assert(covered[rule.trait_id], "fixture missing " .. rule.trait_id)
end

-- A participant still gets their independently earned result.
local familiarToFirst = {
    ordinary_sighting = true, ordinary_unfamiliar = {["102"] = true},
    ordinary_stop_unfamiliar = {["102"] = true},
}
setOutcome(true, false, nil, familiarToFirst)
traits[101], traits[102] = {Helper = true}, {Helper = true}
effects.onResult(encounter, automaticExit)
assert(moodlets[101] == "HZoiGameplay_Satisfied" and moodlets[102] == "HZoiGameplay_NowhereToHide")
setOutcome(false, false, nil, familiarToFirst)
traits[101], traits[102] = {}, {}
effects.onResult(encounter, witnessExit)
assert(not moodlets[101] and moodlets[102] == "HZoiGameplay_AwkwardTiming")
setOutcome(false, false, nil, familiarToFirst)
traits[101] = {Popular = true}
effects.onResult(encounter, automaticExit)
assert(moodlets[101] == "HZoiGameplay_PlayedItCool", "Familiarity still allows positive witness reactions")
setOutcome(false, false, nil, {
    ordinary_sighting = true, ordinary_unfamiliar = unfamiliarToBoth,
    ordinary_stop_unfamiliar = {["102"] = true},
})
traits[101], traits[102] = {Clumsy = true}, {Clumsy = true}
effects.onResult(encounter, witnessExit)
assert(not moodlets[101] and moodlets[102] == "HZoiGameplay_ThatWasAwkward",
    "Only the unfamiliar stopping witness can trigger a negative stop reaction")

-- Equal specificity favors core personality, then characteristic, then aptitude.
setOutcome(true, true)
traits[101] = {Artist = true, Bookworm = true, Aptitude_Casanova = true}
effects.onResult(encounter, automaticExit)
assert(moodlets[101] == "HZoiGameplay_PerfectImprovisation")
traits[101].Artist = nil
effects.onResult(encounter, automaticExit)
assert(moodlets[101] == "HZoiGameplay_AChapterWorthKeeping")
encounter.participants = {"101", "102", "103"}
encounter.witnessPolicy = nil
encounter.completions = {["101"] = {excitement = 2}, ["103"] = {excitement = 1}}
traits = {}
moodlets = {}
effects.onResult(encounter, manualExit)
assert(moodlets[101] == "HZoiGameplay_Satisfied" and moodlets[103] == moodlets[101])
assert(moodlets[102] == "HZoiGameplay_OutOfSync")
traits[103] = {Perfectionist = true}
effects.onResult(encounter, manualExit)
assert(moodlets[103] == "HZoiGameplay_OutOfOrder", "Mixed group outcomes count as a mismatch")
encounter.completions["102"] = {excitement = 1}
effects.onResult(encounter, manualExit)
for _, who in ipairs({101, 102, 103}) do
    assert(moodlets[who] == "HZoiGameplay_InSync")
end

print("Encounter consequences and all 48 trait, characteristic, and aptitude cases passed")
