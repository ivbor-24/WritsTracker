-- WritsTracker: кнопка у миникарты + LibDataBroker-объект для Bazooka.
-- Счётчик: сдано сегодня / доступно writs максимального доступного тира
-- (по профессиям персонажа и уровню). Клик — окно, ПКМ — scan.
local ADDON, ns = ...

ns.Broker = {}
local B = ns.Broker

local TIER_REQLEVEL = { Journeyman = 10, Expert = 20, Artisan = 35 }
local TIER_ORDER = { Journeyman = 1, Expert = 2, Artisan = 3 }

-- Максимальный тир, доступный персонажу по уровню.
local function maxTierForLevel()
    local lvl = UnitLevel("player") or 1
    if lvl >= 35 then return "Artisan" end
    if lvl >= 20 then return "Expert" end
    return "Journeyman"
end

-- Счётчики: writs максимального доступного тира по моим профессиям.
-- done = сдано сегодня (лок или IsQuestFlaggedCompleted), total = всего таких writs.
function B.Counts()
    local state = ns.state or {}
    local profs = ns.profs or {}
    local maxTier = maxTierForLevel()
    local maxOrder = TIER_ORDER[maxTier]
    local done, total = 0, 0
    local doneAll, totalAll = 0, 0
    for _, w in ipairs(ns.WRITS or {}) do
        local s = state[w.writId]
        local mine = (not next(profs)) or (s and s.hasProf)
        local isDone = (s and s.doneToday) or ns.Daily.LockSeconds(w.questId) ~= nil
        if mine then
            totalAll = totalAll + 1
            if isDone then doneAll = doneAll + 1 end
            local order = TIER_ORDER[w.tier] or 0
            if order == maxOrder then
                total = total + 1
                if isDone then done = done + 1 end
            end
        end
    end
    return done, total, maxTier, doneAll, totalAll
end

function B.Text()
    local done, total, maxTier = B.Counts()
    local color = (total > 0 and done >= total) and "|cff5fbf73" or "|cffffd100"
    return ("%s%d/%d|r"):format(color, done, total)
end

local function tooltipLines()
    local done, total, maxTier, doneAll, totalAll = B.Counts()
    local lines = {}
    lines[#lines + 1] = ("|cffffd100Craftsman's Writs|r — %s (ур. %d+)"):format(maxTier, TIER_REQLEVEL[maxTier])
    lines[#lines + 1] = ("Сдано сегодня: %s%d/%d|r writs %s тира"):format(
        (done >= total and total > 0) and "|cff5fbf73" or "|cffffffff", done, total, maxTier)
    lines[#lines + 1] = ("Всего по моим профессиям: %d/%d (все тиры)"):format(doneAll, totalAll)
    -- разбивка по тирам
    local state = ns.state or {}
    local profs = ns.profs or {}
    for _, tier in ipairs({ "Journeyman", "Expert", "Artisan" }) do
        local d, t = 0, 0
        for _, w in ipairs(ns.WRITS or {}) do
            if w.tier == tier then
                local s = state[w.writId]
                if (not next(profs)) or (s and s.hasProf) then
                    t = t + 1
                    if (s and s.doneToday) or ns.Daily.LockSeconds(w.questId) ~= nil then d = d + 1 end
                end
            end
        end
        if t > 0 then
            lines[#lines + 1] = ("  %s: %d/%d"):format(tier, d, t)
        end
    end
    lines[#lines + 1] = "|cff888888ЛКМ — окно, ПКМ — пересчитать|r"
    return lines
end

local function showTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    for i, l in ipairs(tooltipLines()) do
        if i == 1 then GameTooltip:AddLine(l) else GameTooltip:AddLine(l, 0.9, 0.9, 0.9) end
    end
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- LDB-объект (Bazooka подхватывает через LibDataBroker_DataObjectCreated)
-- ---------------------------------------------------------------------------

local ldbObj

function B.InitLDB()
    if not _G.LibStub then return end
    local LDB = LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    if ldbObj then return end
    ldbObj = LDB:NewDataObject("WritsTracker", {
        type = "data source",
        text = B.Text(),
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        label = "Writs",
        OnClick = function(_, button)
            if button == "RightButton" then
                ns.Refresh()
                if ns.WindowRefresh then ns.WindowRefresh() end
            else
                if ns.ToggleWindow then ns.ToggleWindow() end
            end
        end,
        OnTooltipShow = function(tt)
            for i, l in ipairs(tooltipLines()) do
                if i == 1 then tt:AddLine(l) else tt:AddLine(l, 0.9, 0.9, 0.9) end
            end
        end,
    })
    ns.Broker.ldb = ldbObj
end

function B.Update()
    if ldbObj then
        ldbObj.text = B.Text()
    end
    if B.minimapBtn then
        B.minimapBtn.text:SetText(B.Text())
    end
end

-- ---------------------------------------------------------------------------
-- Кнопка у миникарты (без LibDBIcon — свой фрейм, draggable по кругу)
-- ---------------------------------------------------------------------------

local function minimapPos(angle)
    local r = 80
    return math.cos(math.rad(angle)) * r, math.sin(math.rad(angle)) * r
end

function B.InitMinimap()
    if B.minimapBtn then return end
    if not Minimap then return end
    local db = WritsTrackerDB or {}
    db.minimapAngle = db.minimapAngle or 220

    local btn = CreateFrame("Button", "WritsTrackerMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    btn.border = border

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("BOTTOM", btn, "BOTTOM", 0, -2)
    text:SetFontObject("GameFontNormalSmall")
    btn.text = text

    local function place()
        local x, y = minimapPos(db.minimapAngle)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    place()

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            place()
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.Refresh()
            if ns.WindowRefresh then ns.WindowRefresh() end
        else
            if ns.ToggleWindow then ns.ToggleWindow() end
        end
    end)
    btn:SetScript("OnEnter", function(self) showTooltip(self) end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    B.minimapBtn = btn
    B.Update()
end

function B.SetMinimapShown(on)
    WritsTrackerDB = WritsTrackerDB or {}
    WritsTrackerDB.minimapShown = on and true or false
    if B.minimapBtn then
        if on then B.minimapBtn:Show() else B.minimapBtn:Hide() end
    end
end