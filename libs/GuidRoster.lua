-- A utility to map GUIDs to unit tokens.
--
-- SuperWoW's "custom units" (focus2..N) live in PTUnitProxy and remain
-- SuperWoW-only; GuidRoster does NOT track them — ResolveUnitGuid falls back
-- to PTUnitProxy when present.
--
-- This file owns no event registrations: callers drive
-- ResetRoster/PopulateRoster/SetUnitGuid (CheckGroup on group changes,
-- the PLAYER_TARGET_CHANGED handler).

PTGuidRoster = {}
PTUtil.SetEnvironment(PTGuidRoster)
local _G = getfenv(0)


local util = PTUtil

GuidUnitMap = {}
GuidFrameMap = {}

function ResetRoster()
    local roster = GuidUnitMap
    for k in pairs(roster) do
        roster[k] = nil
    end
end

function PopulateRoster()
    for _, unit in ipairs(util.AllRealUnits) do
        local guid = UnitGUID(unit)
        if guid then
            AddUnit(guid, unit)
        end
    end
    if PTUnitProxy and PTUnitProxy.GUIDCustomUnitMap then
        for guid, units in pairs(PTUnitProxy.GUIDCustomUnitMap) do
            for _, unit in ipairs(units) do
                AddUnit(guid, unit)
            end
        end
    end
end

function AddUnit(guid, unit)
    if not GuidUnitMap[guid] then
        GuidUnitMap[guid] = {}
    end
    table.insert(GuidUnitMap[guid], unit)
end

function SetUnitGuid(unit, guid)
    for guidInMap, units in pairs(GuidUnitMap) do
        if util.ArrayContains(units, unit) then
            util.RemoveElement(units, unit)
            if table.getn(units) == 0 then
                GuidUnitMap[guidInMap] = nil
            end
            break
        end
    end

    if not guid then
        return
    end

    if not GuidUnitMap[guid] then
        GuidUnitMap[guid] = {}
    end
    table.insert(GuidUnitMap[guid], unit)
end

function GetUnitGuid(unit)
    if not unit or unit == "" then return nil end
    return UnitGUID(unit)
end

-- Resolves the GUID of a unit token, custom unit, or returns the input if it
-- already looks like a GUID (SuperWoW-era callers pass GUIDs as units).
function ResolveUnitGuid(unit)
    local guid = UnitGUID(unit)
        or (PTUnitProxy and PTUnitProxy.CustomUnitGUIDMap and PTUnitProxy.CustomUnitGUIDMap[unit])
        or unit
    if guid ~= "target" then
        return guid
    end
end

function GetUnits(guid)
    return GuidUnitMap[guid]
end

function HasUnits(guid)
    return GuidUnitMap[guid] ~= nil
end

function GetAllUnits(unit)
    return GetUnits(UnitGUID(unit))
end

function GetTrackedGuids()
    return util.ToArray(GuidUnitMap)
end
