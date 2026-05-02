-- Predicts healing based on previously seen healing.
-- This library currently is not independent and relies on some Puppeteer code.

PTHealPredict = {}
PTUtil.SetEnvironment(PTHealPredict)
local _G = getfenv(0)


RelevantGUIDs = {} -- A set of GUIDs to listen to

IncomingHeals = {} -- Key: Receiver | Value: List of incoming casts
IncomingHots = {} -- Key: Receiver | Value: {HoT Name: {"caster", "id", "heal"}}
Casts = {} -- Key: Caster | Value: {"targets", "spellID", "startTime"}
LastCastedSpells = {}

-- A cache of expected heal values for spells. These values are saved.
-- Key: Spell ID | Value: Typical heal value for the spell ID
HealCache = {}

-- Since every healer heals for different values based on talents and gear,
-- everyone's heal values are cached
-- Key: Name | Value: Array: {Spell ID: Heal value}
PlayerHealCache = {}

ResurrectionTargets = {} -- Key: Receiver | Value: {Caster: {"startTime", "castTime"}}

-- An array of functions that listen to changes to incoming healing
Listeners = {}

local print
local colorize = PTUtil.Colorize

local PRAYER_OF_HEALING_NAMES = PTUtil.ToSet({"Prayer of Healing"})
PTLocale.Keys(PRAYER_OF_HEALING_NAMES)
local ResurrectionSpells = PTUtil.ToSet({
    "Resurrection", "Revive Champion", "Redemption", "Ancestral Spirit", "Rebirth"
})
PTLocale.Keys(ResurrectionSpells)

local TRACKED_HOTS = PTUtil.ToSet({
    "Rejuvenation", "Regrowth", -- Druid
    "Renew", "Greater Heal", -- Priest
    "Mend Pet", -- Hunter
    "First Aid" -- Generic
})
PTLocale.Keys(TRACKED_HOTS)

function OnLoad()
    print = Puppeteer.print
    if not PTHealCache then
        setglobal("PTHealCache", {})
    end
    HealCache = PTHealCache

    if not PTPlayerHealCache then
        setglobal("PTPlayerHealCache", {})
    end
    if not PTPlayerHealCache[GetRealmName()] then
        PTPlayerHealCache[GetRealmName()] = {}
    end
    PlayerHealCache = PTPlayerHealCache[GetRealmName()]
end

-- Get the expected heal of a player's spell
function GetExpectedHeal(playerName, spellID)
    local playerCache = PlayerHealCache[playerName]
    if not playerCache or not playerCache[spellID] then
        return GetGenericExpectedHeal(spellID)
    end
    return playerCache[spellID]
end

function GetGenericExpectedHeal(spellID)
    return HealCache[spellID] or 0
end

-- Returns all incoming healing and incoming direct healing
function GetIncomingHealing(guid)
    local healing = 0
    local casts = IncomingHeals[guid]
    if casts then
        for _, cast in pairs(casts) do
            healing = healing + cast["heal"]
        end
    end
    local directHealing = healing
    local hots = IncomingHots[guid]
    if hots then
        for _, hot in pairs(hots) do
            healing = healing + hot["heal"]
        end
    end
    return healing, directHealing
end

-- Returns non-HoT incoming healing
function GetIncomingDirectHealing(guid)
    local healing = 0
    local casts = IncomingHeals[guid]
    if casts then
        for _, cast in pairs(casts) do
            healing = healing + cast["heal"]
        end
    end
    return healing
end

-- To mimick HealComm, but this currently only accepts GUIDs
function getHeal(guid)
    return GetIncomingHealing(guid)
end

function IsBeingResurrected(guid)
    return ResurrectionTargets[guid] ~= nil
end

function GetResurrectionCount(guid)
    local resses = ResurrectionTargets[guid]
    if not resses then
        return 0
    end
    local count = 0
    for _ in pairs(resses) do
        count = count + 1
    end
    return count
end

-- Used for Prayer of Healing to add incoming healing to multiple players
function AddIncomingMultiCast(targets, caster, spellID, healAmount, castTime)
    Casts[caster] = {
        targets = targets,
        spellID = spellID,
        startTime = GetTime(),
    }
    for _, target in ipairs(targets) do
        AddIncomingCast(target, caster, spellID, healAmount, castTime, true)
    end
