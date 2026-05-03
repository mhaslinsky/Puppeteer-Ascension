PTUtil.SetEnvironment(Puppeteer)
local _G = getfenv(0)
local util = PTUtil

EventHandlerFrames = {}
local function RegisterEventHandler(events, handler)
    if type(events) == "string" then
        events = {events}
    end
    local frame = CreateFrame("Frame", "PTEventHandler_"..events[1])
    for _, event in ipairs(events) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", handler)
    table.insert(EventHandlerFrames, frame)
end

function UnregisterEventHandlers()
    for _, frame in ipairs(EventHandlerFrames) do
        frame:UnregisterAllEvents()
    end
end

RegisterEventHandler("ADDON_LOADED", function()
    if arg1 ~= "Puppeteer" then
        return
    end
    GuidRoster = PTGuidRoster
    OnAddonLoaded()
end)
RegisterEventHandler("PLAYER_ENTERING_WORLD", function()
    CheckGroup()

    if PTOptions.DisablePartyFrames.InParty then
        SetPartyFramesEnabled(false)
    end

    PromptHealersMateImport()
end)
RegisterEventHandler({"UNIT_HEALTH", "UNIT_MAXHEALTH"}, function()
    local unit = arg1
    if not IsRelevantUnit(unit) then
        return
    end
    for ui in UnitFrames(unit) do
        ui:UpdateHealth()
    end
end)
RegisterEventHandler({"UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_FOCUS", "UNIT_MAXMANA", "UNIT_DISPLAYPOWER"}, function()
    local unit = arg1
    if not IsRelevantUnit(unit) then
        return
    end

    for ui in UnitFrames(unit) do
        ui:UpdatePower()
    end
    
    if unit == "player" then
        ReapplySpellsTooltip()
    end
end)
RegisterEventHandler("UNIT_AURA", function()
    local unit = arg1
    if not IsRelevantUnit(unit) then
        return
    end
    if unit == "player" then
        util.MarkSpellCostCacheDirty()
    end
    PTUnit.Get(unit):UpdateAuras()
    for ui in UnitFrames(unit) do
        ui:UpdateAuras()
        ui:UpdateHealth() -- Update health because there may be an aura that changes health bar color
    end
end)
RegisterEventHandler({"PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE"}, function()
    CheckGroupThrottled()
end)
RegisterEventHandler({"UNIT_PET", "PLAYER_PET_CHANGED"}, function()
    local unit = arg1
    if IsRelevantUnit(unit) then
        CheckGroupThrottled()
    end
end)
RegisterEventHandler("PLAYER_TARGET_CHANGED", function()
    for _, ui in ipairs(AllUnitFrames) do
        ui:EvaluateTarget()
    end
    local exists = UnitExists("target")
    local guid = UnitGUID("target")

    PTUnit.Get("target"):UpdateAll()
    if GuidRoster then
        GuidRoster.SetUnitGuid("target", guid)
        PTHealPredict.SetRelevantGUIDs(GuidRoster.GetTrackedGuids())
    end

    if exists then
        EvaluateTracking("target", true)
    end

    if PTOptions.Hidden then
        return
    end

    CheckTarget()
end)
RegisterEventHandler("SPELLS_CHANGED", function()
    PuppeteerSettings.UpdateTrackedDebuffTypes()
    util.MarkSpellCostCacheDirty()
end)
RegisterEventHandler("CHARACTER_POINTS_CHANGED", function()
    util.MarkSpellCostCacheDirty()
end)
RegisterEventHandler("RAID_TARGET_UPDATE", function()
    for _, ui in ipairs(AllUnitFrames) do
        ui:UpdateRaidMark()
    end
end)
RegisterEventHandler("UNIT_FACTION", function()
    if not IsRelevantUnit(arg1) then
        return
    end
    for ui in UnitFrames(arg1) do
        ui:UpdatePVP()
    end
end)
RegisterEventHandler("PLAYER_LOGOUT", function()
    RemoveOverrideBindings()
    PuppeteerSettings.SaveFramePositions()
end)
RegisterEventHandler("PLAYER_REGEN_DISABLED", function()
    -- Auto-close settings if combat starts mid-edit: binding writes are combat-protected and would silently drop.
    if PTSettingsGui and PTSettingsGui.TabFrame and PTSettingsGui.TabFrame:IsShown() then
        PTSettingsGui.TabFrame:Hide()
        Puppeteer.Info("Settings closed: edits aren't allowed during combat.")
    end
end)

local GetKeyModifier = util.GetKeyModifier
local keyListener = CreateFrame("Frame", "PTTooltipKeyListener")
local lastModifier = "None"
local function PTTooltipKeyListener_OnUpdate()
    local modifier = GetKeyModifier()
    if lastModifier ~= modifier then
        lastModifier = modifier
        if SpellsTooltip:IsVisible() then
            ReapplySpellsTooltip()
        end
    end
end

function SetTooltipKeyListenerEnabled(enabled)
    if keyListener:GetScript("OnUpdate") ~= nil == enabled then -- Don't set the script if the state is unchanged
        return
    end
    if enabled then
        lastModifier = GetKeyModifier()
        keyListener:SetScript("OnUpdate", PTTooltipKeyListener_OnUpdate)
    else
        keyListener:SetScript("OnUpdate", nil)
    end
end