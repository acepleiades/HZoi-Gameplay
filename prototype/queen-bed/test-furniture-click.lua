-- Run from prototype/queen-bed.
local source = "HZoiGameplay_4BD2AC16/lua/B1/"
local context, emotionClass = {}, {}
local controlled = {Value = 37}
local emotion = {CurrentEmotionInfo = {EmotionId = "Sad", Level = 2}}
local time = os.time() * 1000
local command = ("invite-%d-1|37|321"):format(time)
local dispatched = {}

package.loaded["Components.InvitationUI"] = {context = context}
UE = {
    UGameplayStatics = {GetPlayerController = function(value, index)
        assert(value == context and index == 0)
        return {
            GetCharacterEntityId = function() return controlled end,
            GetB1Character = function()
                return {K2_GetComponentsByClass = function(_, class)
                    assert(class == emotionClass)
                    return {emotion}
                end}
            end,
        }
    end},
    UWidgetBlueprintLibrary = {GetAllWidgetsOfClass = function()
        error("SceneZOI owns menu scanning")
    end},
}
inzoi = {
    UB1EmotionComponent = {StaticClass = function() return emotionClass end},
    cli = {execute = function(key)
        assert(key:find("key=furniture_invite", 1, true))
        return true, nil, '{"value":"' .. command .. '"}'
    end},
    message = {send_to_sim = function(who, kind, value)
        assert(who == controlled and kind == "HZoiGameplay.FurnitureInvite")
        dispatched[#dispatched + 1] = value
    end},
}

local Bridge = assert(loadfile(source .. "Main.lua"))()
Bridge.on_begin()
Bridge.on_tick(.1)
assert(#dispatched == 0, "Ignore the persisted click on startup")

command = ("invite-%d-2|37|987"):format(time)
Bridge.on_tick(.05)
assert(#dispatched == 0, "Poll clicks every tenth of a second")
Bridge.on_tick(.05)
Bridge.on_tick(.1)
assert(#dispatched == 1 and dispatched[1] == command, "Dispatch the exact furniture ID once, even after the menu closes")

command = ("invite-%d-3|38|987"):format(time)
Bridge.on_tick(.1)
command = ("invite-%d-4|37|987"):format(time - 90000)
Bridge.on_tick(.1)
assert(#dispatched == 1, "Ignore another Zoi's command or a stale command")

emotion.CurrentEmotionInfo.Level = 3
command = ("invite-%d-5|37|987"):format(time)
Bridge.on_tick(.1)
assert(#dispatched == 1, "Block the furniture click when the controlled Zoi cannot ask")
emotion.CurrentEmotionInfo.EmotionId = "Joyful"
Bridge.on_tick(.1)
assert(#dispatched == 1, "Do not replay the blocked click after mood recovery")

print("Furniture click delivery, stale click protection and native mood checks passed without widget scans.")
