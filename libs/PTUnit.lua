-- Caches important information about units and makes the data easily readable at any time.
--
-- The cache is keyed by unit-id ("party1", "raid3", "target", etc.) — not by GUID.
-- WotLK-native APIs like UnitHealth/UnitAura require a unit-token, not a GUID, so
-- callers always have a token in hand by the time they reach PTUnit.Get. CLEU-driven
-- code paths that only have a GUID translate via PTGuidRoster.GetUnits(guid) before
-- looking up.

PTUnit = {}
PTUtil.SetEnvironment(PTUnit)
local _G = getfenv(0)

local util = PTUtil
local AllUnits = util.AllUnits
local AllRealUnits = util.AllRealUnits
local AllUnitsSet = util.AllUnitsSet
local canGetAuraIDs = util.CanClientGetAuraIDs()


-- Non-instance variable
-- Key: unit-id ("party1", "target", etc.) | Value: PTUnit instance
PTUnit.Cached = {}

PTUnit.Unit = nil

PTUnit.AurasPopulated = false
-- Buff/debuff entry contents: {"name", "stacks", "texture", "index", "type", "id"}
-- 3.3.5a's UnitAura returns spellID natively as the 11th return value.
PTUnit.Buffs = {} -- Array of all buffs
PTUnit.BuffsMap = {} -- Key: Name | Value: Array of buffs with key's name
PTUnit.BuffsIDSet = {} -- Set of currently applied buff IDs
PTUnit.Debuffs = {} -- Array of all debuffs
PTUnit.DebuffsMap = {} -- Key: Name | Value: Array of debuffs with key's name
PTUnit.DebuffsIDSet = {} -- Set of currently applied debuff IDs
PTUnit.TypedDebuffs = {} -- Key: Type | Value: Array of debuffs that are the type
PTUnit.AfflictedDebuffTypes = {} -- Set of the afflicted debuff types
PTUnit.TrackedDebuffTypes = {} -- Set of debuff types that exclude frivilous debuffs

PTUnit.HasHealingModifier = false
PTUnit.HasImportantDebuff = false

PTUnit.DisplayPVP = false -- This is not the real PVP status of the unit, this is affected by other conditions

PTUnit.Distance = 0
PTUnit.InSight = true
PTUnit.IsNew = false

function CreateCaches()
    for _, unit in ipairs(AllUnits) do
        PTUnit:New(unit)
    end
end

function UpdateAllUnits()
    for _, cache in pairs(PTUnit.Cached) do
        cache:UpdateAll()
    end
end

function Get(unit)
    return PTUnit.Cached[unit] or PTUnit
end

function GetAllUnits()
    return PTUnit.Cached
end

function PTUnit:New(unit)
    local obj = {Unit = unit}
    setmetatable(obj, self)
    self.__index = self
    PTUnit.Cached[unit] = obj
    obj:AllocateAuras()
    obj.AurasPopulated = true -- To force aura fields to generate
    obj.IsNew = true
    obj.IsSelf = UnitIsUnit(unit, "player")
    obj:UpdateAll()
    return obj
end

function PTUnit:Dispose()
    -- AuraTimes table was a SuperWoW-only feature; nothing to reclaim on 3.3.5a.
end

function PTUnit:UpdateAll()
    self:UpdateAuras()
    self:UpdatePVP()
    self:UpdateDistance()
    self:UpdateSight()
end

-- Returns true if this unit is new, clearing its new status.
function PTUnit:CheckNew()
    if self.IsNew then
        self.IsNew = false
        return true
    end
end

function PTUnit:UpdatePVP()
    if not self.Unit then
        return
    end
    local shouldDisplay = UnitIsPVP(self.Unit) and (not util.IsReallyInInstance() or not UnitIsVisible(self.Unit))
    if self.DisplayPVP ~= (shouldDisplay == 1 or shouldDisplay == true) then
        self.DisplayPVP = shouldDisplay
        return true
    end
    return false
end

function PTUnit:ShouldDisplayPVP()
    return self.DisplayPVP