end

local castIcons = {}
function RemoveAllCastIcons()
    for caster, icons in pairs(castIcons) do
        for _, icon in ipairs(castIcons[caster]) do
            icon:End(false)
        end
        castIcons[caster] = nil
    end
end

function AddIncomingCast(target, caster, spellID, healAmount, castTime, multi)
    if not multi then
        Casts[caster] = {
            targets = {target},
            spellID = spellID,
            startTime = GetTime(),
        }
    end
    local targetTable = IncomingHeals[target]
    if not targetTable then
        targetTable = {}
        IncomingHeals[target] = targetTable
    end
    targetTable[caster] = {
        spellID = spellID,
        heal = healAmount,
        castTime = castTime,
        startTime = GetTime(),
    }

    UpdateTarget(target)
end

function RemoveIncomingCast(caster, successful)
    local cast = Casts[caster]
    if cast then
        for _, target in ipairs(cast["targets"]) do
            local incomingHeals = IncomingHeals[target]
            incomingHeals[caster] = nil
            UpdateTarget(target)
        end
        Casts[caster] = nil
    end
end

function GetCurrentCast(caster)
    local cast = Casts[caster]
    if cast then
        return table.getn(cast["targets"]) > 0 and IncomingHeals[cast["targets"][1]][caster] or nil
    end
end

function AddHot(target, caster, spellID, spellName, healAmount)
    local hot = {
        caster = caster,
        id = spellID,
        heal = healAmount,
        startTime = GetTime(),
    }
    local targetTable = IncomingHots[target]
    if not targetTable then
        targetTable = {}
        IncomingHots[target] = targetTable
    end
    targetTable[spellName] = hot

    UpdateTarget(target)
end

function UpdateTarget(target)
    for _, listener in ipairs(Listeners) do
        listener(target, GetIncomingHealing(target))
    end
end

local function trimDecimal(number, places)
    local factor = 10 ^ places
    return math.floor(number * factor) / factor
end

local GENERIC_CHANGE_FACTOR = 0.05
local PLAYER_CHANGE_FACTOR = 0.25
function UpdateCache(heal, name)
    name = name or UnitName("player")
    local lastCastedSpell = LastCastedSpells[name]
    LastCastedSpells[name] = nil

    if not lastCastedSpell then
        return
    end

    local spellID = lastCastedSpell["spellID"]

    if not PRAYER_OF_HEALING_NAMES[spellID] then
        if lastCastedSpell["target"] == "" then
            --print(colorize("Don't have a target of spell cast for "..name.."'s "..spellID, 1, 0, 0))
            return
        end
        local cache = PTUnit.Get(lastCastedSpell["target"])
        if not cache or cache == PTUnit then
            --print(colorize("Could not find "..name.."'s unit while updating cache!", 1, 0, 0))
            return
        end
        if cache.HasHealingModifier then
            --print(colorize("Not updating cache for "..name.."'s "..spellID.." because of healing modifier", 0.5, 0.5, 0.5))
            return
        end
    end

    -- Update the generic cache
    if not HealCache[spellID] then
        HealCache[spellID] = heal
    else
        local prevHeal = HealCache[spellID]
        local adjustedHeal = trimDecimal(prevHeal + ((heal - prevHeal) * GENERIC_CHANGE_FACTOR), 2)
        HealCache[spellID] = adjustedHeal
        print(colorize("Generic "..spellID..": "..prevHeal.." -> "..adjustedHeal, 0, 0.8, 0.8))
    end

    if not PlayerHealCache[name] then
        PlayerHealCache[name] = {}
    end
    -- Update the player-specific cache
    local playerCache = PlayerHealCache[name]
    if not playerCache[spellID] then
        playerCache[spellID] = heal
        print(colorize("Created cache for "..name.."'s "..spellID, 1, 0.5, 1))
    end
    local prevHeal = playerCache[spellID]
    local adjustedHeal = trimDecimal(prevHeal + ((heal - prevHeal) * PLAYER_CHANGE_FACTOR), 2)
    playerCache[spellID] = adjustedHeal
    playerCache["lastSeen"] = time()

    print(colorize(name.."'s "..spellID..": "..prevHeal.." -> "..adjustedHeal, 0, 0.8, 0.2))
