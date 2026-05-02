PTGuiUtil = {}
PTUtil.SetEnvironment(PTGuiUtil)
local _G = getfenv(0)
local util = PTUtil
local colorize = util.Colorize

function CreateColorUpdater(checkboxGetter, colorSelectGetter, colorGetter)
    return function(self)
        local color = colorGetter(self)
        if color then
            checkboxGetter(self):SetChecked(true)
            colorSelectGetter(self):Show()
            colorSelectGetter(self):SetColor(color)
        else
            checkboxGetter(self):SetChecked(false)
            colorSelectGetter(self):Hide()
        end
    end
end