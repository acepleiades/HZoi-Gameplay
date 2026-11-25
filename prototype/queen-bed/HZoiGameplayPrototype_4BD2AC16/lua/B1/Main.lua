local UI = require("Components.InvitationUI")
local M = {}
local MOD = "HZoiGameplayPrototype_4BD2AC16"
local MARKER = "_UIMod_" .. MOD .. "/partner-picker~hzoi_queen_invite"
local COLLAPSED = 1
local queenBeds = {
    Bed01 = true, Bed01_v01 = true, Bed01_v02 = true, Bed01_v03 = true, Bed01_v04 = true, Bed01_v05 = true,
    Bed04 = true, Bed04_v01 = true, Bed04_v02 = true, Bed04_v03 = true, Bed04_v04 = true,
    E01_Bed01 = true, E01_Bed01_v01 = true, E01_Bed01_v03 = true,
}
local hidden = {}
local held, elapsed, initialized, lastError

local function read()
    local ok, label, value = inzoi.cli.execute("uimod.cfg_load mod_id=" .. MOD .. " section=gameplay key=invite")
    if not ok then return "" end
    local raw = value or label or ""
    if raw:match("^[a-z0-9_%-]+|%d+|%d+$") then return raw end
    return raw:match('"value"%s*:%s*"([a-z0-9_%-]+|%d+|%d+)"') or ""
end

local function restore(entry)
    local visibility = hidden[entry]
    hidden[entry] = nil
    if visibility ~= nil and entry:GetVisibility() == COLLAPSED then entry:SetVisibility(visibility) end
end

local function release()
    for entry in pairs(hidden) do pcall(restore, entry) end
end

local function updateMenu(ctx, manager, canInvite)
    local seen = {}
    local class = inzoi.UB1ObjectInteractionListEntry:StaticClass()
    for _, entry in ipairs(UE.UWidgetBlueprintLibrary.GetAllWidgetsOfClass(ctx, nil, class, false)) do
        local data = entry.Data
        local own = data and tostring(data.InteractionBagId) == MARKER
        local bed = own and manager.GameObjectMap:Find(data.TargetEntityId)
        -- UI Mod currently injects object actions on every object. Filter only
        -- our own rendered row, using the framework's built-in queen model IDs.
        -- The live API checks the actual venue, availability and the chosen pair.
        if own and not (canInvite and bed and queenBeds[tostring(bed.ObjectDataTableId)]) then
            local visibility = entry:GetVisibility()
            if visibility ~= COLLAPSED then
                hidden[entry] = visibility
                entry:SetVisibility(COLLAPSED)
            end
            seen[entry] = true
        else
            restore(entry)
        end
    end
    for entry in pairs(hidden) do if not seen[entry] then pcall(restore, entry) end end
end

local function tick()
    local ctx = UI.context
    if not ctx then
        release()
        return
    end
    local controller = UE.UGameplayStatics.GetPlayerController(ctx, 0)
    local system = inzoi.UB1System.Get()
    local manager = system and system.ManagerMap:Find(inzoi.EB1ManagerType.Entity)
    if not (controller and manager) then release(); return end

    local controlled = controller:GetCharacterEntityId()
    local actor = manager.CharacterMap:Find(controlled)
    local appearance = actor and actor.AppearanceComponent
    local stage = appearance and appearance:GetGrowthStep()
    local stages = inzoi.EB1GrowthStep
    local canInvite = stage ~= nil and
        (stage == stages.Youth or stage == stages.Adult or stage == stages.Old or stage == stages.Elderly)
    updateMenu(ctx, manager, canInvite)

    local command = read()
    if not initialized then
        held, initialized = command, true
        print("[HZoiGameplay] Partner picker ready")
        return
    end
    if command == held then return end
    held = command
    local nonce, initiator, bed = command:match("^([a-z0-9_%-]+)|(%d+)|(%d+)$")
    if not (nonce and canInvite and tostring(controlled.Value) == initiator) then return end
    local target = inzoi.FB1EntityId()
    target.Value = tonumber(bed)
    local object = manager.GameObjectMap:Find(target)
    if not object or not queenBeds[tostring(object.ObjectDataTableId)] then return end
    inzoi.message.send_to_sim(controlled, "HZoiGameplay.Invite", command)
end

function M.on_begin()
    held, elapsed, initialized = "", 0, false
end

function M.on_tick(dt, moduleDt)
    elapsed = elapsed + (moduleDt or dt or 0)
    if elapsed < .20 then return end
    elapsed = 0
    local ok, err = pcall(tick)
    if not ok then
        release()
        if tostring(err) ~= lastError then
            lastError = tostring(err)
            print("[HZoiGameplay] Menu update failed: " .. lastError)
        end
    else
        lastError = nil
    end
end

function M.on_end()
    release()
    UI.context = nil
end

return M
