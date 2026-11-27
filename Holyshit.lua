local ADDON_NAME = ...
local COOLDOWN = 60
local ATTACKED_MSG = "Help! I'm getting attacked!"
local MANA_MSG = "I'm out of mana."

local HEAL_SPELL = "Heal"

local lastAttacked, lastMana = 0, 0
local playerGUID
local outOfMana = false

local function InDungeon()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "party" and IsInGroup()
end

local function SpellCost(spellID)
    if GetSpellPowerCost then
        local costs = GetSpellPowerCost(spellID)
        if costs then
            for _, c in ipairs(costs) do
                if c.type == 0 then return c.cost end
            end
        end
    end
end

-- Mana cost of the highest known rank of Heal (spellbook lists ranks in ascending order).
local function HealCost()
    local best
    local i = 1
    while true do
        local name, _, spellID
        if GetSpellBookItemName then
            name, _, spellID = GetSpellBookItemName(i, "spell")
        else
            name = GetSpellName(i, "spell")
        end
        if not name then break end
        if name == HEAL_SPELL and spellID then
            best = SpellCost(spellID) or best
        end
        i = i + 1
    end
    return best
end

local function CheckMana()
    if not InDungeon() or UnitPowerType("player") ~= 0 then return end
    local cost = HealCost()
    if not cost then return end
    if UnitPower("player", 0) < cost then
        if not outOfMana and GetTime() - lastMana >= COOLDOWN then
            outOfMana = true
            lastMana = GetTime()
            SendChatMessage(MANA_MSG, "PARTY")
        end
    else
        outOfMana = false
    end
end

local function OnDamageTaken(sourceGUID)
    if not InDungeon() or sourceGUID == playerGUID then return end
    if GetTime() - lastAttacked >= COOLDOWN then
        lastAttacked = GetTime()
        SendChatMessage(ATTACKED_MSG, "YELL")
    end
end

-- Damage taken per second (DTPS) shown on the unit frames.
local DTPS_WINDOW = 5
local damageLog = {} -- guid -> { {time, amount}, ... }
local dtpsTexts = {}
local UNIT_FRAMES = {
    player = "PlayerFrame",
    party1 = "PartyMemberFrame1", party2 = "PartyMemberFrame2",
    party3 = "PartyMemberFrame3", party4 = "PartyMemberFrame4",
}

local function RecordDamage(guid, amount)
    local list = damageLog[guid]
    if not list then list = {}; damageLog[guid] = list end
    list[#list + 1] = { GetTime(), amount }
end

local function Dtps(guid)
    local list = damageLog[guid]
    if not list then return 0 end
    local cutoff, total, kept = GetTime() - DTPS_WINDOW, 0, {}
    for _, e in ipairs(list) do
        if e[1] >= cutoff then
            total = total + e[2]
            kept[#kept + 1] = e
        end
    end
    damageLog[guid] = kept
    return total / DTPS_WINDOW
end

-- Own frame parented to UIParent so Blizzard's secure frames are never modified (avoids taint).
local overlay = CreateFrame("Frame", nil, UIParent)
overlay:SetAllPoints(UIParent)
overlay:SetFrameStrata("HIGH")

local function GetDtpsText(frame)
    local t = dtpsTexts[frame]
    if not t then
        t = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if frame.unit and frame:GetName() and frame:GetName():find("^Compact") then
            t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
        else
            t:SetPoint("BOTTOM", frame, "TOP", 0, -2)
        end
        dtpsTexts[frame] = t
    end
    return t
end

local function ShowDtps(frame, unit)
    local t = GetDtpsText(frame)
    local guid = unit and UnitGUID(unit)
    if HolyshitDB.dtps and guid and IsInGroup() and frame:IsVisible() then
        local v = Dtps(guid)
        if v >= 0.5 then
            t:SetText(string.format("%.0f", v))
            t:SetTextColor(1, math.max(0, 1 - v / 300), 0)
            return
        end
    end
    t:SetText("")
end

local function UpdateDtps()
    for unit, name in pairs(UNIT_FRAMES) do
        local f = _G[name]
        if f then ShowDtps(f, unit) end
    end
    -- Blizzard raid-style frames (party and raid)
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i]
        if f then ShowDtps(f, f.displayedUnit or f.unit) end
    end
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if f then ShowDtps(f, f.displayedUnit or f.unit) end
    end
    for g = 1, 8 do
        for m = 1, 5 do
            local f = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if f then ShowDtps(f, f.displayedUnit or f.unit) end
        end
    end
end

local function DamageAmount(subevent, ...)
    if subevent == "SWING_DAMAGE" then
        return (select(12, ...))
    elseif subevent == "ENVIRONMENTAL_DAMAGE" then
        return (select(13, ...))
    elseif subevent == "SPELL_DAMAGE" or subevent == "RANGE_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" then
        return (select(15, ...))
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then
            HolyshitDB = HolyshitDB or {}
            if HolyshitDB.dtps == nil then HolyshitDB.dtps = true end
        end
    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local info = { CombatLogGetCurrentEventInfo() }
        local subevent, sourceGUID, destGUID = info[2], info[4], info[8]
        if destGUID == playerGUID and subevent:find("_DAMAGE$") then
            OnDamageTaken(sourceGUID)
        end
        local amount = DamageAmount(subevent, unpack(info))
        if amount and destGUID and destGUID:find("^Player") then
            RecordDamage(destGUID, amount)
        end
    elseif event == "UNIT_POWER_UPDATE" then
        if ... == "player" then CheckMana() end
    end
end)

local elapsedSum = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSum = elapsedSum + elapsed
    if elapsedSum >= 0.5 then
        elapsedSum = 0
        if HolyshitDB then UpdateDtps() end
    end
end)

SLASH_HOLYSHIT1 = "/holyshit"
SlashCmdList["HOLYSHIT"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "dtps" then
        HolyshitDB.dtps = not HolyshitDB.dtps
        print("|cff00ff00Holyshit|r: damage per second display " .. (HolyshitDB.dtps and "on" or "off"))
        UpdateDtps()
        return
    end
    local cost = HealCost()
    print("|cff00ff00Holyshit|r: attacked/mana messages repeat at most every " .. COOLDOWN .. "s. Heal cost: " .. (cost or "unknown"))
    print("  /holyshit dtps - toggle damage per second on unit frames (currently " .. (HolyshitDB.dtps and "on" or "off") .. ")")
end
