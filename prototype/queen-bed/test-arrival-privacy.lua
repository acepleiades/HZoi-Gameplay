local Privacy = require("ArrivalPrivacy")
inzoi = {EB1GenderType = {Male = 1, Female = 2}}
local roster = {"1", "2", "3"}
local function actor(id, gender)
    return {id = id, GetGenderType = function() return gender end}
end
local world = {["1"] = actor("1", 1), ["2"] = actor("2", 2), ["3"] = actor("3", 2),
    ["4"] = actor("4", 1), ["5"] = actor("5", 2)}
local scores = {
    ["4"] = {["1"] = {Romance = 9, Friendship = 30}, ["2"] = {Romance = 35}, ["3"] = {Romance = 30}},
    ["5"] = {["1"] = {Romance = 30}, ["2"] = {Romance = 30}, ["3"] = {Romance = 30}},
}
local function evaluate(seen, participants)
    return Privacy.evaluate(participants or roster, seen, function(id) return world[id] end,
        function(observer, participant, stat)
            assert(scores[observer.id], "Read from observer to participant")
            return scores[observer.id][participant.id][stat]
        end)
end
local two = {{id = "4"}, {id = "5"}}
assert(next(evaluate({})) == nil)
local result = evaluate(two)
assert(result["4"] and result["5"], "Both threshold routes qualify independently")
scores["4"]["3"].Romance = 29
local allowed, reason, witness = evaluate(two)
assert(allowed == false and reason == "observer_not_qualified" and witness == "4")
scores["4"]["3"].Romance, scores["4"]["1"].Friendship = 30, 29
assert(evaluate(two) == false)
scores["4"]["1"].Friendship = nil
allowed, reason, witness = evaluate(two)
assert(allowed == nil and reason == "friendship_unavailable" and witness == "4", "Technical lookup failure")
assert(evaluate({{id = "1"}}) == nil, "A participant is not an observer")
assert(evaluate({{id = "4"}, {id = "4"}}) == nil, "Duplicate observer data is malformed")

scores["5"]["2"].Romance, scores["5"]["2"].Friendship = 0, 100
scores["5"]["3"].Romance, scores["5"]["3"].Friendship = 0, 100
assert(evaluate({{id = "5"}}, {"2", "3"}) == false, "An all-same-sex group requires Romance")
scores["5"]["2"].Romance, scores["5"]["3"].Romance = 30, 30
assert(evaluate({{id = "5"}}, {"2", "3"})["5"], "An all-same-sex group can use the all-Romance route")
print("Arrival privacy passed: directional scores, thresholds, independent observers and technical failures.")
