-- WritsTracker: список покупок в Auctionator (реагенты для выбранных writs)
-- + waypoint по клику (C_Map.SetUserWaypoint / TomTom).
local ADDON, ns = ...

ns.Shopping = {}
local S = ns.Shopping

-- Суммирует недостающие реагенты по writs (фильтр окна или выбранный writ).
-- Возвращает {[itemId] = count}, список имён.
function S.CollectNeeds(writs)
    local needs = {}
    local state = ns.state or {}
    for _, w in ipairs(writs or {}) do
        local s = state[w.writId]
        local v = s and s.variant
        if s and s.known and v and v.reagents and not s.doneToday then
            for _, r in ipairs(v.reagents) do
                local have = s.reagentCounts and s.reagentCounts[r[1]] or 0
                local missing = math.max(0, r[2] - have)
                if missing > 0 then
                    needs[r[1]] = (needs[r[1]] or 0) + missing
                end
            end
        end
    end
    return needs
end

-- Создать список в Auctionator: недостающие реагенты всех writs окна.
function S.CreateList()
    local a = Auctionator and Auctionator.API and Auctionator.API.v1
    if not a or type(a.CreateShoppingList) ~= "function" or type(a.ConvertToSearchString) ~= "function" then
        print("|cff33ff99WritsTracker|r: Auctionator не найден — список покупок недоступен.")
        return
    end
    local writs = ns.GetFilteredWrits and ns.GetFilteredWrits() or ns.WRITS
    local needs = S.CollectNeeds(writs)
    if not next(needs) then
        print("|cff33ff99WritsTracker|r: нечего докупать — реагенты в наличии (или рецепты не изучены).")
        return
    end
    local terms = {}
    for id, count in pairs(needs) do
        local name = ns.GetItemName(id)
        if name then
            local ok, term = pcall(a.ConvertToSearchString, "WritsTracker", { searchString = name, quantity = count })
            if ok and term then terms[#terms + 1] = term end
        end
    end
    if #terms == 0 then
        print("|cff33ff99WritsTracker|r: не удалось собрать поисковые строки.")
        return
    end
    local listName = "Writs " .. date("%H:%M")
    local ok, err = pcall(a.CreateShoppingList, "WritsTracker", listName, terms)
    if ok then
        print(("|cff33ff99WritsTracker|r: список «%s» создан в Auctionator (%d позиций)."):format(listName, #terms))
    else
        print("|cff33ff99WritsTracker|r: ошибка списка: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Waypoint
-- ---------------------------------------------------------------------------

ns.Waypoint = {}
local W = ns.Waypoint

function W.Set(w)
    if not w or not w.coord or not w.mapId then
        print("|cff33ff99WritsTracker|r: у этого writ нет координат точки сдачи.")
        return false
    end
    local x, y = w.coord[1] / 100, w.coord[2] / 100
    local title = (w.npc or "Сдача") .. " — " .. (w.zone or "")
    -- TomTom если стоит
    if TomTom and type(TomTom.AddWaypoint) == "function" then
        local ok = pcall(TomTom.AddWaypoint, TomTom, w.mapId, x, y, { title = title, persistent = false, minimap = true, world = true })
        if ok then
            print(("|cff33ff99WritsTracker|r: waypoint (TomTom): %s (%.1f, %.1f)"):format(title, w.coord[1], w.coord[2]))
            return true
        end
    end
    -- Blizzard user waypoint + supertrack
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(w.mapId, x, y))
        if ok then
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            end
            print(("|cff33ff99WritsTracker|r: waypoint: %s (%.1f, %.1f)"):format(title, w.coord[1], w.coord[2]))
            return true
        end
    end
    print("|cff33ff99WritsTracker|r: нет API waypoint (TomTom/C_Map).")
    return false
end