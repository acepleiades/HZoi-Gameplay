-- Run from prototype/queen-bed.
local source = "HZoiGameplayPrototype_4BD2AC16/lua/B1/"
local context, widgetClass = {}, {}
local invite = "HZoiGameplay_SelectVenue"
local ui = {context = context}
local text = "Localized invitation"
local function entry(bag, caption)
    local label = {text = caption, writes = 0}
    function label:GetText() return self.text end
    function label:SetText(value)
        self.text = value
        self.writes = self.writes + 1
    end
    return setmetatable({Data = {InteractionBagId = bag}, BW_Text_Content = label}, {
        __index = function(_, property)
            error("Menu code must leave the native row and its icons alone: " .. property)
        end,
    })
end

local ground = entry(invite, "")
local bed = entry(invite, "")
local sofa = entry(invite, "")
local unrelated = entry("ClickMove_Cleaning", "Clean Here")
local rows = {ground, bed, sofa, unrelated}

package.loaded["Components.InvitationUI"] = ui
package.loaded.Localization = {text = function(key)
    assert(key == "Have Sex Here")
    return text
end}
UE = {
    UWidgetBlueprintLibrary = {GetAllWidgetsOfClass = function(value, _, class, topOnly)
        assert(value == context and class == widgetClass and not topOnly)
        rows.Num = rawlen
        return setmetatable(rows, {__len = function() error("Use native TArray:Num()") end})
    end},
}
inzoi = {
    UB1ObjectInteractionListEntry = {StaticClass = function() return widgetClass end},
}

local Menu = assert(loadfile(source .. "Main.lua"))()
Menu.on_tick()
for _, row in ipairs({ground, bed, sofa}) do
    assert(row.BW_Text_Content.text == text and row.BW_Text_Content.writes == 1)
end
assert(unrelated.BW_Text_Content.text == "Clean Here" and unrelated.BW_Text_Content.writes == 0)

Menu.on_tick()
assert(ground.BW_Text_Content.writes == 1, "Skip setting an already translated caption")
ground.Data.InteractionBagId = "ClickMove_Cleaning"
ground.BW_Text_Content.text = "Clean Here"
text = "New language"
Menu.on_tick()
assert(ground.BW_Text_Content.text == "Clean Here" and ground.BW_Text_Content.writes == 1,
    "The recycled row should keep its new native caption and icons")
assert(sofa.BW_Text_Content.text == text and sofa.BW_Text_Content.writes == 2)
rows = {}
Menu.on_tick()
ui.context = nil
Menu.on_tick()

print("Native venue captions passed for ground, bed, sofa, and recycled rows.")
