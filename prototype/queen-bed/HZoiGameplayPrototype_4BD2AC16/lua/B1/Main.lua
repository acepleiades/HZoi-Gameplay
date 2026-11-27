local UI = require("Components.InvitationUI")
local Localization = require("Localization")
local M = {}
local MOD = "HZoiGameplayPrototype_4BD2AC16"
local INVITE = "HZoiGameplay_SelectVenue"
local ROMANCE_INVITE = "HZoiGameplay_FindVenue"
local FURNITURE = "_UIMod_" .. MOD .. "/venue-invitation~scenezoi_furniture"
local COMMAND = "uimod.cfg_load mod_id=" .. MOD .. " section=gameplay key=furniture_invite"
local HEART = "/Game/UI/Icon/Conversation/Conversation_Icon_Mood.Conversation_Icon_Mood"
local EMOTION_TEXT = "/Game/Data/String/Data/ST_Emotion.ST_Emotion"
local BLOCKING_MOODS = {Sad = true, Uneasy = true, Cringing = true, Irritated = true, Worried = true}
local COLLAPSED, SELF_HIT_TEST_INVISIBLE = 1, 4
local DIMMED_OPACITY = 0.5
local lastCommand, elapsed, heart
local dimmed = {}

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

local function moodTooltip(mood)
    local ok, value = pcall(function()
        return tostring(UE.UKismetTextLibrary.TextFromStringTable(EMOTION_TEXT,
            "Emotion_EmotionLevelDatas_Level3_" .. mood .. "_DisableTooltipTextId"))
    end)
    if ok and value ~= "" and value ~= "nil" and not value:find("MISSING STRING TABLE", 1, true) then return value end
    return Localization.text("Your Zoi cannot ask in this mood.")
end

local function setHoverTooltip(row, previous)
    local current = row.ToolTipText
    if current == nil or row.ToolTipWidget then return end
    current = tostring(current)
    if previous.hoverTooltip == nil then
        previous.originalHoverTooltip = current
    elseif current ~= previous.hoverTooltip then
        return
    end
    row:SetToolTipText(previous.appliedTooltip)
    previous.hoverTooltip = previous.appliedTooltip
end

local function restoreHoverTooltip(row, previous)
    if row.ToolTipText ~= nil and tostring(row.ToolTipText) == previous.hoverTooltip then
        row:SetToolTipText(previous.originalHoverTooltip)
    end
end

local function restoreRow(row)
    local previous = dimmed[row]
    if not previous then return end
    dimmed[row] = nil
    if row:GetRenderOpacity() == DIMMED_OPACITY then row:SetRenderOpacity(previous.opacity) end
    if previous.hoverTooltip then pcall(restoreHoverTooltip, row, previous) end
    if row.Data ~= previous.data then return end
    if row.Data.DimmedTooltipText == previous.appliedTooltip then
        row.Data.IsDimmed = previous.isDimmed
        row.Data.DimmedTooltipText = previous.tooltip
    end
end

local function dimRow(row, mood)
    local data = row.Data
    local previous = dimmed[row]
    if previous and previous.data ~= data then
        restoreRow(row)
        previous = nil
    end
    -- Keep the game's own tooltip when the native ground row is already disabled.
    if not previous and data.IsDimmed then return end
    if not previous then
        previous = {data = data, opacity = row:GetRenderOpacity(), isDimmed = data.IsDimmed,
            tooltip = data.DimmedTooltipText}
        dimmed[row] = previous
    end
    local culture = Localization.culture()
    if previous.mood ~= mood or previous.culture ~= culture then
        previous.mood, previous.culture = mood, culture
        previous.appliedTooltip = moodTooltip(mood)
        -- ModKit's object trigger does not set up the list entry's native tooltip.
        if tostring(data.InteractionBagId) == FURNITURE then pcall(setHoverTooltip, row, previous) end
    end
    if not data.IsDimmed then data.IsDimmed = true end
    if data.DimmedTooltipText ~= previous.appliedTooltip then data.DimmedTooltipText = previous.appliedTooltip end
    if row:GetRenderOpacity() > DIMMED_OPACITY then row:SetRenderOpacity(DIMMED_OPACITY) end
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

local function localizeRomanceInvitation(context)
    local label = Localization.text("Have Sex")
    local class = inzoi.UB1TalkInteractionListEntry:StaticClass()
    for _, row in ipairs(UE.UWidgetBlueprintLibrary.GetAllWidgetsOfClass(context, nil, class, false)) do
        local bag = row.Data and tostring(row.Data.InteractionBagId)
        local caption = row.BW_CategoryText
        if bag == ROMANCE_INVITE and caption and tostring(caption:GetText()) ~= label then caption:SetText(label) end
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
        localizeRomanceInvitation(context)
    end
    local class = inzoi.UB1ObjectInteractionListEntry:StaticClass()
    local rows = UE.UWidgetBlueprintLibrary.GetAllWidgetsOfClass(context, nil, class, false)
    if rows:Num() == 0 and next(dimmed) == nil then return end
    local keepDimmed = {}
    local mood, moodChecked
    for _, row in ipairs(rows) do
        local bag = row.Data and tostring(row.Data.InteractionBagId)
        if bag == INVITE or bag == FURNITURE then
            local caption = row.BW_Text_Content
            local text = Localization.text("Have Sex Here")
            if caption and tostring(caption:GetText()) ~= text then caption:SetText(text) end
            local visible = row:GetVisibility() ~= COLLAPSED
            if visible and not moodChecked then
                mood = readBlockingMood(UE.UGameplayStatics.GetPlayerController(context, 0))
                moodChecked = true
            end
            if visible and mood then
                dimRow(row, mood)
                keepDimmed[row] = true
            end
            if bag == FURNITURE and visible then
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
    for row in pairs(dimmed) do
        if not keepDimmed[row] then pcall(restoreRow, row) end
    end
end

function M.on_end()
    for row in pairs(dimmed) do pcall(restoreRow, row) end
    heart = nil
    lastCommand = nil
end

return M