end

function UpdateCacheHot(spellName, heal, targetGuid, targetName, casterGuid, casterName)
    if not IncomingHots[targetGuid] then
        return
    end
    local hots = IncomingHots[targetGuid]
    if not hots[spellName] then
        return
    end
    heal = tonumber(heal) or 0
    local hot = hots[spellName]
    if hot["heal"] ~= heal then
        local prevHeal = hot["heal"]
        hot["heal"] = heal
        UpdateTarget(targetGuid)
        if not PlayerHealCache[casterName] then
            PlayerHealCache[casterName] = {}
        end
        local spellID = hot["id"]

        local cache = PTUnit.Get(targetGuid)
        if not cache or cache == PTUnit then
            print(colorize("Could not find "..targetName.."'s unit while updating cache!", 1, 0, 0))
            return
        end
        if cache.HasHealingModifier then
            print(colorize("Not updating cache for "..casterName.."'s "..spellID.." because of healing modifier", 0.5, 0.5, 0.5))
            return
        end
        -- Update the player-specific cache
        local playerCache = PlayerHealCache[casterName]
        spellID = spellID.."-HoT"
        if not playerCache[spellID] then
            playerCache[spellID] = heal
            print(colorize("Created cache for "..casterName.."'s "..spellID.." ("..spellName..")", 1, 0.5, 1))
        end
        PlayerHealCache[casterName][spellID] = heal
        print(colorize(casterName.."'s "..spellID.." ("..spellName..")"..": "..prevHeal.." -> "..heal, 0, 0.8, 0.2))
    end
end

function RemoveHoT(spellName, targetGuid)
    if not IncomingHots[targetGuid] then
        return
    end
    if not IncomingHots[targetGuid][spellName] then
        return
    end
    local hot = IncomingHots[targetGuid][spellName]
    -- A hack needed because overwritten HoTs cause the previous HoT to be removed,
    -- which happens after the cast-success event
    if hot["startTime"] + 0.5 > GetTime() and not hot["swiftmend"] then
        return
    end
    IncomingHots[targetGuid][spellName] = nil
    UpdateTarget(targetGuid)
end

-- Native name->unit lookup; replaces RosterLib's GetUnitIDFromName.
local function getUnitFromName(name)
    for _, unit in ipairs(PTUtil.AllRealUnits) do
        if UnitName(unit) == name then
            return unit
        end
    end
end

local function getGuidFromLogName(name)
    local petName, owner = PTUtil.cmatch(name, "%s (%s)")
    if owner then -- A pet is being healed
        local ownerUnit = getUnitFromName(owner)
        if not ownerUnit then
            return
        end
        local petUnit = ownerUnit.."pet"
        if UnitExists(petUnit) then
            return UnitGUID(petUnit)
        end
        return
    end
    local unit = getUnitFromName(name)
    if unit then
        return UnitGUID(unit)
    end
    -- SuperWoW custom-units fallback
    if PTUnitProxy and PTUnitProxy.CustomUnitGUIDMap then
        for _, guid in pairs(PTUnitProxy.CustomUnitGUIDMap) do
            if UnitName(guid) == name then
                return guid
            end
        end
    end
end

local function getSelfGuid()
    return UnitGUID("player")
end

local autoShotName = PTLocale.Translate("Auto Shot")
local trackedHostileSpells = PTUtil.ToSet({
    "Shackle Undead", "Mind Control", "Fear", "Polymorph",
    "Polymorph: Turtle", "Polymorph: Cow", "Polymorph: Rodent"
})
PTLocale.Keys(trackedHostileSpells)

local SelfCastInfo = {}

local eventFrame = CreateFrame("Frame", "PTHealPredictCasts")
eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")

local function endCastIcons(casterGuid, successful)
    if castIcons[casterGuid] then
        for _, icon in ipairs(castIcons[casterGuid]) do
            icon:End(successful)
        end
        castIcons[casterGuid] = nil
    end
end

