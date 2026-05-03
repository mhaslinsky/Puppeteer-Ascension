-- Phase 5 / Slice 1: secure click-cast + secure keybind dispatch (Wrath 3.3.5a).
--
-- Architecture (read .research/BINDINGS-AND-CLICK-CAST.md before editing):
--   1. Per-frame overlay: every Puppeteer unit frame gets a SecureActionButtonTemplate
--      child that overlays the body. Carries unit="<frame's unit>" and per-modifier
--      type/spell attributes. Direct clicks dispatch through WoW's secure code, no
--      taint, works in combat. The unit attribute also makes WoW set its `mouseover`
--      token when the cursor enters this button -- which is what the keybind path needs.
--   2. Hidden keybind buttons: one or more SecureActionButtonTemplate buttons carry
--      static [@mouseover] macrotext per modifier slot. SetBindingClick(key, btn, click)
--      routes a key press to a virtual click on the button, OOC-only. The macro's
--      [@mouseover] resolves at click-time against whatever frame the cursor is over.
--      No per-hover attribute writes; combat-safe by construction.
--
-- Slice 1 scope: SPELL bindings only. Other binding types (ACTION/MACRO/SCRIPT/MULTI)
-- fall through to the existing insecure path -- protected ones won't work in combat,
-- which is the same limitation as before slice 1.

PTUtil.SetEnvironment(Puppeteer)
local _G = getfenv(0)
local util = PTUtil

SecureClickCast = {}

-- Modifier name (PTBindings format) -> WoW secure attribute prefix.
-- Wrath requires strict order: alt-, ctrl-, shift-.
local MODIFIER_PREFIXES = {
    ["None"] = "",
    ["Shift"] = "shift-",
    ["Control"] = "ctrl-",
    ["Alt"] = "alt-",
    ["Shift+Control"] = "ctrl-shift-",
    ["Shift+Alt"] = "alt-shift-",
    ["Control+Alt"] = "alt-ctrl-",
    ["Shift+Control+Alt"] = "alt-ctrl-shift-",
}
local ALL_MODIFIERS = {"None", "Shift", "Control", "Alt",
    "Shift+Control", "Shift+Alt", "Control+Alt", "Shift+Control+Alt"}

local MOUSE_BUTTON_TO_VARIANT = {
    ["LeftButton"] = 1, ["RightButton"] = 2, ["MiddleButton"] = 3,
    ["Button4"] = 4, ["Button5"] = 5,
}
local VARIANT_TO_VIRTUAL = {
    [1] = "LeftButton", [2] = "RightButton", [3] = "MiddleButton",
    [4] = "Button4", [5] = "Button5",
}
local MAX_VARIANTS_PER_BUTTON = 5

local keybindButtons = {}    -- ordered list of secure keybind buttons
local keyToSlot = {}         -- key name -> {button=<frame>, variant=1..5}
local overlaysByFrame = {}   -- unitFrame -> overlay button
local pendingRefreshOnRegen = false
local initialized = false


-- ---------- Feature flag ----------

function SecureClickCast.IsEnabled()
    if not PTGlobalOptions then return true end
    if PTGlobalOptions.UseSecureClickCast == nil then return true end
    return PTGlobalOptions.UseSecureClickCast
end


-- ---------- Macrotext synthesis ----------

local function bindingSpellName(binding)
    if not binding or binding.Type ~= "SPELL" then return nil end
    local data = binding.Data
    if not data or data == "" then return nil end
    return data
end

