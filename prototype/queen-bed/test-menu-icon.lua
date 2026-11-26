-- Run from prototype/queen-bed.
local source = "HZoiGameplayPrototype_4BD2AC16/lua/B1/"
local context, widgetClass = {}, {}
local invite = "HZoiGameplay_SelectVenue"
local furniture = "_UIMod_HZoiGameplayPrototype_4BD2AC16/venue-invitation~scenezoi_furniture"
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
local texture = {}
local function furnitureEntry(visibility)
    local row = entry(furniture, "")
    local icon = {visibility = 1, writes = 0}
    function icon:GetVisibility() return self.visibility end
    function icon:SetVisibility(value) self.visibility = value end
    function icon:SetBrushFromTexture(value, resize)
        assert(value == texture and not resize)
        self.writes = self.writes + 1
    end
    row.GetVisibility = function() return visibility end
    row.BW_Image_Icon = icon
    return row
end
local bed = furnitureEntry(4)
local sofa = furnitureEntry(4)
local unsupported = furnitureEntry(1)
local unrelated = entry("ClickMove_Cleaning", "Clean Here")
local rows = {ground, bed, sofa, unsupported, unrelated}
local controlled = {Value = 37}
local time = os.time() * 1000
local command = ("invite-%d-1|37|321"):format(time)
local dispatched = {}

package.loaded["Components.InvitationUI"] = ui
package.loaded.Localization = {text = function(key)
    assert(key == "Have Sex Here")
    return text
end}
UE = {
    UObject = {Load = function(path)
        assert(path:find("Conversation_Icon_Mood", 1, true))
        return texture
    end},
    UGameplayStatics = {GetPlayerController = function(value, index)
        assert(value == context and index == 0)
        return {GetCharacterEntityId = function() return controlled end}
    end},
    UWidgetBlueprintLibrary = {GetAllWidgetsOfClass = function(value, _, class, topOnly)
        assert(value == context and class == widgetClass and not topOnly)
        rows.Num = rawlen
        return setmetatable(rows, {__len = function() error("Use native TArray:Num()") end})
    end},
}
inzoi = {
    UB1ObjectInteractionListEntry = {StaticClass = function() return widgetClass end},
    cli = {execute = function(key)
        assert(key:find("key=furniture_invite", 1, true))
        return true, nil, '{"value":"' .. command .. '"}'
    end},
    message = {send_to_sim = function(who, kind, value)
        assert(who == controlled and kind == "HZoiGameplay.FurnitureInvite")
        dispatched[#dispatched + 1] = value
    end},
}

local Menu = assert(loadfile(source .. "Main.lua"))()
Menu.on_begin()
Menu.on_tick()
for _, row in ipairs({ground, bed, sofa}) do
    assert(row.BW_Text_Content.text == text and row.BW_Text_Content.writes == 1)
end
assert(bed.BW_Image_Icon.writes == 1 and sofa.BW_Image_Icon.writes == 1)
assert(unsupported.BW_Image_Icon.writes == 0, "Skip the icon on a row hidden by SceneZOI")
assert(unrelated.BW_Text_Content.text == "Clean Here" and unrelated.BW_Text_Content.writes == 0)

Menu.on_tick(.1)
assert(#dispatched == 0, "Ignore the persisted click on startup")
command = ("invite-%d-2|37|987"):format(time)
Menu.on_tick(.1)
Menu.on_tick(.1)
assert(#dispatched == 1 and dispatched[1] == command, "Dispatch the exact furniture ID only once")
command = ("invite-%d-3|38|987"):format(time)
Menu.on_tick(.1)
command = ("invite-%d-4|37|987"):format(time - 90000)
Menu.on_tick(.1)
assert(#dispatched == 1, "Ignore commands for a different Zoi or from an earlier run")
assert(ground.BW_Text_Content.writes == 1, "Skip setting an already translated caption")
assert(bed.BW_Image_Icon.writes == 1 and sofa.BW_Image_Icon.writes == 1)
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

print("Venue captions, furniture heart, recycled rows, and click delivery passed.")
