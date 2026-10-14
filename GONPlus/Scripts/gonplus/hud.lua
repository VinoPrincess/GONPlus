-- Спидран-панель
------------------------------------------------------------------------
local function updateHud()
    if not valid(UI.hud) then return end
    local show = P.hud and (R.phase == "running" or R.phase == "over") and R.base ~= "nightmare"
    UI.hud:SetVisibility(show and VIS_SHOW or VIS_HIDE)
    if not show then return end
    local L = UI.hudLines
    local now = gameNow() or 0
    setText(L.pines, string.format("%d/66", R.pines))

    -- мутатор с обратным отсчётом (реактор): вместо секундомера — сколько осталось
    local cd = nil
    local short = false       -- короткие часы (Zero Hour): пороги цвета/тряски в секундах, а не в минутах
    for _, id in ipairs(ACTIVE_LIST) do
        local m = MUTS[id]
        if m.countdown then
            local ok, left = pcall(m.countdown, m.state); if ok then cd = left end
            short = m.shortClock == true
            break
        end
    end
    local lovesick = R.base == "lovesick"
    if lovesick and loveLeft then cd = loveLeft() end
    if lovesick and lovePercent then setText(L.pines, string.format("LOVE %d%%", lovePercent())) end
    if R.phase == "over" and R.lastCountdown then cd = R.lastCountdown end
    UI.countdown = cd
    if cd then
        if R.phase == "running" then R.lastCountdown = cd end
        setText(L.time, fmtTime(math.max(0, cd), true))
        if lovesick then
            -- таймер-сердце: тук-тук, к концу всё чаще
            local limit = (R.loveMin or 8) * 60
            local k = 1 - math.max(0, math.min(1, cd / limit))
            local period = 1.1 - 0.65 * k
            if cd <= 60 then period = 0.42 end
            local ph = (os.clock() % period) / period
            local sc = 1
            if ph < 0.12 then sc = 1 + 0.16 * (1 - ph / 0.12)
            elseif ph > 0.22 and ph < 0.32 then sc = 1 + 0.09 * (1 - (ph - 0.22) / 0.1) end
            if R.phase ~= "running" then sc = 1 end
            setColor(L.time, { R = 1.0, G = 0.35 + 0.25 * (1 - k), B = 0.65, A = 1 })
            pcall(function() L.time:SetRenderScale({ X = sc, Y = sc }) end)
            UI.wasCountdown = true
            goto hud_rest
        end
        local col = GAME.white
        local tRed, tPink, tBlue = 60, 300, 600
        if short then tRed, tPink, tBlue = 10, 20, 40 end
        if cd <= tRed then col = GAME.warn
        elseif cd <= tPink then col = { R = 1, G = 0.45, B = 0.5, A = 1 }
        elseif cd <= tBlue then col = GAME.blue end
        setColor(L.time, col)
        -- пульс раз в секунду в последнюю минуту
        local sc = 1
        if cd <= tRed and R.phase == "running" then
            local frac = cd - math.floor(cd)
            sc = 1 + 0.18 * math.max(0, frac - 0.75) / 0.25
        end
        pcall(function() L.time:SetRenderScale({ X = sc, Y = sc }) end)
        -- тряска панели: сильнее с каждым рубежом
        local amp = 0
        if R.phase == "running" then
            if short then
                if cd <= 5 then amp = 7 elseif cd <= 10 then amp = 3 end
            elseif cd <= 10 then amp = 9 elseif cd <= 60 then amp = 5 elseif cd <= 300 then amp = 2.5 elseif cd <= 600 then amp = 1.2 end
        end
        pcall(function()
            UI.hudSlot:SetPosition({ X = -P.hudX + (math.random() * 2 - 1) * amp, Y = P.hudY + (math.random() * 2 - 1) * amp })
        end)
    else
        setText(L.time, fmtTime(runTime(), true))
        if UI.wasCountdown then
            setColor(L.time, GAME.white)
            pcall(function() L.time:SetRenderScale({ X = 1, Y = 1 }) end)
            pcall(function() UI.hudSlot:SetPosition({ X = -P.hudX, Y = P.hudY }) end)
        end
    end
    UI.wasCountdown = cd ~= nil
    ::hud_rest::

    if R.deltaText and now < R.deltaUntil then
        setText(L.delta, R.deltaText)
        L.delta:SetVisibility(VIS_SHOW)
    else
        L.delta:SetVisibility(VIS_HIDE)
    end

    local modeText = runLabel and runLabel() or ""
    if R.banner and now < R.bannerUntil then modeText = R.banner end
    setText(L.mode, modeText)
    local mc = runColor and runColor() or GAME.soft
    setColor(L.mode, (R.base == "normal" and not R.mutId and R.mode ~= "chaos") and GAME.soft or { R = mc.R, G = mc.G, B = mc.B, A = 0.9 })

    if R.mode == "chaos" and R.chaos and R.phase == "running" then
        local left = R.chaos.nextAt - now
        if left <= P.chaosWarn then setText(L.chaos, string.format("CHANGE IN %d", math.ceil(left)))
        else setText(L.chaos, "next change " .. fmtTime(left)) end
        L.chaos:SetVisibility(VIS_SHOW)
        setColor(L.chaos, left <= P.chaosWarn and GAME.warn or GAME.blue)
    else
        -- мутатор может показать свою строку: hud(state) -> текст, тревога
        local txt, warn = nil, false
        if R.phase == "running" then
            for _, id in ipairs(ACTIVE_LIST) do
                local m = MUTS[id]
                if m.hud then
                    local ok, t, w = pcall(m.hud, m.state)
                    if ok and t then txt, warn = t, w break end
                end
            end
        end
        if txt then
            setText(L.chaos, txt)
            setColor(L.chaos, warn and GAME.warn or GAME.blue)
            L.chaos:SetVisibility(VIS_SHOW)
        else
            L.chaos:SetVisibility(VIS_HIDE)
        end
    end

    local b = bestFor(recordKey())
    local cdm = R.mutId and MUTS[R.mutId]
    if not (cdm and cdm.countdown) then cdm = nil end
    if b and cdm and cdm.limit then
        if b.win then setText(L.best, string.format("best  %s left", fmtTime(cdm.limit - b.time, true)))
        else setText(L.best, string.format("best  %d/66", b.pines)) end
    elseif b then setText(L.best, string.format("best  %s%d/66  %s", b.win and "WIN  " or "", b.pines, fmtTime(b.time, true)))
    elseif recordKey() then setText(L.best, "best  -")
    else setText(L.best, "fun mutator  no records") end
