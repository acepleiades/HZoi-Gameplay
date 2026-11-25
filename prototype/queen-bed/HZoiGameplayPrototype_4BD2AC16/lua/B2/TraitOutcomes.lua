local M = {}

local triggers = {
    mismatch = {rank = 1, matches = function(f) return f.any_completed and not f.all_completed end},
    self_completed = {rank = 1, matches = function(f) return f.self_completed end},
    all_completed = {rank = 2, matches = function(f) return f.all_completed end},
    self_partial = {rank = 2, matches = function(f) return f.self_completed and not f.all_completed end},
    other_partial = {rank = 2, matches = function(f) return f.any_completed and not f.self_completed end},
    none_manual_exit = {rank = 2, matches = function(f)
        return f.player_exit and not f.any_completed
    end},
    all_furniture = {rank = 3, matches = function(f)
        return f.furniture and f.all_completed
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

local together = "From everyone reaching orgasm"
local own = "From reaching orgasm"
local selfPartial = "From reaching orgasm when some participants didn’t"
local otherPartial = "From someone else reaching orgasm while you didn’t"
local ending = "From stopping early"
local seen = "From being seen having sex"
local interrupted = "From being interrupted during sex"
local caught = "From getting caught cheating"

add("nature", "Perfectionist", "mismatch", "OutOfOrder", "Irritated", 2, 120,
    "Out of Order", "From the encounter ending before everyone reached orgasm", "You wanted everyone to enjoy it. Ending before everyone could finish made the whole thing feel a little uneven.")
add("nature", "Activist", "all_completed", "FoundABetterRhythm", "Curious", 2, 240,
    "Found a Better Rhythm", together, "Changing things up came naturally once you started paying attention to each other. You’re glad you tried something different.")
add("nature", "Helper", "seen", "NowhereToHide", "Cringing", 2, 120,
    "Nowhere to Hide", seen, "You thought you had some privacy. The second you realized someone could see you, you wished you could disappear.")
add("nature", "Popular", "ordinary", "PlayedItCool", "Calm", 2, 120,
    "Played It Cool", seen, "Being seen was awkward for a second, but you kept your cool. It doesn’t feel like something you need to make a big deal of.")
add("nature", "Achiever", "none_manual_exit", "UnfinishedBusiness", "Irritated", 2, 120,
    "Unfinished Business", ending, "You were just getting into it when things stopped. The feeling that you left something unfinished is hard to shake.")
add("nature", "Artist", "all_completed", "PerfectImprovisation", "Curious", 3, 240,
    "Perfect Improvisation", together, "You stopped thinking about how it ought to go and followed each other’s lead. Now you’re curious what else might feel that natural.")
add("nature", "Independent", "self_completed", "AtMyOwnPace", "Calm", 2, 180,
    "At My Own Pace", own, "You gave yourself time to enjoy being close without worrying about how fast things were moving. That was exactly what you needed.")
add("nature", "Observer", "self_completed", "SomethingToThinkAbout", "Curious", 2, 180,
    "Something to Think About", own, "You keep thinking about what made that feel so good. It might be worth talking about what you liked next time.")
add("nature", "Intellect", "other_partial", "AQuestionOfTiming", "Uneasy", 2, 120,
    "A Question of Timing", otherPartial, "Someone finished just when you were starting to get close. You’re still wondering how the timing got so out of step.")
add("nature", "Risk-averse", "seen", "ExactlyWhatIWorriedAbout", "Uneasy", 2, 120,
    "Exactly What I Worried About", seen, "You’d been wondering whether someone might see you, and then it actually happened. It’s going to take a while to stop worrying about it.")
add("nature", "Cooperator", "own_partner", "ThrillOfBeingCaught", "Excited", 3, 120,
    "Thrill of Being Caught", caught, "Your partner caught you with someone else. You know the conversation won’t be easy, but the rush caught you by surprise.")
add("nature", "Entertainer", "ordinary", "WhatAnEntrance", "Funny", 2, 120,
    "What an Entrance", seen, "The timing was so bad that it was almost funny. Once the surprise wore off, you had to fight the urge to laugh.")
add("nature", "Adventurer", "all_completed", "WorthTheRush", "Excited", 3, 240,
    "Worth the Rush", together, "Getting carried away together felt better than you expected. Your heart is still racing a little just thinking about it.")
add("nature", "Arrogant", "seen", "WhoLetThemIn", "Irritated", 2, 120,
    "Who Let Them In?", seen, "You expected a bit of privacy. Now you’re thinking about how easily someone saw you and how annoyed you are about it.")
add("nature", "Leader", "ordinary_stop", "KeptItTogether", "Convinced", 2, 120,
    "Kept It Together", interrupted, "You were embarrassed at first, but you took a breath and kept your composure. It feels good to know you can handle an awkward moment.")
add("nature", "Peacemaker", "other_partial", "MixedFeelings", "Sad", 1, 120,
    "Mixed Feelings", otherPartial, "You’re glad someone had a good time. You wish you’d had a little more time too.")
add("nature", "Dreamer", "all_completed", "TheWorldWentQuiet", "Calm", 3, 240,
    "The World Went Quiet", together, "For a little while you forgot about everything outside that moment. You’re still carrying that quiet feeling with you.")

add("characteristic", "Extrovert", "ordinary", "LetsLaughAboutIt", "Funny", 2, 120,
    "Let’s Laugh About It", seen, "It was embarrassing to realize someone could see you, but the timing was hard to take seriously. You can already laugh about it.")
add("characteristic", "Introvert", "seen", "TooManyEyes", "Cringing", 2, 120,
    "Too Many Eyes", seen, "The moment felt private until you noticed someone looking. You’d rather be somewhere quiet where you don’t have to face anyone for a bit.")
add("characteristic", "Cheerful", "other_partial", "ALittleLetDown", "Sad", 1, 120,
    "A Little Letdown", otherPartial, "You enjoyed the closeness. It’s still a little disappointing to stop when you were getting close.")
add("characteristic", "Gloomy", "all_completed", "ALittleLight", "Calm", 3, 240,
    "A Little Light", together, "Feeling wanted and close to someone gave you a break from the things weighing on you. You’re glad you had that time together.")
add("characteristic", "Clumsy", "ordinary_stop", "ThatWasAwkward", "Cringing", 2, 120,
    "That Was Awkward", interrupted, "The second you noticed someone watching, you forgot where to look. Just remembering the awkward silence makes you cringe.")
add("characteristic", "Bookworm", "all_completed", "AChapterWorthKeeping", "Touched", 3, 240,
    "A Chapter Worth Keeping", together, "It’s the little details you’ll remember, like the look you shared afterward. You’re glad you got to spend that time together.")
add("characteristic", "Needy", "other_partial", "StayClose", "Sad", 2, 120,
    "Stay Close", otherPartial, "Someone finished while you were still getting there. You’d like a little reassurance and a moment to stay close.")
add("characteristic", "Active", "all_completed", "FoundOurPace", "Excited", 3, 240,
    "Found Our Pace", together, "Once you found a pace that felt good to everyone, everything clicked. You still feel the rush now that you’ve caught your breath.")
add("characteristic", "Energetic", "self_partial", "StillBuzzing", "Excited", 2, 180,
    "Still Buzzing", selfPartial, "Even though the encounter ended early for some, you came away with more energy than you expected. Sitting still doesn’t sound very appealing right now.")
add("characteristic", "CleanFreak", "low_hygiene", "CouldUseAShower", "Uncomfortable", 2, 120,
    "Could Use a Shower", "From feeling sweaty after sex", "You had a good time, but now everything feels a little sticky. A warm shower and a change of clothes sound wonderful.")
add("characteristic", "Childish", "ordinary", "CouldntKeepAStraightFace", "Funny", 2, 120,
    "Couldn’t Keep a Straight Face", seen, "You knew you should probably look serious, but the surprise got the better of you. Thinking about it still makes you want to giggle.")
add("characteristic", "Genius", "other_partial", "MissingPiece", "Irritated", 2, 120,
    "Missing Piece", otherPartial, "You can’t help replaying what happened. Someone finished, and you’re frustrated that you can’t work out what was missing for you.")
add("characteristic", "Lazy", "self_partial", "GoodEnoughForMe", "Calm", 2, 180,
    "Good Enough for Me", selfPartial, "You got what you needed and now you’re happy to take it easy. A few quiet minutes to yourself sound pretty good.")
add("characteristic", "Snob", "all_furniture", "ALittleLuxury", "Calm", 3, 240,
    "A Little Luxury", together, "Having somewhere comfortable made it so much easier to relax together. You could get used to taking your time like that.")
add("characteristic", "Mean", "self_partial", "IGotMine", "Funny", 2, 180,
    "I Got Mine", selfPartial, "You noticed some hadn’t finished when it ended. You’re still feeling pretty smug about how well things went for you.")
add("characteristic", "Workaholic", "all_completed", "ABreakWellSpent", "Calm", 3, 240,
    "A Break Well Spent", together, "You managed to put everything else aside and give each other your full attention. It was worth making room for that.")
add("characteristic", "Flirt", "ordinary", "CoolUnderPressure", "Funny", 2, 120,
    "Cool Under Pressure", seen, "You caught someone looking and felt more amused than embarrassed. A little awkwardness wasn’t enough to ruin the moment for you.")
add("characteristic", "Faithful", "own_partner", "WhatHaveIDone", "Sad", 2, 120,
    "What Have I Done?", caught, "Getting caught made it sink in how much you’d hurt your partner. You wish you could take back what just happened.")

add("aptitude", "Aptitude_Peace", "ordinary_stop", "QuietAgain", "Calm", 2, 120,
    "Quiet Again", interrupted, "Things got tense when you realized someone had seen you. Now that you’ve stopped, you’re glad to have a moment to breathe.")
add("aptitude", "Aptitude_Wikipedia", "self_partial", "WellNowIKnow", "Curious", 2, 180,
    "Well, Now I Know", selfPartial, "Finishing made you think about how much your own preferences matter. You’d like to compare notes sometime.")
add("aptitude", "Aptitude_Seeker", "all_completed", "WorthTheDetour", "Excited", 3, 240,
    "Worth the Detour", together, "Taking a little time out of the day turned into something you’ll be smiling about later. You’re glad you went for it.")
add("aptitude", "Aptitude_Casanova", "all_completed", "AGoodImpression", "Enchanting", 3, 240,
    "A Good Impression", together, "Knowing everyone enjoyed it gave you butterflies. You’re still thinking about the looks you shared afterward.")
add("aptitude", "Aptitude_CoffeeMaster", "self_partial", "APleasantBuzz", "Excited", 2, 180,
    "A Pleasant Buzz", selfPartial, "You thought you might feel sleepy afterward, but your body is still humming with energy. It’s a pleasant surprise.")
add("aptitude", "Aptitude_BakingMaster", "all_completed", "SweetFinish", "Calm", 3, 240,
    "Sweet Finish", together, "You took your time and it paid off for everyone. You’re in no hurry to move on from how good that felt.")
add("aptitude", "Aptitude_BeverageMaster", "ordinary_stop", "TakingItEasy", "Calm", 2, 120,
    "Taking It Easy", interrupted, "It was tense when someone noticed what was happening. After stopping and taking a breath, you’re ready to let the awkwardness pass.")
add("aptitude", "Aptitude_Collect", "all_completed", "AMemoryToKeep", "Touched", 3, 240,
    "A Memory to Keep", together, "You’ve already caught yourself smiling at the memory of being that close. It’s one of those moments you’d like to hold on to.")
add("aptitude", "Aptitude_Fishing", "none_manual_exit", "BetterLuckNextTime", "Sad", 1, 120,
    "Better Luck Next Time", ending, "Things ended before anyone could finish. You’re disappointed, but maybe you’ll have better luck when there’s more time.")
add("aptitude", "Aptitude_Smith", "all_furniture", "FoundTheFit", "Preoccupied", 3, 240,
    "Found the Fit", together, "Once you found a comfortable position, you could pay attention to each other. You’ll remember what worked next time.")
add("aptitude", "Aptitude_Swim", "self_completed", "ASecondWind", "Excited", 2, 180,
    "A Second Wind", own, "You felt worn out for a moment, then came away more energized than before. You could keep going with your day now.")
add("aptitude", "Aptitude_FirstImpression", "ordinary", "KeptMyComposure", "Convinced", 2, 120,
    "Kept My Composure", seen, "You felt a flash of embarrassment when you realized someone could see you. Staying calm through it left you feeling sure of yourself.")

local function moreSpecific(candidate, incumbent)
    if not incumbent then return true end
    return triggers[candidate.trigger].rank > triggers[incumbent.trigger].rank
end

local positive = {
    Calm = true, Convinced = true, Curious = true, Enchanting = true, Excited = true,
    Funny = true, Preoccupied = true, Touched = true,
}

local function applies(rule, facts)
    if not triggers[rule.trigger].matches(facts) then return false end
    if positive[rule.mood] then return true end
    if rule.trigger == "ordinary_stop" then return facts.ordinary_stop_unfamiliar end
    if rule.trigger == "seen" then return facts.official_sighting or facts.ordinary_unfamiliar end
    return rule.trigger ~= "ordinary" or facts.ordinary_unfamiliar
end

-- Table order breaks equal-specificity ties: nature, characteristic, aptitude.
function M.select(hasTrait, facts)
    local outcome, witness
    for _, rule in ipairs(rules) do
        local trigger = triggers[rule.trigger]
        if applies(rule, facts) and hasTrait(rule.trait_id) then
            if trigger.witness then
                if moreSpecific(rule, witness) then witness = rule end
            elseif moreSpecific(rule, outcome) then
                outcome = rule
            end
        end
    end
    -- The retail Lua module boundary forwards only the first result.
    return {outcome = outcome, witness = witness}
end

local witnessDialogue = {
    {trait = "Perfectionist", bubble = "HZoiGameplay_WitnessPerfectionist"},
    {trait = "Helper", bubble = "HZoiGameplay_WitnessRecluse"},
}

function M.witnessDialogue(hasTrait)
    for _, rule in ipairs(witnessDialogue) do
        if hasTrait(rule.trait) then return rule.bubble end
    end
end

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
