-- РЕКОРДЫ (Mods\GONPlus\records.txt)
-- ключ|шишки|время|победа|сплиты через запятую
------------------------------------------------------------------------
local RECORDS_PATH = ROOT .. "\\records.txt"
local RECORDS = {}

local function loadRecords()
    local f = io.open(RECORDS_PATH, "r")
    if not f then return end
    for line in f:lines() do
        local key, pines, t, win, splits = line:match("^([^|]+)|(%d+)|([%d%.]+)|(%d)|?(.*)$")
        if key then
            local sp = {}
            for v in (splits or ""):gmatch("[^,]+") do sp[#sp + 1] = tonumber(v) end
            RECORDS[key] = { pines = tonumber(pines), time = tonumber(t), win = win == "1", splits = sp }
        end
    end
    f:close()
end

local function saveRecords()
    local f = io.open(RECORDS_PATH, "w")
    if not f then return end
    local keys = {}
    for k in pairs(RECORDS) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local r = RECORDS[k]
        local sp = {}
        for i, v in ipairs(r.splits or {}) do sp[i] = string.format("%.2f", v) end
        f:write(string.format("%s|%d|%.2f|%d|%s\n", k, r.pines, r.time, r.win and 1 or 0, table.concat(sp, ",")))
    end
    f:close()
end
loadRecords()

local function isBetter(new, old)
    if not old then return true end
    if new.love then
        -- Lovesick: победа лучше; среди побед — меньше влюблённости; среди поражений — дольше продержался
        if new.win ~= old.win then return new.win end
        if new.win then return new.pines > old.pines end
        return new.time > old.time
    end
    if new.win ~= old.win then return new.win end
    if new.win then return new.time < old.time end
    if new.pines ~= old.pines then return new.pines > old.pines end
    return new.time < old.time
end

------------------------------------------------------------------------
-- ЗАБЕГ
------------------------------------------------------------------------
local R = {
    pawnAddr = nil,     -- персонаж, к которому относится забег
    phase = "none",     -- none / choosing / running / over
    mode = nil,         -- none / pick / random / chaos
    mutId = nil,        -- выбранный мутатор (pick / random)
    t0 = nil,           -- время игры на старте
    pines = 0,
    splits = {},
    chaos = nil,        -- { nextAt, current }
    graceUntil = nil, graceHp = nil,
    result = nil, finalTime = nil,
    deltaText = nil, deltaUntil = 0,
    banner = nil, bannerUntil = 0,
}

local function runTime()
    if not R.t0 then return 0 end
    if R.finalTime then return R.finalTime end
    local now = gameNow()
    if not now then return 0 end
    return math.max(0, now - R.t0)
end

local function recordKey()
    if not R.base then return nil end
    local mk = (R.mode == "chaos" and "chaos") or (R.mutId and MUTS[R.mutId] and ("mut:" .. R.mutId)) or nil
    if R.base == "stealth" then return "stealth:" .. tostring(R.rokus) .. (mk and ("/" .. mk) or "") end
    if R.base == "nightmare" then return "nightmare" .. (mk and ("/" .. mk) or "") end
    if R.base == "lovesick" then return "lovesick:" .. tostring(R.loveMin) .. (mk and ("/" .. mk) or "") end
    if R.base == "shy" then return "shy" .. (mk and ("/" .. mk) or "") end
    return mk or ("normal" .. (vanillaRecordSuffix and vanillaRecordSuffix(R.diff) or ""))
end

local function bestFor(key) return key and RECORDS[key] or nil end

-- "+ PURE STEALTH: 2 ROKU · ZOOMIES +" — что за забег сейчас
function runLabel()
    local parts = {}
    if R.base == "stealth" then parts[#parts + 1] = "PURE STEALTH: " .. tostring(R.rokus) .. " ROKU"
    elseif R.base == "nightmare" then parts[#parts + 1] = "NIGHTMARE"
    elseif R.base == "lovesick" then parts[#parts + 1] = "LOVESICK"
    elseif R.base == "shy" then parts[#parts + 1] = "BASHFUL" end
    if R.mode == "chaos" then parts[#parts + 1] = "CHAOS: " .. activeNames():upper()
    elseif R.mode == "pick" or R.mode == "random" then parts[#parts + 1] = activeNames():upper() end
    if #parts == 0 then
        if not R.base then return "" end
        parts[1] = "NORMAL RUN"
    end
    return "+ " .. table.concat(parts, "  ·  ") .. " +"
end

local function showBanner(text, sec)
    R.banner, R.bannerUntil = text, (gameNow() or 0) + (sec or 3)
end

local UI -- forward: окно и панель
local onThrowLab -- задаётся в разделе лаборатории
local stealthStart, stealthStop -- задаются в разделе стелс-режима
-- nightmareStart / nightmareStop — глобальные, раздел Nightmare
local openChooser, refreshUI, applyPause -- forward

local function endRun(result)
    if R.phase ~= "running" then
        R.phase = "over"
        return
    end
    R.finalTime = runTime()
    R.result = result
    R.phase = "over"
    R.chaos = nil
    disableAll()
    if R.base == "stealth" and stealthStop then stealthStop(result) end
    if nightmareStop then nightmareStop() end
    if loveStop then loveStop() end
    if shyStop then shyStop() end

    local key = recordKey()
    local msg = string.format("%s  %s  apples %d", string.upper(result), fmtTime(R.finalTime, true), R.pines)
    if R.cheated then msg = msg .. "   (lab: no record)" end
    if key and not R.cheated and (result == "dead" or result == "win" or result == "caught" or result == "meltdown" or result == "zerohour" or result == "lovesick") then
        if R.base == "lovesick" and lovePercent then R.pines = 100 - lovePercent() end
        local new = { pines = R.pines, time = R.finalTime, win = result == "win", splits = R.splits, love = R.base == "lovesick" }
        if isBetter(new, RECORDS[key]) then
            RECORDS[key] = new
            saveRecords()
            msg = msg .. "   NEW BEST!"
        end
    end
    log("Run over: " .. msg .. " (mode " .. tostring(R.mode) .. ", key " .. tostring(key) .. ")")
    showBanner(msg, 8)
end

local function chaosPick()
    local pool = {}
    local cur = R.chaos and R.chaos.current
    for _, id in ipairs(MUT_ORDER) do
        local m = MUTS[id]
        local ok = not (R.base == "stealth" and m.noStealth) and not (R.base == "nightmare" and m.noNightmare)
            and not (R.base == "shy" and SHY_BLOCK and SHY_BLOCK[id])
        if m.chaos ~= false and id ~= cur and ok then pool[#pool + 1] = id end
    end
    if #pool == 0 then return cur end
    return pool[math.random(1, #pool)]
end

local function chaosSwitch(quiet)
    local nextId = chaosPick()
    if R.chaos.current then disableMut(R.chaos.current) end
    R.chaos.current = nextId
    if nextId then enableMut(nextId) end
    local now = gameNow() or 0
    R.chaos.nextAt = now + math.max(10, P.chaosInterval)
    -- пара секунд без урона, чтобы новый мутатор не убил мгновенно
    if P.graceSec > 0 then
        R.graceUntil = now + P.graceSec
        local p = getPawn()
        R.graceHp = p and num(p.health) or nil
    end
    showBanner("+ CHAOS: " .. (nextId and MUTS[nextId].name:upper() or "NONE") .. " +", 3)
    if quiet then return nextId end
    if flash then flash("+ " .. (nextId and MUTS[nextId].name:upper() or "NONE") .. " +", 3, nextId and MUT_COLOR[nextId] or nil, nextId and TAGLINE[nextId] or nil) end
    return nextId
end

------------------------------------------------------------------------
-- Подписи на старте: название крупно + под ним короткая (иногда шутливая) строка о сути.
-- Новым режимам и мутаторам — сюда же. Хаос показывает подпись каждого нового мутатора.
------------------------------------------------------------------------
TAGLINE = {
    normal    = "66 apples, one way out. She'll be around.",
    ["normal@easy"] = "The shelves are generous today.",
    ["normal@hard"] = "Less of everything. Except her.",
    stealth   = "If she sees you, it's over. Be a shadow.",
    stealthN  = "%d of them now. Not one of them can see you.",
    lovesick  = "She's drunk and clingy. Don't fall for her.",
    nightmare = "Lights out. One hit. Nowhere to hide. Good luck.",
    shy       = "Don't make her blush.",
    chaos     = "Something new every %d seconds. First up: %s.",
    reactor   = "The reactor is failing. Get out before it blows.",
    critical  = "It's getting worse. The lights won't hold.",
    meltdown  = "It's hot, it's red, and she's in a mood.",
    zerohour  = "One minute. Every apple buys you twenty seconds.",
    slippery  = "Butterfingers. Things slip out of your hands.",
    sutegoma  = "You're bleeding. Medkits are your best friends now.",
    twins     = "There are two of her now. Double the trouble.",
    nofood    = "No snacks for her today. Find another way.",
    zoomies   = "She's got the zoomies. Sprint, rest, sprint again.",
    razor     = "Sharper claws. Every hit hurts more.",
}

-- показать по очереди: { {title, sub, col}, ... }
function runIntro(list)   -- глобальная: в главном куске лимит 200 local
    if not flash then return end
    local t = 0
    for _, e in ipairs(list) do
        after(t, function() if R.phase == "running" then flash(e[1], e[2] and 3.6 or 2.5, e[3], e[2]) end end)
        t = t + (e[2] and 4400 or 3200)
    end
end
function mutIntro(id)
    local m = MUTS[id]
    if not m then return nil end
    return { "+ " .. m.name:upper() .. " +", TAGLINE[id], MUT_COLOR[id] }
end

local function startRun(mode, mutId)
    R.mode, R.mutId = mode, mutId
    R.base, R.rokus = P.selBase or "normal", P.selRokus or 1
    R.phase = "running"
    R.t0 = gameNow()
    R.pines, R.splits = 0, {}
    R.result, R.finalTime = nil, nil
    R.chaos, R.cheated = nil, false
    R.diff = gameDifficulty and gameDifficulty() or nil   -- для рекорда ванильной игры (normal@hard...)
    local p = getPawn()
    R.pines = p and num(p.pinecollected) or 0

    saveSettings()

    -- режим (правила); надписи — одной очередью после (название + подпись)
    local shows = {}
    if R.base == "stealth" then
        stealthStart(R.rokus)
        shows[#shows + 1] = { "+ PURE STEALTH +", R.rokus > 1 and string.format(TAGLINE.stealthN, R.rokus) or TAGLINE.stealth, MODE_COLOR.stealth }
    elseif R.base == "lovesick" then
        R.loveMin = P.selLoveMin or 8
        shows[#shows + 1] = { "+ LOVESICK +", TAGLINE.lovesick, MODE_COLOR.lovesick }
        if loveStart then loveStart(R.loveMin) end
    elseif R.base == "nightmare" then
        shows[#shows + 1] = { "+ NIGHTMARE +", TAGLINE.nightmare, MODE_COLOR.nightmare }
        if nightmareStart then nightmareStart() end
    elseif R.base == "shy" then
        shows[#shows + 1] = { "+ BASHFUL +", TAGLINE.shy, MODE_COLOR.shy }
        if shyStart then shyStart() end
    end
    -- мутатор (условия)
    if mode == "pick" or mode == "random" then
        enableMut(mutId)
        shows[#shows + 1] = mutIntro(mutId)
    elseif mode == "chaos" then
        R.chaos = { current = nil, nextAt = 0 }
        local first = chaosSwitch(true)
        shows[#shows + 1] = { "+ CHAOS +", string.format(TAGLINE.chaos, math.max(10, P.chaosInterval),
            first and MUTS[first].name or "nothing"), MODE_COLOR.chaos }
    elseif R.base == "normal" then
        local k = recordKey() or "normal"
        local label = (R.diff == 1 and "+ NORMAL RUN: EASY +") or (R.diff == 3 and "+ NORMAL RUN: HARD +") or "+ NORMAL RUN +"
        shows[#shows + 1] = { label, TAGLINE[k] or TAGLINE.normal }
    end
    runIntro(shows)
    log("Run started: " .. R.base .. ", mutator mode " .. mode .. (mutId and (" " .. mutId) or "") .. ", key " .. tostring(recordKey()))
end

-- новый персонаж = новый забег
local function newRun(pawn)
    if R.phase == "running" then endRun("restart") end
    disableAll()
    R.pawnAddr = pawn:GetAddress()
    R.held, R.heldAt = nil, nil
    R.phase = "choosing"
    R.mode, R.mutId, R.t0, R.chaos, R.base = nil, nil, nil, nil, nil
    R.pines, R.splits, R.finalTime, R.result = 0, {}, nil, nil
    R.banner, R.lastCountdown = nil, nil
    if stealthStop then stealthStop("new run") end
    if nightmareStop then nightmareStop() end
    if loveStop then loveStop() end
    if shyStop then shyStop() end
    forgetGameRefs()          -- после остановки режимов: им ещё нужны старые данные, чтобы всё вернуть
    -- экран поражения прошлого забега больше не нужен
    UI.defeatGen, UI.defeatOn = (UI.defeatGen or 0) + 1, false
    for _, w in ipairs({ UI.veil, UI.notice, UI.loseSub, UI.loseStats }) do
        if valid(w) then pcall(function() w:SetVisibility(VIS_HIDE) end) end
    end
    log("New run detected, opening chooser")
    openChooser()
    if diffResume then diffResume() end   -- уровень перезапускался ради сложности: стартуем сами
end

------------------------------------------------------------------------