end

------------------------------------------------------------------------
-- Главный цикл (4 раза в секунду) + быстрый для панели
------------------------------------------------------------------------
local TICK = 0.25

every(250, function()
    local pawn = getPawn()
    if not pawn then
        -- нет персонажа: главное меню или загрузка
        -- (смерть могла прийти в том же такте, что и исчезновение персонажа)
        if R.phase == "running" then endRun(pending.death and "dead" or (pending.victory and "win" or "quit")) end
        pending = {}
        if R.phase ~= "none" then
            disableAll()
            R.phase, R.pawnAddr = "none", nil
            if UI.open then UI.open = false end
        end
        return
    end

    if not ensureUI() then return end

    local addr = pawn:GetAddress()
    if addr ~= R.pawnAddr then newRun(pawn) return end

    -- события игры
    local ev = pending
    pending = {}
    if ev.death and R.phase == "running" then
        local lose = nil
        if R.mode == "chaos" then lose = LOSE and LOSE.chaos
        elseif R.mutId and MUTS[R.mutId] then lose = MUTS[R.mutId].lose
        elseif R.base == "nightmare" then lose = LOSE and LOSE.nightmare end
        endRun("dead")
        if lose and defeat and not UI.defeatOn then
            defeat({ title = lose.title, sub = lose.sub, veil = lose.veil, color = lose.color or GAME.deep,
                fadeIn = 0.5, hold = 3.5 })
        end
    end
    if ev.victory and R.phase == "running" then
        local w = winScreen and winScreen() or nil
        endRun("win")
        if w and defeat and not UI.defeatOn then
            defeat({ title = w.title, sub = w.sub, veil = w.veil or { 0.0, 0.03, 0.1 }, color = w.color or GAME.blue,
                fadeIn = 0.6, hold = 4 })
        end
    end
    -- что сейчас в руке (для "Скользких рук")
    if ev.pickup then R.held, R.heldAt = ev.pickedObj, gameNow() end
    if ev.throw or ev.death then R.held = nil end
    for _, name in ipairs({ "pickup", "throw", "damage" }) do
        if ev[name] then eventMuts(name) end
        if name == "throw" and ev.throw and onThrowLab then onThrowLab(ev.thrownObj) end
        if name == "throw" and ev.throw and loveOnThrow then loveOnThrow(ev.thrownObj) end
        if name == "throw" and ev.spank and loveOnSpank then loveOnSpank() end
    end

    if R.phase ~= "running" then return end

    -- шишки и сплиты
    local pines = num(pawn.pinecollected)
    if pines and pines > R.pines then
        local t = runTime()
        for n = R.pines + 1, pines do R.splits[n] = t end
        R.pines = pines
        local b = bestFor(recordKey())
        if b and b.splits and b.splits[pines] then
            local d = t - b.splits[pines]
            R.deltaText = string.format("%s%.2f  vs best", d >= 0 and "+" or "-", math.abs(d))
            setColor(UI.hudLines.delta, d <= 0 and GAME.blue or GAME.warn)
        else
            R.deltaText = "split " .. fmtTime(t, true)
            setColor(UI.hudLines.delta, GAME.soft)
        end
        R.deltaUntil = (gameNow() or 0) + 4
    end

    -- защита после смены в хаосе
    local now = gameNow() or 0
    if R.graceUntil then
        if now < R.graceUntil then
            local hp = num(pawn.health)
            if hp and R.graceHp and hp < R.graceHp then pawn.health = R.graceHp end
        else
            R.graceUntil, R.graceHp = nil, nil
        end
    end

    -- хаос
    if R.mode == "chaos" and R.chaos and now >= R.chaos.nextAt then chaosSwitch() end

    -- мутаторы живут по времени игры: на паузе время стоит, тик пропускается
    local dt = R.lastMutT and (now - R.lastMutT) or TICK
    R.lastMutT = now
    if dt > 0.001 then tickMuts(math.min(dt, 1)) end
end)

