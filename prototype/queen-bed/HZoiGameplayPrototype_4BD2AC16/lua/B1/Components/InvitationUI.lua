local M = {context = nil}
local notices = {
    picker_unavailable = "The partner picker could not open. Close any open picker and make sure your Zoi is out of their group.",
    picker_busy = "Close the current Zoi picker before sending an invitation.",
    busy = "An HZoi invitation is already in progress.",
    failed = "Could not finish the invitation.",
    furniture_unavailable = "That queen bed is occupied or unavailable.",
    initiator_not_controlled = "Select the Zoi who sent the invitation first.",
    no_matching_scenes = "No queen-bed scenes were found for these Zois.",
    goal_unreachable = "No queen-bed scenes can complete the goals for this pair.",
    not_eligible = "These Zois cannot use Set the Mood right now.",
    participant_busy = "One of the Zois is already in a scene. Try again afterward.",
    queue_failed = "The invitation could not be added to the action queue.",
    required_stage_unavailable = "An activity needed for this encounter is unavailable.",
    session_already_running = "End the current SceneZOI scene before starting another.",
    timeout = "The invitation took too long. Check the Zois' action queues and try again.",
    transport_timeout = "SceneZOI did not respond. Check that it is installed and enabled.",
    unsupported_bed = "SceneZOI does not recognize that queen bed, or it is too far away.",
    update_scenezoi = "Update SceneZOI to use HZoi Gameplay.",
    walk_failed = "Both Zois need a clear path to the queen bed.",
}

function M.on_begin(self, component)
    self.actor = component:GetOwner()
    if not M.context then M.context = self.actor end
end

function M.on_tick(self, component)
    if not M.context then M.on_begin(self, component) end
end

function M.on_lua_message(self, component, kind, content)
    if kind ~= "HZoiGameplay.Notice" then return end
    local message = notices[content] or notices.failed
    inzoi.cli.execute('toast.show immediate=true message="' .. message .. '"')
end

function M.on_end(self)
    if M.context == self.actor then M.context = nil end
    self.actor = nil
end

return M
