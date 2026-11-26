-- WritsTracker: дейли-локи с таймером до ресета, самообучение точек сдачи, экспорт.
local ADDON, ns = ...

ns.Daily = {}
local D = ns.Daily

local function charDB()
    WritsTrackerCharDB = WritsTrackerCharDB or {}
    WritsTrackerCharDB.locks = WritsTrackerCharDB.locks or {}
    return WritsTrackerCharDB
end

local function secondsUntilReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local ok, s = pcall(C_DateAndTime.GetSecondsUntilDailyReset)
        if ok and type(s) == "number" and s > 0 then return s end
    end
    if GetQuestResetTime then
        local ok, s = pcall(GetQuestResetTime)
        if ok and type(s) == "number" and s > 0 then return s end
    end
    return 86400
end

-- QUEST_TURNED_IN: записать лок до ресета.
function D.MarkTurnedIn(questId)
    if not questId then return end
    local cdb = charDB()
    cdb.locks[questId] = time() + secondsUntilReset()
end

-- Сколько секунд до разлока (nil = не сдан сегодня).
function D.LockSeconds(questId)
    local cdb = WritsTrackerCharDB
    local untilTs = cdb and cdb.locks and cdb.locks[questId]
    if not untilTs then return nil end
    local left = untilTs - time()
    if left <= 0 then
        cdb.locks[questId] = nil
        return nil
    end
    return left
end

function D.PruneLocks()
    local cdb = WritsTrackerCharDB
    if not cdb or not cdb.locks then return end
    local now = time()
    for q, ts in pairs(cdb.locks) do
        if type(ts) ~= "number" or ts <= now then cdb.locks[q] = nil end
    end
end

function D.FormatLock(sec)
    sec = math.max(60, math.floor(sec or 0))
    if SecondsToTime then
        local ok, txt = pcall(SecondsToTime, sec, true)
        if ok and type(txt) == "string" and txt ~= "" then return txt end
    end
    return ("%dч %02dм"):format(math.floor(sec / 3600), math.floor((sec % 3600) / 60))
end

-- ---------------------------------------------------------------------------
-- Самообучение точек сдачи: QUEST_COMPLETE у NPC, если у writ нет координат.
-- ---------------------------------------------------------------------------

function D.TryLearnLocation()
    if not GetQuestID then return end
    local ok, qid = pcall(GetQuestID)
    if not ok or not qid then return end
    local w = ns.WRIT_BY_QUEST and ns.WRIT_BY_QUEST[qid]
    if not w or (w.coord and w.mapId) then return end

    local npcName, npcId = nil, 0
    if UnitExists and UnitExists("npc") then
        npcName = UnitName and UnitName("npc") or nil
        local guid = UnitGUID and UnitGUID("npc") or nil
        if guid then
            local unitType, _, _, _, _, idStr = strsplit("-", guid)
            if unitType == "Creature" or unitType == "Vehicle" then
                npcId = tonumber(idStr) or 0
            end
        end
    end
    local mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    if not mapId or mapId <= 0 then return end
    local x, y
    if C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(mapId, "player")
        if pos then
            if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
        end
    end
    if not x or not y or (x == 0 and y == 0) then return end
    x = math.floor(x * 1000 + 0.5) / 10
    y = math.floor(y * 1000 + 0.5) / 10

    WritsTrackerDB = WritsTrackerDB or {}
    WritsTrackerDB.learned = WritsTrackerDB.learned or {}
    WritsTrackerDB.learned[qid] = { npcId = npcId, npcName = npcName, mapId = mapId, x = x, y = y, ts = time() }

    -- сразу применяем к живой базе
    w.coord = { x, y }
    w.mapId = mapId
    if npcName and (not w.npc or w.npc == "-") then w.npc = npcName end
    if npcId > 0 then w.npcId = npcId end
    w.handinSrc = "learned"
    local mapName = C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
    if mapName and mapName.name and (not w.zone or w.zone == "-") then w.zone = mapName.name end

    print(("|cff33ff99WritsTracker|r: выучена точка %s — %s, %s (%.1f, %.1f). /writs export — поделиться."):format(
        w.name, npcName or "NPC", w.zone or ("map " .. mapId), x, y))
    if ns.WindowRefresh then ns.WindowRefresh() end
    if ns.MapPins then pcall(ns.MapPins.render) end
end

-- Применить выученные точки при логине.
function D.ApplyLearned()
    local learned = WritsTrackerDB and WritsTrackerDB.learned
    if not learned then return end
    for _, w in ipairs(ns.WRITS or {}) do
        local rec = learned[w.questId]
        if rec and rec.mapId and rec.x and not (w.coord and w.mapId) then
            w.coord = { rec.x, rec.y }
            w.mapId = rec.mapId
            if rec.npcName and (not w.npc or w.npc == "-") then w.npc = rec.npcName end
            if rec.npcId and rec.npcId > 0 then w.npcId = rec.npcId end
            w.handinSrc = "learned"
        end
    end
end

-- Экспорт выученного в чат (для передачи в БД).
function D.Export()
    local learned = WritsTrackerDB and WritsTrackerDB.learned
    if not learned or not next(learned) then
        print("|cff33ff99WritsTracker|r: выученных точек нет.")
        return
    end
    for qid, rec in pairs(learned) do
        local w = ns.WRIT_BY_QUEST and ns.WRIT_BY_QUEST[qid]
        print(("|cff33ff99WT-EXPORT|r quest=%d writ=%d npc=%d name=%s map=%d x=%.1f y=%.1f"):format(
            qid, w and w.writId or 0, rec.npcId or 0, rec.npcName or "?", rec.mapId, rec.x, rec.y))
    end
end