local function spawnCastIcon(casterGuid, spellName, texture, durationMs, targetGuid, healAmount)
    local targetFrame
    for f in Puppeteer.UnitFrames(targetGuid) do
        if f.owningGroup:GetContainer():IsShown() then
            targetFrame = f
            break
        end
    end
    if not targetFrame then return end
    local icon = PTGuiLib.Get("puppeteer_cast_icon")
    icon:Start(spellName, texture, durationMs / 1000, casterGuid, healAmount or 0, targetFrame)
    if not castIcons[casterGuid] then
        castIcons[casterGuid] = {}
    end
    table.insert(castIcons[casterGuid], icon)
end

eventFrame:SetScript("OnEvent", function()
    local unit = arg1
    if unit ~= "player" then return end
    local casterGuid = UnitGUID("player")
    if not casterGuid or not RelevantGUIDs[casterGuid] then return end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local spellName, _, _, texture, startTime, endTime
        if event == "UNIT_SPELLCAST_START" then
            spellName, _, _, texture, startTime, endTime = UnitCastingInfo(unit)
        else
            spellName, _, _, texture, startTime, endTime = UnitChannelInfo(unit)
        end
        if not spellName then return end
        local duration = endTime - startTime

        local targetGuid
        if UnitExists("target") and UnitIsFriend("player", "target") then
            targetGuid = UnitGUID("target")
        end

        if ResurrectionSpells[spellName] and targetGuid then
            ResurrectionTargets[targetGuid] = ResurrectionTargets[targetGuid] or {}
            ResurrectionTargets[targetGuid][casterGuid] = {
                startTime = GetTime(),
                castTime = duration,
            }
            UpdateTarget(targetGuid)
        end

        if event == "UNIT_SPELLCAST_START" and not ResurrectionSpells[spellName] and duration > 0 then
            if PRAYER_OF_HEALING_NAMES[spellName] then
                local anchor = targetGuid or casterGuid
                local inRange = PTUtil.GetSurroundingPartyMembers(anchor, 28)
                local expectedHeal = GetExpectedHeal(UnitName("player"), spellName)
                AddIncomingMultiCast(inRange, casterGuid, spellName, expectedHeal, duration)
            else
                local expectedHeal = GetExpectedHeal(UnitName("player"), spellName)
                if expectedHeal > 0 then
                    AddIncomingCast(targetGuid or casterGuid, casterGuid, spellName, expectedHeal, duration)
                end
            end
        end

        SelfCastInfo[casterGuid] = {
            spellName = spellName,
            target = targetGuid,
            startTime = GetTime(),
            duration = duration,
            isChannel = (event == "UNIT_SPELLCAST_CHANNEL_START"),
        }

        if PuppeteerSettings.IsExperimentEnabled("CastIcons") then
            local showIcon = (targetGuid ~= nil) or trackedHostileSpells[spellName]
                or PRAYER_OF_HEALING_NAMES[spellName]
            if showIcon then
                local iconTargets
                if PRAYER_OF_HEALING_NAMES[spellName] then
                    iconTargets = PTUtil.GetSurroundingPartyMembers(targetGuid or casterGuid, 28)
                else
                    iconTargets = {targetGuid or casterGuid}
                end
                for _, t in ipairs(iconTargets) do
                    local healAmount = (targetGuid and not trackedHostileSpells[spellName])
                        and GetExpectedHeal(UnitName("player"), spellName) or 0
                    spawnCastIcon(casterGuid, spellName, texture, duration, t, healAmount)
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local cast = SelfCastInfo[casterGuid]
        if not cast then return end
        local spellName = cast.spellName
        local castTarget = cast.target

        if ResurrectionSpells[spellName] and castTarget then
            local resses = ResurrectionTargets[castTarget]
            if resses and resses[casterGuid] then
                resses[casterGuid] = nil
                if not next(resses) then
                    ResurrectionTargets[castTarget] = nil
                end
                UpdateTarget(castTarget)
            end
        end

        -- Swiftmend tags HoTs so RemoveHoT permits the otherwise-suspicious early removal
        if spellName == "Swiftmend" and castTarget and IncomingHots[castTarget] then
            local hots = IncomingHots[castTarget]
            if hots["Rejuvenation"] then hots["Rejuvenation"]["swiftmend"] = true end
            if hots["Regrowth"] then hots["Regrowth"]["swiftmend"] = true end
        end

        if TRACKED_HOTS[spellName] then
            local hotTarget
            if spellName == "Mend Pet" then
                if UnitExists("pet") then
                    hotTarget = UnitGUID("pet")
                end
            else
                hotTarget = castTarget or casterGuid
            end
            if hotTarget then
                AddHot(hotTarget, casterGuid, spellName, spellName,
                    GetExpectedHeal(UnitName("player"), spellName.."-HoT"))
            end
        end

        local currentCast = GetCurrentCast(casterGuid)
        if currentCast and currentCast["spellID"] == spellName then
            RemoveIncomingCast(casterGuid, true)
            LastCastedSpells[UnitName("player")] = {
                unit = casterGuid,
                target = castTarget or "",
                spellID = spellName,
            }
        end

        if castIcons[casterGuid] and castIcons[casterGuid][1].spellName == spellName then
            endCastIcons(casterGuid, true)
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local cast = SelfCastInfo[casterGuid]
        local spellName = cast and cast.spellName

        if spellName ~= autoShotName then
            RemoveIncomingCast(casterGuid, false)
        end

        if cast and ResurrectionSpells[spellName] and cast.target then
            local resses = ResurrectionTargets[cast.target]
            if resses and resses[casterGuid] then
                resses[casterGuid] = nil
                if not next(resses) then
                    ResurrectionTargets[cast.target] = nil
                end
                UpdateTarget(cast.target)
            end
        end

        if spellName ~= autoShotName then
            endCastIcons(casterGuid, false)
        end
        SelfCastInfo[casterGuid] = nil
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        SelfCastInfo[casterGuid] = nil
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        local cast = SelfCastInfo[casterGuid]
        if cast then
            local spellName, _, _, _, startTime, endTime = UnitCastingInfo(unit)
            if spellName and startTime and endTime then
                cast.startTime = startTime / 1000
                cast.duration = endTime - startTime
            end
        end
    end
end)


