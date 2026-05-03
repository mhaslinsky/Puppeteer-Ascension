-- This can either be used as a normal dropdown or a context menu. If the parent is UIParent, it will be a context menu.
-- Otherwise, it is a dropdown. This can be changed during runtime simply by calling SetParent through the GUI component.
-- The positioning of the dropdown's components are modified to behave like you'd expect. SetWidth actually sets the width.
-- SetHeight does nothing, and will always be 25 px.

-- Initialization is handled by this component. Use SetOptions to set the options table.
-- === New Fields ===
-- initFunc(self, gui) - Runs on level initialization before the button is added
-- dropdownText - The text the dropdown will be set to when this option is clicked, runs before "func"
-- closeOnClick - If true, closes all menus regardless of level, runs after "func"
-- children - Array for a next level menu; If present, "hasArrow" is automatically set to true
-- parent [Automatically Assigned] - Reference to the previous level element, or nil if root
-- siblings [Automatically Assigned] - Reference to the array of elements in the level
-- gui [Automatically Assigned] - Reference to the GUI instance
-- === Adjusted Existing Fields ===
-- func(self, gui) - Always passes self as the first argument and the GUI instance as the second argument
-- arg1, arg2 - Do not use, now internally used to pass self and gui to "func"
-- value - Do not use, now internally used to reference self

PTGuiDropdown = PTGuiComponent:Extend("dropdown")
local _G = getfenv(0)

PTGuiDropdown.Options = nil

