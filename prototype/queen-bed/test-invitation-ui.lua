-- Run from prototype/queen-bed.
local source = "HZoiGameplayPrototype_4BD2AC16/lua/B1/"
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

print("Privacy toast follows the initiating Zoi at receipt time.")