-- Because the prediction code is not currently bullet-proof to infinite incoming heals, we're checking once a while for old casts
local GARBAGE_CHECK_INTERVAL = 10
local nextGarbageCheck = GetTime() + GARBAGE_CHECK_INTERVAL
eventFrame:SetScript("OnUpdate", function()
    if GetTime() > nextGarbageCheck then
        local time = GetTime()
        nextGarbageCheck = time + GARBAGE_CHECK_INTERVAL

        for receiver, casts in pairs(IncomingHeals) do
            for caster, cast in pairs(casts) do
                if cast["startTime"] + 15 < time then
                    print(colorize("Removed "..caster.."'s heal on "..receiver.." for taking too long", 1, 0, 0))
                    casts[caster] = nil
                    UpdateTarget(receiver)
                end
            end
        end

        for receiver, hots in pairs(IncomingHots) do
            for name, hot in pairs(hots) do
                if hot["startTime"] + 25 < time then
                    print(colorize("Removed "..hot["caster"].."'s "..name.." (HoT) on "..
                        receiver.." for taking too long", 1, 0, 0))
                    hots[name] = nil
                    UpdateTarget(receiver)
                end
            end
        end

        for target, resses in pairs(ResurrectionTargets) do
            for caster, res in pairs(resses) do
                if res["startTime"] + 20 < time then
                    print(colorize("Removed "..caster.."'s resurrection on "..
                        target.." for taking too long", 1, 0, 0))
                    resses[caster] = nil
                    ResurrectionTargets[target] = nil
                    UpdateTarget(target)
                end
            end
            if not ResurrectionTargets[target] then -- Must've been removed
            end
        end

        for caster, icons in pairs(castIcons) do
            local icon = icons[1]
            if icon:GetOvertime() > 10 then
                for _, icon in ipairs(castIcons[caster]) do
                    icon:End(false)
                end
                castIcons[caster] = nil
            end
        end
    end
end)

local cmatch = PTUtil.cmatch

