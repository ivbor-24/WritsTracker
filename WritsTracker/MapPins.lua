-- WritsTracker: пины точек сдачи writs на world map + миникарте.
-- Подход TaurenGuide/MapPins: HereBeDragons-Pins (MINOR 18, гард MAP_CANVAS_OK),
-- classic-фолбэк для старого WorldMapFrame без MapCanvas. Всё в pcall.
local ADDON, ns = ...

ns.MapPins = { mode = nil, lastError = nil }

local PINS_MAJOR = "HereBeDragons-Pins-2.0"
local worldPins, miniPins = {}, {}
local classicPoints = {}
local classicListener
local pinsEnabled = true

local function getLib(major)
    if not _G.LibStub then return nil end
    return LibStub(major, true)
end

-- Пин: иконка writ-предмета + рамка цвета тира.
local function makePin()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(20, 20)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 2, -2)
    f.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetAllPoints()
    f.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    f:Hide()
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not self.info then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.info.title or "Writ", 1, 0.82, 0)
        if self.info.lines then
            for _, l in ipairs(self.info.lines) do
                GameTooltip:AddLine(l, 0.9, 0.9, 0.9)
            end
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    return f
end

local function ensurePools(n)
    for i = #worldPins + 1, n do
        worldPins[i] = makePin()
        miniPins[i] = makePin()
    end
end

local TIER_RGB = {
    Journeyman = { 0.44, 0.83, 1 },
    Expert = { 0.12, 1, 0 },
    Artisan = { 0.64, 0.21, 0.93 },
}

local function setPin(f, w, s)
    f.tex:SetTexture(ns.GetItemIcon(w.writId))
    local rgb = TIER_RGB[w.tier] or { 1, 1, 1 }
    f.border:SetVertexColor(rgb[1], rgb[2], rgb[3])
    local lines = {}
    lines[#lines + 1] = ("Сдать: %s (%s)"):format(w.npc or "?", w.zone or "?")
    if w.coord then
        lines[#lines + 1] = ("Координаты: %.1f, %.1f"):format(w.coord[1], w.coord[2])
    end
    if s then
        if s.doneToday then lines[#lines + 1] = "|cff808080Сдан сегодня|r" end
        if s.active then lines[#lines + 1] = "|cffffff00В журнале|r" end
        if s.known then lines[#lines + 1] = "|cff33ff33Рецепт изучен|r"
        else lines[#lines + 1] = "|cffff6060Рецепт не изучен|r" end
    end
    f.info = { title = w.name, lines = lines }
end

-- Точки для пинов: writs с координатами, прошедшие фильтры окна (если открыто),
-- иначе все известные точки. Сданные сегодня прячем.
local function collectPoints()
    local pts = {}
    local state = ns.state or {}
    local list = ns.GetFilteredWrits and ns.GetFilteredWrits() or ns.WRITS
    for _, w in ipairs(list or {}) do
        local s = state[w.writId]
        if w.coord and w.mapId and not (s and s.doneToday) then
            pts[#pts + 1] = { w = w, s = s, mapId = w.mapId, x = w.coord[1] / 100, y = w.coord[2] / 100 }
        end
    end
    return pts
end

-- ---------------------------------------------------------------------------
-- Classic-фолбэк (старый WorldMapFrame без MapCanvas)
-- ---------------------------------------------------------------------------

local function displayedMapId()
    if not WorldMapFrame then return nil end
    local ok, id = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
    if ok and id then return id end
    if C_Map and C_Map.GetBestMapForUnit then
        ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then return id end
    end
    return nil
end

local function hideWorldPins()
    for i = 1, #worldPins do worldPins[i]:Hide() end
end

local function classicRedraw()
    if ns.MapPins.mode ~= "classic" then return end
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        hideWorldPins()
        return
    end
    local parent = WorldMapDetailFrame or WorldMapFrame
    local mapId = displayedMapId()
    for i, c in ipairs(classicPoints) do
        local f = worldPins[i]
        if not f then break end
        if c.mapId == mapId then
            f:SetParent(parent)
            f:ClearAllPoints()
            f:SetPoint("CENTER", parent, "TOPLEFT",
                parent:GetWidth() * c.x, -parent:GetHeight() * c.y)
            f:SetFrameLevel(parent:GetFrameLevel() + 5)
            f:Show()
        else
            f:Hide()
        end
    end
end

local function classicEnsureListener()
    if classicListener then return end
    classicListener = CreateFrame("Frame")
    classicListener:SetScript("OnEvent", function()
        local ok, err = pcall(classicRedraw)
        if not ok then ns.MapPins.lastError = tostring(err) end
    end)
    pcall(function() classicListener:RegisterEvent("WORLD_MAP_UPDATE") end)
    if WorldMapFrame then
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", function()
            local ok, err = pcall(classicRedraw)
            if not ok then ns.MapPins.lastError = tostring(err) end
        end)
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnHide", hideWorldPins)
    end
end

local function libWorldMapOK(Pins)
    if not Pins then return false end
    if Pins.MAP_CANVAS_OK ~= nil then return Pins.MAP_CANVAS_OK end
    return not not (WorldMapFrame and WorldMapFrame.GetCanvas
        and WorldMapFrame.pinPools and WorldMapFrame.AddDataProvider)
end

-- ---------------------------------------------------------------------------
-- Основной вход
-- ---------------------------------------------------------------------------

function ns.MapPins.render()
    local Pins = getLib(PINS_MAJOR)
    if Pins then
        pcall(function() Pins:RemoveAllWorldMapIcons(ADDON) end)
        pcall(function() Pins:RemoveAllMinimapIcons(ADDON) end)
    end
    if not pinsEnabled then
        hideWorldPins()
        for i = 1, #miniPins do miniPins[i]:Hide() end
        return
    end

    local pts = collectPoints()
    ensurePools(#pts)

    -- Миникарта: только точки текущей зоны игрока (либа сама фильтрует по mapId).
    if Pins then
        for i, c in ipairs(pts) do
            setPin(miniPins[i], c.w, c.s)
            local ok, err = pcall(function()
                Pins:AddMinimapIconMap(ADDON, miniPins[i], c.mapId, c.x, c.y, true, true)
            end)
            if not ok then ns.MapPins.lastError = tostring(err) end
        end
    else
        ns.MapPins.lastError = PINS_MAJOR .. " не загружен"
    end

    if libWorldMapOK(Pins) then
        ns.MapPins.mode = "lib"
        local showFlag = _G.HBD_PINS_WORLDMAP_SHOW_CONTINENT
        for i, c in ipairs(pts) do
            setPin(worldPins[i], c.w, c.s)
            local ok, err = pcall(function()
                Pins:AddWorldMapIconMap(ADDON, worldPins[i], c.mapId, c.x, c.y, showFlag)
            end)
            if not ok then ns.MapPins.lastError = tostring(err) end
        end
    else
        ns.MapPins.mode = "classic"
        classicPoints = pts
        for i, c in ipairs(pts) do setPin(worldPins[i], c.w, c.s) end
        classicEnsureListener()
        local ok, err = pcall(classicRedraw)
        if not ok then ns.MapPins.lastError = tostring(err) end
    end

    for i = #pts + 1, #worldPins do
        worldPins[i]:Hide()
        miniPins[i]:Hide()
    end
    ns.MapPins.count = #pts
end

function ns.MapPins.setEnabled(on)
    pinsEnabled = on and true or false
    local ok, err = pcall(ns.MapPins.render)
    if not ok then ns.MapPins.lastError = tostring(err) end
end

function ns.MapPins.isEnabled()
    return pinsEnabled
end