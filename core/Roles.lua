PTUtil.SetEnvironment(Puppeteer)
local _G = getfenv(0)
local util = PTUtil
local colorize = util.Colorize
local GetColoredRoleText = util.GetColoredRoleText

AssignedRoles = nil

function GetAssignedRole(name)
    if not AssignedRoles or not AssignedRoles[name] then
        return
    end
    AssignedRoles[name]["lastSeen"] = time()
    return AssignedRoles[name]["role"]
end

function GetUnitAssignedRole(unit)
    if not UnitIsPlayer(unit) then
        return
    end
    return GetAssignedRole(UnitName(unit))
end

function SetAssignedRole(name, role)
    if role == nil or role == "No Role" then
        AssignedRoles[name] = nil
        return
    end
    AssignedRoles[name] = {
        ["role"] = role,
        ["lastSeen"] = time()
    }
end

-- Returns true if role assignment failed
function SetUnitAssignedRole(unit, role)
    if not UnitIsPlayer(unit) then
        return true
    end
    SetAssignedRole(UnitName(unit), role)
end

function PruneAssignedRoles()
    local currentTime = time()
    for name, data in pairs(AssignedRoles) do
        if not data["lastSeen"] or data["lastSeen"] < currentTime - (24 * 60 * 60) then
            AssignedRoles[name] = nil
            --print("Pruned "..name.."'s role")
        end
    end
end

function SetRoleAndUpdate(name, role)
    SetAssignedRole(name, role)
    UpdateUnitFrameGroups()
end

function SetUnitRoleAndUpdate(unit, role)
    if not SetUnitAssignedRole(unit, role) then
        UpdateUnitFrameGroups()
    end
end

RoleAssignInfo = {}

RoleDropdown = PTGuiLib.Get("dropdown", UIParent)

function InitRoleDropdown()
    local initFunc = function(self)
        self.checked = (GetAssignedRole(RoleAssignInfo.Name) or "No Role") == self.role
    end

    local genRole = function(role)
        return {
            text = GetColoredRoleText(role),
            role = role,
            initFunc = initFunc,
            func = function(info)
                SetAssignedRole(RoleAssignInfo.Name, info.role)
                UpdateUnitFrameGroups()
            end
        }
    end
    local massRoleFunc = function(info)
        if not RoleAssignInfo.FrameGroup then
            return
        end
        for _, ui in pairs(RoleAssignInfo.FrameGroup.uis) do
            if (not ui:GetRole() or not info.role) and UnitIsPlayer(ui:GetUnit()) then
                SetAssignedRole(UnitName(ui:GetUnit()), info.role)
            end
        end
        UpdateUnitFrameGroups()
        RoleDropdown:SetToggleState(false)
    end
    local genMassRole = function(role)
        return {
            text = GetColoredRoleText(role),
            role = role,
            notCheckable = true,
            func = massRoleFunc
        }
    end

    local options = {
        {
            initFunc = function(self)
                self.text = colorize(RoleAssignInfo.Name.."'s Role", RoleAssignInfo.ClassColor)
            end,
            notCheckable = true,
            disabled = true,
            textHeight = 12
        }, 
        genRole("Tank"),
        genRole("Healer"),
        genRole("Damage"),
        genRole("No Role"),
        {
            notCheckable = true,
            disabled = true
        }, {
            text = "Set Unassigned As",
            tooltipTitle = "Set Unassigned As",
            tooltipText = "Mass-set the roles of unassigned players. Only applies to players contained in this UI group.",
            notCheckable = true,
            textHeight = 11,
            children = {
                genMassRole("Tank"),
                genMassRole("Healer"),
                genMassRole("Damage")
            }
        }, {
            text = "Clear Roles",
            tooltipTitle = "Clear Roles",
            tooltipText = "Clear all players' roles. Only applies to players contained in this UI group.",
            notCheckable = true,
            textHeight = 11,
            func = massRoleFunc
        }
    }
    RoleDropdown:SetOptions(options)
end