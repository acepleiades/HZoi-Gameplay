local UI = require("Components.InvitationUI")
local M = {}
local MOD = "HZoiGameplay_4BD2AC16"
local COMMAND = "uimod.cfg_load mod_id=" .. MOD .. " section=gameplay key=furniture_invite"
local BLOCKING_MOODS = {Sad = true, Uneasy = true, Cringing = true, Irritated = true, Worried = true}
local lastCommand, elapsed

local function blockingMood(controller)
    if not controller then return end
    local character = controller:GetB1Character()
    if not character or not inzoi.UB1EmotionComponent then return end
    local components = character:K2_GetComponentsByClass(inzoi.UB1EmotionComponent:StaticClass())
    local emotion = components and components[1]
    local info = emotion and emotion.CurrentEmotionInfo
    if not info or (tonumber(info.Level) or 0) < 3 then return end
    local mood = tostring(info.EmotionId)
    if BLOCKING_MOODS[mood] then return mood end
end

local function readBlockingMood(controller)
    local ok, mood = pcall(blockingMood, controller)
    if ok then return mood end
end

local function readCommand()
    local ok, label, data = inzoi.cli.execute(COMMAND)
    if not ok then return end
    local value = data or label
    if type(value) ~= "string" then return end
    return value:match('^invite%-%d+%-%d+|[1-9]%d*|[1-9]%d*$')
        or value:match('"value"%s*:%s*"(invite%-%d+%-%d+|[1-9]%d*|[1-9]%d*)"')
end

local function pollFurnitureClick(context)
    local command = readCommand()
    if not command or command == lastCommand then return end
    lastCommand = command
    local time, initiator = command:match("^invite%-(%d+)%-%d+|(%d+)|%d+$")
    if math.abs(os.time() - math.floor(tonumber(time) / 1000)) > 5 then return end
    local controller = UE.UGameplayStatics.GetPlayerController(context, 0)
    local controlled = controller and controller:GetCharacterEntityId()
    if controlled and tostring(controlled.Value) == initiator and not readBlockingMood(controller) then
        inzoi.message.send_to_sim(controlled, "HZoiGameplay.FurnitureInvite", command)
    end
end

function M.on_begin()
    lastCommand = readCommand()
    elapsed = 0
end

function M.on_tick(dt, moduleDt)
    local context = UI.context
    if not context then return end
    elapsed = (elapsed or 0) + (moduleDt or dt or 0)
    if elapsed >= 0.1 then
        elapsed = 0
        -- The native menu closes before the click command reaches the bridge.
        pollFurnitureClick(context)
    end
end

function M.on_end()
    lastCommand = nil
end

return M