-- Synthesize a single-line [@mouseover,help/harm] macrotext for one (key, modifier)
-- slot. Returns nil if neither friendly nor hostile is a SPELL binding.
-- Honors UseFriendlyForHostile (mirrors GetBinding's behavior).
local function buildMacrotextForSlot(modifierName, buttonName)
    local friendly = GetBinding("Friendly", modifierName, buttonName)
    local hostile = GetBinding("Hostile", modifierName, buttonName)

    local friendlySpell = bindingSpellName(friendly)
    local hostileSpell = bindingSpellName(hostile)

    if not friendlySpell and not hostileSpell then
        return nil
    end
    if friendlySpell and hostileSpell and friendlySpell == hostileSpell then
        return "/cast [@mouseover,nodead] " .. friendlySpell
    end

    local parts = {}
    if friendlySpell then
        table.insert(parts, "[@mouseover,help,nodead] " .. friendlySpell)
    end
    if hostileSpell then
        table.insert(parts, "[@mouseover,harm,nodead] " .. hostileSpell)
    end
    return "/cast " .. table.concat(parts, "; ")
end


-- ---------- Per-frame overlay ----------

-- Forward an event from the secure overlay to the original button's script so the
-- existing tooltip / mouseover-state / .pressed bookkeeping keeps working.
local function forwardScript(overlay, original, scriptName)
    overlay:SetScript(scriptName, function()
        local fn = original:GetScript(scriptName)
        if fn then fn() end
    end)
end

local function refreshPerFrameAttrs(overlay, unit)
    if InCombatLockdown() then
        pendingRefreshOnRegen = true
        return
    end

    overlay:SetAttribute("unit", unit)

    -- Wipe stale attrs across all 8 modifiers x 5 variants.
    for _, modName in ipairs(ALL_MODIFIERS) do
        local prefix = MODIFIER_PREFIXES[modName]
        for variant = 1, MAX_VARIANTS_PER_BUTTON do
            overlay:SetAttribute(prefix .. "type" .. variant, nil)
            overlay:SetAttribute(prefix .. "spell" .. variant, nil)
        end
    end

    -- Write SPELL bindings for each (modifier, mouseButton) combo.
    -- Frame buttons own their unit so we use type=spell directly (no [@mouseover]).
    -- The hostile/friendly choice is hard-coded to the frame's unit's faction here:
    -- if the frame represents a friendly unit, only the Friendly bindings apply
    -- (and vice versa). Mirrors how UnitFrame_OnClick already routes.
    local isHostile = UnitCanAttack("player", unit)
    local side = isHostile and "Hostile" or "Friendly"

    for _, modName in ipairs(ALL_MODIFIERS) do
        local prefix = MODIFIER_PREFIXES[modName]
        for buttonName, variant in pairs(MOUSE_BUTTON_TO_VARIANT) do
            local binding = GetBinding(side, modName, buttonName)
            local spell = bindingSpellName(binding)
            if spell then
                overlay:SetAttribute(prefix .. "type" .. variant, "spell")
                overlay:SetAttribute(prefix .. "spell" .. variant, spell)
            end
        end
    end
end

function SecureClickCast.AttachOverlay(unitFrame)
    if not SecureClickCast.IsEnabled() then return end
    if overlaysByFrame[unitFrame] then return end

    local existing = unitFrame.button
    if not existing then return end

    local overlay = CreateFrame("Button", nil, existing, "SecureActionButtonTemplate")
    overlay:SetAllPoints(existing)
    overlay:SetFrameLevel(existing:GetFrameLevel() + 1)
    overlay:RegisterForClicks("AnyDown", "AnyUp")
    overlay:EnableMouse(true)

    forwardScript(overlay, existing, "OnEnter")
    forwardScript(overlay, existing, "OnLeave")
    forwardScript(overlay, existing, "OnMouseDown")
    forwardScript(overlay, existing, "OnMouseUp")

    overlaysByFrame[unitFrame] = overlay

    refreshPerFrameAttrs(overlay, unitFrame:GetUnit())
end

function SecureClickCast.RefreshOverlay(unitFrame)
    local overlay = overlaysByFrame[unitFrame]
    if not overlay then return end
    refreshPerFrameAttrs(overlay, unitFrame:GetUnit())
end


-- ---------- Hidden keybind buttons ----------

local function newKeybindButton(index)
    local btn = CreateFrame("Button", "PuppeteerKeybindButton" .. index, UIParent,
        "SecureActionButtonTemplate")
    btn:Hide()
    return btn
end

local function ensureKeybindCapacity(needed)
    while table.getn(keybindButtons) * MAX_VARIANTS_PER_BUTTON < needed do
        local idx = table.getn(keybindButtons) + 1
        table.insert(keybindButtons, newKeybindButton(idx))
    end
end

-- Build keyToSlot from the current PTOptions.Buttons list (key-style only --
-- mouse buttons are handled by per-frame overlays).
local function rebuildKeyAssignments()
    util.ClearTable(keyToSlot)
    local mouseSet = util.GetAllButtonsSet()
    local keys = {}
    for _, button in ipairs(PTOptions.Buttons) do
        if not mouseSet[button] then
            table.insert(keys, button)
        end
    end
    ensureKeybindCapacity(table.getn(keys))
    for i, key in ipairs(keys) do
        local btnIdx = math.floor((i - 1) / MAX_VARIANTS_PER_BUTTON) + 1
        local variant = ((i - 1) - (btnIdx - 1) * MAX_VARIANTS_PER_BUTTON) + 1
        keyToSlot[key] = {button = keybindButtons[btnIdx], variant = variant}
    end
end

local function refreshKeybindAttrs()
    if InCombatLockdown() then
        pendingRefreshOnRegen = true
        return
    end

    -- Wipe everything first so a removed binding doesn't linger.
    for _, btn in ipairs(keybindButtons) do
        for _, modName in ipairs(ALL_MODIFIERS) do
            local prefix = MODIFIER_PREFIXES[modName]
            for variant = 1, MAX_VARIANTS_PER_BUTTON do
                btn:SetAttribute(prefix .. "type" .. variant, nil)
                btn:SetAttribute(prefix .. "macrotext" .. variant, nil)
            end
        end
    end

    -- Write per-(key, modifier) macrotexts.
    for keyName, slot in pairs(keyToSlot) do
        for _, modName in ipairs(ALL_MODIFIERS) do
            local macro = buildMacrotextForSlot(modName, keyName)
            if macro then
                local prefix = MODIFIER_PREFIXES[modName]
                slot.button:SetAttribute(prefix .. "type" .. slot.variant, "macro")
                slot.button:SetAttribute(prefix .. "macrotext" .. slot.variant, macro)
            end
        end
    end
end

local function applySetBindingClick()
    if InCombatLockdown() then
        pendingRefreshOnRegen = true
        return
    end
    for keyName, slot in pairs(keyToSlot) do
        SetBindingClick(keyName, slot.button:GetName(), VARIANT_TO_VIRTUAL[slot.variant])
    end
end


-- ---------- Public refresh ----------

function SecureClickCast.RefreshAll()
    if not SecureClickCast.IsEnabled() then return end
    if InCombatLockdown() then
        pendingRefreshOnRegen = true
        return
    end
    rebuildKeyAssignments()
    refreshKeybindAttrs()
    applySetBindingClick()
    for unitFrame, _ in pairs(overlaysByFrame) do
        SecureClickCast.RefreshOverlay(unitFrame)
    end
    pendingRefreshOnRegen = false
end


-- ---------- Init ----------

local function onRegenEnabled()
    if pendingRefreshOnRegen then
        SecureClickCast.RefreshAll()
    end
    -- Flush deferred Show/Hide on unit-frame group containers. Once the secure
    -- overlay is parented under them, container:Show/Hide() is combat-protected
    -- and was being silently dropped (or producing taint warnings) until now.
    if Puppeteer.UnitFrameGroups then
        for _, group in pairs(Puppeteer.UnitFrameGroups) do
            if group.FlushPendingShown then group:FlushPendingShown() end
        end
    end
end

function SecureClickCast.Init()
    if initialized then return end
    initialized = true
    if not SecureClickCast.IsEnabled() then return end

    -- One-time event registration via the addon's frame-based dispatcher.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function() onRegenEnabled() end)

    SecureClickCast.RefreshAll()
end
