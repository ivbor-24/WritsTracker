-- WritsTracker: экономика через Auctionator API v1.
-- Три пути получения предмета-заказа: скрафтить (реагенты) / купить готовое / купить writ.
-- cost/rep = (цена пути - награда) / реп. Награда — Coin Pouch тира (среднее из открытий).
local ADDON, ns = ...

ns.Pricing = {}
local P = ns.Pricing
local CALLER = "WritsTracker"

local function api()
    if Auctionator and Auctionator.API and Auctionator.API.v1 then return Auctionator.API.v1 end
    return nil
end

function P.IsAvailable()
    local a = api()
    return a and type(a.GetAuctionPriceByItemID) == "function"
end

function P.GetPrice(itemID)
    local a = api()
    if not a or not itemID then return nil end
    local ok, price = pcall(a.GetAuctionPriceByItemID, CALLER, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

function P.GetAge(itemID)
    local a = api()
    if not a or not itemID or type(a.GetAuctionAgeByItemID) ~= "function" then return nil end
    local ok, age = pcall(a.GetAuctionAgeByItemID, CALLER, itemID)
    if ok and type(age) == "number" then return age end
    return nil
end

-- Награда writ: среднее из открытых Coin Pouch тира (SavedVariables), иначе статика гайда.
-- Гайд: Journeyman 5-19s, Expert ~36s, Artisan ~74s 56c (медиана/среднее).
local TIER_PAYOUT_STATIC = { Journeyman = 1200, Expert = 3600, Artisan = 7456 }
local POUCH_BY_TIER = { [284584] = "Journeyman", [284585] = "Expert", [284586] = "Artisan" }
ns.POUCH_BY_TIER = POUCH_BY_TIER

function P.GetPayout(tier)
    local db = WritsTrackerDB
    local s = db and db.pouchStats and db.pouchStats[tier]
    if s and s.n and s.n > 0 and s.sum and s.sum > 0 then
        return math.floor(s.sum / s.n + 0.5)
    end
    return TIER_PAYOUT_STATIC[tier]
end

-- Записать открытие pouch (вызывается из Core при PLAYER_MONEY + сумка-дельта).
function P.RecordPouch(tier, copper)
    if not tier or type(copper) ~= "number" or copper <= 0 then return end
    local db = WritsTrackerDB
    db.pouchStats = db.pouchStats or {}
    local s = db.pouchStats[tier]
    if not s then s = { n = 0, sum = 0 }; db.pouchStats[tier] = s end
    s.n = s.n + 1
    s.sum = s.sum + copper
    s.min = (s.min and s.min < copper) and s.min or copper
    s.max = (s.max and s.max > copper) and s.max or copper
end

function P.FormatMoney(copper)
    if type(copper) ~= "number" or copper <= 0 then return "|cff888888-|r" end
    copper = math.floor(copper + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return ("|cffffd700%dз|r |cffc7c7cf%dс|r"):format(g, s) end
    if s > 0 then return ("|cffc7c7cf%dс|r |cffeda55f%dм|r"):format(s, c) end
    return ("|cffeda55f%dм|r"):format(c)
end

function P.FormatAge(age)
    if type(age) ~= "number" then return "" end
    if age <= 0 then return " |cff888888(сегодня)|r" end
    return (" |cff888888(%d дн.)|r"):format(age)
end

-- Анализ writ: три пути + cost/rep лучшего доступного.
-- s = state[writId] из Core.Refresh (variant, known, reagentCounts...).
function P.Analyze(w, s)
    if not P.IsAvailable() then return { available = false } end
    local v = s and s.variant
    local rep = ({ Journeyman = 75, Expert = 125, Artisan = 200 })[w.tier] or 75
    local payout = P.GetPayout(w.tier)

    -- путь 1: крафт (реагенты по ценам AH)
    local craftCost, craftComplete = nil, true
    if v and v.reagents then
        craftCost = 0
        for _, r in ipairs(v.reagents) do
            local unit = P.GetPrice(r[1])
            if unit then craftCost = craftCost + unit * r[2]
            else craftComplete = false end
        end
        if not craftComplete then craftCost = nil end
    end
    -- путь 2: готовый предмет
    local craftId = v and v.creates and v.creates[1]
    local buyItem = craftId and P.GetPrice(craftId) or nil
    -- путь 3: writ с AH (сам предмет-заказ уже внутри? нет — writ требует предмет,
    -- цена writ = доплата за право сдать; предмет всё равно нужен)
    local writPrice = P.GetPrice(w.writId)

    -- лучший путь: крафт если знаю рецепт, иначе покупка готового
    local bestCost, bestPath = nil, nil
    if s and s.known and craftCost then
        bestCost, bestPath = craftCost, "craft"
    end
    if buyItem and (not bestCost or buyItem < bestCost) then
        bestCost, bestPath = buyItem, "buy"
    end
    -- writ добавляет цену, если его надо покупать (нет в сумках)
    local haveWrit = (s and s.writCount or 0) > 0 or (s and s.active)
    local writAdd = (not haveWrit and writPrice) and writPrice or 0
    local totalCost = bestCost and (bestCost + writAdd) or nil
    local netCost = totalCost and (totalCost - payout) or nil
    local cpr = (netCost and rep > 0) and (math.max(0, netCost) / rep) or nil

    -- рейтинг (пороги в медных за 1 реп; настройки в db)
    local db = WritsTrackerDB or {}
    local cheap = db.cheapCPR or 500
    local exp = db.expensiveCPR or 1500
    local rating, color = "none", "a8b0b8"
    if cpr then
        if cpr <= cheap then rating, color = "good", "5fbf73"
        elseif cpr <= exp then rating, color = "mid", "ffd24a"
        else rating, color = "bad", "e05a5a" end
    end

    return {
        available = true,
        rep = rep, payout = payout,
        craftCost = craftCost, craftComplete = craftComplete,
        buyItem = buyItem, buyItemAge = craftId and P.GetAge(craftId) or nil,
        writPrice = writPrice, writAge = P.GetAge(w.writId),
        haveWrit = haveWrit,
        bestCost = bestCost, bestPath = bestPath,
        totalCost = totalCost, netCost = netCost,
        cpr = cpr, rating = rating, color = color,
        -- продать writ выгоднее, чем сдать: цена writ > чистая выгода сдачи (награда - затраты)
        sellBetter = (writPrice and bestCost and payout and writPrice > (payout - bestCost)) or false,
    }
end

-- Короткая строка для списка: "12с/реп" цветом рейтинга.
function P.ShortLabel(p)
    if not p or not p.available then return "" end
    if not p.cpr then return "|cff888888нет цен|r" end
    local txt = P.FormatMoney(p.cpr) .. "/реп"
    return ("|cff%s%s|r"):format(p.color, txt)
end