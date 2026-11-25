local M = {}

local triggers = {
    mismatch = {rank = 1, matches = function(f) return f.self_completed ~= f.partner_completed end},
    self_completed = {rank = 1, matches = function(f) return f.self_completed end},
    both = {rank = 2, matches = function(f) return f.self_completed and f.partner_completed end},
    only_self = {rank = 2, matches = function(f) return f.self_completed and not f.partner_completed end},
    only_partner = {rank = 2, matches = function(f) return f.partner_completed and not f.self_completed end},
    neither_manual_exit = {rank = 2, matches = function(f)
        return f.player_exit and not f.self_completed and not f.partner_completed
    end},
    both_furniture = {rank = 3, matches = function(f)
        return f.furniture and f.self_completed and f.partner_completed
    end},
    low_hygiene = {rank = 3, matches = function(f) return f.low_hygiene and f.self_completed end},
    seen = {rank = 1, witness = true, matches = function(f) return f.seen end},
    ordinary = {rank = 2, witness = true, matches = function(f) return f.ordinary_sighting end},
    ordinary_stop = {rank = 3, witness = true, matches = function(f) return f.ordinary_stop end},
    own_partner = {rank = 4, witness = true, matches = function(f) return f.caught_by_own_partner end},
}

local rules = {}
local function add(source, trait, trigger, name, mood, points, minutes, title, reason, description)
    rules[#rules + 1] = {
        source = source, trait_id = trait, trigger = trigger,
        buff_id = "HZoiGameplay_" .. name, mood = mood, points = points, minutes = minutes,
        title = title, reason = reason, description = description,
    }
end

local together = "From finishing together"
local own = "From finishing"
local solo = "From being the only one to finish"
local partner = "From only your partner finishing"
local ending = "From ending the encounter early"
local seen = "From being seen"
local interrupted = "From an encounter interrupted by a witness"
local caught = "From getting caught cheating"

add("nature", "Perfectionist", "mismatch", "OutOfOrder", "Irritated", 2, 120,
    "Out of Order", "From a mismatch", "The encounter felt out of step when only one of you finished.")
add("nature", "Activist", "both", "FoundABetterRhythm", "Curious", 2, 240,
    "Found a Better Rhythm", together, "Exploring new boundaries with someone special felt exciting.")
add("nature", "Helper", "seen", "NowhereToHide", "Cringing", 2, 120,
    "Nowhere to Hide", seen, "You wanted privacy. Being seen left you flustered.")
add("nature", "Popular", "ordinary", "PlayedItCool", "Calm", 2, 120,
    "Played It Cool", seen, "You took the awkward moment in stride.")
add("nature", "Achiever", "neither_manual_exit", "UnfinishedBusiness", "Irritated", 2, 120,
    "Unfinished Business", ending, "You were frustrated to stop before either of you finished.")
add("nature", "Artist", "both", "PerfectImprovisation", "Curious", 3, 240,
    "Perfect Improvisation", together, "The rhythm you found together left you curious about what else might work.")
add("nature", "Independent", "self_completed", "AtMyOwnPace", "Calm", 2, 180,
    "At My Own Pace", own, "You enjoyed the moment on your own terms.")
add("nature", "Observer", "self_completed", "SomethingToThinkAbout", "Curious", 2, 180,
    "Something to Think About", own, "You’re curious about what made the encounter feel so good.")
add("nature", "Intellect", "only_partner", "AQuestionOfTiming", "Uneasy", 2, 120,
    "A Question of Timing", partner, "You keep replaying the moment, wondering where your timing went wrong.")
add("nature", "Risk-averse", "seen", "ExactlyWhatIWorriedAbout", "Uneasy", 2, 120,
    "Exactly What I Worried About", seen, "Someone saw you, just as you feared.")
add("nature", "Cooperator", "own_partner", "ThrillOfBeingCaught", "Excited", 3, 120,
    "Thrill of Being Caught", caught, "You felt an unexpected rush when your partner caught you.")
add("nature", "Entertainer", "ordinary", "WhatAnEntrance", "Funny", 2, 120,
    "What an Entrance", seen, "The awkward timing amused you.")
