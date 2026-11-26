local invitation = require("Components.VenueInvite")
local witness = require("WitnessNative")

local M = {}

function M.on_tick()
    witness.tickSpeech()
end

function M.on_end()
    witness.clearSpeech()
    invitation.shutdown()
end

return M
