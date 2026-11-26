-- WritsTracker: окно со списком writs, фильтры, тултипы, shift-click в аукцион.
local ADDON, ns = ...

local WT = ns.WT
local ROW_H = 72
local WINDOW_W, WINDOW_H = 860, 600

local main, scrollChild, rows = nil, nil, {}
local filterWidgets = {}

local PROF_ORDER = { "Engineering", "Leatherworking", "Alchemy", "Blacksmithing", "Tailoring" }
local PROF_LABEL = {
    Engineering = "Инжа", Leatherworking = "Кожевник", Alchemy = "Алхимия",
    Blacksmithing = "Кузнец", Tailoring = "Портной",
}
local TIER_ORDER = { Journeyman = 1, Expert = 2, Artisan = 3 }
local TIER_COLOR = {
    Journeyman = "|cff71d5ff", Expert = "|cff1eff00", Artisan = "|cffa335ee",
}

local function db()
    WritsTrackerDB = WritsTrackerDB or {}
    WritsTrackerDB.filters = WritsTrackerDB.filters or {
        prof = "auto", known = "all", zone = "all",
        hideDruid = true, hideDone = false, sort = "prof", text = "", pins = true,
    }
    if WritsTrackerDB.filters.pins == nil then WritsTrackerDB.filters.pins = true end
    return WritsTrackerDB.filters
end

