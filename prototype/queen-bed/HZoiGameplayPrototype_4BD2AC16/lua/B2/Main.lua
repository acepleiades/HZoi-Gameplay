local invitation = require("Components.VenueInvite")

local M = {}

function M.on_end()
    invitation.shutdown()
end

return M