end

-- Returns true if the distance changed
function PTUnit:UpdateDistance()
    if not self.Unit then
        return
    end
    local prevDist = self.Distance
    self.Distance = self.IsSelf and 0 or util.GetDistanceTo(self.Unit)

    return self.Distance ~= prevDist
end

function PTUnit:GetDistance()
    return self.Distance
end

-- Returns true if the sight state has changed
function PTUnit:UpdateSight()
    if not self.Unit then
        return
    end
    local wasInSight = self.InSight
    self.InSight = self.IsSelf or util.IsInSight(self.Unit)

    return self.InSight ~= wasInSight
end

function PTUnit:IsInSight()
    return self.InSight
end

function PTUnit:IsBeingResurrected()
    if not self.Unit then
        return false
    end
    if PTHealPredict then
        return PTHealPredict.IsBeingResurrected(self.Unit)
    end
    -- Phase 2b: HealComm-1.0 stubbed; LibHealComm-4.0 wires up in Phase 3.
    return false
end

function PTUnit:GetResurrectionCasts()
    if not self.Unit then
        return 0
    end
    if PTHealPredict then
        return PTHealPredict.GetResurrectionCount(self.Unit)
    end
    -- Phase 2b: HealComm-1.0 stubbed; LibHealComm-4.0 wires up in Phase 3.
    return 0
end

function PTUnit:AllocateAuras()
    self.Buffs = {}
    self.BuffsMap = {}
    self.BuffsIDSet = {}
    self.Debuffs = {}
    self.DebuffsMap = {}
    self.DebuffsIDSet = {}
    self.TypedDebuffs = {}
    self.AfflictedDebuffTypes = {}
    self.TrackedDebuffTypes = {}
end

function PTUnit:ClearAuras()
    if not self.AurasPopulated or self == PTUnit then
        return
    end
    util.ClearTable(self.BuffsIDSet)
    util.ClearTable(self.DebuffsIDSet)
    util.ClearTable(self.AfflictedDebuffTypes)
    util.ClearTable(self.TrackedDebuffTypes)
    self.Buffs = {}
    self.BuffsMap = {}
    self.Debuffs = {}
    self.DebuffsMap = {}
    self.TypedDebuffs = {}
    self.HasHealingModifier = false
    self.AurasPopulated = false
    self.HasImportantDebuff = false
end

