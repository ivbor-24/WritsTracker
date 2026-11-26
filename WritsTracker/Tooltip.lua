-- WritsTracker: тултипы writ-предметов (сумка, чат, аукцион) через TooltipDataProcessor.
-- Показывает: реп, реагенты крафта (знаю/не знаю), точку сдачи, дейли-статус, экономику.
local ADDON, ns = ...

ns.Tooltip = {}
local T = ns.Tooltip

local ICON_READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t"
local ICON_NOT_READY = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14:0:0|t"
local ICON_ACTIVE = "|TInterface\\GossipFrame\\ActiveQuestIcon:14:14:0:0|t"
local ICON_DONE = "|TInterface\\Icons\\INV_Misc_PocketWatch_01:14:14:0:0|t"

local function extractItemId(tooltip, data)
    if data and type(data.id) == "number" then return data.id end
    if tooltip and tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok and link then
            local id = tonumber(link:match("item:(%d+)"))
            if id then return id end
        end
    end
    return nil
end

local function addWritLines(tooltip, w)
    local s = ns.state and ns.state[w.writId]
    local v = s and s.variant
    local rep = ({ Journeyman = 75, Expert = 125, Artisan = 200 })[w.tier] or 75

    tooltip:AddLine(" ")
    tooltip:AddLine("|TInterface\\Icons\\INV_Misc_Note_01:14:14:0:0|t |cffffd100Craftsman's Writ|r")
    tooltip:AddDoubleLine("Репутация:", ("|cff5fbf73+%d|r (%s)"):format(rep, w.tier or "?"), 0.75, 0.75, 0.75, 1, 1, 1)

    -- рецепт: знаю/не знаю + порог скилла
    if s then
        if s.known then
            tooltip:AddLine(ICON_READY .. " |cff5fbf73Рецепт изучен|r")
        else
            local learn = v and v.learnedat
            tooltip:AddLine(ICON_NOT_READY .. (" |cffe05a5aРецепт не изучен|r%s"):format(
                learn and (" (скилл " .. learn .. ")") or ""))
        end
    end

    -- реагенты крафта с наличием
    if v and v.reagents then
        local parts = {}
        for _, r in ipairs(v.reagents) do
            local have = ns.GetItemCount and ns.GetItemCount(r[1]) or (GetItemCount and GetItemCount(r[1], true) or 0)
            local name = ns.GetItemName(r[1]) or ("item:" .. r[1])
            local color = have >= r[2] and "5fbf73" or "e05a5a"
            parts[#parts + 1] = ("|cff%s%d/%d|r %s"):format(color, have, r[2], name)
        end
        tooltip:AddLine("Крафт: " .. table.concat(parts, ", "), 0.9, 0.9, 0.9, true)
    end

    -- точка сдачи
    if w.coord and w.mapId then
        local zone = w.zone or ("map " .. w.mapId)
        local tag = w.handinSrc == "learned" and " |cff88ccee(выучено)|r" or ""
        tooltip:AddDoubleLine("Сдать:", ("%s — %s (%.1f, %.1f)%s"):format(w.npc or "?", zone, w.coord[1], w.coord[2], tag), 0.75, 0.75, 0.75, 1, 0.92, 0.75)
    elseif w.zone and w.zone ~= "-" then
        tooltip:AddDoubleLine("Сдать:", ("%s — %s"):format(w.npc or "?", w.zone), 0.75, 0.75, 0.75, 1, 0.92, 0.75)
    else
        tooltip:AddDoubleLine("Сдать:", "|cff9a9488неизвестно (выучится при сдаче)|r", 0.75, 0.75, 0.75, 1, 1, 1)
    end

    -- дейли-статус
    local lock = ns.Daily and ns.Daily.LockSeconds(w.questId)
    if lock then
        tooltip:AddLine(ICON_DONE .. " |cff88cceeСдан сегодня, снова через " .. ns.Daily.FormatLock(lock) .. "|r")
    elseif s and s.active then
        tooltip:AddLine(ICON_ACTIVE .. " |cffffd24aКвест в журнале|r")
    end

    -- экономика
    if ns.Pricing and ns.Pricing.IsAvailable() then
        local p = ns.Pricing.Analyze(w, s)
        if p and p.available then
            if p.craftCost then
                tooltip:AddDoubleLine("Крафт (реагенты):", ns.Pricing.FormatMoney(p.craftCost), 0.75, 0.75, 0.75, 1, 1, 1)
            end
            if p.buyItem then
                tooltip:AddDoubleLine("Готовый предмет:", ns.Pricing.FormatMoney(p.buyItem) .. ns.Pricing.FormatAge(p.buyItemAge), 0.75, 0.75, 0.75, 1, 1, 1)
            end
            if p.writPrice then
                tooltip:AddDoubleLine("Цена writ:", ns.Pricing.FormatMoney(p.writPrice) .. ns.Pricing.FormatAge(p.writAge), 0.75, 0.75, 0.75, 1, 1, 1)
            end
            if p.payout then
                tooltip:AddDoubleLine("Награда (среднее):", ns.Pricing.FormatMoney(p.payout), 0.75, 0.75, 0.75, 1, 1, 1)
            end
            if p.cpr then
                tooltip:AddDoubleLine("Цена за 1 реп:", ("|cff%s%s|r"):format(p.color, ns.Pricing.FormatMoney(p.cpr)), 0.75, 0.75, 0.75, 1, 1, 1)
            end
            if p.sellBetter then
                tooltip:AddLine("|cffffd24aВыгоднее продать writ, чем сдавать|r")
            end
        end
    end
end

local function onTooltipItem(tooltip, data)
    if not tooltip or not ns.WRIT_BY_ITEM then return end
    local id = extractItemId(tooltip, data)
    if not id then return end
    local w = ns.WRIT_BY_ITEM[id]
    if w then addWritLines(tooltip, w) end
end

function T.Init()
    if T.hooked then return end
    T.hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltipItem)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt) onTooltipItem(tt, nil) end)
        if ItemRefTooltip and ItemRefTooltip.HookScript then
            ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt) onTooltipItem(tt, nil) end)
        end
    end
end