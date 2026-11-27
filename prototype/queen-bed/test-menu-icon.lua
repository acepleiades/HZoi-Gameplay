-- Run from prototype/queen-bed.
local source = "HZoiGameplayPrototype_4BD2AC16/lua/B1/"
local context, widgetClass, talkClass, emotionClass = {}, {}, {}, {}
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
    local row = {Data = {InteractionBagId = bag, IsDimmed = false, DimmedTooltipText = ""},
        BW_Text_Content = label, opacity = 1, ToolTipText = "", ToolTipWidget = false}
    function row:GetVisibility() return 4 end
    function row:GetRenderOpacity() return self.opacity end
    function row:SetRenderOpacity(value) self.opacity = value end
    function row:SetToolTipText(value) self.ToolTipText = value end
    return setmetatable(row, {
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
sofa.ToolTipText = "Original sofa tooltip"
local unsupported = furnitureEntry(1)
local unrelated = entry("ClickMove_Cleaning", "Clean Here")
local rows = {ground, bed, sofa, unsupported, unrelated}
local romance = entry("HZoiGameplay_FindVenue", "Have Sex")
local nativeMood = entry("Co_TryTo_Mood_Lover", "Set the Mood")
romance.BW_CategoryText = romance.BW_Text_Content
nativeMood.BW_CategoryText = nativeMood.BW_Text_Content
local talkRows = {romance, nativeMood}
local controlled = {Value = 37}
local emotion = {CurrentEmotionInfo = {EmotionId = "Sad", Level = 2}}
local nativeTooltipAvailable = true
local time = os.time() * 1000
local command = ("invite-%d-1|37|321"):format(time)
local dispatched = {}

package.loaded["Components.InvitationUI"] = ui
package.loaded.Localization = {culture = function() return "en-us" end, text = function(key)
    if key == "Have Sex" then return "Localized Romance invitation" end
    if key == "Your Zoi cannot ask in this mood." then return "Localized fallback" end
    assert(key == "Have Sex Here")
    return text
end}
UE = {
    UObject = {Load = function(path)
        assert(path:find("Conversation_Icon_Mood", 1, true))
        return texture
    end},
    UKismetTextLibrary = {TextFromStringTable = function(path, key)
        assert(path == "/Game/Data/String/Data/ST_Emotion.ST_Emotion")
        local mood = assert(key:match("^Emotion_EmotionLevelDatas_Level3_(%a+)_DisableTooltipTextId$"))
        return nativeTooltipAvailable and "Native mood tooltip " .. mood or "<MISSING STRING TABLE ENTRY>"
    end},
    UGameplayStatics = {GetPlayerController = function(value, index)
        assert(value == context and index == 0)
        return {
            GetCharacterEntityId = function() return controlled end,
            GetB1Character = function()
                return {K2_GetComponentsByClass = function(_, class)
                    assert(class == emotionClass)
                    return {emotion}
                end}
            end,
        }
    end},
    UWidgetBlueprintLibrary = {GetAllWidgetsOfClass = function(value, _, class, topOnly)
        assert(value == context and not topOnly)
        assert(class == widgetClass or class == talkClass)
        local found = class == widgetClass and rows or talkRows
        found.Num = rawlen
        return setmetatable(found, {__len = function() error("Use native TArray:Num()") end})
    end},
}
inzoi = {
    UB1EmotionComponent = {StaticClass = function() return emotionClass end},
    UB1ObjectInteractionListEntry = {StaticClass = function() return widgetClass end},
    UB1TalkInteractionListEntry = {StaticClass = function() return talkClass end},
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
Menu.on_tick(.1)
for _, row in ipairs({ground, bed, sofa}) do
    assert(row.BW_Text_Content.text == text and row.BW_Text_Content.writes == 1)
end
assert(bed.BW_Image_Icon.writes == 1 and sofa.BW_Image_Icon.writes == 1)
assert(unsupported.BW_Image_Icon.writes == 0, "Skip the icon on a row hidden by SceneZOI")
assert(unrelated.BW_Text_Content.text == "Clean Here" and unrelated.BW_Text_Content.writes == 0)
assert(romance.BW_CategoryText.text == "Localized Romance invitation")
assert(nativeMood.BW_CategoryText.text == "Set the Mood" and nativeMood.BW_CategoryText.writes == 0)

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
assert(romance.BW_CategoryText.writes == 1)
assert(bed.BW_Image_Icon.writes == 1 and sofa.BW_Image_Icon.writes == 1)
assert(not bed.Data.IsDimmed and not ground.Data.IsDimmed, "Mild Sad must leave both menu entries available")

emotion.CurrentEmotionInfo.Level = 3
Menu.on_tick(.1)
for _, row in ipairs({ground, bed, sofa}) do
    assert(row.Data.IsDimmed and row.Data.DimmedTooltipText == "Native mood tooltip Sad")
    assert(row.opacity == 0.5)
end
assert(ground.ToolTipText == "", "Keep the native ground row's tooltip mechanism")
assert(bed.ToolTipText == "Native mood tooltip Sad" and sofa.ToolTipText == bed.ToolTipText)
assert(not unsupported.Data.IsDimmed and not unrelated.Data.IsDimmed and not nativeMood.Data.IsDimmed)
command = ("invite-%d-5|37|987"):format(time)
Menu.on_tick(.1)
assert(#dispatched == 1, "A click delivered while blocked must not open a furniture picker")

ground.Data = {InteractionBagId = invite, IsDimmed = true, DimmedTooltipText = "Native restriction"}
emotion.CurrentEmotionInfo.EmotionId = "Worried"
nativeTooltipAvailable = false
Menu.on_tick(.1)
assert(ground.Data.IsDimmed and ground.Data.DimmedTooltipText == "Native restriction" and ground.opacity == 1)
assert(sofa.Data.IsDimmed and sofa.Data.DimmedTooltipText == "Localized fallback")
assert(sofa.ToolTipText == "Localized fallback")

bed.Data = {InteractionBagId = "UnrelatedFurniture", IsDimmed = true, DimmedTooltipText = "Native furniture reason"}
bed.ToolTipText = "Native rebound hover tooltip"
emotion.CurrentEmotionInfo.EmotionId = "Joyful"
Menu.on_tick(.1)
assert(bed.Data.IsDimmed and bed.Data.DimmedTooltipText == "Native furniture reason" and bed.opacity == 1)
assert(not sofa.Data.IsDimmed and sofa.Data.DimmedTooltipText == "" and sofa.opacity == 1)
assert(bed.ToolTipText == "Native rebound hover tooltip" and sofa.ToolTipText == "Original sofa tooltip")
assert(#dispatched == 1, "Do not replay the blocked click after mood recovery")

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

print("Venue captions, strong moods, furniture heart, recycled rows, and click delivery passed.")