function PTUnit:UpdateAuras()
    local unit = self.Unit

    if not unit then
        return
    end

    Puppeteer.StartTiming("PTUnitAuraUpdate")

    self:ClearAuras()

    if not UnitExists(unit) then
        Puppeteer.EndTiming("PTUnitAuraUpdate")
        return
    end

    local buffs = self.Buffs
    local buffsMap = self.BuffsMap
    local buffsIDSet = self.BuffsIDSet
    for index = 1, 40 do
        local name, _, texture, stacks, _, duration, expirationTime, unitCaster, _, _, id = UnitAura(unit, index, "HELPFUL")
        if not name then
            break
        end
        if PuppeteerSettings.TrackedHealingBuffs[name] then
            self.HasHealingModifier = true
        end
        local auraTime
        if duration and duration > 0 then
            auraTime = {
                startTime = expirationTime - duration,
                endTime = expirationTime,
                duration = duration,
                owner = unitCaster,
                ownerName = unitCaster and UnitName(unitCaster) or nil,
                nampower = false
            }
        end
        local buff = {name = name, index = index, texture = texture, stacks = stacks, type = "", id = id, time = auraTime}
        if not buffsMap[name] then
            buffsMap[name] = {}
        end
        if id ~= nil then
            buffsIDSet[id] = true
        end
        table.insert(buffsMap[name], buff)
        table.insert(buffs, buff)
    end

    local afflictedDebuffTypes = self.AfflictedDebuffTypes
    local trackedDebuffTypes = self.TrackedDebuffTypes
    local debuffs = self.Debuffs
    local debuffsMap = self.DebuffsMap
    local debuffsIDSet = self.DebuffsIDSet
    local typedDebuffs = self.TypedDebuffs -- Dispellable debuffs
    for index = 1, 40 do
        local name, _, texture, stacks, debuffType, duration, expirationTime, unitCaster, _, _, id = UnitAura(unit, index, "HARMFUL")
        if not name then
            break
        end
        local type = debuffType or ""
        if PuppeteerSettings.TrackedHealingDebuffs[name] then
            self.HasHealingModifier = true
        end
        if PuppeteerSettings.ImportantDebuffs[name] then
            self.HasImportantDebuff = true
        end
        local auraTime
        if duration and duration > 0 then
            auraTime = {
                startTime = expirationTime - duration,
                endTime = expirationTime,
                duration = duration,
                owner = unitCaster,
                ownerName = unitCaster and UnitName(unitCaster) or nil,
                nampower = false
            }
        end
        local debuff = {name = name, index = index, texture = texture, stacks = stacks, type = type, id = id, time = auraTime}
        if not debuffsMap[name] then
            debuffsMap[name] = {}
        end
        if id ~= nil then
            debuffsIDSet[id] = true
        end
        table.insert(debuffsMap[name], debuff)
        if type ~= "" then
            afflictedDebuffTypes[type] = 1
            if not PuppeteerSettings.IgnoredDispellableDebuffs[name] then
                trackedDebuffTypes[type] = 1
            end
            if not typedDebuffs[type] then
                typedDebuffs[type] = {}
            end
            table.insert(typedDebuffs[type], debuff)
        end
        table.insert(debuffs, debuff)
    end
    self.AurasPopulated = true
    Puppeteer.EndTiming("PTUnitAuraUpdate")
end

function PTUnit:HasBuff(name)
    return self.BuffsMap[name] ~= nil
end

-- SuperWoW/Turtle WoW only
function PTUnit:HasBuffID(id)
    return self.BuffsIDSet[id] ~= nil
end

-- Looks for ID if SuperWoW/Turtle WoW is present, otherwise searches by name
function PTUnit:HasBuffIDOrName(id, name)
    if canGetAuraIDs then
        return self:HasBuffID(id)
    end
    return self:HasBuff(name)
end

function PTUnit:HasDebuff(name)
    return self.DebuffsMap[name] ~= nil
end

-- SuperWoW/Turtle WoW only
function PTUnit:HasDebuffID(id)
    return self.DebuffsIDSet[id] ~= nil
end

-- Looks for ID if SuperWoW/Turtle WoW is present, otherwise searches by name
function PTUnit:HasDebuffIDOrName(id, name)
    if canGetAuraIDs then
        return self:HasDebuffID(id)
    end
    return self:HasDebuff(name)
end

function PTUnit:HasDebuffType(type)
    return self.AfflictedDebuffTypes[type]
end

function PTUnit:HasTrackedDebuffType(type)
    return self.TrackedDebuffTypes[type]
end

-- Returns the first buff with the provided name
function PTUnit:GetBuff(name)
    if not self:HasBuff(name) then
        return
    end
    return self.BuffsMap[name][1]
end

-- Returns the table of all buffs with the provided name
function PTUnit:GetBuffs(name)
    return self.BuffsMap[name]
end

function PTUnit:GetDebuff(name)
    if not self:HasDebuff(name) then
        return
    end
    return self.DebuffsMap[name][1]
end

function PTUnit:GetDebuffs(name)
    return self.DebuffsMap[name]
end

-- Phase 4: ApplyTimedAura removed with AuraTracker.lua retirement; UnitAura on 3.3.5a
-- returns native duration/expirationTime, so the SuperWoW-side aura-timer cache is gone.

-- Stub kept for binding-script API compatibility (BindingScriptEditor advertises
-- unitData:GetAuraTimeRemaining(auraName)). Returns nil on 3.3.5a; consider rewiring
-- to UnitAura's expirationTime if the binding-script docs grow this back.
function PTUnit:GetAuraTimeRemaining(name)
    return nil
end