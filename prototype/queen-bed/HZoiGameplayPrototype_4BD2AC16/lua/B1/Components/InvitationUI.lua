local WitnessTrace = require("WitnessTraceBridge")
local Json = require("SceneZOIAddon.Json")
local Localization = require("Localization")
local M = {context = nil}
local notices = {
    picker_unavailable = "The partner picker could not open. Close any open picker and make sure your Zoi is out of their group.",
    picker_busy = "Close the current Zoi picker before sending an invitation.",
    busy = "An HZoi invitation is already in progress.",
    failed = "Could not finish the invitation.",
    furniture_unavailable = "That bed is occupied or unavailable.",
    sofa_unavailable = "The selected sofa seats are occupied or unavailable.",
    sofa_walk_failed = "Both Zois need a clear path to the selected sofa seats.",
    ground_unavailable = "Choose a walkable spot for the encounter.",
    ground_click_missing = "Could not read the selected ground spot. Open the ground menu and try again.",
    ground_walk_failed = "Both Zois need a clear path and room to stand at the selected spot.",
    initiator_not_controlled = "Select the Zoi who sent the invitation first.",
    partner_ineligible = "No eligible partner was selected.",
    no_eligible_partners = "No eligible partners are available.",
    mood_blocked = "Your Zoi cannot ask in this mood.",
    arrival_privacy_denied = "They need more privacy.",
    no_matching_scenes = "No scenes were found for these Zois at this spot.",
    no_reachable_venue = "No suitable place is available.",
    goal_unreachable = "No scenes at this spot can complete the goals for this pair.",
    not_eligible = "These Zois cannot use Set the Mood right now.",
    participant_busy = "One of the Zois is already in a SceneZOI session. Try again afterward.",
    queue_failed = "The invitation could not be added to the action queue.",
    required_stage_unavailable = "An activity needed for this encounter is unavailable.",
    session_already_running = "End the current SceneZOI session before starting another.",
    timeout = "The invitation took too long. Check the Zois' action queues and try again.",
    transport_timeout = "SceneZOI did not respond. Check that it is installed and enabled.",
    unsupported_venue = "SceneZOI could not find a supported bed or adjacent sofa seats here.",
    update_scenezoi = "Update SceneZOI to use HZoi Gameplay.",
    walk_failed = "Both Zois need a clear path to the selected bed.",
}

function M.on_begin(self, component)
    self.actor = component:GetOwner()
    if not M.context then M.context = self.actor end
end

function M.on_tick(self, component)
    if not M.context then M.on_begin(self, component) end
end

local function showNotice(message)
    inzoi.cli.execute("toast.show immediate=true message=" .. Json.encode(Localization.text(message)))
end

local function isControlled(actor)
    if not actor then return false end
    local controller = UE.UGameplayStatics.GetPlayerController(actor, 0)
    local controlledId = controller and controller:GetCharacterEntityId()
    return controlledId and controlledId.Value == actor:GetEntityId().Value
end

function M.on_lua_message(self, component, kind, content)
    if kind == "HZoiGameplay.WitnessTrace" then
        if self.actor then WitnessTrace.reply(self.actor, content) end
        return
    end
    if kind == "HZoiGameplay.PickerPaused" then
        if isControlled(self.actor) then
            inzoi.cli.execute("toast.show immediate=true message=" .. Json.encode(content))
        end
    elseif kind == "HZoiGameplay.Notice" then
        -- The player can switch Zois while the notification is in transit.
        if content == "arrival_privacy_denied" and not isControlled(self.actor) then return end
        showNotice(notices[content] or notices.failed)
    end
end

function M.on_end(self)
    if M.context == self.actor then M.context = nil end
    self.actor = nil
end

return M