local combatLogFrame = CreateFrame("Frame", "PTHealPredictCombatLog")
combatLogFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
combatLogFrame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
combatLogFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF") -- Needed to see casts coming from other players to yourself
combatLogFrame:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
combatLogFrame:RegisterEvent("CHAT_MSG_SPELL_PET_BUFF")
combatLogFrame:SetScript("OnEvent", function()
    if string.find(arg1, "critically") then
        return
    end

    if string.find(arg1, "Bonus Healing") then
        return
    end

    local spell, targetName, heal = cmatch(arg1, HEALEDSELFOTHER) -- "Your %s heals %s for %d."
    if spell and targetName and heal then
        UpdateCache(tonumber(heal))
        return
    end

    local spell, heal = cmatch(arg1, HEALEDSELFSELF) -- "Your %s heals you for %d."
    if spell and heal then
        UpdateCache(tonumber(heal))
        return
    end

    local name, spell, heal = cmatch(arg1, HEALEDOTHERSELF) -- "%s's %s heals you for %d."
    if name and spell and heal then
        UpdateCache(tonumber(heal), name)
        return
    end

    local name, spell, targetName, heal = cmatch(arg1, HEALEDOTHEROTHER) -- "%s's %s heals %s for %d."
    if name and spell and targetName and heal then
        UpdateCache(tonumber(heal), name)
        return
    end
end)

local periodicCombatLogFrame = CreateFrame("Frame", "PTHealPredictPerCombatLog")
periodicCombatLogFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
periodicCombatLogFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
periodicCombatLogFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")
periodicCombatLogFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
periodicCombatLogFrame:SetScript("OnEvent", function()
    local heal, spell = cmatch(arg1, PERIODICAURAHEALSELFSELF) -- "You gain %d health from %s."
    if heal and spell then
        local selfName = UnitName("player")
        local selfGuid = getSelfGuid()
        UpdateCacheHot(spell, heal, selfGuid, selfName, selfGuid, selfName)
        return
    end

    local name, heal, spell = cmatch(arg1, PERIODICAURAHEALSELFOTHER) -- "%s gains %d health from your %s."
    if name and heal and spell then
        local casterGuid = getSelfGuid()
        local targetGuid = getGuidFromLogName(name)
        UpdateCacheHot(spell, heal, targetGuid, name, casterGuid, UnitName(casterGuid))
        return
    end

    local heal, name, spell = cmatch(arg1, PERIODICAURAHEALOTHERSELF) -- "You gain %d health from %s's %s."
    if heal and name and spell then
        local casterGuid = getGuidFromLogName(name)
        local targetGuid = getSelfGuid()
        UpdateCacheHot(spell, heal, targetGuid, UnitName("player"), casterGuid, name)
        return
    end

    local targetName, heal, name, spell = cmatch(arg1, PERIODICAURAHEALOTHEROTHER) -- "%s gains %d health from %s's %s."
    if targetName and heal and name and spell then
        local casterGuid = getGuidFromLogName(name)
        local targetGuid = getGuidFromLogName(targetName)
        UpdateCacheHot(spell, heal, targetGuid, targetName, casterGuid, name)
        return
    end
end)

local auraCombatLogFrame = CreateFrame("Frame", "PTHealPredictAuraCombatLog")
auraCombatLogFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")
auraCombatLogFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_PARTY")
auraCombatLogFrame:SetScript("OnEvent", function()
    local spell, name = cmatch(arg1, AURAREMOVEDOTHER) -- "%s fades from %s."
    if spell and name then
        local guid = getGuidFromLogName(name)
        if not guid then
            return
        end
        RemoveHoT(spell, guid)
        return
    end
end)

local selfAuraCombatLogFrame = CreateFrame("Frame", "PTHealPredictSelfAuraCombatLog")
selfAuraCombatLogFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_SELF")
selfAuraCombatLogFrame:SetScript("OnEvent", function()
    local spell = cmatch(arg1, AURAREMOVEDSELF) -- "%s fades from you."
    if spell then
        RemoveHoT(spell, getSelfGuid())
        return
    end
end)

-- Set the GUIDs to listen to
function SetRelevantGUIDs(guidArray)
    RelevantGUIDs = PTUtil.ToSet(guidArray)
end

-- Provided listener function will receive the arguments: Updated GUID, Updated Incoming Healing
function HookUpdates(listener)
    table.insert(Listeners, listener)
end
