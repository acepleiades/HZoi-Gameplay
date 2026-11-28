-- Run from prototype/queen-bed.
local source = "HZoiGameplay_4BD2AC16/lua/B1/"
local initiator, partner, bystander = {Value = 1}, {Value = 2}, {Value = 3}
local controlled, toasts = initiator, {}
local actor = {GetEntityId = function() return initiator end}
local controller = {GetCharacterEntityId = function() return controlled end}

package.loaded.WitnessTraceBridge = {}
package.loaded.Localization = {text = function(message) return message end}
UE = {
    UGameplayStatics = {GetPlayerController = function(context, index)
        assert(context == actor and index == 0)
        return controller
    end},
}
inzoi = {cli = {execute = function(command) toasts[#toasts + 1] = command end}}

local UI = assert(loadfile(source .. "Components/InvitationUI.lua"))()
local state = {actor = actor}
local function deliver(code)
    UI.on_lua_message(state, nil, "HZoiGameplay.Notice", code)
end

deliver("arrival_privacy_denied")
assert(#toasts == 1 and toasts[1]:match("They need more privacy%."))

controlled = partner
deliver("arrival_privacy_denied")
assert(#toasts == 1, "Switching to the partner before delivery must suppress the privacy toast")
controlled = bystander
deliver("arrival_privacy_denied")
assert(#toasts == 1, "Switching to a bystander before delivery must suppress the privacy toast")
controlled = nil
deliver("arrival_privacy_denied")
assert(#toasts == 1, "A transition without an active character must suppress the privacy toast")

controlled = initiator
UI.on_lua_message(state, nil, "HZoiGameplay.PickerPaused", "Jeu en pause")
assert(#toasts == 2 and toasts[2]:match("Jeu en pause"), "Use SceneZOI's localized picker pause message")
controlled = bystander
UI.on_lua_message(state, nil, "HZoiGameplay.PickerPaused", "Jeu en pause")
assert(#toasts == 2, "Do not show a delayed picker notice for another Zoi")

controlled = initiator
for _, notice in ipairs({
    {"picker_grouped", "Leave your group before choosing a partner."},
    {"picker_busy", "Close the open picker before choosing a partner."},
    {"picker_unavailable", "The partner picker could not open."},
}) do
    deliver(notice[1])
    assert(toasts[#toasts] == "toast.show immediate=true message=" .. string.format('%q', notice[2]))
end

print("Privacy and picker toasts follow the initiating Zoi at receipt time.")
