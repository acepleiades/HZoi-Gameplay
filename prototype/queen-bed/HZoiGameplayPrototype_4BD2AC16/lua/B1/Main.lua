local UI = require("Components.InvitationUI")
local Localization = require("Localization")
local M = {}
local INVITE = "HZoiGameplay_SelectVenue"

function M.on_tick()
    local context = UI.context
    if not context then return end
    local class = inzoi.UB1ObjectInteractionListEntry:StaticClass()
    local rows = UE.UWidgetBlueprintLibrary.GetAllWidgetsOfClass(context, nil, class, false)
    if rows:Num() == 0 then return end

    for _, row in ipairs(rows) do
        if row.Data and tostring(row.Data.InteractionBagId) == INVITE then
            -- inZOI renders the native row and both icons. The translated
            -- caption belongs to this mod's locale catalog.
            local caption = row.BW_Text_Content
            local text = Localization.text("Have Sex Here")
            if caption and tostring(caption:GetText()) ~= text then caption:SetText(text) end
        end
    end
end

return M