-- Список writs после фильтров и сортировки
local function FilteredWrits()
    local f = db()
    local state = ns.state or {}
    local profs = ns.profs or {}
    local list = {}
    local text = (f.text or ""):lower()
    for _, w in ipairs(ns.WRITS or {}) do
        local s = state[w.writId] or {}
        local prof = w.prof
        if f.prof == "auto" then
            -- авто: профессии персонажа; если нет ни одной — все
            if next(profs) and not s.hasProf then prof = nil end
        elseif f.prof ~= "all" and prof ~= f.prof then
            prof = nil
        end
        if prof then
            if f.known == "known" and not s.known then prof = nil end
            if f.known == "unknown" and s.known then prof = nil end
        end
        if prof and f.zone == "mine" and not s.zoneOk then prof = nil end
        if prof and f.zone == "notmine" and s.zoneOk then prof = nil end
        if prof and f.hideDruid and s.druidZone then prof = nil end
        if prof and f.hideDone and s.doneToday then prof = nil end
        if prof and text ~= "" then
            local hay = (w.name .. " " .. (w.zone or "") .. " " .. (w.npc or "")):lower()
            if not hay:find(text, 1, true) then prof = nil end
        end
        -- фильтр тира
        if prof and f.tier and f.tier ~= "all" and w.tier ~= f.tier then prof = nil end
        -- фильтр статуса: ready = знаю + реагенты хватает + не сдан; missing = не хватает
        if prof and f.status and f.status ~= "all" then
            local ready = s.known and not s.doneToday
            if ready and s.variant and s.variant.reagents then
                for _, r in ipairs(s.variant.reagents) do
                    if (s.reagentCounts and s.reagentCounts[r[1]] or 0) < r[2] then ready = false; break end
                end
            end
            if f.status == "ready" and not ready then prof = nil end
            if f.status == "missing" and (ready or s.doneToday) then prof = nil end
            if f.status == "done" and not s.doneToday then prof = nil end
        end
        if prof then list[#list + 1] = w end
    end
    local sort = f.sort or "prof"
    table.sort(list, function(a, b)
        if sort == "zone" then
            if a.zone ~= b.zone then return (a.zone or "") < (b.zone or "") end
        elseif sort == "skill" then
            local sa = a.learnedat or 0
            local sb = b.learnedat or 0
            if sa ~= sb then return sa < sb end
        elseif sort == "name" then
            return a.name < b.name
        elseif sort == "cpr" then
            local sa = ns.state and ns.state[a.writId]
            local sb = ns.state and ns.state[b.writId]
            local ca = sa and sa.price and sa.price.cpr or 999999999
            local cb = sb and sb.price and sb.price.cpr or 999999999
            if ca ~= cb then return ca < cb end
        elseif sort == "rep" then
            local ra = ({ Journeyman = 75, Expert = 125, Artisan = 200 })[a.tier] or 0
            local rb = ({ Journeyman = 75, Expert = 125, Artisan = 200 })[b.tier] or 0
            if ra ~= rb then return ra > rb end
        elseif sort == "level" then
            local la, lb = a.writReqLevel or 0, b.writReqLevel or 0
            if la ~= lb then return la < lb end
        end
        local pa, pb = PROF_ORDER[a.prof] or 9, PROF_ORDER[b.prof] or 9
        if pa ~= pb then return pa < pb end
        local ta, tb = TIER_ORDER[a.tier] or 9, TIER_ORDER[b.tier] or 9
        if ta ~= tb then return ta < tb end
        return a.name < b.name
    end)
    return list
end

-- Экспорт для MapPins: пины следуют фильтрам окна.
ns.GetFilteredWrits = FilteredWrits

local function StatusBadges(w, s)
    local parts = {}
    if s.doneToday then
        if s.lockSeconds and ns.Daily then
            parts[#parts + 1] = "|cff808080[сдан, через " .. ns.Daily.FormatLock(s.lockSeconds) .. "]|r"
        else
            parts[#parts + 1] = "|cff808080[сдан сегодня]|r"
        end
    end
    if s.active then parts[#parts + 1] = "|cffffff00[в журнале]|r" end
    if s.known then
        parts[#parts + 1] = "|cff33ff33[знаю]|r"
    else
        parts[#parts + 1] = "|cffff6060[не знаю]|r"
    end
    if s.hasProf and s.variant and s.variant.learnedat then
        local color = (s.profRank or 0) >= s.variant.learnedat and "|cff33ff33" or "|cffff6060"
        parts[#parts + 1] = ("%sскилл %d/%d|r"):format(color, s.variant.learnedat, s.profRank or 0)
    end
    if s.price and s.price.available and s.price.cpr then
        parts[#parts + 1] = ns.Pricing.ShortLabel(s.price)
    end
    return table.concat(parts, " ")
end

local function ShowRecipeTooltip(self, w, s)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local v = s.variant
    local shown = false
    if v and v.spellId then
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. v.spellId)
    end
    if not shown and v and v.creates then
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. v.creates[1])
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("|cff33ff99Writ:|r %s"):format(w.name), 1, 1, 1)
    local rep = ({ Journeyman = 75, Expert = 125, Artisan = 200 })[w.tier] or 0
    GameTooltip:AddLine(("Репутация: |cff5fbf73+%d|r (%s)"):format(rep, w.tier or "?"), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(("Сдать: %s — %s"):format(w.npc or "?", w.zone or "?"), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(("Требует уровень %d (writ), скилл %d"):format(w.writReqLevel or 1, (s.variant and s.variant.learnedat) or w.learnedat or 0), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Клик по ингредиенту — его поиск в аукционе • СКМ — waypoint", 0.5, 0.8, 1)
    GameTooltip:Show()
end

local function MakeRow(i)
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(ROW_H)
    row:SetPoint("LEFT", scrollChild, "LEFT", 4, 0)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", -4, 0)
    row:RegisterForClicks("AnyUp")

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
    row.icon = icon

    local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    title:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    row.title = title

    local writBtn = CreateFrame("Button", nil, row)
    writBtn:SetSize(24, 24)
    writBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    local wt = writBtn:CreateTexture(nil, "ARTWORK")
    wt:SetAllPoints()
    writBtn.icon = wt
    writBtn:SetScript("OnEnter", function(self)
        if not self.writId then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.writId)
        GameTooltip:AddLine("Shift-клик — поиск writ на аукционе", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    writBtn:SetScript("OnLeave", GameTooltip_Hide)
    writBtn:RegisterForClicks("AnyUp")
    writBtn:SetScript("OnClick", function(self)
        if IsShiftKeyDown() and self.writId then
            ns.InsertLink(ns.GetItemLink(self.writId))
        end
    end)
    row.writBtn = writBtn

    local info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    info:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(false)
    row.info = info

    local reag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reag:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -4)
    reag:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    reag:SetJustifyH("LEFT")
    reag:SetWordWrap(false)
    row.reag = reag

    -- разделитель между строками
    local sep = row:CreateTexture(nil, "BACKGROUND")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetTexture("Interface\\Buttons\\WHITE8X8")
    sep:SetVertexColor(1, 1, 1, 0.08)
    row.sep = sep

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")

    row:SetScript("OnEnter", function(self)
        if self.writ then ShowRecipeTooltip(self, self.writ, self.state or {}) end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self, button)
        if not self.writ then return end
        local w = self.writ
        if button == "LeftButton" and IsShiftKeyDown() then
            local v = (self.state or {}).variant
            local id = v and v.creates and v.creates[1]
            if id then ns.InsertLink(ns.GetItemLink(id)) end
        elseif button == "RightButton" then
            -- правый клик: прямой поиск в Auctionator (если аукцион открыт), иначе ссылка
            local v = (self.state or {}).variant
            local name = v and v.creates and ns.GetItemName(v.creates[1])
            if name and ns.AuctionSearch(name) then return end
            local id = v and v.creates and v.creates[1]
            if id then ns.InsertLink(ns.GetItemLink(id)) end
        elseif button == "LeftButton" then
            -- обычный клик: выбрать writ (для кнопки Waypoint)
            if main then main.selectedWrit = w end
            if main and main.wpBtn then
                main.wpBtn:SetEnabled(w.coord and w.mapId and true or false)
            end
        elseif button == "MiddleButton" then
            if ns.Waypoint then ns.Waypoint.Set(w) end
        end
    end)
    return row
end

-- Реагенты: каждый ингредиент — отдельная кнопка-чип (клик = поиск именно его).
local REAG_MAX = 8

local function MakeReagChip(row, idx)
    local chip = CreateFrame("Button", nil, row)
    chip:SetHeight(16)
    chip:RegisterForClicks("AnyUp")
    chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chip.text:SetPoint("LEFT", chip, "LEFT", 0, 0)
    chip.text:SetJustifyH("LEFT")
    chip:SetFontString(chip.text)
    local hl = chip:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    chip:SetScript("OnClick", function(self, button)
        if not self.itemId then return end
        if button == "LeftButton" then
            -- клик по конкретному ингредиенту — ищем именно его
            if IsShiftKeyDown() then
                ns.InsertLink(ns.GetItemLink(self.itemId))
            elseif ns.AuctionSearch(ns.GetItemName(self.itemId) or "") then
                -- прямой поиск, если аукцион открыт
            else
                ns.InsertLink(ns.GetItemLink(self.itemId))
            end
        end
    end)
    chip:SetScript("OnEnter", function(self)
        if not self.itemId then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.itemId)
        GameTooltip:AddLine("Клик — поиск этого ингредиента в аукционе", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    chip:SetScript("OnLeave", GameTooltip_Hide)
    chip:Hide()
    return chip
end

local function LayoutReagents(row, w, s)
    row.reagChips = row.reagChips or {}
    local v = s.variant
    local reagents = v and v.reagents or {}
    local x = 0
    local rowWidth = row:GetWidth() - 8
    for i = 1, math.max(#reagents, #row.reagChips) do
        local chip = row.reagChips[i]
        if i <= #reagents and i <= REAG_MAX then
            if not chip then
                chip = MakeReagChip(row, i)
                row.reagChips[i] = chip
            end
            local r = reagents[i]
            local id, need = r[1], r[2]
            local have = (s.reagentCounts and s.reagentCounts[id]) or 0
            local name = ns.GetItemName(id) or ("item:" .. id)
            local color = have >= need and "|cff33ff33" or "|cffff6060"
            chip.itemId = id
            chip.text:SetText(("%s%d/%d %s|r"):format(color, have, need, name))
            local tw = chip.text:GetStringWidth() + 4
            -- перенос на следующую строку, если не влезает (макс 2 строки)
            if x > 0 and x + tw > rowWidth and i <= 4 then
                x = 0
                chip.row2 = true
            else
                chip.row2 = false
            end
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", row.reag, "TOPLEFT", x, chip.row2 and -14 or 0)
            chip:SetWidth(tw)
            chip:Show()
            x = x + tw + 10
        elseif chip then
            chip.itemId = nil
            chip:Hide()
        end
    end
end

function ns.UpdateCounts()
    local state = ns.state
    if not state then return end
    for _, w in ipairs(ns.WRITS or {}) do
        local s = state[w.writId]
        if s and s.variant and s.variant.reagents then
            s.reagentCounts = {}
            for _, r in ipairs(s.variant.reagents) do
                s.reagentCounts[r[1]] = GetItemCount(r[1]) or 0
            end
        end
    end
end

-- Ленивый рендер: создаём/обновляем только видимые строки + запас.
-- Полный список хранится в pendingList; строки за скроллом не трогаем.
local pendingList = {}
local VISIBLE_ROWS = 12  -- сколько строк влезает в окно + запас

local function RenderRow(i, w, s)
    local row = rows[i]
    if not row then
        row = MakeRow(i)
        rows[i] = row
    end
    row.writ = w
    row.state = s
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -(i - 1) * ROW_H - 2)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", -4, 0)
    local v = s.variant
    local craftId = v and v.creates and v.creates[1]
    row.icon:SetTexture(ns.GetItemIcon(craftId))
    local nameColor = s.known and "|cff33ff33" or "|cffc0c0c0"
    local craftName = (craftId and ns.GetItemName(craftId)) or w.name:gsub("^Craftsman's Writ: ", "")
    row.title:SetText(("%s%s|r |cff808080(%s)|r"):format(nameColor, craftName, PROF_LABEL[w.prof] or w.prof))
    local zoneColor = s.zoneOk and "|cff71d5ff" or "|cffff6060"
    row.info:SetText(("%s%s|r • %s • %s%s|r %s"):format(
        zoneColor, w.zone or "?", w.npc or "?",
        TIER_COLOR[w.tier] or "", w.tier or "?", StatusBadges(w, s)))
    row.reag:SetText("")
    LayoutReagents(row, w, s)
    row.writBtn.writId = w.writId
    row.writBtn.icon:SetTexture(ns.GetItemIcon(w.writId))
    row:Show()
end

local function RenderVisibleRange()
    if not main or not main:IsShown() then return end
    local state = ns.state or {}
    local scroll = WritsTrackerScroll
    local offset = scroll and scroll:GetVerticalScroll() or 0
    local first = math.max(1, math.floor(offset / ROW_H))
    local last = math.min(#pendingList, first + VISIBLE_ROWS)
    for i = first, last do
        local w = pendingList[i]
        if w then RenderRow(i, w, state[w.writId] or {}) end
    end
    -- скрыть строки вне диапазона
    for i = 1, #rows do
        if i < first or i > last then rows[i]:Hide() end
    end
end

function ns.WindowRefresh()
    if not main or not main:IsShown() then return end
    pendingList = FilteredWrits()
    scrollChild:SetHeight(math.max(#pendingList * ROW_H + 4, 1))
    if main.count then
        main.count:SetText(("Показано %d из %d"):format(#pendingList, #(ns.WRITS or {})))
    end
    RenderVisibleRange()
    -- пины пересоздаём только при смене фильтра/статуса, не каждый refresh
    if ns.MapPins and ns.MapPins.dirty then
        ns.MapPins.dirty = false
        local ok, err = pcall(ns.MapPins.render)
        if not ok then ns.MapPins.lastError = tostring(err) end
    end
end

local function AddCheck(parent, label, x, y, key, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText(label)
    cb:SetChecked(db()[key] and true or false)
    cb:SetScript("OnClick", function(self)
        db()[key] = self:GetChecked() and true or false
        if onChange then onChange() end
        markPinsDirty()
        ns.WindowRefresh()
    end)
    filterWidgets[key] = cb
    return cb
end

local function AddDropdown(parent, label, x, y, width, items, key)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(label)
    local dd = CreateFrame("Frame", "WritsTrackerDD" .. key, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(dd, width)
    local function OnClick(self)
        db()[key] = self.value
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        markPinsDirty()
        ns.WindowRefresh()
    end
    UIDropDownMenu_Initialize(dd, function()
        for _, it in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = it[2]
            info.value = it[1]
            info.func = OnClick
            info.checked = db()[key] == it[1]
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetSelectedValue(dd, db()[key] or items[1][1])
    filterWidgets[key] = dd
    return dd
end

-- Пометить пины грязными при смене фильтров (пересоздаём только тогда)
local function markPinsDirty()
    if ns.MapPins then ns.MapPins.dirty = true end
end

function ns.BuildWindow()
    if main then return end
    main = CreateFrame("Frame", "WritsTrackerFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    main:SetSize(WINDOW_W, WINDOW_H)
    main:SetPoint("CENTER")
    main:SetMovable(true)
    main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", main.StopMovingOrSizing)
    main:SetFrameStrata("HIGH")
    if main.SetBackdrop then
        main:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end
    main:Hide()

    local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", main, "TOP", 0, -12)
    title:SetText("Craftsman's Writs — дейлики")

    local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", main, "TOPRIGHT", -4, -4)

    -- ── Панель фильтров: 2 ряда дропдаунов, ровная сетка ──
    -- Ряд 1: Профессия | Рецепт | Зона | Тир | Статус | Сортировка
    local r1 = -38
    local col = { 12, 152, 282, 412, 522, 652 }
    AddDropdown(main, "Профессия", col[1], r1, 110, {
        { "auto", "Мои профессии" }, { "all", "Все" },
        { "Engineering", "Инжа" }, { "Leatherworking", "Кожевник" },
        { "Alchemy", "Алхимия" }, { "Blacksmithing", "Кузнец" }, { "Tailoring", "Портной" },
    }, "prof")
    AddDropdown(main, "Рецепт", col[2], r1, 90, {
        { "all", "Все" }, { "known", "Знаю" }, { "unknown", "Не знаю" },
    }, "known")
    AddDropdown(main, "Зона по уровню", col[3], r1, 100, {
        { "all", "Все" }, { "mine", "Мой уровень" }, { "notmine", "Не мой уровень" },
    }, "zone")
    AddDropdown(main, "Тир", col[4], r1, 80, {
        { "all", "Все" }, { "Journeyman", "Journeyman" }, { "Expert", "Expert" }, { "Artisan", "Artisan" },
    }, "tier")
    AddDropdown(main, "Статус", col[5], r1, 90, {
        { "all", "Все" }, { "ready", "Готовы" }, { "missing", "Не хватает" }, { "done", "Сданы" },
    }, "status")
    AddDropdown(main, "Сортировка", col[6], r1, 110, {
        { "prof", "Профессия" }, { "zone", "Зона" }, { "skill", "Скилл" },
        { "name", "Имя" }, { "cpr", "Цена/реп" }, { "rep", "Репутация" },
        { "level", "Уровень" },
    }, "sort")

    -- Ряд 2: чекбоксы слева, поиск справа
    local r2 = r1 - 56
    AddCheck(main, "Скрыть Moonglade (друиды)", col[1], r2, "hideDruid")
    AddCheck(main, "Скрыть сданные сегодня", 230, r2, "hideDone")
    AddCheck(main, "Пины на карте", 440, r2, "pins", function()
        if ns.MapPins then ns.MapPins.setEnabled(db().pins) end
    end)

    local search = CreateFrame("EditBox", "WritsTrackerSearch", main, "InputBoxTemplate")
    search:SetSize(220, 20)
    search:SetPoint("TOPLEFT", main, "TOPLEFT", 600, r2 - 2)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        db().text = self:GetText() or ""
        markPinsDirty()
        ns.WindowRefresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local searchLabel = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 0, 3)
    searchLabel:SetText("Поиск (имя/зона/NPC)")

    -- Ряд 3: кнопки действий
    local r3 = r2 - 30
    local wpBtn = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
    wpBtn:SetSize(100, 22)
    wpBtn:SetPoint("TOPLEFT", main, "TOPLEFT", col[1], r3)
    wpBtn:SetText("Waypoint")
    wpBtn:SetScript("OnClick", function()
        local sel = main.selectedWrit
        if sel and ns.Waypoint then ns.Waypoint.Set(sel) end
    end)
    wpBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Поставить маркер на точку сдачи выбранного writ")
        GameTooltip:AddLine("Выбор: клик по строке. Или СКМ по строке.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    wpBtn:SetScript("OnLeave", GameTooltip_Hide)
    main.wpBtn = wpBtn

    local shopBtn = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
    shopBtn:SetSize(120, 22)
    shopBtn:SetPoint("LEFT", wpBtn, "RIGHT", 8, 0)
    shopBtn:SetText("Купить (AH)")
    shopBtn:SetScript("OnClick", function()
        if ns.Shopping then ns.Shopping.CreateList() end
    end)
    shopBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Создать список покупок в Auctionator:")
        GameTooltip:AddLine("недостающие реагенты всех writs в списке", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    shopBtn:SetScript("OnLeave", GameTooltip_Hide)

    local scanBtn = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
    scanBtn:SetSize(100, 22)
    scanBtn:SetPoint("LEFT", shopBtn, "RIGHT", 8, 0)
    scanBtn:SetText("Обновить")
    scanBtn:SetScript("OnClick", function()
        ns.Refresh()
        ns.WindowRefresh()
        if ns.Broker then ns.Broker.Update() end
    end)

    -- ── Список ──
    local scroll = CreateFrame("ScrollFrame", "WritsTrackerScroll", main, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", main, "TOPLEFT", 12, r3 - 32)
    scroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -30, 32)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(WINDOW_W - 50, 1)
    scroll:SetScrollChild(scrollChild)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        -- ленивый рендер при прокрутке
        RenderVisibleRange()
    end)

    local count = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 14, 12)
    main.count = count

    local hint = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -32, 12)
    hint:SetText("Клик по ингредиенту — аукцион • Shift+клик — предмет • СКМ — waypoint")

    ns.WindowRefresh()
end

function ns.ToggleWindow()
    if not main then ns.BuildWindow() end
    if main:IsShown() then
        main:Hide()
    else
        ns.Refresh()
        main:Show()
        ns.WindowRefresh()
    end
end