add("nature", "Adventurer", "both", "WorthTheRush", "Excited", 3, 240,
    "Worth the Rush", together, "You came away exhilarated.")
add("nature", "Arrogant", "seen", "WhoLetThemIn", "Irritated", 2, 120,
    "Who Let Them In?", seen, "You’re annoyed that someone intruded on a private moment.")
add("nature", "Leader", "ordinary_stop", "KeptItTogether", "Convinced", 2, 120,
    "Kept It Together", interrupted, "You kept your composure when the encounter ended.")
add("nature", "Peacemaker", "only_partner", "MixedFeelings", "Sad", 1, 120,
    "Mixed Feelings", partner, "You’re glad your partner enjoyed it. You wish you’d felt the same.")
add("nature", "Dreamer", "both", "TheWorldWentQuiet", "Calm", 3, 240,
    "The World Went Quiet", together, "For a little while, it felt like you were the only two in the world.")

add("characteristic", "Extrovert", "ordinary", "LetsLaughAboutIt", "Funny", 2, 120,
    "Let’s Laugh About It", seen, "You found the funny side of being seen.")
add("characteristic", "Introvert", "seen", "TooManyEyes", "Cringing", 2, 120,
    "Too Many Eyes", seen, "The extra attention made you feel exposed.")
add("characteristic", "Cheerful", "only_partner", "ALittleLetDown", "Sad", 1, 120,
    "A Little Let Down", partner, "You enjoyed being together and still feel a little let down.")
add("characteristic", "Gloomy", "both", "ALittleLight", "Calm", 3, 240,
    "A Little Light", together, "Spending a good moment with someone brought you some relief.")
add("characteristic", "Clumsy", "ordinary_stop", "ThatWasAwkward", "Cringing", 2, 120,
    "That Was Awkward", interrupted, "You were too flustered to know where to look.")
add("characteristic", "Bookworm", "both", "AChapterWorthKeeping", "Touched", 3, 240,
    "A Chapter Worth Keeping", together, "You shared a moment worth remembering.")
add("characteristic", "Needy", "only_partner", "StayClose", "Sad", 2, 120,
    "Stay Close", partner, "You’re left wanting reassurance that your experience mattered too.")
add("characteristic", "Active", "both", "FoundOurPace", "Excited", 3, 240,
    "Found Our Pace", together, "Finding a pace that suited you both gave you a rush.")
add("characteristic", "Energetic", "only_self", "StillBuzzing", "Excited", 2, 180,
    "Still Buzzing", solo, "You’re still buzzing from how good it felt.")
add("characteristic", "CleanFreak", "low_hygiene", "CouldUseAShower", "Uncomfortable", 2, 120,
    "Could Use a Shower", "From low Hygiene after an encounter", "You feel uncomfortable and keep thinking about getting clean.")
add("characteristic", "Childish", "ordinary", "CouldntKeepAStraightFace", "Funny", 2, 120,
    "Couldn’t Keep a Straight Face", seen, "The surprise was enough to give you the giggles.")
add("characteristic", "Genius", "only_partner", "MissingPiece", "Irritated", 2, 120,
    "Missing Piece", partner, "You’re frustrated that you can’t figure out why the encounter fell short for you.")
add("characteristic", "Lazy", "only_self", "GoodEnoughForMe", "Calm", 2, 180,
    "Good Enough for Me", solo, "You’re satisfied and ready to relax.")
add("characteristic", "Snob", "both_furniture", "ALittleLuxury", "Calm", 3, 240,
    "A Little Luxury", together, "A comfortable place made the moment feel like a small luxury.")
add("characteristic", "Mean", "only_self", "IGotMine", "Funny", 2, 180,
    "I Got Mine", solo, "You feel smug about getting what you wanted.")
add("characteristic", "Workaholic", "both", "ABreakWellSpent", "Calm", 3, 240,
    "A Break Well Spent", together, "Making time for each other felt worthwhile.")
add("characteristic", "Flirt", "ordinary", "CoolUnderPressure", "Funny", 2, 120,
    "Cool Under Pressure", seen, "The awkward moment amused you.")
add("characteristic", "Faithful", "own_partner", "WhatHaveIDone", "Sad", 2, 120,
    "What Have I Done?", caught, "You feel guilty for hurting your partner.")

