-- РЕЖИМ LOVESICK: свой мозг Року.
--   Цель — продержаться N минут. Яблоки не нужны.
--   Року не бьёт, а обнимает (сердечко руками): шкала влюблённости растёт.
--   Шкала полная — проигрыш ("по уши влюбился"). Таймер вышел — победа ("вместе").
--   "Сила любви": время от времени она точно знает, где ты; в конце — всегда.
--   Подарки: брошенный в неё предмет остужает шкалу (еда — сильнее).
------------------------------------------------------------------------
; (function()
local LV = { on = false }
local HEART = "/Game/ROKUv3/anims/cuteanims/cute_hearthands2_Montage.cute_hearthands2_Montage"
local HUG_LOVE = 0.20          -- одно объятие
local HUG_DIST = 170
local FINAL = 120              -- последние 2 минуты: знает всегда
local FOOD_GIFT = { BP_T_Apple_C = true, BP_T_Carrot_C = true, BP_coffee_C = true, BP_T_Beercan_C = true,
                    ["4pack_of_beer_C"] = true, BP_T_WineBottle_C = true }
local PINK = { R = 1.0, G = 0.35, B = 0.65, A = 1 }
LV_DRUNK = 1.5          -- уровень опьянения (максимум у игры — 1.5), держим на нём

local function rnd(a, b) return a + math.random() * (b - a) end

-- Предметы в Lovesick: только "подарки". Алкоголь (она и так пьяна), мусор, пробирки,
-- яблоки-образцы, черепа и аптечки убираем; подарков докладываем побольше
local LV_REMOVE = { "BP_TrashCube_C", "BP_T_TestTubes_C", "BP_T_Beercan_C", "4pack_of_beer_C", "BP_T_WineBottle_C",
    "BP_PineCone_C", "BP_T_PackofPines_C", "BP_T_Skull_C", "BP_T_SumOfNothing_C", "BP_Medikit_C" }
local LV_GIFTS = {   -- путь класса, вес
    { "/Game/INTERACTION/BP_T_Apple.BP_T_Apple_C", 30 },
    { "/Game/INTERACTION/BP_T_Carrot.BP_T_Carrot_C", 15 },
    { "/Game/INTERACTION/BP_T_Flashlight.BP_T_Flashlight_C", 20 },
    { "/Game/INTERACTION/BP_T_Gstick.BP_T_Gstick_C", 20 },
    { "/Game/INTERACTION/BP_coffee.BP_coffee_C", 10 },
    { "/Game/INTERACTION/BP_T_cowbell.BP_T_cowbell_C", 5 },
}
local LV_EXTRA_GIFTS = 250     -- вместо ~900 штук мусора; кладём партиями, чтобы игра не подвисла

local function lvSweep(first)
    local pawn = getPawn(); if not pawn then return 0 end
    local me = pawn:K2_GetActorLocation()
    local n = 0
    for _, cn in ipairs(LV_REMOVE) do
        for _, a in ipairs(FindAllOf(cn) or {}) do
            if valid(a) and a ~= R.held then
                local addr = a:GetAddress()
                local keep = LV.killed[addr] == true
                pcall(function() if valid(a:GetAttachParentActor()) then keep = true end end)
                pcall(function() local st = num(a.State); if st and st ~= 0 then keep = true end end)
                if not first and not keep then
                    pcall(function()
                        local p = itemPos(a) or a:K2_GetActorLocation()
                        if vlen(p.X - me.X, p.Y - me.Y, 0) < 600 then keep = true end   -- на глазах не исчезает
                    end)
                end
                if not keep and pcall(function() a:K2_DestroyActor() end) then LV.killed[addr] = true; n = n + 1 end
            end
        end
    end
    return n
end

local function lvAddGifts()
    local total = 0
    for _, e in ipairs(LV_GIFTS) do total = total + e[2] end
    local pawn = getPawn(); if not pawn then return end
    local spots = itemSpots(LV_EXTRA_GIFTS, 400)
    local made, batch = 0, 25
    for b = 0, math.ceil(#spots / batch) - 1 do
        after(b * 400, function()
            if not LV.on then return end
            local p2 = getPawn(); if not p2 then return end
            for i = b * batch + 1, math.min(#spots, (b + 1) * batch) do
                local l = spots[i]
                local roll, pick = math.random() * total, LV_GIFTS[1]
                for _, e in ipairs(LV_GIFTS) do roll = roll - e[2]; if roll <= 0 then pick = e break end end
                local cls = itemClass(pick[1])
                if cls then
                    local ok = pcall(function()
                        p2:GetWorld():SpawnActor(cls, { X = l.X, Y = l.Y, Z = l.Z + 15 }, { Pitch = 0, Yaw = math.random(0, 359), Roll = 0 })
                    end)
                    if ok then made = made + 1 end
                end
            end
            if (b + 1) * batch >= #spots then log("Lovesick: placed " .. made .. " extra gifts") end
        end)
    end
end

local function heartMontage()
    local m = nil
    pcall(function() m = StaticFindObject(HEART) end)
    if valid(m) then return m end
    if LoadAsset then
        pcall(function() LoadAsset(HEART:gsub("%.[^%.]+$", "")) end)
        pcall(function() m = StaticFindObject(HEART) end)
    end
    return valid(m) and m or nil
end

local function playerLoc()
    local p = getPawn(); if not p then return nil end
    local l = p:K2_GetActorLocation()
    return { X = l.X, Y = l.Y, Z = l.Z }
end

local function speed(r, v, running)
    pcall(function() r.CharacterMovement.MaxWalkSpeed = v end)
    if v > 0 then
        pcall(function() if math.abs((num(r.MoveSpeed) or 0) - v) > 1 then r.MoveSpeed = v end end)
        pcall(function() if math.abs((num(r.chasespeed) or 0) - v) > 1 then r.chasespeed = v end end)
    end
    pcall(function() if r.bIsChasing ~= (running == true) then r.bIsChasing = (running == true) end end)
end

-- одно состояние на каждую Року
local function state(r)
    local addr = r:GetAddress()
    local st = LV.rokus[addr]
    if not st then
        st = { r = r, mode = "wander", t = 0, lastPos = nil, still = 0, hugReady = 0, nextOrder = 0, drunkAt = -100 }
        LV.rokus[addr] = st
        brainOff(r)
        log("Lovesick: Roku under the love brain")
        -- в первые секунды после появления она уже знает, где ты
        LV.nextPing = math.min(LV.nextPing, (gameNow() or 0) + rnd(2, 8))
    end
    return st
end

local MOVING = { wander = true, chase = true, seek = true }
local function setMode(st, mode, g)
    -- пошла дальше — снять наши анимации (сердечко, осмотр), иначе она так и идёт с ними
    if MOVING[mode] and not MOVING[st.mode] then pcall(function() st.r:StopAnimMontage(nil) end) end
    st.mode, st.t = mode, g
    st.dest, st.still = nil, 0
end

-- играет ли сейчас анимация самой игры (падение, реакция на попадание) — тогда не мешаем
local function gameMontage(r)
    local m = nil
    pcall(function() m = r:GetCurrentMontage() end)
    if not valid(m) then return false end
    local n = ""
    pcall(function() n = m:GetFName():ToString():lower() end)
    if type(n) ~= "string" then return false end
    -- только реакции игры, во время которых ей нельзя идти: падение, попадание, толчок, шлепок, череп
    for _, w in ipairs({ "fallover", "mhit", "spank", "stagger", "skullcatch", "skullthrow" }) do
        if n:find(w, 1, true) then return true end
    end
    return false
end

local function goTo(st, dest, g)
    st.dest = dest
    sendTo(st.r, dest)
    st.nextOrder = g + 0.4
end

-- объятие: сердечко, шкала растёт, игрока мягко отталкивает
local function hug(st, g)
    local r, p = st.r, getPawn()
    setMode(st, "hug", g)
    pcall(function() r.Controller:StopMovement() end)
    if p then
        local rl, me = r:K2_GetActorLocation(), p:K2_GetActorLocation()
        local yaw = math.deg(math.atan(me.Y - rl.Y, me.X - rl.X))
        pcall(function() r:K2_SetActorRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }, false) end)
        local dx, dy = me.X - rl.X, me.Y - rl.Y
        local d = math.max(1, vlen(dx, dy, 0))
        pcall(function() p:LaunchCharacter({ X = dx / d * 700, Y = dy / d * 700, Z = 220 }, true, true) end)
    end
    local m = heartMontage()
    local ok = m and pcall(function() r:PlayAnimMontage(m, 1.0, FName("None")) end)
    if not ok then playLookAround(r) end
    LV.love = math.min(1, LV.love + HUG_LOVE)
    LV.lastHug = g
    showBanner("+ SHE HUGGED YOU +", 2)
    flash(string.format("+ %d%% +", math.floor(LV.love * 100 + 0.5)), 1.5)
    log(string.format("Lovesick: hug! love %.0f%% (heart montage %s)", LV.love * 100, m and "ok" or "missing"))
    if LV.love >= 1 and not LV.lost then
        LV.lost = true
        after(1500, function()
            if not LV.on then return end
            defeat({ title = "+ HEAD OVER HEELS +", sub = "A few drinks, and she showed you who's in charge.",
                veil = { 0.35, 0.02, 0.16 }, color = PINK, fadeIn = 2.0, hold = 4, scripted = true,
                result = "lovesick", restart = true })
        end)
    end
end

-- подарок: брошенный предмет долетел до неё
local function gift(st, item, g)
    local cname = ""
    pcall(function() cname = item:GetClass():GetFName():ToString() end)
    local food = FOOD_GIFT[cname] == true
    local cool = food and 0.12 or 0.06
    LV.love = math.max(0, LV.love - cool)
    -- она не останавливается: реакцию на попадание (если есть) играет сама игра
    showBanner(food and "+ SHE LOVED THE GIFT +" or "+ A GIFT +", 2)
    log(string.format("Lovesick: gift %s, love -%d%% -> %.0f%%", cname, cool * 100, LV.love * 100))
end

local function rokuTick(r, g, final)
    local st = state(r)
    local running = false
    pcall(function() running = r.Controller.BrainComponent:IsRunning() == true end)
    if running then
        brainOff(r)
        log("Lovesick: the game restarted her brain - switched off again")
    end
    if not st.attackOff then
        st.attackOff = true
        pcall(function() r.AttackBox:SetCollisionEnabled(0) end)
    end
    -- падение / реакция на попадание: стоим, пока игра доигрывает свою анимацию
    if gameMontage(r) then
        speed(r, 0)
        st.busyUntil = g + 0.3
        return
    end
    -- в движении: никаких расследований игры (предмет упал рядом) и чужих анимаций на месте
    if MOVING[st.mode] then
        pcall(function() if r.bIsInvestigating then r.bIsInvestigating = false end end)
        local cur = nil
        pcall(function() cur = r:GetCurrentMontage() end)
        if valid(cur) then pcall(function() r:StopAnimMontage(nil) end) end
        -- встала (MoveTo сбросился) — сразу новый приказ
        if st.still > 0.6 and st.dest then goTo(st, st.dest, g) end
    end
    local o = origSpeeds(r)
    local me = playerLoc(); if not me then return end
    local l = r:K2_GetActorLocation()
    local pos = { X = l.X, Y = l.Y, Z = l.Z }
    local dist = vlen(pos.X - me.X, pos.Y - me.Y, 0)
    local sees = rokuSeesNM(r)
    local hiding = false
    pcall(function() hiding = getPawn().bIsHiding == true end)

    -- застряла?
    if st.lastPos then
        local moved = vlen(pos.X - st.lastPos.X, pos.Y - st.lastPos.Y, 0)
        st.still = (moved < 5) and (st.still + 0.1) or 0
    end
    st.lastPos = pos

    if st.mode == "hug" then
        speed(r, 0, true)
        if g - st.t >= 2.4 then
            -- сразу снова за тобой
            setMode(st, "chase", g)
            st.lastSeen, st.lastLoc = g, me
            st.hugReady = g + 1.0       -- только чтобы не обнять дважды в одном кадре после толчка
        end
        return
    elseif st.mode == "stun" then
        speed(r, 0)
        if g - st.t >= 2.5 then setMode(st, "chase", g); st.lastSeen = g end
        return
    elseif st.mode == "shy" then
        speed(r, final and o.chase or o.move, final)
        if g - st.t >= 4 then setMode(st, "wander", g) end
        return
    end

    -- увидела — гонится
    if sees and not hiding and st.mode ~= "chase" then
        setMode(st, "chase", g); st.lastSeen = g
        log("Lovesick: she sees you")
    end

    if st.mode == "chase" then
        speed(r, final and o.chase or o.chase * 0.85, true)
        if sees and not hiding then st.lastSeen = g; st.lastLoc = me end
        if g >= st.nextOrder then goTo(st, st.lastLoc or me, g) end
        if dist < HUG_DIST and g >= st.hugReady and not hiding then hug(st, g) return end
        if g - (st.lastSeen or g) > (final and 30 or 5) then
            pcall(function() r.Controller:StopMovement() end)
            playLookAround(r)
            setMode(st, "look", g)
        end
    elseif st.mode == "seek" then
        speed(r, o.chase, true)
        if not st.dest or g >= st.nextOrder + 2 then goTo(st, st.seekLoc or me, g) end
        if vlen(pos.X - st.dest.X, pos.Y - st.dest.Y, 0) < 200 or st.still > 3 then
            playLookAround(r); setMode(st, "look", g)
        end
    elseif st.mode == "look" then
        speed(r, 0)
        if g - st.t >= (final and 1 or 4) then setMode(st, "wander", g) end
    else -- wander
        speed(r, final and o.chase or o.move, final)
        if not st.dest or vlen(pos.X - st.dest.X, pos.Y - st.dest.Y, 0) < 150 or st.still > 3 then
            local d = pickDest(r); if d then goTo(st, d, g) end
        end
    end
end

-- "Сила любви": она узнаёт, где ты
local function lovePing(g, quiet)
    local me = playerLoc(); if not me then return end
    for _, r in ipairs(allRokus()) do
        local st = state(r)
        if st.mode == "wander" or st.mode == "look" or st.mode == "seek" then
            setMode(st, "seek", g); st.seekLoc = me
            goTo(st, me, g)
        elseif st.mode == "chase" then
            st.lastSeen, st.lastLoc = g, me
        end
    end
    if not quiet then flash("+ SHE KNOWS +", 2.5); log("Lovesick: love power - she knows where you are") end
end

-- следим за брошенным предметом: долетел до Року — подарок
function loveOnSpank() if LV.on then LV.spanked = true end end
function loveOnThrow(obj)
    if not LV.on or not valid(obj) then return end
    LV.thrown = { obj = obj, untilT = (gameNow() or 0) + 3 }
end

local function giftTick(g)
    local th = LV.thrown
    if not th then return end
    if g > th.untilT or not valid(th.obj) then LV.thrown = nil return end
    local ip = itemPos(th.obj); if not ip then return end
    -- подарок = попал В НЕЁ на лету, а не упал рядом
    local fast = false
    if th.last then
        local dt = g - th.lastG
        if dt > 0.01 then fast = vlen(ip.X - th.last.X, ip.Y - th.last.Y, ip.Z - th.last.Z) / dt > 250 end
    end
    th.last, th.lastG = ip, g
    if not fast then return end
    for _, r in ipairs(allRokus()) do
        local l = r:K2_GetActorLocation()
        if vlen(ip.X - l.X, ip.Y - l.Y, ip.Z - (l.Z + 40)) < 110 then
            LV.thrown = nil
            gift(state(r), th.obj, g)
            return
        end
    end
end

function loveLeft()
    if not LV.on and not LV.finalLeft then return nil end
    if not LV.on then return LV.finalLeft end
    return LV.limit - ((gameNow() or 0) - LV.t0)
end
function lovePercent() return math.floor((LV.love or 0) * 100 + 0.5) end
function loveSkip(sec) if LV.on then LV.t0 = LV.t0 - sec; LV.nextPing = LV.nextPing - sec end end
function loveActive() return LV.on end

loveStart = function(minutes)
    LV.on, LV.lost, LV.won = true, false, false
    LV.limit, LV.t0 = (minutes or 8) * 60, gameNow() or 0
    LV.love, LV.rokus, LV.lastHug, LV.thrown, LV.finalLeft = 0, {}, -100, nil, nil
    LV.nextPing = LV.t0 + rnd(70, 100)
    LV.finalAnnounced = false
    LV.killed, LV.nextSweep = {}, LV.t0 + 3
    setHiders(true)
    log("Lovesick: removed " .. lvSweep(true) .. " items")
    after(12000, function() if LV.on then lvAddGifts() end end)
    log("Lovesick: started, " .. (minutes or 8) .. " min")
end

loveStop = function()
    if not LV.on then return end
    LV.finalLeft = loveLeft()
    LV.on = false
    for _, st in pairs(LV.rokus or {}) do
        if valid(st.r) then
            local o = LAB.orig[st.r:GetAddress()]
            if o then
                pcall(function() st.r.CharacterMovement.MaxWalkSpeed = o.move end)
                setIf(st.r, "MoveSpeed", o.move); setIf(st.r, "chasespeed", o.chase)
            end
            pcall(function() st.r.bIsChasing = false end)
            pcall(function() st.r.AttackBox:SetCollisionEnabled(1) end)
            pcall(function() st.r:DrunkClear() end)
            brainOn(st.r)
        end
    end
    LV.rokus = {}
    setHiders(false)
    log("Lovesick: stopped")
end

every(100, function()
    if not LV.on or R.phase ~= "running" then return end
    local p = getPawn(); if not p then return end
    local g = gameNow() or 0
    local left = LV.limit - (g - LV.t0)
    -- здоровье всегда полное: она не бьёт
    pcall(function() if (num(p.health) or 1) < 1 then p.health = 1.0 end end)
    -- она пьяна весь забег. Опьянение у игры — переменная Drunk_level (её поднимает пиво/вино)
    -- + эффект NS_drunk; держим уровень не ниже DRUNK, вызываем DrunkMode и пишем в лог изменения
    for _, r in ipairs(allRokus()) do
        local st = LV.rokus[r:GetAddress()]
        if st and g - st.drunkAt > 1 then
            st.drunkAt = g
            local lvl = nil
            pcall(function() lvl = num(r.Drunk_level) end)
            if lvl ~= st.lastLvl then
                log("Lovesick: Roku drunk level " .. tostring(st.lastLvl) .. " -> " .. tostring(lvl))
                st.lastLvl = lvl
            end
            if lvl and lvl < LV_DRUNK then
                pcall(function() r.Drunk_level = LV_DRUNK end)
                if not st.drunkCalled or g - st.drunkCalled > 30 then
                    st.drunkCalled = g
                    local ok = pcall(function() r:DrunkMode() end)
                    log("Lovesick: DrunkMode() -> " .. tostring(ok))
                end
            end
            pcall(function()
                local fx = r.NS_drunk
                if valid(fx) then fx:SetVisibility(true, false); if not fx:IsActive() then fx:Activate(true) end end
            end)
        end
    end
    -- шлёпнул упавшую пьяную Року: она смущена, влюблённость падает
    if LV.spanked then
        LV.spanked = false
        LV.love = math.max(0, LV.love - 0.15)
        showBanner("+ BEHAVE! +", 2)
        log(string.format("Lovesick: spank! love -15%% -> %.0f%%", LV.love * 100))
    end
    local final = left <= FINAL
    for _, r in ipairs(allRokus()) do
        local ok, err = pcall(rokuTick, r, g, final)
        if not ok then log("Lovesick: roku tick error " .. tostring(err)) end
    end
    giftTick(g)
    -- игра доспавнивает предметы с задержкой: лишнее убираем вдали от игрока
    if g >= LV.nextSweep then
        LV.nextSweep = g + 3
        setHiders(true)
        local n = lvSweep(false)
        if n > 0 then log("Lovesick: removed " .. n .. " more items") end
    end
    -- остывает, если давно не обнимала
    if g - LV.lastHug > 15 then LV.love = math.max(0, LV.love - 0.01 / 3 * 0.1) end   -- 1% за 3 с
    -- сила любви: чем ближе к концу, тем чаще; в конце — постоянно
    if final then
        if not LV.finalAnnounced then
            LV.finalAnnounced = true
            flash("+ SHE ALWAYS KNOWS +", 3)
            showBanner("+ SHE ALWAYS KNOWS +", 4)
        end
        if g >= LV.nextPing then LV.nextPing = g + 4; lovePing(g, true) end
    elseif g >= LV.nextPing then
        local k = math.max(0, math.min(1, (g - LV.t0) / math.max(1, LV.limit - FINAL)))
        LV.nextPing = g + rnd(70, 100) * (1 - k) + rnd(25, 35) * k
        lovePing(g, false)
    end
    -- выжил: вместе
    if left <= 0 and not LV.won and not LV.lost then
        LV.won = true
        defeat({ title = "+ SOBER +", sub = "She sobered up. Now she's just embarrassed.",
            veil = { 0.3, 0.05, 0.18 }, color = PINK, fadeIn = 2.0, hold = 4.5, scripted = true,
            result = "win", victory = true })
    end
end)
end)() -- LOVESICK
