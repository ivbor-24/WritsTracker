-- WritsTracker: состояние, детект изученных рецептов, дейли-статус, shift-click в аукцион.
local ADDON, ns = ...
WritsTracker = {}
ns.WT = WritsTracker

local DB = WritsTrackerDB

local function safe(fn, ...)
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
    return nil
end

-- Профессии персонажа: skillLine -> {name, rank, max}
-- Forever = классика: GetProfessions() нет, идём по GetSkillLine(i).
local PROFESSION_SKILLS = {
    [171] = "Alchemy", [164] = "Blacksmithing", [202] = "Engineering",
    [165] = "Leatherworking", [197] = "Tailoring",
}
ns.PROFESSION_SKILLS = PROFESSION_SKILLS

function ns.GetPlayerProfessions()
    local profs = {}
    -- modern path: GetProfessions + GetProfessionInfo (7-е значение = skillLineID)
    if GetProfessions and GetProfessionInfo then
        for i = 1, 6 do
            local idx = select(i, safe(GetProfessions))
            if idx then
                local name, _, rank, max, _, _, line = safe(GetProfessionInfo, idx)
                if line and PROFESSION_SKILLS[line] then
                    profs[line] = { name = name, rank = rank or 0, max = max or 0 }
                elseif name then
                    for skill, pname in pairs(PROFESSION_SKILLS) do
                        if name == pname then profs[skill] = { name = name, rank = rank or 0, max = max or 0 } end
                    end
                end
            end
        end
    end
    -- classic path: список скиллов под заголовком TRADE_SKILLS
    if not next(profs) and GetNumSkillLines and GetSkillLineInfo then
        local n = safe(GetNumSkillLines) or 0
        local inProfessions = false
        for i = 1, n do
            local name, header, _, rank, _, _, maxRank = safe(GetSkillLineInfo, i)
            if header then
                inProfessions = (name == TRADE_SKILLS) or (name == SECONDARY_SKILLS)
            elseif name and (inProfessions or not TRADE_SKILLS) then
                for skill, pname in pairs(PROFESSION_SKILLS) do
                    if name == pname then
                        profs[skill] = { name = name, rank = rank or 0, max = maxRank or 0 }
                    end
                end
            end
        end
    end
    return profs
end

-- Изучен ли рецепт: на Forever IsPlayerSpell(spellID) = true для изученных крафт-спеллов
-- (проверено Mastercraft: Smelt Copper true / Smelt Silver false; IsSpellKnown врёт).
function ns.IsRecipeKnown(spellId)
    if not spellId then return false end
    if IsPlayerSpell then
        local ok = safe(IsPlayerSpell, spellId)
        if ok ~= nil then return ok end
    end
    if IsSpellKnown then
        local ok = safe(IsSpellKnown, spellId)
        if ok ~= nil then return ok end
    end
    return false
end

-- Активные квесты: modern C_QuestLog, фолбэк GetQuestLogTitle (как в TaurenGuide).
function ns.GetActiveQuests()
    local active = {} -- [questID] = title
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local n = safe(C_QuestLog.GetNumQuestLogEntries) or 0
        for i = 1, n do
            local info = safe(C_QuestLog.GetInfo, i)
            if info and not info.isHeader and info.questID then
                active[info.questID] = info.title
            end
        end
    end
    if not next(active) and GetNumQuestLogEntries and GetQuestLogTitle then
        local n = safe(GetNumQuestLogEntries) or 0
        for i = 1, n do
            local title, _, _, _, header, _, _, questID = safe(GetQuestLogTitle, i)
            if title and not header and questID then active[questID] = title end
        end
    end
    return active
end

-- Сданные сегодня дейлики: IsQuestFlaggedCompleted (классика) / C_QuestLog.IsQuestFlaggedCompleted.
function ns.IsQuestDoneToday(questId)
    if not questId then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok = safe(C_QuestLog.IsQuestFlaggedCompleted, questId)
        if ok ~= nil then return ok end
    end
    if IsQuestFlaggedCompleted then
        local ok = safe(IsQuestFlaggedCompleted, questId)
        if ok ~= nil then return ok end
    end
    return false