add("aptitude", "Aptitude_Peace", "ordinary_stop", "QuietAgain", "Calm", 2, 120,
    "Quiet Again", interrupted, "The awkwardness passed once the encounter ended.")
add("aptitude", "Aptitude_Wikipedia", "only_self", "WellNowIKnow", "Curious", 2, 180,
    "Well, Now I Know", solo, "You’re curious about what made the difference for you.")
add("aptitude", "Aptitude_Seeker", "both", "WorthTheDetour", "Excited", 3, 240,
    "Worth the Detour", together, "You’re glad you made time for a moment that felt this good.")
add("aptitude", "Aptitude_Casanova", "both", "AGoodImpression", "Enchanting", 3, 240,
    "A Good Impression", together, "Knowing your partner enjoyed it too gave you butterflies.")
add("aptitude", "Aptitude_CoffeeMaster", "only_self", "APleasantBuzz", "Excited", 2, 180,
    "A Pleasant Buzz", solo, "You still feel a little jolt of excitement.")
add("aptitude", "Aptitude_BakingMaster", "both", "SweetFinish", "Calm", 3, 240,
    "Sweet Finish", together, "You’re still savoring how well the moment went.")
add("aptitude", "Aptitude_BeverageMaster", "ordinary_stop", "TakingItEasy", "Calm", 2, 120,
    "Taking It Easy", interrupted, "You feel calmer now that the awkward moment has passed.")
add("aptitude", "Aptitude_Collect", "both", "AMemoryToKeep", "Touched", 3, 240,
    "A Memory to Keep", together, "You shared a moment you want to remember.")
add("aptitude", "Aptitude_Fishing", "neither_manual_exit", "BetterLuckNextTime", "Sad", 1, 120,
    "Better Luck Next Time", ending, "You’re disappointed it ended, and you hope next time goes better.")
add("aptitude", "Aptitude_Smith", "both_furniture", "FoundTheFit", "Preoccupied", 3, 240,
    "Found the Fit", together, "A comfortable position made everything click.")
add("aptitude", "Aptitude_Swim", "self_completed", "ASecondWind", "Excited", 2, 180,
    "A Second Wind", own, "You came away feeling energized.")
add("aptitude", "Aptitude_FirstImpression", "ordinary", "KeptMyComposure", "Convinced", 2, 120,
    "Kept My Composure", seen, "Keeping your cool in an awkward moment made you feel more confident.")

local function moreSpecific(candidate, incumbent)
    if not incumbent then return true end
    return triggers[candidate.trigger].rank > triggers[incumbent.trigger].rank
end

-- Table order breaks equal-specificity ties: nature, characteristic, aptitude.
function M.select(hasTrait, facts)
    local outcome, witness
    for _, rule in ipairs(rules) do
        local trigger = triggers[rule.trigger]
        if trigger.matches(facts) and hasTrait(rule.trait_id) then
            if trigger.witness then
                if moreSpecific(rule, witness) then witness = rule end
            elseif moreSpecific(rule, outcome) then
                outcome = rule
            end
        end
    end
    return outcome, witness
end

local positive = {
    Calm = true, Convinced = true, Curious = true, Enchanting = true, Excited = true,
    Funny = true, Preoccupied = true, Touched = true,
}

-- Buff point values are data. Reserve a second row for a positive completion
-- with Charmer's point bonus rather than adding a separate visible moodlet.
function M.buffId(rule, hasTrait)
    if rule and rule.source ~= "nature" and not triggers[rule.trigger].witness
        and positive[rule.mood] and hasTrait("Romantic") then
        return rule.buff_id .. "_Romantic"
    end
    return rule and rule.buff_id
end

function M.catalog()
    local rows = {}
    for _, rule in ipairs(rules) do
        rows[#rows + 1] = rule
        if not triggers[rule.trigger].witness and positive[rule.mood] and rule.source ~= "nature" then
            local stronger = {}
            for key, value in pairs(rule) do stronger[key] = value end
            stronger.buff_id = rule.buff_id .. "_Romantic"
            stronger.points = rule.points + 1
            rows[#rows + 1] = stronger
        end
    end
    return rows
end

return M
