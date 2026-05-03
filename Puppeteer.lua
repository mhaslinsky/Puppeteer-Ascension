Puppeteer = {}
PTUtil.SetEnvironment(Puppeteer)
local _G = getfenv(0)

-- Phase 2b: replaced AceAddon-2.0:new("AceEvent-2.0") with a minimal frame-based dispatcher.
-- Only RegisterEvent is used by addon code (one call site, in this file).
do
    local frame = CreateFrame("Frame")
    local handlers = {}
    frame:SetScript("OnEvent", function(self, event, ...)
        local list = handlers[event]
        if not list then return end
        for _, fn in ipairs(list) do
            fn(...)
        end
    end)
    local lib = {}
    function lib:RegisterEvent(eventName, handler)
        if not handlers[eventName] then
            handlers[eventName] = {}
            frame:RegisterEvent(eventName)
        end
        table.insert(handlers[eventName], handler)
    end
    _G.PuppeteerLib = lib
end

VERSION = GetAddOnMetadata("Puppeteer", "version")

TestUI = false

-- Phase 2b: Banzai/HealComm-1.0 ripped. Aggro now via native UnitThreatSituation.
-- Heal prediction temporarily stubbed; Phase 3 wires up LibHealComm-4.0.
GuidRoster = nil -- Will be nil if SuperWoW isn't present

local util = PTUtil
local colorize = util.Colorize
local GetKeyModifier = util.GetKeyModifier
local GetClass = util.GetClass
local GetPowerType = util.GetPowerType
local UseItem = util.UseItem
local GetItemCount = util.GetItemCount

PartyUnits = util.PartyUnits
PetUnits = util.PetUnits
TargetUnits = util.TargetUnits
RaidUnits = util.RaidUnits
RaidPetUnits = util.RaidPetUnits
AllUnits = util.AllUnits
AllUnitsSet = util.AllUnitsSet
AllCustomUnits = util.CustomUnits
AllCustomUnitsSet = util.CustomUnitsSet