end

-- Зона writ доступна по уровню? reqlevel writ-предмета vs уровень игрока.
function ns.IsZoneAvailable(w)
    local lvl = UnitLevel("player") or 1
    local req = w.writReqLevel or 1
    return lvl >= req
end

-- Друидская зона (Moonglade): телепорт друидов, остальным туда долго.
ns.DRUID_ZONES = { ["Moonglade"] = true }

-- Иконка предмета из игры; фолбэк — имя из БД.
function ns.GetItemName(id)
    if not id then return nil end
    local name = safe(GetItemInfo, id)
    if name then return name end
    local meta = ns.ITEMS and ns.ITEMS[id]
    return meta and meta.name
end

function ns.GetItemIcon(id)
    if not id then return nil end
    local icon = safe(GetItemIcon, id)
    if icon then return icon end
    local meta = ns.ITEMS and ns.ITEMS[id]
    if meta and meta.icon then return "Interface\\Icons\\" .. meta.icon end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function ns.GetItemLink(id)
    if not id then return nil end
    local _, link = safe(GetItemInfo, id)
    if link then return link end
    local name = ns.GetItemName(id)
    if name then return ("|cff1eff00|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(id, name) end
    return nil
end

-- Shift-click: вставить ссылку в аукцион (Auctionator сам ищет при ChatEdit_InsertLink,
-- если открыт его Shopping-фрейм) или в чат.
function ns.InsertLink(link)
    if not link then return end
    if Auctionator and Auctionator.Utilities and Auctionator.Utilities.InsertLink then
        Auctionator.Utilities.InsertLink(link)
        return
    end
    if ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
    elseif ChatFrameUtil and ChatFrameUtil.InsertLink then
        ChatFrameUtil.InsertLink(link)
    end
end

-- Прямой поиск в Auctionator по имени (если аукцион открыт).
function ns.AuctionSearch(term)
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.MultiSearch then
        local ok = pcall(Auctionator.API.v1.MultiSearch, "WritsTracker", { term })
        if ok then return true end
    end
    return false
end

-- Индексы для быстрого поиска (тултипы, самообучение).
local function buildIndexes()
    ns.WRIT_BY_ITEM = {}
    ns.WRIT_BY_QUEST = {}
    for _, w in ipairs(ns.WRITS or {}) do
        ns.WRIT_BY_ITEM[w.writId] = w
        if w.questId then ns.WRIT_BY_QUEST[w.questId] = w end
    end
end

-- Учёт банка: GetItemCount(id, true) включает банк на Forever; фолбэк — скан банка.
local bankCache = {}
local bankOpen = false

function ns.GetItemCount(id)
    if not id then return 0 end
    local bags = safe(GetItemCount, id, false) or 0
    local total = safe(GetItemCount, id, true)
    if type(total) == "number" and total >= bags then return total end
    return bags + (bankCache[id] or 0)
end

local function scanBank()
    if not GetContainerNumSlots then return end
    local cache = {}
    local bags = { -1 }
    local startBag = (NUM_BAG_SLOTS or 4) + 1
    for bag = startBag, startBag + (NUM_BANKBAGSLOTS or 7) - 1 do bags[#bags + 1] = bag end
    for _, bag in ipairs(bags) do
        local slots = safe(GetContainerNumSlots, bag) or 0
        for slot = 1, slots do
            local id = safe(GetContainerItemID, bag, slot)
            if id then cache[id] = (cache[id] or 0) + (safe(GetContainerItemCount, bag, slot) or 1) end
        end
    end
    bankCache = cache
end
ns.ScanBank = scanBank

-- Пересчёт состояния всех writs.
function ns.Refresh()
    local profs = ns.GetPlayerProfessions()
    local active = ns.GetActiveQuests()
    local state = {}
    for _, w in ipairs(ns.WRITS or {}) do
        local s = {}
        -- варианты рецепта (dual-prof writs): берём доступные персонажу
        local variants = w.variants or { { skill = w.skill, spellId = w.spellId, learnedat = w.learnedat, creates = w.creates, reagents = w.reagents, colors = w.colors } }
        local known, best = false, nil
        for _, v in ipairs(variants) do
            local hasProf = profs[v.skill] ~= nil
            local k = ns.IsRecipeKnown(v.spellId)
            if k then known = true end
            if hasProf and (not best or (k and not best.known)) then
                best = { v = v, hasProf = hasProf, known = k, prof = profs[v.skill] }
            end
        end
        if not best then best = { v = variants[1], hasProf = false, known = false } end
        s.variant = best.v
        s.hasProf = best.hasProf
        s.known = known
        s.profRank = best.prof and best.prof.rank or 0
        s.canLearn = best.prof and best.v.learnedat and best.prof.rank >= best.v.learnedat
        s.active = active[w.questId] ~= nil
        s.doneToday = ns.IsQuestDoneToday(w.questId) or (ns.Daily and ns.Daily.LockSeconds(w.questId) ~= nil)
        s.lockSeconds = ns.Daily and ns.Daily.LockSeconds(w.questId) or nil
        s.zoneOk = ns.IsZoneAvailable(w)
        s.druidZone = ns.DRUID_ZONES[w.zone] == true
        -- writ-предмет в сумках/банке (для экономики: не надо покупать)
        s.writCount = ns.GetItemCount(w.writId)
        -- сколько реагентов в сумках+банке
        s.reagentCounts = {}
        if best.v.reagents then
            for _, r in ipairs(best.v.reagents) do
                s.reagentCounts[r[1]] = ns.GetItemCount(r[1])
            end
        end
        -- экономика (Auctionator)
        if ns.Pricing then
            local ok, p = pcall(ns.Pricing.Analyze, w, s)
            if ok then s.price = p end
        end
        state[w.writId] = s
    end
    ns.state = state
    ns.profs = profs
    return state
end

-- События
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("SKILL_LINES_CHANGED")
f:RegisterEvent("CHAT_MSG_SKILL")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("BAG_UPDATE")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
f:RegisterEvent("PLAYER_MONEY")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
pcall(f.RegisterEvent, f, "ITEM_DATA_LOAD_RESULT")

-- Coin Pouch: золото приходит не за квест, а при открытии pouch.
-- BAG_UPDATE (pouch исчез) приходит раньше PLAYER_MONEY — запоминаем pending.
local lastPouchCounts = {}
local lastMoney = nil
local pendingPouch = nil

local function pouchDelta()
    if not ns.POUCH_BY_TIER then return end
    for id, tier in pairs(ns.POUCH_BY_TIER) do
        local now = safe(GetItemCount, id, false) or 0
        local before = lastPouchCounts[id] or now
        if now < before then pendingPouch = tier end
        lastPouchCounts[id] = now
    end
end

local function afterRefresh()
    if ns.WindowRefresh then ns.WindowRefresh() end
    if ns.Broker then ns.Broker.Update() end
    if ns.MapPins and ns.MapPins.isEnabled() then
        local ok, err = pcall(ns.MapPins.render)
        if not ok then ns.MapPins.lastError = tostring(err) end
    end
end

-- Зональный алерт: готовые writs в текущей зоне.
local lastAlertMap, lastAlertTime = 0, 0
local function zoneAlert()
    if not (WritsTrackerDB and WritsTrackerDB.zoneAlert ~= false) then return end
    local mapId = C_Map and C_Map.GetBestMapForUnit and safe(C_Map.GetBestMapForUnit, "player")
    if not mapId or mapId <= 0 then return end
    local now = GetTime and GetTime() or 0
    if mapId == lastAlertMap and now - lastAlertTime < 120 then return end
    local ready = 0
    for _, w in ipairs(ns.WRITS or {}) do
        local s = ns.state and ns.state[w.writId]
        if s and not s.doneToday and s.known and w.mapId == mapId and w.coord then
            local haveAll = true
            if s.variant and s.variant.reagents then
                for _, r in ipairs(s.variant.reagents) do
                    if (s.reagentCounts[r[1]] or 0) < r[2] then haveAll = false; break end
                end
            end
            if haveAll then ready = ready + 1 end
        end
    end
    if ready > 0 then
        lastAlertMap, lastAlertTime = mapId, now
        local info = C_Map.GetMapInfo and safe(C_Map.GetMapInfo, mapId)
        print(("|cff33ff99WritsTracker|r: %d готовых writs в зоне %s — можно сдать!"):format(ready, info and info.name or ("map " .. mapId)))
    end
end

f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "PLAYER_LOGIN" then
        WritsTrackerDB = WritsTrackerDB or {}
        DB = WritsTrackerDB
        DB.filters = DB.filters or {}
        buildIndexes()
        if ns.Daily then
            ns.Daily.PruneLocks()
            ns.Daily.ApplyLearned()
        end
        ns.Refresh()
        if ns.Tooltip then ns.Tooltip.Init() end
        if ns.BuildWindow then ns.BuildWindow() end
        if ns.Broker then
            ns.Broker.InitLDB()
            ns.Broker.InitMinimap()
            if DB.minimapShown == false then ns.Broker.SetMinimapShown(false) end
            ns.Broker.Update()
        end
        if ns.MapPins then
            local on = DB.filters.pins
            if on == nil then on = true end
            ns.MapPins.setEnabled(on)
        end
        lastMoney = GetMoney and GetMoney() or nil
        for id in pairs(ns.POUCH_BY_TIER or {}) do
            lastPouchCounts[id] = safe(GetItemCount, id, false) or 0
        end
        print("|cff33ff99WritsTracker|r: /wt — окно, /wt scan, /wt pins, /wt export. Writs: " .. #(ns.WRITS or {}))
        return
    end
    if event == "QUEST_TURNED_IN" then
        local questId = arg1
        if ns.Daily and ns.WRIT_BY_QUEST and ns.WRIT_BY_QUEST[questId] then
            ns.Daily.MarkTurnedIn(questId)
        end
        ns.Refresh()
        afterRefresh()
        return
    end
    if event == "QUEST_COMPLETE" then
        if ns.Daily then pcall(ns.Daily.TryLearnLocation) end
        return
    end
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        scanBank()
        ns.Refresh()
        afterRefresh()
        return
    end
    if event == "BANKFRAME_CLOSED" then
        bankOpen = false
        return
    end
    if event == "PLAYERBANKSLOTS_CHANGED" then
        if bankOpen then scanBank() end
        return
    end
    if event == "PLAYER_MONEY" then
        local now = GetMoney and GetMoney() or nil
        if pendingPouch and now and lastMoney and now > lastMoney then
            ns.Pricing.RecordPouch(pendingPouch, now - lastMoney)
        end
        pendingPouch = nil
        lastMoney = now
        return
    end
    if event == "ZONE_CHANGED_NEW_AREA" then
        zoneAlert()
        return
    end
    if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        pouchDelta()
        if bankOpen then scanBank() end
        if ns.state and ns.UpdateCounts then ns.UpdateCounts() end
        if ns.WindowRefresh then ns.WindowRefresh() end
        if ns.Broker then ns.Broker.Update() end
        return
    end
    ns.Refresh()
    afterRefresh()
end)
ns.frame = f

SLASH_WRITS1 = "/writs"
SLASH_WRITS2 = "/wt"
SlashCmdList["WRITS"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "scan" then
        ns.Refresh()
        local known, active, done = 0, 0, 0
        for _, s in pairs(ns.state or {}) do
            if s.known then known = known + 1 end
            if s.active then active = active + 1 end
            if s.doneToday then done = done + 1 end
        end
        print(("|cff33ff99WritsTracker|r: всего %d, изучено %d, в журнале %d, сдано сегодня %d"):format(#(ns.WRITS or {}), known, active, done))
        if ns.WindowRefresh then ns.WindowRefresh() end
        return
    end
    if msg == "pins" then
        if ns.MapPins then
            local on = not ns.MapPins.isEnabled()
            ns.MapPins.setEnabled(on)
            WritsTrackerDB.filters = WritsTrackerDB.filters or {}
            WritsTrackerDB.filters.pins = on
            print("|cff33ff99WritsTracker|r: пины " .. (on and "включены" or "выключены") ..
                " (режим " .. tostring(ns.MapPins.mode) .. ", точек " .. tostring(ns.MapPins.count or 0) ..
                (ns.MapPins.lastError and (", ошибка: " .. ns.MapPins.lastError) or "") .. ")")
        end
        return
    end
    if msg == "selftest" then
        -- Прогон чек-листа в игре, результат в WritsTrackerDB.selftest (читается из файла).
        local r = { ts = date and date("%Y-%m-%d %H:%M:%S") or "?", char = UnitName and UnitName("player") or "?" }
        local function check(name, fn)
            local ok, val = pcall(fn)
            r[name] = ok and val or ("ERR: " .. tostring(val))
        end
        check("writsCount", function() return #(ns.WRITS or {}) end)
        check("withCoord", function()
            local n = 0
            for _, w in ipairs(ns.WRITS or {}) do if w.coord then n = n + 1 end end
            return n
        end)
        check("level", function() return UnitLevel("player") end)
        check("profs", function()
            local t = {}
            for skill, p in pairs(ns.GetPlayerProfessions()) do t[#t + 1] = skill .. ":" .. p.name .. ":" .. p.rank end
            return table.concat(t, ", ")
        end)
        check("api", function()
            return ("IsPlayerSpell=%s IsQuestFlaggedCompleted=%s C_QuestLog=%s GetProfessions=%s TooltipDataProcessor=%s Auctionator=%s LDB=%s")
                :format(tostring(IsPlayerSpell ~= nil), tostring(IsQuestFlaggedCompleted ~= nil),
                    tostring(C_QuestLog ~= nil), tostring(GetProfessions ~= nil),
                    tostring(TooltipDataProcessor ~= nil), tostring(Auctionator ~= nil),
                    tostring(_G.LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true) ~= nil))
        end)
        check("knownSample", function()
            local t = {}
            for i = 1, math.min(8, #(ns.WRITS or {})) do
                local w = ns.WRITS[i]
                local s = ns.state and ns.state[w.writId]
                t[#t + 1] = w.writId .. ":" .. tostring(s and s.known) .. ":" .. tostring(ns.IsRecipeKnown(w.spellId))
            end
            return table.concat(t, ", ")
        end)
        check("knownTotal", function()
            local n = 0
            for _, s in pairs(ns.state or {}) do if s.known then n = n + 1 end end
            return n
        end)
        check("doneToday", function()
            local n = 0
            for _, s in pairs(ns.state or {}) do if s.doneToday then n = n + 1 end end
            return n
        end)
        check("dailyLocks", function()
            local n = 0
            for _ in pairs(WritsTrackerCharDB and WritsTrackerCharDB.locks or {}) do n = n + 1 end
            return n
        end)
        check("pricing", function()
            if not ns.Pricing.IsAvailable() then return "no Auctionator" end
            local w = ns.WRITS[1]
            local p = ns.Pricing.Analyze(w, ns.state and ns.state[w.writId])
            return ("avail=%s cpr=%s rating=%s craft=%s buy=%s writ=%s"):format(
                tostring(p.available), tostring(p.cpr), tostring(p.rating),
                tostring(p.craftCost), tostring(p.buyItem), tostring(p.writPrice))
        end)
        check("broker", function()
            local d, t, tier = ns.Broker.Counts()
            return ("%d/%d %s ldb=%s minimap=%s"):format(d, t, tostring(tier),
                tostring(ns.Broker.ldb ~= nil), tostring(ns.Broker.minimapBtn ~= nil))
        end)
        check("pins", function()
            return ("mode=%s count=%s err=%s"):format(tostring(ns.MapPins.mode),
                tostring(ns.MapPins.count), tostring(ns.MapPins.lastError))
        end)
        check("tooltipHooked", function() return tostring(ns.Tooltip.hooked) end)
        check("windowShown", function()
            return tostring(WritsTrackerFrame and WritsTrackerFrame:IsShown())
        end)
        check("filteredCount", function()
            return #(ns.GetFilteredWrits and ns.GetFilteredWrits() or {})
        end)
        check("bankCount", function()
            local id = ns.WRITS[1].creates and ns.WRITS[1].creates[1]
            if not id then return "n/a" end
            local bags = GetItemCount and GetItemCount(id, false) or 0
            local total = GetItemCount and GetItemCount(id, true) or 0
            return ("item=%d bags=%d total=%d"):format(id, bags, total)
        end)
        check("repFaction", function()
            local fid = UnitFactionGroup and UnitFactionGroup("player") == "Alliance" and 2586 or 2587
            if C_Reputation and C_Reputation.GetFactionDataByID then
                local ok, d = pcall(C_Reputation.GetFactionDataByID, fid)
                if ok and d and d.name then return d.name .. " standing=" .. tostring(d.currentStanding) end
            end
            if GetFactionInfoByID then
                local ok, name, _, standing, barMin, barMax, barValue = pcall(GetFactionInfoByID, fid)
                if ok and name then return name .. " " .. tostring(barValue) .. "/" .. tostring(barMax) end
            end
            return "no rep API"
        end)
        WritsTrackerDB.selftest = r
        print("|cff33ff99WritsTracker|r: selftest записан в SavedVariables (" .. tostring(r.char) .. ")")
        return
    end
    if msg == "export" then
        if ns.Daily then ns.Daily.Export() end
        return
    end
    if msg == "minimap" then
        if ns.Broker then
            local on = WritsTrackerDB.minimapShown == false
            ns.Broker.SetMinimapShown(on)
            print("|cff33ff99WritsTracker|r: кнопка у миникарты " .. (on and "включена" or "выключена"))
        end
        return
    end
    if msg == "shop" then
        if ns.Shopping then ns.Shopping.CreateList() end
        return
    end
    if msg == "debug" then
        local profs = ns.GetPlayerProfessions()
        for skill, p in pairs(profs) do
            print(("профессия %d: %s %d/%d"):format(skill, p.name, p.rank, p.max))
        end
        local w = ns.WRITS and ns.WRITS[1]
        if w then
            print(("тест known: %s spell=%d known=%s done=%s zoneOk=%s"):format(w.name, w.spellId or 0, tostring(ns.IsRecipeKnown(w.spellId)), tostring(ns.IsQuestDoneToday(w.questId)), tostring(ns.IsZoneAvailable(w))))
        end
        print("IsPlayerSpell=" .. tostring(IsPlayerSpell ~= nil) .. " IsQuestFlaggedCompleted=" .. tostring(IsQuestFlaggedCompleted ~= nil) .. " C_QuestLog=" .. tostring(C_QuestLog ~= nil))
        if ns.MapPins then
            print("пины: режим=" .. tostring(ns.MapPins.mode) .. " точек=" .. tostring(ns.MapPins.count or 0) .. " ошибка=" .. tostring(ns.MapPins.lastError))
        end
        local withCoord = 0
        for _, w in ipairs(ns.WRITS or {}) do if w.coord then withCoord = withCoord + 1 end end
        print("writs с координатами: " .. withCoord .. "/" .. #(ns.WRITS or {}))
        return
    end
    if ns.ToggleWindow then ns.ToggleWindow() end
end