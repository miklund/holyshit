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

local function PowerCost(spellID)
    local getCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    local costs = getCost and getCost(spellID)
    if costs then
        for _, c in ipairs(costs) do
            if c.type == 0 then return c.cost end
        end
    end
end

-- Mana cost of the highest known rank of Heal (nil if Heal is not known).
local function HealCost()
    local spellID
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(HEAL_SPELL)
        spellID = info and info.spellID
    elseif GetSpellInfo then
        spellID = select(7, GetSpellInfo(HEAL_SPELL))
    end
    return spellID and PowerCost(spellID)
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

local function OnDamageTaken()
    if not InDungeon() then return end
    if GetTime() - lastAttacked >= COOLDOWN then
        lastAttacked = GetTime()
        SendChatMessage(ATTACKED_MSG, "YELL")
    end
end

-- Damage taken per second (DTPS) shown on the unit frames.
local DTPS_WINDOW = 8
local DTPS_MIN_SPAN = 1.5
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
    if #kept == 0 then return 0 end
    -- Divide by time since the first hit so a fresh burst is not diluted by the full window.
    local span = math.min(DTPS_WINDOW, math.max(DTPS_MIN_SPAN, GetTime() - kept[1][1]))
    return total / span
end

-- Own frame parented to UIParent so Blizzard's secure frames are never modified (avoids taint).
local overlay = CreateFrame("Frame", nil, UIParent)
if overlay then
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("HIGH")
end

local function GetDtpsText(frame)
    local t = dtpsTexts[frame]
    if not t then
        t = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dtpsTexts[frame] = t
    end
    return t
end

-- Positioned with absolute coordinates; text is never anchored to Blizzard's protected frames.
local function PlaceText(t, frame)
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not left then return false end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    t:ClearAllPoints()
    if (frame:GetName() or ""):find("^Compact") then
        t:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", (right - 3) * ratio, (bottom + 3) * ratio)
    else
        t:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", (left + right) / 2 * ratio, (top - 2) * ratio)
    end
    return true
end

local function ShowDtps(frame, unit)
    local t = GetDtpsText(frame)
    local guid = unit and UnitGUID(unit)
    if HolyshitDB.dtps and guid and IsInGroup() and frame:IsVisible() then
        local v = Dtps(guid)
        if v >= 0.5 and PlaceText(t, frame) then
            t:SetText(string.format("%.0f", v))
            local secondsLeft = UnitHealth(unit) / v
            if secondsLeft <= 5 then t:SetTextColor(1, 0, 0)
            elseif secondsLeft <= 10 then t:SetTextColor(1, 1, 0)
            elseif secondsLeft <= 15 then t:SetTextColor(0, 1, 0)
            else t:SetTextColor(1, 1, 1) end
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

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("UNIT_COMBAT")
frame:RegisterEvent("UNIT_POWER_UPDATE")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then
            HolyshitDB = HolyshitDB or {}
            if HolyshitDB.dtps == nil then HolyshitDB.dtps = true end
            local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
            local version = getMeta and getMeta(ADDON_NAME, "Version") or "?"
            print("|cff00ff00Holyshit|r " .. version .. " loaded. Type /holyshit.")
        end
    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
    elseif event == "UNIT_COMBAT" then
        local unit, action, _, amount = ...
        if action == "WOUND" and amount then
            if unit == "player" then OnDamageTaken() end
            local guid = UnitGUID(unit)
            if guid then RecordDamage(guid, amount) end
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
