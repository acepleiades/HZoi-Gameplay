local UI = require("Components.InvitationUI")
local Localization = require("Localization")
local M = {}
local MOD = "HZoiGameplayPrototype_4BD2AC16"
local INVITE = "HZoiGameplay_SelectVenue"
local FURNITURE = "_UIMod_" .. MOD .. "/venue-invitation~scenezoi_furniture"
local COMMAND = "uimod.cfg_load mod_id=" .. MOD .. " section=gameplay key=furniture_invite"
local HEART = "/Game/UI/Icon/Conversation/Conversation_Icon_Mood.Conversation_Icon_Mood"
local COLLAPSED, SELF_HIT_TEST_INVISIBLE = 1, 4
local lastCommand, elapsed, heart

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
    if controlled and tostring(controlled.Value) == initiator then
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
        pollFurnitureClick(context)
    end
    local class = inzoi.UB1ObjectInteractionListEntry:StaticClass()
    local rows = UE.UWidgetBlueprintLibrary.GetAllWidgetsOfClass(context, nil, class, false)
    if rows:Num() == 0 then return end

    for _, row in ipairs(rows) do
        local bag = row.Data and tostring(row.Data.InteractionBagId)
        if bag == INVITE or bag == FURNITURE then
            local caption = row.BW_Text_Content
            local text = Localization.text("Have Sex Here")
            if caption and tostring(caption:GetText()) ~= text then caption:SetText(text) end
            if bag == FURNITURE and row:GetVisibility() ~= COLLAPSED then
                -- ModKit supplies its own badge on the injected row. Only the
                -- invitation's interaction icon needs to be set here.
                local icon = row.BW_Image_Icon
                if icon and icon:GetVisibility() == COLLAPSED then
                    if heart == nil then heart = UE.UObject.Load(HEART) or false end
                    if heart then
                        icon:SetBrushFromTexture(heart, false)
                        icon:SetVisibility(SELF_HIT_TEST_INVISIBLE)
                    end
                end
            end
        end
    end
end

function M.on_end()
    heart = nil
    lastCommand = nil
end

return M