function PTGuiDropdown:New()
    local obj = setmetatable({}, self)
    local dropdown = CreateFrame("Frame", self:GenerateName(), nil, "UIDropDownMenuTemplate")
    obj:SetHandle(dropdown)
    -- Make SetWidth actually set the width, like one would hope
    local dropdownSetWidth = dropdown.SetWidth
    dropdownSetWidth(dropdown, 0) -- Allows points to size the dropdown
    dropdown.SetWidth = function(self, width)
        _G[dropdown:GetName().."Middle"]:SetWidth(width - 15)
        dropdownSetWidth(self, width)
        _G[dropdown:GetName().."Text"]:SetWidth(width - 25)
        dropdown.noResize = 1
    end
    -- The dropdown doesn't stretch vertically, so the height is always 25
    local dropdownSetHeight = dropdown.SetHeight
    dropdown.SetHeight = function(self, height)
        dropdownSetHeight(self, 25)
    end
    obj:SetShowShadow(true) -- Need to do this on creation to fix the visual position
    -- Make clicking anywhere on the dropdown open the menu.
    -- Phase 4: was relaying through the chevron button's OnClick via CallWithThis,
    -- but on 3.3.5a that path is unreliable (the Blizzard chevron's OnClick body
    -- expects to be invoked from a real Button click, and Ascension's
    -- UIDropDownMenuTemplate may bind extra logic we can't reliably re-fire).
    -- ToggleDropDownMenu directly is the modern-WoW idiom and works on the dropdown
    -- frame regardless of which sub-region was clicked.
    dropdown:EnableMouse(true)
    dropdown:SetScript("OnMouseUp", function()
        local frame = this
        if frame and MouseIsOver(frame) then
            ToggleDropDownMenu(1, nil, frame)
        end
    end)
    dropdown:SetScript("OnSizeChanged", function()
        local width = this:GetWidth()
        _G[this:GetName().."Middle"]:SetWidth(width - 15)
        dropdownSetWidth(this, width)
        _G[this:GetName().."Text"]:SetWidth(width - 25)
    end)
    return obj
end

local partProps = {
    Default = {
        Left = {
            Width = 25, Height = 64,
            Coords = {0, 0.1953125, 0, 1},
            Point = {"TOPLEFT", "$parent", "TOPLEFT", -18, 18}
        },
        Middle = {
            Width = 115, Height = 64,
            Coords = {0.1953125, 0.8046875, 0, 1},
            Point = {"LEFT", "$parentLeft", "RIGHT"}
        },
        Right = {
            Width = 25, Height = 64,
            Coords = {0.8046875, 1, 0, 1},
            Point = {"LEFT", "$parentMiddle", "RIGHT"}
        },
        Text = {
            Point = {"RIGHT", "$parentRight", -43, 2}
        },
        Button = {
            Point = {"TOPRIGHT", "$parentRight", -16, -18}
        }
    },
    Shadowless = {
        Left = {
            Width = 6, Height = 24,
            Coords = {18 / 128, (18 + 6) / 128, 19 / 64, (19 + 24) / 64},
            Point = {"TOPLEFT", 0, -1}
        },
        Middle = {
            Width = 115, Height = 24,
            Coords = {0.1953125, 0.8046875, 19 / 64, (19 + 24) / 64},
            Point = {"LEFT", "$parentLeft", "RIGHT", 0, 0}
        },
        Right = {
            Width = 9, Height = 24,
            Coords = {102 / 128, (102 + 9) / 128, 19 / 64, (19 + 24) / 64},
            Point = {"LEFT", "$parentMiddle", "RIGHT", 0, 0}
        },
        Text = {
            Point = {"RIGHT", "$parentRight", -26, 1}
        },
        Button = {
            Point = {"TOPRIGHT", "$parentRight", 1, 1}
        }
    }
}
function PTGuiDropdown:SetShowShadow(showShadow)
    local frameName = self:GetHandle():GetName()
    for partName, props in pairs(showShadow and partProps.Default or partProps.Shadowless) do
        local part = _G[frameName..partName]
        if props.Coords then
            part:SetTexCoord(unpack(props.Coords))
        end
        if props.Width then
            part:SetWidth(props.Width)
            part:SetHeight(props.Height)
        end
        part:ClearAllPoints()
        part:SetPoint(unpack(props.Point))
    end
    self:SetWidth(self:GetWidth())
    UIDropDownMenu_SetAnchor(self:GetHandle(), showShadow and 18 or 0, showShadow and 17 or 0, "TOPLEFT",
        _G[frameName.."Left"], "BOTTOMLEFT")
    return self
end

local defaultTextures = {
    ButtonNormalTexture = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
    ButtonDisabledTexture = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled",
    ButtonPushedTexture = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down",
    ButtonHighlightTexture = "Interface\\Buttons\\UI-Common-MouseHilight"
}
function PTGuiDropdown:SetParent(obj)
    local menuType = obj == UIParent and "MENU" or nil
    if menuType ~= "MENU" and self:GetHandle().displayMode == "MENU" then
        -- Show the dropdown if we're switching from a context menu to a dropdown
        -- BROKEN: When put back as a context menu, the button shows forever???
        local frameName = self:GetHandle():GetName()
        _G[frameName.."Left"]:Show()
		_G[frameName.."Middle"]:Show()
		_G[frameName.."Right"]:Show()
        for texName, texPath in pairs(defaultTextures) do
            _G[frameName..texName]:SetTexture(texPath)
        end
        self:SetShowShadow(true)
        self:GetHandle().displayMode = nil
    end
    UIDropDownMenu_Initialize(self:GetHandle(), function(level)
        self:Initialize(level)
    end, menuType)
    self.super.SetParent(self, obj)
end

function PTGuiDropdown:OnDispose()
    self:SetToggleState(false)
    self:SetShowShadow(true)
    self.super.OnDispose(self)

    self.Options = nil
    if self.DynamicOptions then
        self.DynamicOptionsArgs = nil
    end
    self.TextUpdater = nil
    self:SetText("")
end

local dynamicOptions
local function addDynamicOption(...)
    local option = {}
    local n = select("#", ...)
    for i = 1, n, 2 do
        local k, v = select(i, ...)
        if k ~= nil then
            option[k] = v
        end
    end
    table.insert(dynamicOptions, option)
end

function PTGuiDropdown:Initialize(level)
    if not self.Options then
        return
    end
    level = level or 1
    local options = self.Options
    if type(options) == "function" then
        if self.DynamicOptions then
        end
        self.DynamicOptions = {}
        dynamicOptions = self.DynamicOptions
        options(addDynamicOption, level, self.DynamicOptionsArgs)
        options = dynamicOptions
        self:BakeOptions(options)
    end
    local value = UIDROPDOWNMENU_MENU_VALUE
    if level ~= 1 then
        if not (value and value.children) then return end
        options = value.children
    end
    for _, option in ipairs(options) do
        if option.initFunc then
            option:initFunc(self)
        end
        UIDropDownMenu_AddButton(option, level)
    end
end

-- Similar to normal dropdown initialization. Really only should be used for single level options.
-- The initFunc receives a function to add options, use in the style of Compost:AcquireHash
-- args are passed into the initFunc
function PTGuiDropdown:SetDynamicOptions(initFunc, args)
    self.Options = initFunc
    self.DynamicOptionsArgs = args
    return self
end

function PTGuiDropdown:SetSimpleOptions(options, createFunc, dropdownText)
    local optTable = {}
    for _, option in ipairs(options) do
        table.insert(optTable, createFunc(option))
    end
    self:SetOptions(optTable)
    if dropdownText then
        self:SetText(dropdownText)
    end
    return self
end

-- Sets the options for this dropdown. If elements are added afterwards, it is mandatory that this function is called again.
function PTGuiDropdown:SetOptions(options)
    self.Options = options
    self:BakeOptions(options)
    return self
end

function PTGuiDropdown:BakeOptions(options, parent)
    for _, opt in ipairs(options) do
        opt.parent = parent
        opt.siblings = options
        opt.value = opt
        opt.arg1 = opt
        opt.arg2 = self
        opt.gui = self
        if opt.dropdownText or opt.closeOnClick then
            local func = opt.func
            opt.func = function(self, gui)
                if self.dropdownText then
                    gui:SetText(self.dropdownText)
                end
                if func then
                    func(self, gui)
                end
                if self.closeOnClick then
                    gui:SetToggleState(false)
                end
            end
        end
        if opt.children then
            opt.hasArrow = true
            self:BakeOptions(opt.children, opt)
        end
    end
end

function PTGuiDropdown:SetTextBy(field, value, textField)
    for _, option in ipairs(self.Options) do
        if option[field] == value then
            self:SetText(option[textField or "text"])
            return self
        end
    end
    return self
end

function PTGuiDropdown:SetTextUpdater(updater, noImmediateUpdate)
    self.TextUpdater = updater
    if not noImmediateUpdate then
        self:TextUpdater()
    end
    return self
end

function PTGuiDropdown:UpdateText()
    if self.TextUpdater then
        self:TextUpdater()
    end
    return self
end

function PTGuiDropdown:SetText(text)
    UIDropDownMenu_SetText(self:GetHandle(), text)
    return self
end

function PTGuiDropdown:GetText()
    return UIDropDownMenu_GetText(self:GetHandle())
end

local dropdownList1 = _G["DropDownList1"]
function PTGuiDropdown:SetTimer(time)
    dropdownList1.showTimer = time
end

function PTGuiDropdown:StopCounting()
    dropdownList1.isCounting = nil
end

local keepOpenFrame = CreateFrame("Frame", "PTGuiDropdownKeepOpen")
local keepOpenDropdown
local checkNext
local keepOpenScript = function()
    if GetTime() > checkNext then
        if not keepOpenDropdown:IsToggledOn() then
            keepOpenFrame:SetScript("OnUpdate", nil)
            return
        end
        checkNext = GetTime() + 1
        dropdownList1.showTimer = 10
        dropdownList1.isCounting = nil
    end
end
-- Keeps the dropdown open until it is forcibly hidden
function PTGuiDropdown:SetKeepOpen(keepOpen)
    if not self:IsToggledOn() then
        return self
    end
    if keepOpen then
        checkNext = 0
        keepOpenDropdown = self
        keepOpenFrame:SetScript("OnUpdate", keepOpenScript)
    else
        keepOpenFrame:SetScript("OnUpdate", nil)
    end
    return self
end

function PTGuiDropdown:IsToggledOn()
    return (dropdownList1:IsVisible() ~= nil) and (UIDROPDOWNMENU_OPEN_MENU == self:GetName())
end

function PTGuiDropdown:SetToggleState(shown, anchor, xOffset, yOffset)
    if self:IsToggledOn() ~= shown then
        ToggleDropDownMenu(1, nil, self:GetHandle(), anchor and anchor:GetName() or nil, xOffset, yOffset)
    end
    return self
end

PTGuiLib.RegisterComponent(PTGuiDropdown)