-- крупная надпись посреди экрана: появляется, висит, тает
-- цвет забега: у режима свой, у мутатора свой (для крупных надписей и строки режима)
MODE_COLOR = {
    stealth   = { R = 0.25, G = 0.55, B = 1.0 },
    nightmare = { R = 1.0, G = 0.15, B = 0.3 },
    lovesick  = { R = 1.0, G = 0.4, B = 0.7 },
    chaos     = { R = 0.7, G = 0.45, B = 1.0 },
}
MUT_COLOR = {
    reactor  = { R = 1.0, G = 0.45, B = 0.15 }, critical = { R = 1.0, G = 0.45, B = 0.15 }, meltdown = { R = 1.0, G = 0.45, B = 0.15 },
    zerohour = { R = 0.3, G = 0.85, B = 1.0 },
    slippery = { R = 0.55, G = 0.9, B = 1.0 },
    sutegoma = { R = 0.95, G = 0.12, B = 0.18 },
    twins    = { R = 0.8, G = 0.55, B = 1.0 },
    nofood   = { R = 1.0, G = 0.78, B = 0.3 },
    zoomies  = { R = 0.3, G = 1.0, B = 0.6 },
    razor    = { R = 1.0, G = 0.3, B = 0.3 },
}
function runColor()
    if R.base and MODE_COLOR[R.base] then return MODE_COLOR[R.base] end
    if R.mode == "chaos" then return MODE_COLOR.chaos end
    if R.mutId and MUT_COLOR[R.mutId] then return MUT_COLOR[R.mutId] end
    return GAME.blue
end

function flash(text, sec, col)
    if not valid(UI.flash) then return end
    col = col or runColor()
    UI.flashGen = (UI.flashGen or 0) + 1
    local gen = UI.flashGen
    setText(UI.flash, text)
    UI.flash:SetVisibility(VIS_SHOW)
    local hold = (sec or 2.5) * 1000
    local function alpha(a) pcall(function() setColor(UI.flash, { R = col.R, G = col.G, B = col.B, A = a }) end) end
    for i = 0, 8 do after(i * 30, function() if UI.flashGen == gen then alpha(i / 8) end end) end
    for i = 0, 12 do after(hold + i * 50, function() if UI.flashGen == gen then alpha(1 - i / 12) end end) end
    after(hold + 650, function() if UI.flashGen == gen then UI.flash:SetVisibility(VIS_HIDE) end end)
