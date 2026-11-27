local invitation = require("Components.VenueInvite")
local witness = require("WitnessNative")

local M = {}

function M.on_begin()
    invitation.on_begin()
end

function M.on_tick(first, second)
    local dt = type(second) == "number" and second or type(first) == "number" and first or 0
    invitation.tick(dt)
    witness.tickSpeech()
end

function M.on_end()
    witness.clearSpeech()
    invitation.shutdown()
end

return M
