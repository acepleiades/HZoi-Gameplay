local WitnessTrace = require("WitnessTraceBridge")
local Json = require("SceneZOIAddon.Json")
local M = {context = nil}
local notices = {
    picker_unavailable = "The partner picker could not open. Close any open picker and make sure your Zoi is out of their group.",
    picker_busy = "Close the current Zoi picker before sending an invitation.",
    busy = "An HZoi invitation is already in progress.",
    failed = "Could not finish the invitation.",
    furniture_unavailable = "That queen bed is occupied or unavailable.",
    sofa_unavailable = "The selected sofa seats are occupied or unavailable.",
    sofa_walk_failed = "Both Zois need a clear path to the selected sofa seats.",
    ground_unavailable = "Choose a walkable spot for the scene.",
    ground_click_missing = "Could not read the selected ground spot. Open the ground menu and try again.",
    ground_walk_failed = "Both Zois need a clear path and room to stand at the selected spot.",
    initiator_not_controlled = "Select the Zoi who sent the invitation first.",
    no_matching_scenes = "No scenes were found for these Zois at this spot.",
    goal_unreachable = "No scenes at this spot can complete the goals for this pair.",
    not_eligible = "These Zois cannot use Set the Mood right now.",
    participant_busy = "One of the Zois is already in a scene. Try again afterward.",
    queue_failed = "The invitation could not be added to the action queue.",
    required_stage_unavailable = "An activity needed for this encounter is unavailable.",
    session_already_running = "End the current SceneZOI scene before starting another.",
    timeout = "The invitation took too long. Check the Zois' action queues and try again.",
    transport_timeout = "SceneZOI did not respond. Check that it is installed and enabled.",
    unsupported_venue = "SceneZOI could not find a supported queen bed or adjacent sofa seats here.",
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

local function showNotice(message)
    inzoi.cli.execute("toast.show immediate=true message=" .. Json.encode(message))
end

local function showUrge(self, content)
    if not self.actor then return end
    local controller = UE.UGameplayStatics.GetPlayerController(self.actor, 0)
    if not controller or controller:GetCharacterEntityId().Value ~= self.actor:GetEntityId().Value then return end
    local ok, urge = pcall(Json.decode, content, 1024)
    if not ok or type(urge) ~= "table" or type(urge.partner) ~= "string" or #urge.partner > 256 then return end
    if urge.kind == "selected" then
        showNotice("Your Zoi wants some private time with " .. urge.partner .. ".")
    elseif urge.kind == "fulfilled" then
        showNotice("Your Zoi fulfilled their urge with " .. urge.partner .. ".")
    end
end

function M.on_lua_message(self, component, kind, content)
    if kind == "HZoiGameplay.WitnessTrace" then
        if self.actor then WitnessTrace.reply(self.actor, content) end
        return
    end
    if kind == "HZoiGameplay.Urge" then
        showUrge(self, content)
    elseif kind == "HZoiGameplay.Notice" then
        showNotice(notices[content] or notices.failed)
    end
end

function M.on_end(self)
    if M.context == self.actor then M.context = nil end
    self.actor = nil
end

return M