end

-- родные полоски и счётчик игры: прячем, пока показываем свои
local GAMEUI = { bars = nil, count = nil, orig = {} }
onForgetRefs(function()
    GAMEUI.bars, GAMEUI.count, GAMEUI.cross, GAMEUI.mask, GAMEUI.orig = nil, nil, nil, nil, {}
end)
local function gameHudParts(pawn)
    local hud = nil
    pcall(function() hud = pawn.UI_Horror end)
    if not valid(hud) then hud = FindFirstOf("UI_Horror_C") end
    if not valid(hud) then return end
    if not valid(GAMEUI.bars) then
        pcall(function()
            local w = hud.ProgressBar_21
            for _ = 1, 4 do
                if not valid(w) then return end
                if w:GetFName():ToString() == "VerticalBox_0" then GAMEUI.bars = w return end
                w = w:GetParent()
            end
        end)
    end
    if not valid(GAMEUI.count) then pcall(function() GAMEUI.count = hud.PineCount:GetParent() end) end
    if not valid(GAMEUI.cross) then pcall(function() GAMEUI.cross = hud.crosshair end) end
    if not valid(GAMEUI.mask) then pcall(function() GAMEUI.mask = hud.MASKTIMER end) end
end
local function setGamePart(key, hide)
    local w = GAMEUI[key]
    if not valid(w) then return end
    local cur = nil
    pcall(function() cur = w:GetVisibility() end)
    if GAMEUI.orig[key] == nil and cur ~= VIS_HIDE then GAMEUI.orig[key] = cur end
    local want = hide and VIS_HIDE or (GAMEUI.orig[key] or 4)
    if cur ~= want then pcall(function() w:SetVisibility(want) end) end
end