local ptBarsPath = util.GetAssetsPath().."textures\\bars\\"
BarStyles = {
    ["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
    ["Blizzard Smooth"] = ptBarsPath.."Blizzard-Smooth",
    ["Blizzard Raid"] = ptBarsPath.."Blizzard-Raid",
    ["Blizzard Raid Sideless"] = ptBarsPath.."Blizzard-Raid-Sideless",
    ["Puppeteer"] = ptBarsPath.."Puppeteer",
    ["Puppeteer Borderless"] = ptBarsPath.."Puppeteer-Borderless",
    ["Puppeteer Shineless"] = ptBarsPath.."Puppeteer-Shineless",
    ["Puppeteer Shineless Borderless"] = ptBarsPath.."Puppeteer-Shineless-Borderless"
}

CurrentlyHeldButton = nil

-- An unmapped array of all unit frames
AllUnitFrames = {}
-- A map of units to an array of unit frames associated with the unit
PTUnitFrames = {}

-- Key: Unit frame group name | Value: The group
UnitFrameGroups = {}

-- Phase 4: CustomUnitGUIDMap / GUIDCustomUnitMap removed with UnitProxy delete.


CurrentlyInRaid = false

Mouseover = nil

-- Returns the array of unit frames of the unit
function GetUnitFrames(unit)
    return PTUnitFrames[unit]
end

-- A temporary dummy function while the addon initializes. See below for the real iterator.
function UnitFrames(unit)
    return function() end
end

local function OpenUnitFramesIterator()
    -- UnitFrames function definition.
    -- Returns an iterator for the unit frames of the unit.
    -- These iterators have a serious problem in that they do not support concurrent iteration.
    -- Phase 4: GUID-keyed iterator branch removed; revisit when Task A collapses PTUnit
    -- to GUID-only and the iterator may need to accept either GUID or unit-id.
    local PTUnitFrames = PTUnitFrames
    local uis
    local i = 0
    local len = 0
    local iterFunc = function()
        i = i + 1
        if i <= len then
            return uis[i]
        end
    end
    function UnitFrames(unit)
        i = 0
        uis = PTUnitFrames[unit]
        len = uis and table.getn(uis) or 0
        return iterFunc
    end
end

function Debug(msg)
    DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- Captures unit-frame state into PTGlobalOptions._debug. Triggered manually via
-- /run Puppeteer.DumpFrameState("target"); /reload to flush to SavedVariables.
local function snapshotFrame(f)
    if not f then return "nil" end
    local r, g, b, a
    if f.GetStatusBarColor then
        r, g, b, a = f:GetStatusBarColor()
    end
    local parent = f:GetParent()
    return {
        name = f:GetName() or "unnamed",
        shown = f:IsShown() and 1 or 0,
        visible = f:IsVisible() and 1 or 0,
        alpha = f:GetAlpha(),
        width = f:GetWidth(),
        height = f:GetHeight(),
        left = f:GetLeft(),
        top = f:GetTop(),
        level = f:GetFrameLevel(),
        strata = f:GetFrameStrata(),
        parent = parent and (parent:GetName() or "anon") or "nil",
        value = f.GetValue and f:GetValue() or "n/a",
        texture = (f.GetStatusBarTexture and f:GetStatusBarTexture()) and "set" or "nil",
        color = r and (r..","..g..","..b..","..(a or 1)) or "n/a",
    }
end

function DumpFrameState(unit)
    if not PTGlobalOptions then return end
    PTGlobalOptions._debug = {timestamp = GetTime(), frames = {}}
    for ui in UnitFrames(unit or "target") do
        table.insert(PTGlobalOptions._debug.frames, {
            unit = ui:GetUnit(),
            unitGuid = UnitGUID(ui:GetUnit() or ""),
            unitExists = UnitExists(ui:GetUnit() or "") and 1 or 0,
            incomingHealing = ui.incomingHealing,
            incomingDirectHealing = ui.incomingDirectHealing,
            healthBar = snapshotFrame(ui.healthBar),
            incomingHealthBar = snapshotFrame(ui.incomingHealthBar),
            incomingDirectHealthBar = snapshotFrame(ui.incomingDirectHealthBar),
            container = ui.GetContainer and snapshotFrame(ui:GetContainer()) or "nil",
        })
    end
    DEFAULT_CHAT_FRAME:AddMessage("[PT] state captured for "..(unit or "target")..". /reload to flush.")
end

function UpdateUnitFrameGroups()
    for _, group in pairs(UnitFrameGroups) do
        group:UpdateUIPositions()
    end
end

function UpdateAllIncomingHealing()
    if PTHealPredict then
        for _, ui in ipairs(AllUnitFrames) do
            if PTOptions.UseHealPredictions then
                local guid = UnitGUID(ui:GetUnit())
                ui:SetIncomingHealing(PTHealPredict.GetIncomingHealing(guid))
            else
                ui:SetIncomingHealing(0)
            end
        end
    else
        for _, ui in ipairs(AllUnitFrames) do
            if PTOptions.UseHealPredictions then
                ui:UpdateIncomingHealing()
            else
                ui:SetIncomingHealing(0)
            end
        end
    end
end

function UpdateAllOutlines()
    for _, ui in ipairs(AllUnitFrames) do
        ui:UpdateOutline()
    end
end

function CreateUnitFrameGroup(groupName, environment, units, petGroup, profile, sortByRole)
    if UnitFrameGroups[groupName] then
        error("[Puppeteer] Tried to create a unit frame group using existing name! \""..groupName.."\"")
        return
    end
    local uiGroup = PTUnitFrameGroup:New(groupName, environment, units, petGroup, profile, sortByRole)
    for _, unit in ipairs(units) do
        local ui = PTUnitFrame:New(unit, AllCustomUnitsSet[unit] ~= nil)
        if not PTUnitFrames[unit] then
            PTUnitFrames[unit] = {}
        end
        table.insert(PTUnitFrames[unit], ui)
        table.insert(AllUnitFrames, ui)
        uiGroup:AddUI(ui, true)
        if unit ~= "target" then
            ui:Hide()
        end
    end
    UnitFrameGroups[groupName] = uiGroup
    uiGroup:UpdateUIPositions()
    return uiGroup
end

local function initUnitFrames()
    local getSelectedProfile = PuppeteerSettings.GetSelectedProfile
    CreateUnitFrameGroup("Party", "party", PartyUnits, false, getSelectedProfile("Party"))
    CreateUnitFrameGroup("Pets", "party", PetUnits, true, getSelectedProfile("Pets"))
    CreateUnitFrameGroup("Raid", "raid", RaidUnits, false, getSelectedProfile("Raid"))
    CreateUnitFrameGroup("Raid Pets", "raid", RaidPetUnits, true, getSelectedProfile("Raid Pets"))
    CreateUnitFrameGroup("Target", "all", TargetUnits, false, getSelectedProfile("Target"), false)
    -- Phase 4: Focus and Enemy frame groups removed (SuperWoW-only). Multi-focus deferred to v2.1.

    local baseCondition = UnitFrameGroups["Target"].ShowCondition
    UnitFrameGroups["Target"].ShowCondition = function(self)
        local friendly = not UnitCanAttack("player", "target")
        return (PTOptions.AlwaysShowTargetFrame or (UnitExists("target") and 
            (friendly and PTOptions.ShowTargets.Friendly) or (not friendly and PTOptions.ShowTargets.Hostile))) 
            and baseCondition(self)
    end

    OpenUnitFramesIterator()
end

function OnAddonLoaded()
    PuppeteerSettings.SetDefaults()

    if PTBindings == nil then
        GenerateDefaultBindings()
    end

    InitOverrideBindingsMapping()
    InitBindingDisplayCache()

    -- Phase 4: Nampower SetCVar + PTUnitProxy reapply removed (capability flags hardcoded false).

    if not _G.PTRoleCache then
        _G.PTRoleCache = {}
    end
    if not _G.PTRoleCache[GetRealmName()] then
        _G.PTRoleCache[GetRealmName()] = {}
    end
    AssignedRoles = _G.PTRoleCache[GetRealmName()]
    PruneAssignedRoles()

    -- Phase 4: PTCustomUnitUpdater frame removed (SuperWoW-only custom-unit GUID polling).
    PTUnit.CreateCaches()
    PuppeteerSettings.UpdateTrackedDebuffTypes()
    PTProfileManager.InitializeDefaultProfiles()

    do
        if PTOptions.Scripts.OnLoad then
            local scriptString = "local GetProfile = PTProfileManager.GetProfile "..
                "local CreateProfile = PTProfileManager.CreateProfile "..PTOptions.Scripts.OnLoad
            local script, err = loadstring(scriptString)
            if script then
                local ok, result = pcall(script)
                if not ok then
                    DEFAULT_CHAT_FRAME:AddMessage(colorize("[Puppeteer] ", 1, 0.4, 0.4)..colorize("ERROR: ", 1, 0.2, 0.2)
                        ..colorize("The Load Script produced an error! If this causes Puppeteer to fail to load, "..
                            "you will need to manually edit the script in your game files.", 1, 0.4, 0.4))
                    DEFAULT_CHAT_FRAME:AddMessage(colorize("OnLoad Script Error: "..tostring(result), 1, 0, 0))
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage(colorize("[Puppeteer] ", 1, 0.4, 0.4)..colorize("ERROR: ", 1, 0.2, 0.2)
                    ..colorize("The Load Script failed to load: "..err, 1, 0.4, 0.4))
            end
        end
    end
    PTSettingsGui.Init()
    if PTHealPredict then
        PTHealPredict.OnLoad()

        PTHealPredict.HookUpdates(function(guid, incomingHealing, incomingDirectHealing)
            if not PTOptions.UseHealPredictions then return end
            local units = GuidRoster.GetUnits(guid)
            if not units then return end
            for _, unit in ipairs(units) do
                for ui in UnitFrames(unit) do
                    ui:SetIncomingHealing(incomingHealing, incomingDirectHealing)
                end
            end
        end)
    end
    -- Phase 2b: HealComm-1.0 + RosterLib-2.0 ripped. Heal prediction on non-SuperWoW
    -- clients is offline until Phase 3 wires up LibHealComm-4.0.

    InitRoleDropdown()
    
    SetLFTAutoRoleEnabled(PTOptions.LFTAutoRole)

    SetOutOfRangeArrowEnabled(PTOptions.OutOfRangeArrow)

    TestUI = PTOptions.TestUI

    if TestUI then
        DEFAULT_CHAT_FRAME:AddMessage(colorize("[Puppeteer] UI Testing is enabled. Use /pt testui to disable.", 1, 0.6, 0.6))
    end

    initUnitFrames()
    StartUnitTracker()

    PuppeteerLib:RegisterEvent("UNIT_THREAT_LIST_UPDATE", function(unit)
        if PTGuidRoster then
            unit = PTGuidRoster.GetUnitGuid(unit)
        end
        for ui in UnitFrames(unit) do
            ui:UpdateOutline()
        end
    end)

    if PTOnLoadInfoDisabled == nil then
        PTOnLoadInfoDisabled = false
    end

    do
        local INFO_SEND_TIME = GetTime() + 0.5
        local infoFrame = CreateFrame("Frame")
        infoFrame:SetScript("OnUpdate", function()
            if GetTime() < INFO_SEND_TIME then
                return
            end
            infoFrame:SetScript("OnUpdate", nil)
            if PTGlobalOptions.ShowLoadMessage then
                DEFAULT_CHAT_FRAME:AddMessage(colorize("[Puppeteer] Use ", 0.5, 1, 0.5)..colorize("/pt help", 0, 1, 0)
                    ..colorize(" to see commands.", 0.5, 1, 0.5))
            end
    
            -- Phase 2b: HealComm-1.0 SuperWoW conflict check removed; replaced by LibHealComm-4.0 in Phase 3.
            -- Phase 4: Nampower-without-SuperWoW warning removed (capability flags hardcoded false).
        end)
    end

    do
        if PTOptions.Scripts.OnPostLoad then
            local scriptString = "local GetProfile = PTProfileManager.GetProfile "..
                "local CreateProfile = PTProfileManager.CreateProfile "..PTOptions.Scripts.OnPostLoad
            local script, err = loadstring(scriptString)
            if script then
                local ok, result = pcall(script)
                if not ok then
                    DEFAULT_CHAT_FRAME:AddMessage(colorize("[Puppeteer] ", 1, 0.4, 0.4)..colorize("ERROR: ", 1, 0.2, 0.2)
                        ..colorize("The Postload Script produced an error! If this causes Puppeteer to fail to operate, "..
                            "you may need to manually edit the script in your game files.", 1, 0.4, 0.4))
                    DEFAULT_CHAT_FRAME:AddMessage(colorize("OnPostLoad Script Error: "..tostring(result), 1, 0, 0))
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage(colorize("[Puppeteer] ", 1, 0.4, 0.4)..colorize("ERROR: ", 1, 0.2, 0.2)
                    ..colorize("The Postload Script failed to load: "..err, 1, 0.4, 0.4))
            end
        end
    end
end

function PromptHealersMateImport()
    if IsAddOnLoaded("HealersMate") and HealersMate and PTOptions["ImportedFromHM"] == nil then
        local dialog = PTGuiLib.Get("simple_dialog", UIParent)
            :SetWidth(350)
            :SetPoint("CENTER")
            :SetTitle("Puppeteer HealersMate Import")
            :SetText("Puppeteer has detected HealersMate. Would you like to import your character's data from HealersMate? "..
                "This will overwrite your settings in Puppeteer!")
            :SetMovable(true)
        dialog:GetHandle():SetFrameStrata("HIGH")
        dialog:SetDisposeHandler(function(self)
            self:GetHandle():SetFrameStrata("MEDIUM")
        end)

        dialog:AddButton("Import & Disable HM", function()
            DisableAddOn("HealersMate")
            ImportHealersMateSettings()
        end)
        dialog:AddButton("Import & Don't Disable HM", function()
            ImportHealersMateSettings()
        end)
        dialog:AddButton("Don't Import & Disable HM", function()
            PTOptions["ImportedFromHM"] = false
            DisableAddOn("HealersMate")
            ReloadUI()
            dialog:Dispose()
        end)
        dialog:AddButton("Don't Import & Don't Disable HM", function()
            PTOptions["ImportedFromHM"] = false
            dialog:Dispose()
        end)
        dialog:AddButton("Ask Me Later", function()
            dialog:Dispose()
        end)
    end
end

function ImportHealersMateSettings()
    if _G.HMOptions then
        _G.PTOptions = util.CloneTable(_G.HMOptions, true)
        _G.PTOptions["ImportedFromHM"] = true
    end
    if _G.HMSpells then
        local loadout = ConvertSpellsToBindings(_G.HMSpells)
        GetBindingLoadouts()["Imported"] = loadout
        PTBindings.SelectedLoadout = "Imported"
    end

    if _G.PTGlobalOptions["ImportedFromHM"] == nil then
        -- Import global fields if HealersMate has a larger heal cache
        if _G.PTHealCache and (util.GetTableSize(_G.PTHealCache) < util.GetTableSize(_G.HMHealCache)) then
            _G.PTHealCache = _G.HMHealCache
            _G.PTPlayerHealCache = _G.HMPlayerHealCache
            _G.PTRoleCache = _G.HMRoleCache
        end
        _G.PTGlobalOptions["ImportedFromHM"] = true
    end

    ReloadUI()
end

-- Converts legacy HealersMate spells to a Puppeteer loadout
function ConvertSpellsToBindings(spells)
    local specialToActionMap = {
        ["TARGET"] = "Target",
        ["ASSIST"] = "Assist",
        ["FOLLOW"] = "Follow",
        ["CONTEXT"] = "Menu",
        ["ROLE"] = "Role",
        ["SET ROLE"] = "Role",
        ["ROLE: TANK"] = "Role: Tank",
        ["ROLE: HEALER"] = "Role: Healer",
        ["ROLE: DAMAGE"] = "Role: Damage",
        ["ROLE: NONE"] = "Role: None"
    }
    local loadout = CreateEmptyBindingsLoadout()
    for target, modifiers in pairs(spells) do
        for modifier, buttons in pairs(modifiers) do
            loadout.Bindings[target][modifier] = {}
            for button, spell in pairs(buttons) do
                local binding
                if util.StartsWith(spell, "Item: ") then
                    binding = {
                        Type = "ITEM",
                        Data = string.sub(spell, string.len("Item: ") + 1)
                    }
                elseif util.StartsWith(spell, "Macro: ") then
                    binding = {
                        Type = "MACRO",
                        Data = string.sub(spell, string.len("Macro: ") + 1)
                    }
                elseif specialToActionMap[string.upper(spell)] then
                    binding = {
                        Type = "ACTION",
                        Data = specialToActionMap[string.upper(spell)]
                    }
                else
                    binding = {
                        Type = "SPELL",
                        Data = spell
                    }
                end

                loadout.Bindings[target][modifier][button] = binding
            end
        end
    end
    PruneLoadout(loadout)
    return loadout
end

function CheckPartyFramesEnabled()
    local shouldBeDisabled = (CurrentlyInRaid and PTOptions.DisablePartyFrames.InRaid) or 
        (not CurrentlyInRaid and PTOptions.DisablePartyFrames.InParty)
    SetPartyFramesEnabled(not shouldBeDisabled)
end

function SetPartyFramesEnabled(enabled)
    if enabled then
        for i = 1, MAX_PARTY_MEMBERS do
            local frame = getglobal("PartyMemberFrame"..i)
            if frame and frame.PTRealShow then
                frame.Show = frame.PTRealShow
                frame.PTRealShow = nil

                if UnitExists("party"..i) then
                    frame:Show()
                end
                local prevThis = _G.this
                _G.this = frame
                PartyMemberFrame_OnLoad()
                _G.this = prevThis
            end
        end
    else
        for i = 1, MAX_PARTY_MEMBERS do
            local frame = getglobal("PartyMemberFrame"..i)
            if frame and not frame.PTRealShow then
                frame:UnregisterAllEvents()
                frame.PTRealShow = frame.Show
                frame.Show = function() end
                frame:Hide()
            end
        end
    end
end

-- Phase 4: ToggleFocusUnit / FocusUnit / UnfocusUnit / PromoteFocus / CycleFocus
-- removed with UnitProxy delete (multi-focus feature cut for v2.0).

local emptySpell = {}
function UnitFrame_OnClick(button, unit, unitFrame)
    local binding = GetBindingFor(unit, GetKeyModifier(), button)
    if not UnitExists(unit) then
        if binding and binding.Type == "ACTION" then
            RunBinding(binding, unit, unitFrame)
        end
        return
    end
    if not binding then
        RunBinding_Spell(emptySpell, unit)
        return
    end

    RunBinding(binding, unit, unitFrame)
end

local CheckGroupThrottler = CreateFrame("Frame", "PTCheckGroupThrottler")
local MAX_GROUP_UPDATE_TOKENS = 2
local GROUP_UPDATE_RECOVERY = 0.2
local groupUpdateTokens = 2
local nextGroupUpdateToken = 0
local groupUpdateWaiting = false
local CheckGroupThrottler_OnUpdate = function()
    if nextGroupUpdateToken <= GetTime() then
        groupUpdateTokens = groupUpdateTokens + 1
        nextGroupUpdateToken = GetTime() + GROUP_UPDATE_RECOVERY
        if groupUpdateWaiting then
            groupUpdateWaiting = false
            print("Delayed Group Update")
            CheckGroupThrottled()
        end
        if groupUpdateTokens == MAX_GROUP_UPDATE_TOKENS then
            CheckGroupThrottler:SetScript("OnUpdate", nil)
        end
    end
end
function UseGroupUpdateToken()
    if groupUpdateTokens > 0 then
        groupUpdateTokens = groupUpdateTokens - 1
        if CheckGroupThrottler:GetScript("OnUpdate") == nil then
            nextGroupUpdateToken = GetTime() + GROUP_UPDATE_RECOVERY
            CheckGroupThrottler:SetScript("OnUpdate", CheckGroupThrottler_OnUpdate)
        end
        return true
    end
    groupUpdateWaiting = true
    return false
end

-- Same as CheckGroup, but may delay and consolidate checks if there's been many calls
function CheckGroupThrottled()
    if UseGroupUpdateToken() then
        CheckGroup()
        print("Group Update "..groupUpdateTokens)
    else
        print("GROUP UPDATE THROTTLED")
    end
end

-- Reevaluates what UI frames should be shown and updates the roster if using SuperWoW
function CheckGroup()
    --StartTiming("CheckGroup")
    if GetNumRaidMembers() > 0 then
        if not CurrentlyInRaid then
            CurrentlyInRaid = true
            SetPartyFramesEnabled(not PTOptions.DisablePartyFrames.InRaid)
        end
    else
        if CurrentlyInRaid then
            CurrentlyInRaid = false
            SetPartyFramesEnabled(not PTOptions.DisablePartyFrames.InParty)
        end
    end
    if GuidRoster then
        GuidRoster.ResetRoster()
        GuidRoster.PopulateRoster()
    end
    for _, unit in ipairs(util.AllRealUnits) do
        local exists, guid = UnitExists(unit)
        if unit ~= "target" then
            if exists then
                for ui in UnitFrames(unit) do
                    ui:Show()
                end
            else
                for ui in UnitFrames(unit) do
                    ui:Hide()
                end
            end
        end
    end
    for _, group in pairs(UnitFrameGroups) do
        group:EvaluateShown()
    end
    -- Without SuperWoW units may have shifted; do a full scan every CheckGroup tick.
    PTUnit.UpdateAllUnits()
    for _, ui in ipairs(AllUnitFrames) do
        if ui:IsShown() then
            ui:UpdateRange()
            ui:UpdateSight()
            ui:UpdateAuras()
            ui:UpdateIncomingHealing()
            ui:UpdateOutline()
        end
    end
    PTHealPredict.SetRelevantGUIDs(GuidRoster.GetTrackedGuids())
    RunTrackingScan()
    --EndTiming("CheckGroup")
end

function CheckTarget()
    local exists, guid = UnitExists("target")
    if exists then
        local friendly = not UnitCanAttack("player", "target")
        if (friendly and PTOptions.ShowTargets.Friendly) or (not friendly and PTOptions.ShowTargets.Hostile) then
            for ui in UnitFrames("target") do
                ui.lastHealthPercent = (ui:GetCurrentHealth() / ui:GetMaxHealth()) * 100
                ui:UpdateRange()
                ui:UpdateSight()
                ui:UpdateRole()
                ui:UpdateIncomingHealing()
            end
        end
    else
        for ui in UnitFrames("target") do
            ui.lastHealthPercent = (ui:GetCurrentHealth() / ui:GetMaxHealth()) * 100
            ui:UpdateAll()
            ui:UpdateRole()
            ui:UpdateIncomingHealing()
        end
    end
    UnitFrameGroups["Target"]:EvaluateShown()
end

function IsRelevantUnit(unit)
    return AllUnitsSet[unit] ~= nil
end

function Info(msg)
    DEFAULT_CHAT_FRAME:AddMessage(colorize("[Puppeteer] ", 0.5, 1, 0.5)..colorize(msg, 1, 1, 0.4))
end

function print(msg)
    if not PTOptions or not PTOptions["Debug"] then
        return
    end
    local window
    local i = 1
    while not window do
        local name = GetChatWindowInfo(i)
        if not name then
            break
        end
        if name == "Debug" then
            window = getglobal("ChatFrame"..i)
            break
        end
        i = i + 1
    end
    if window then
        window:AddMessage(tostring(msg))
    end
end

function StartTiming(name)
    if not pfDebug_StartTiming then
        return
    end
    pfDebug_StartTiming(name)
end

function EndTiming(name)
    if not pfDebug_EndTiming then
        return
    end
    pfDebug_EndTiming(name)
end

function PrintStack()
    print(debugstack(2))
end