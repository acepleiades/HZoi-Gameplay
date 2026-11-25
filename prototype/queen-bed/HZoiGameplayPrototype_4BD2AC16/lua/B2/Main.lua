local invitation = require("Components.QueenBedInvite")

local M = {}

function M.on_end()
    invitation.shutdown()
end

return M