local function updateBars(dt)
    local b = UI.bars; if not b then return end
    local pawn = getPawn()
    -- пока открыто окно выбора — прячем (игра на паузе, а терминал-панель стоит там же, где полоски)
    local menuOpen = UI.open and UI.kind ~= "lab"
    local show = P.ownBars and pawn ~= nil and R.phase ~= "none" and R.base ~= "nightmare" and not menuOpen
    local term = show and P.barsStyle == "term"
    for _, k in ipairs({ "hp", "st" }) do
        for _, part in ipairs({ "frame", "trail", "fill" }) do
            local w = b[k][part]
            if valid(w) then w:SetVisibility(show and VIS_SHOW or VIS_HIDE) end
        end
        for _, part in ipairs({ "name", "num" }) do
            local w = b[k][part]
            if valid(w) and b[k][part .. "On"] ~= term then
                b[k][part .. "On"] = term
                w:SetVisibility(term and VIS_SHOW or VIS_HIDE)
            end
        end
    end
    if not show then if valid(b.label) then b.label:SetVisibility(VIS_HIDE) end return end
    if not b.hp.g then layoutBars() end
    local hg, sg = b.hp.g, b.st.g
    local iw, ih = hg.w - hg.inset * 2, hg.h - hg.inset * 2
    local siw, sih = sg.w - sg.inset * 2, sg.h - sg.inset * 2
    local t = os.clock()
    -- Lovesick: вместо здоровья — шкала влюблённости (розовая, растёт)
    if R.base == "lovesick" and lovePercent then
        local lv = lovePercent() / 100
        pcall(function() b.hp.fillSlot:SetSize({ X = math.max(0.01, iw * lv), Y = ih }) end)
        pcall(function() b.hp.trailSlot:SetSize({ X = 0.01, Y = ih }) end)
        local la = (lv >= 0.6) and (0.65 + 0.35 * math.abs(math.sin(t * 4))) or 1
        pcall(function() b.hp.fill:SetBrushColor({ R = 1.0, G = 0.35, B = 0.65, A = la }) end)
        setText(b.label, string.format("+ IN LOVE  %d%% +", lovePercent()))
        if term then setText(b.hp.num, string.format("%d%%", lovePercent())); setText(b.hp.name, "<3") end
        setColor(b.label, { R = 1.0, G = 0.45, B = 0.7, A = 1 })
        b.label:SetVisibility(VIS_SHOW)
        goto bars_stamina
    end
    do
    -- здоровье + белый хвост, который догоняет с задержкой (как у игры)
    local hp = math.max(0, math.min(1, num(pawn.health) or 1))
    if hp < b.trailV - 0.001 then
        if b.trailHold <= 0 and b.lastHp and hp < b.lastHp - 0.001 then b.trailHold = 0.6 end
        b.trailHold = b.trailHold - dt
        if b.trailHold <= 0 then b.trailV = math.max(hp, b.trailV - dt * 0.5) end
    else
        b.trailV, b.trailHold = hp, 0
    end
    b.lastHp = hp
    if term then setText(b.hp.num, string.format("%d%%", math.floor(hp * 100 + 0.5))); setText(b.hp.name, "HP") end
    pcall(function() b.hp.fillSlot:SetSize({ X = math.max(0.01, iw * hp), Y = ih }) end)
    pcall(function() b.hp.trailSlot:SetSize({ X = math.max(0.01, iw * b.trailV), Y = ih }) end)
    local bleeding = ACTIVE.sutegoma
    local col = bleeding and GAME.blood or GAME.hpGreen
    local a = 1
    if bleeding or hp < 0.25 then a = 0.65 + 0.35 * math.abs(math.sin(t * (hp < 0.25 and 6 or 2.5))) end
    pcall(function() b.hp.fill:SetBrushColor({ R = col.R, G = col.G, B = col.B, A = a }) end)
    if bleeding then
        setText(b.label, "+ BLEEDING +")
        setColor(b.label, GAME.warn)
        b.label:SetVisibility(VIS_SHOW)
    else
        b.label:SetVisibility(VIS_HIDE)
    end
    end
    ::bars_stamina::
    -- выносливость: выдохся — тускнеет и мигает
    local meter, total, rec = num(pawn["Sprint Meter"]), num(pawn["Sprint Time"]), false
    pcall(function() rec = pawn.Recovering == true end)
    local st = (meter and total and total > 0) and math.max(0, math.min(1, meter / total)) or 1
    pcall(function() b.st.fillSlot:SetSize({ X = math.max(0.01, siw * st), Y = sih }) end)
    if term then setText(b.st.num, rec and "--" or string.format("%d%%", math.floor(st * 100 + 0.5))) end
    local sa = rec and (0.35 + 0.25 * math.abs(math.sin(t * 5))) or 1
    pcall(function() b.st.fill:SetBrushColor({ R = GAME.stBlue.R, G = GAME.stBlue.G, B = GAME.stBlue.B, A = sa }) end)
    -- по центру: полная выносливость через 1.5 с прячется, при беге появляется
    local op = 1
    if P.barsStyle == "center" or P.barsStyle == "line" then
        if st >= 0.999 and not rec then
            b.stFullSince = b.stFullSince or t
            op = math.max(0, 1 - (t - b.stFullSince - 1.5) / 0.5)
        else
            b.stFullSince = nil
        end
    end
    if op ~= b.stOp then
        b.stOp = op
        for _, part in ipairs({ "frame", "fill" }) do pcall(function() b.st[part]:SetRenderOpacity(op) end) end
    end
end

every(50, function()
    if not valid(UI.widget) then return end
    updateHud()
    safe(updateBars, 0.05)
end)

every(250, function()
    local pawn = getPawn(); if not pawn then GAMEUI.bars, GAMEUI.count, GAMEUI.orig = nil, nil, {} return end
    gameHudParts(pawn)
    local night = R.base == "nightmare" and R.phase ~= "none"
    setGamePart("bars", P.ownBars or night)
    setGamePart("count", P.hud or night)
    -- прицел и таймер маски трогаем только в кошмаре (таймер маски игра показывает сама)
    if night then
        setGamePart("cross", true); setGamePart("mask", true); GAMEUI.hidNight = true
    elseif GAMEUI.hidNight then
        setGamePart("cross", false); setGamePart("mask", false); GAMEUI.hidNight = false
    end
end)

------------------------------------------------------------------------
