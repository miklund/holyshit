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

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, sourceGUID, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
        if destGUID == playerGUID and subevent:find("_DAMAGE$") then
            OnDamageTaken(sourceGUID)
        end
    elseif event == "UNIT_POWER_UPDATE" then
        if ... == "player" then CheckMana() end
    end
end)

SLASH_HOLYSHIT1 = "/holyshit"
SlashCmdList["HOLYSHIT"] = function()
    local cost = HealCost()
    print("|cff00ff00Holyshit|r: attacked/mana messages repeat at most every " .. COOLDOWN .. "s. Heal cost: " .. (cost or "unknown"))
end
