-- Лампы уровня, которые безопасно трогать: только настоящие (в PersistentLevel, не шаблоны
-- классов), не на предметах, не на Року и не на игроке.
function levelLights()
    local out = {}
    for _, cn in ipairs({ "PointLightComponent", "SpotLightComponent", "RectLightComponent" }) do
        for _, l in ipairs(FindAllOf(cn) or {}) do
            if valid(l) then
                local full = ""
                pcall(function() full = l:GetFullName() end)
                if full:find("PersistentLevel", 1, true) and not full:find("Default__", 1, true) then
                    local owner = nil
                    pcall(function() owner = l:GetOwner() end)
                    local oname = ""
                    if valid(owner) then pcall(function() oname = owner:GetClass():GetFName():ToString() end) end
                    if oname ~= "" and not oname:find("BP_T_") and not oname:find("Rokuv3") and not oname:find("HorrorCharacter") then
                        out[#out + 1] = l
                    end
                end
            end
        end
    end
    return out
end

; (function() -- раздел в своей функции: в одной функции Lua не больше 200 локальных
------------------------------------------------------------------------
-- МУТАТОРЫ ИГРОКА (список от 12.10.2026)
-- Стоят здесь, в конце: им нужны функции лаборатории (бродилка, спавн Року).
------------------------------------------------------------------------
local function rnd(a, b) return a + math.random() * (b - a) end

-- Сцена смерти от мутатора: надпись в стиле игры, затемнение, потом смерть
local function deathScene(o)
    if R.phase ~= "running" or R.scene then return end
    R.scene = true
    o.scripted = true
    defeat(o)
    after((o.fadeIn or 1.5) * 1000 + 200, function() R.scene = nil end)
end

-- Сколько видит / помнит игрока конкретная Року
local function rokuSees(r)
    local inBox, trace = false, false
    pcall(function() inBox = r.bPlayerInVisionBox == true end)
    pcall(function() trace = r.bLineTraceHitPlayer == true end)
    return inBox and trace
end
local function rokuChasing(r)
    local bb = false
    ctrlCall(r, function(c) bb = c.Blackboard:GetValueAsBool(FName("bPlayerDetected")) == true end)
    return bb or rokuSees(r)
end

-- класс предмета: если не загружен на уровне — пробуем загрузить
function itemClass(path)
    local c = nil
    pcall(function() c = StaticFindObject(path) end)
    if valid(c) then return c end
    if LoadAsset then
        pcall(function() LoadAsset(path:gsub("%.[^%.]+$", "")) end)
        pcall(function() c = StaticFindObject(path) end)
        if valid(c) then return c end
    end
    return nil
end

-- случайные места, где игра сама кладёт предметы (спавнеры), подальше от игрока
function itemSpots(n, minDist)
    local pawn = getPawn(); if not pawn then return {} end
    local me = pawn:K2_GetActorLocation()
    local all = FindAllOf("BP_ItemSpawner_C") or {}
    local out = {}
    if #all == 0 then return out end
    for _ = 1, n * 12 do
        if #out >= n then break end
        local sp = all[math.random(1, #all)]
        if valid(sp) then
            pcall(function()
                local l = sp:K2_GetActorLocation()
                if vlen(l.X - me.X, l.Y - me.Y, 0) >= minDist then out[#out + 1] = { X = l.X, Y = l.Y, Z = l.Z } end
            end)
        end
    end
    return out
end

------------------------------------------------------------------------
-- Поломка реактора: успей до взрыва
------------------------------------------------------------------------
-- Свет комплекса: после 5 минут до взрыва краснеет, в последнюю минуту мигает тревогой.
-- Свои источники (фонарик в руке, свет на Року) не трогаем.
local ALARM = { lights = nil }
onForgetRefs(function() ALARM.lights = nil end)
local function alarmLights()
    if ALARM.lights then return ALARM.lights end
    local list = {}
    for _, l in ipairs(levelLights()) do
        local e = { c = l }
        pcall(function() local c = l.LightColor; e.col = { R = c.R / 255, G = c.G / 255, B = c.B / 255 } end)
        pcall(function() e.int = num(l.Intensity) end)
        if e.col then list[#list + 1] = e end
    end
    ALARM.lights = list
    log("Reactor: " .. #list .. " lights in the complex")
    return list
end
-- k: 0 = родной цвет, 1 = полностью красный; f — множитель яркости
local function tintLights(k, f)
    for _, e in ipairs(alarmLights()) do
        if valid(e.c) then
            local r = e.col.R + (1 - e.col.R) * k
            local g = e.col.G * (1 - k * 0.92)
            local b = e.col.B * (1 - k * 0.92)
            pcall(function() e.c:SetLightColor({ R = r, G = g, B = b, A = 1 }, true) end)
            if e.int and f then pcall(function() e.c:SetIntensity(e.int * f) end) end
        end
    end
end
local function restoreLights()
    if not ALARM.lights then return end
    for _, e in ipairs(ALARM.lights) do
        if valid(e.c) then
            pcall(function() e.c:SetLightColor({ R = e.col.R, G = e.col.G, B = e.col.B, A = 1 }, true) end)
            if e.int then pcall(function() e.c:SetIntensity(e.int) end) end
        end
    end
    ALARM.lights = nil
end

-- Уровни реактора: один мутатор "Reactor" в меню, уровень выбирается стрелками.
-- id остались прежними (reactor / critical / meltdown) — рекорды не теряются.
--   Failure  — давление временем: свет иногда моргает, краснеет за 5 мин, тревога в последнюю минуту
--   Critical — темнота: раз в 2-3 мин свет гаснет на 5-8 с (с предупреждением), красный с 10 мин
--   Meltdown — всё красное с начала, отключения чаще и дольше, жара (стамина копится медленнее),
--              в последние 3 минуты Року на взводе (быстрее)
REACTOR_LEVELS = { "reactor", "critical", "meltdown" }

local LEVEL = {
    reactor  = { minutes = 30, redAt = 300, flicker = { 40, 90 } },
    critical = { minutes = 20, redAt = 600, flicker = { 40, 90 }, blackout = { every = { 120, 180 }, dur = { 5, 8 } } },
    meltdown = { minutes = 17, redAt = 1e9, flicker = { 30, 60 }, blackout = { every = { 70, 110 }, dur = { 8, 12 } },
                 heat = 0.5, edge = { at = 180, mult = 1.12 } },
}

-- в отключение, кроме ламп: небо, тени, виньетка (DARK_PRESET в darkness.lua)
local function darkExtras(on) darkPreset(on, "reactor") end

-- Року на взводе: её собственные скорости (шаг и погоня) чуть выше
local function edgeRokus(s, mult)
    s.edged = s.edged or {}
    for _, r in ipairs(allRokus()) do
        local addr = r:GetAddress()
        if not s.edged[addr] then
            local o = origSpeeds(r)
            s.edged[addr] = { r = r, o = o }
            pcall(function() r.MoveSpeed = o.move * mult end)
            pcall(function() r.chasespeed = o.chase * mult end)
        end
    end
end
local function calmRokus(s)
    for _, e in pairs(s.edged or {}) do
        if valid(e.r) then
            pcall(function() e.r.MoveSpeed = e.o.move end)
            pcall(function() e.r.chasespeed = e.o.chase end)
        end
    end
    s.edged = nil
end

local function reactor(id, name, desc)
    local L = LEVEL[id]
    mutator {
        id = id, name = name, tags = { "timer" }, chaos = false, desc = desc, reactor = true,
        limit = L.minutes * 60,
        countdown = function(s) return s.limit - ((gameNow() or 0) - s.t0) end,
        on = function(s)
            local g = gameNow() or 0
            s.t0, s.limit, s.warned = g, L.minutes * 60, {}
            s.red, s.redDone, s.pattern = 0, false, {}
            s.nextFlicker = g + rnd(L.flicker[1], L.flicker[2])
            if L.blackout then s.nextBlack = g + rnd(L.blackout.every[1], L.blackout.every[2]) * 0.6 end
            s.black, s.blackEnd, s.blackWarnAt = false, nil, nil
            s.lastSM = nil
        end,
        tick = function(s, dt)
            local g = gameNow() or 0
            local left = s.limit - (g - s.t0)
            for _, w in ipairs({ 600, 300, 180, 60, 10 }) do
                if left <= w and left > w - 5 and not s.warned[w] and s.limit > w then
                    s.warned[w] = true
                    local msg
                    if w == 180 then
                        if L.edge then msg = "+ SHE FEELS THE HEAT +" end
                    elseif w >= 60 then msg = string.format("+ REACTOR: %d MIN LEFT +", w // 60)
                    else msg = "+ REACTOR: 10 SECONDS +" end
                    if msg then
                        showBanner(msg, 4)
                        flash(msg, 3, MUT_COLOR[id] or MUT_COLOR.reactor)
                    end
                end
            end

            -- Року на взводе (Meltdown, последние минуты)
            if L.edge and left <= L.edge.at then edgeRokus(s, L.edge.mult) end

            -- жара: стамина восстанавливается медленнее (трата — как обычно)
            if L.heat then
                local p = getPawn()
                if p then
                    local sm = nil
                    pcall(function() sm = num(p["Sprint Meter"]) end)
                    if sm and s.lastSM and sm > s.lastSM then
                        sm = s.lastSM + (sm - s.lastSM) * L.heat
                        pcall(function() p["Sprint Meter"] = sm end)
                    end
                    s.lastSM = sm
                end
            end

            -- отключения света (не в последнюю минуту: там тревога)
            if L.blackout and left > 70 then
                if not s.black and not s.blackWarnAt and g >= s.nextBlack then
                    s.blackWarnAt = g
                    showBanner("+ POWER FAILURE +", 2.5)
                    flash("+ POWER FAILURE +", 2, MUT_COLOR[id] or MUT_COLOR.reactor)
                    s.pattern = { 0.3, 1, 0.15, 1, 0.3, 0.1, 1, 0.05 }   -- лампы дёргаются 2 с
                elseif s.blackWarnAt and not s.black and g - s.blackWarnAt >= 2 then
                    s.black, s.blackWarnAt = true, nil
                    s.blackEnd = g + rnd(L.blackout.dur[1], L.blackout.dur[2])
                    s.pattern = {}
                    tintLights(s.red, 0)
                    darkExtras(true)
                    log(string.format("Reactor: blackout for %.0f s", s.blackEnd - g))
                end
            end
            if s.black then
                if g >= s.blackEnd or left <= 62 then
                    s.black = false
                    darkExtras(false)
                    tintLights(s.red, 1)
                    s.redDone = false
                    s.pattern = { 0.2, 1, 0.4, 1 }                        -- свет возвращается рывками
                    s.nextBlack = g + rnd(L.blackout.every[1], L.blackout.every[2])
                    log("Reactor: power back")
                end
                -- лампы держим выключенными (тревога/покраснение не включают их обратно)
                if s.black then return end
            end

            -- покраснение: плавно за 30 с, начиная с redAt
            local f = nil
            if left <= L.redAt then s.red = math.min(1, s.red + (dt or 0.25) / 30) end
            -- тревога: последняя минута
            if left <= 60 then
                s.blink = not s.blink
                f = s.blink and 1.0 or 0.35
            elseif #s.pattern > 0 then
                f = table.remove(s.pattern, 1)
            elseif g >= s.nextFlicker and not s.blackWarnAt then
                s.nextFlicker = g + rnd(L.flicker[1], L.flicker[2])
                s.pattern = { 1, 0.25, 1 }
                f = 0.2
            end
            if f or s.red > 0 and (s.red < 1 or not s.redDone) then
                tintLights(s.red, f or 1)
                s.redDone = s.red >= 1 and not f
            end

            if left <= 0 and not s.boom then
                s.boom = true
                tintLights(0, 4)            -- вспышка
                deathScene({ title = "+ MELTDOWN +", sub = "The reactor took the complex - and you - with it.",
                    white = true, veil = { 0.14, 0.0, 0.02 }, color = GAME.warn, fadeIn = 1.6, hold = 4, result = "meltdown" })
            end
        end,
        off = function(s)
            if s.black then darkExtras(false) end
            s.black = false
            restoreLights()
            calmRokus(s)
        end,
    }
end
reactor("reactor", "Reactor Failure",
    "30 minutes until the reactor blows. Lights flicker, turn red at 5 minutes, alarm in the last minute.")
reactor("critical", "Critical Failure",
    "20 minutes. The power keeps failing: every few minutes the complex goes dark for a few seconds. Red from 10 minutes.")
reactor("meltdown", "Meltdown",
    "17 minutes. Red from the start, longer and more frequent blackouts, the heat slows stamina recovery, and in the last 3 minutes Roku gets faster.")

------------------------------------------------------------------------
-- Скользкие руки: предмет время от времени выпадает (слабый бросок, как F)
------------------------------------------------------------------------
-- Бросок предмета у игры: BP_ThrowableBase:Throw(ThrowDirection, PlayerRef).
-- ThrowDirection — уже готовая скорость броска (силу игрок набирает сам),
-- поэтому маленький вектор = предмет просто выпадает из рук чуть вперёд.
local function tryDrop(item)
    local p = getPawn(); if not p or not valid(item) then return false, "no player/item" end
    local f = { X = 1, Y = 0, Z = 0 }
    pcall(function()
        local rot = getPC():GetControlRotation()
        local y = math.rad(rot.Yaw)
        f = { X = math.cos(y), Y = math.sin(y), Z = 0 }
    end)
    local dir = { X = f.X * 120, Y = f.Y * 120, Z = 60 }
    local ok, err = pcall(function() item:Throw(dir, p) end)
    return ok, ok and "item:Throw(small toss)" or tostring(err)
end

mutator {
    id = "slippery", name = "Slippery Hands", tags = { "hands" }, loveOk = true,
    desc = "Every now and then the item you hold slips out of your hands. Quick hands can catch it.",
    on = function(s) s.next = (gameNow() or 0) + rnd(25, 45) end,
    tick = function(s)
        local g = gameNow() or 0
        if not valid(R.held) then s.next = math.max(s.next, g + rnd(8, 15)) return end
        if R.heldAt and g - R.heldAt < 6 then return end          -- только что подобрал
        if g < s.next then return end
        s.next = g + rnd(25, 55)
        local item = R.held
        local ok, info = tryDrop(item)
        log("Slippery hands: drop attempt -> " .. tostring(ok) .. " (" .. tostring(info) .. ")")
        if ok then showBanner("+ OOPS +", 2) end
        if ok then R.held = nil end
        -- проверка для лога: что предмет сам о себе думает после броска
        after(600, function()
            if not valid(item) then return end
            local st, thrown = "?", "?"
            pcall(function() st = tostring(item.State) end)
            pcall(function() thrown = tostring(item.bIsThrown) end)
            log("Slippery hands: after the drop item State=" .. st .. " bIsThrown=" .. thrown)
        end)
    end,
}

------------------------------------------------------------------------
-- SUTEGOMA: кровотечение, больше аптечек
------------------------------------------------------------------------
local MEDKIT = "/Game/INTERACTION/BP_Medikit.BP_Medikit_C"
local BLEED_PER_SEC = 1 / 300       -- от полного здоровья до нуля за 5 минут

mutator {
    id = "sutegoma", name = "SUTEGOMA", tags = { "health" }, noNightmare = true,
    desc = "You are bleeding out: health slowly drains. Heal up from time to time - there are more medkits around.",
    on = function(s)
        s.medkits = 0
        local cls = itemClass(MEDKIT)
        local pawn = getPawn()
        if cls and pawn then
            for _, l in ipairs(itemSpots(14, 1500)) do
                local a = nil
                pcall(function()
                    a = pawn:GetWorld():SpawnActor(cls, { X = l.X, Y = l.Y, Z = l.Z + 15 }, { Pitch = 0, Yaw = math.random(0, 359), Roll = 0 })
                end)
                if valid(a) then s.medkits = s.medkits + 1 end
            end
        end
        log("SUTEGOMA: extra medkits placed: " .. s.medkits .. (cls and "" or " (medkit class not found)"))
    end,
    tick = function(s, dt)
        local p = getPawn(); if not p then return end
        local hp = num(p.health); if not hp then return end
        hp = hp - BLEED_PER_SEC * (dt or 0.25)
        if hp <= 0.001 then
            if not s.dead then
                s.dead = true
                p.health = 0.001
                log("SUTEGOMA: bled out")
                deathScene({ title = "+ BLED OUT +", sub = "SUTEGOMA", veil = { 0.09, 0.0, 0.0 }, color = GAME.blood,
                    fadeIn = 2.2, hold = 4, result = "dead" })
            end
            return
        end
        p.health = hp
    end,
    hud = function(s)
        local p = getPawn()
        local hp = p and num(p.health) or 0
        return string.format("BLEEDING  %d%%", math.floor(hp * 100 + 0.5)), hp < 0.3
    end,
}

------------------------------------------------------------------------
-- Двойняшки: вторая Року бродит сама по себе, но если увидит — атакует
------------------------------------------------------------------------
local function spawnFarRoku()
    local pawn = getPawn(); if not pawn then return nil end
    local cls = StaticFindObject("/Game/ROKUv3/BP_Rokuv3.BP_Rokuv3_C")
    if not valid(cls) then return nil end
    local loc = stealthSpot(); if not loc then return nil end
    local a = nil
    pcall(function()
        a = pawn:GetWorld():SpawnActor(cls, { X = loc.X, Y = loc.Y, Z = loc.Z + 120 }, { Pitch = 0, Yaw = math.random(0, 359), Roll = 0 })
    end)
    if not valid(a) then return nil end
    LAB.born[a:GetAddress()] = os.clock()
    after(1500, function()
        if not valid(a) then return end
        local has = false
        has = aiCtrl(a) ~= nil
        if not has then pcall(function() a:SpawnDefaultController() end) end
    end)
    log(string.format("Twins: second Roku spawned at (%.0f, %.0f)", loc.X, loc.Y))
    return a
end

-- Наряды Року: её функция ApplyOutfit(имя строки) берёт наряд из таблицы данных.
-- Ищем эту таблицу среди загруженных DataTable и берём имена строк.
local function outfitNames()
    local names, tables = {}, {}
    for _, dt in ipairs(FindAllOf("DataTable") or {}) do
        if valid(dt) then
            local n = describe(dt)
            local ln = n:lower()
            if ln:find("outfit") or ln:find("skin") or ln:find("costume") then
                tables[#tables + 1] = n
                pcall(function()
                    local lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
                    local out = {}
                    lib:GetDataTableRowNames(dt, out)
                    for _, v in ipairs(out) do
                        local s2 = nil
                        pcall(function() s2 = v:ToString() end)
                        if not s2 then pcall(function() s2 = v:get():ToString() end) end
                        if s2 then names[#names + 1] = s2 end
                    end
                end)
                if #names == 0 then
                    pcall(function()
                        local rows = dt:GetRowNames()
                        rows:ForEach(function(_, e) names[#names + 1] = e:get():ToString() end)
                    end)
                end
            end
        end
    end
    return names, tables
end

local function currentSkin(r)
    local s2 = nil
    pcall(function() s2 = r.CurrentSkin:ToString() end)
    return s2
end

-- надеть второй Року другой наряд, не как у первой
local function dressTwin(twin, original)
    local names, tables = outfitNames()
    local mine = original and currentSkin(original)
    log("Twins: outfit tables: " .. (#tables > 0 and table.concat(tables, ", ") or "none found")
        .. "; rows: " .. (#names > 0 and table.concat(names, ", ") or "none") .. "; first Roku wears: " .. tostring(mine))
    if #names == 0 then
        -- таблицу не прочитали: пробуем имена по скинам из достижений (неудачное имя игра просто пропустит)
        names = { "Bunny", "Sailor", "Shibari", "Cowmeat", "Dark", "ShirtOff", "Bottomless", "Bikini", "Source" }
    end
    local pool = {}
    for _, n in ipairs(names) do if n ~= mine and n ~= "None" then pool[#pool + 1] = n end end
    if #pool == 0 then return false end
    local pick = pool[math.random(1, #pool)]
    local ok = pcall(function() twin:ApplyOutfit(FName(pick)) end)
    log("Twins: second Roku outfit '" .. pick .. "' -> " .. tostring(ok))
    return ok
end

mutator {
    id = "twins", name = "Twins", tags = { "rokus", "wander" }, chaos = false, noStealth = true,
    desc = "A second Roku roams the map. She doesn't hunt you on purpose - but if she sees you, she attacks just like the first.",
    on = function(s)
        s.mode, s.twin, s.lost = "wait", nil, 0
        s.saved = { LAB.noiseThrow, LAB.noiseSprint, LAB.noiseVent, LAB.noiseDoor }
        -- шумы нашей бродилки не нужны: родная Року слышит сама
        LAB.noiseThrow, LAB.noiseSprint, LAB.noiseVent, LAB.noiseDoor = false, false, false, false
    end,
    tick = function(s, dt)
        if s.mode == "wait" then
            -- ждём родную Року (она появляется по триггеру после лифта)
            if #allRokus() == 0 then return end
            local original = allRokus()[1]
            s.twin = spawnFarRoku()
            if not s.twin then s.mode = "failed" return end
            local twin = s.twin
            after(2000, function() if valid(twin) then dressTwin(twin, original) end end)
            s.addr = s.twin:GetAddress()
            LAB.wanderOnly = { [s.addr] = true }
            LAB.targets = {}
            LAB.wander = true
            s.mode = "wander"
            return
        end
        local t = s.twin
        if not valid(t) then return end
        if s.mode == "wander" then
            if rokuSees(t) then
                -- увидела: включаем ей родной мозг, бегом как обычно
                LAB.wanderOnly[s.addr] = nil
                LAB.targets[s.addr] = nil
                local o = origSpeeds(t)
                setIf(t, "MoveSpeed", o.move); setIf(t, "chasespeed", o.chase)
                brainOn(t)
                s.mode, s.lost = "hunt", 0
                log("Twins: the second Roku spotted you")
            end
        elseif s.mode == "hunt" then
            if rokuChasing(t) then s.lost = 0 else s.lost = s.lost + (dt or 0.25) end
            if s.lost >= 8 then
                -- потеряла: снова бродит сама по себе
                brainOff(t)
                LAB.wanderOnly[s.addr] = true
                s.mode = "wander"
                log("Twins: the second Roku lost you, back to roaming")
            end
        end
    end,
    off = function(s)
        LAB.wander = false
        LAB.wanderOnly = nil
        LAB.targets = {}
        if valid(s.twin) then
            ctrlCall(s.twin, function(c) c:K2_DestroyActor() end)
            pcall(function() s.twin:K2_DestroyActor() end)
        end
        if s.saved then
            LAB.noiseThrow, LAB.noiseSprint, LAB.noiseVent, LAB.noiseDoor = s.saved[1], s.saved[2], s.saved[3], s.saved[4]
        end
    end,
    hud = function(s)
        if s.mode == "hunt" then return "TWIN: HUNTING", true end
        return nil
    end,
}

------------------------------------------------------------------------
-- Нет еды: еда исчезает из комплекса (яблоки-образцы не трогаем)
------------------------------------------------------------------------
-- еда по словам игрока: яблоки, морковь, кофе, пиво, вино; яблоки-образцы (BP_PineCone_C) не трогаем
local FOOD = { "BP_T_Apple_C", "BP_T_Carrot_C", "BP_coffee_C", "BP_T_Beercan_C", "4pack_of_beer_C", "BP_T_WineBottle_C" }

local function sweepFood(keepNear)
    local pawn = getPawn(); if not pawn then return 0 end
    local me = pawn:K2_GetActorLocation()
    local n = 0
    for _, cn in ipairs(FOOD) do
        for _, a in ipairs(FindAllOf(cn) or {}) do
            if valid(a) and a ~= R.held then
                local far = true
                if keepNear then
                    pcall(function()
                        local l = itemPos(a) or a:K2_GetActorLocation()
                        far = vlen(l.X - me.X, l.Y - me.Y, l.Z - me.Z) > keepNear
                    end)
                end
                if far and pcall(function() a:K2_DestroyActor() end) then n = n + 1 end
            end
        end
    end
    return n
end

mutator {
    id = "nofood", name = "No Food", tags = { "items" }, chaos = false,
    desc = "No apples, carrots, drinks or coffee: only trash and junk to throw. Short staggers, no drunk Roku, no coffee boost.",
    on = function(s)
        s.removed = sweepFood(nil)
        s.next = (gameNow() or 0) + 3
        log("No food: removed " .. s.removed .. " food item(s)")
    end,
    tick = function(s)
        local g = gameNow() or 0
        if g < s.next then return end
        s.next = g + 3
        -- новые (если игра доспавнит) — только вдали от игрока, чтобы не исчезали на глазах
        local n = sweepFood(600)
        if n > 0 then s.removed = s.removed + n; log("No food: removed " .. n .. " more") end
    end,
}

------------------------------------------------------------------------
-- Зумиз: Року всё время бегает, но иногда останавливается отдышаться
-- (если видит игрока — не останавливается)
------------------------------------------------------------------------
mutator {
    id = "zoomies", name = "Zoomies", tags = { "roku_speed" },
    desc = "Roku runs everywhere from the very start. Now and then she stops to catch her breath - but never while she sees you.",
    on = function(s) s.phase, s.untilT = "run", (gameNow() or 0) + rnd(40, 70) end,
    tick = function(s)
        local g = gameNow() or 0
        local rokus = allRokus()
        local anyChase = false
        for _, r in ipairs(rokus) do if rokuChasing(r) then anyChase = true end end
        if s.phase == "run" and g >= s.untilT and not anyChase then
            s.phase, s.untilT = "rest", g + rnd(12, 20)
            for _, r in ipairs(rokus) do
                ctrlCall(r, function(c) c:StopMovement() end)
                playLookAround(r)
            end
            log("Zoomies: Roku is catching her breath")
        elseif s.phase == "rest" and (g >= s.untilT or anyChase) then
            s.phase, s.untilT = "run", g + rnd(40, 70)
            log("Zoomies: Roku runs again" .. (anyChase and " (she saw you)" or ""))
        end
        for _, r in ipairs(rokus) do
            local o = origSpeeds(r)
            if s.phase == "run" then
                setIf(r, "MoveSpeed", o.chase); setIf(r, "chasespeed", o.chase)
            else
                -- отдых: обход стоит, погоня — как обычно
                setIf(r, "MoveSpeed", 0); setIf(r, "chasespeed", o.chase)
                if not rokuChasing(r) then pcall(function() setIf(r.CharacterMovement, "MaxWalkSpeed", 0) end) end
            end
        end
    end,
    off = function(s)
        for _, r in ipairs(allRokus()) do
            local o = LAB.orig[r:GetAddress()]
            if o then
                setIf(r, "MoveSpeed", o.move); setIf(r, "chasespeed", o.chase)
                pcall(function() r.CharacterMovement.MaxWalkSpeed = o.move end)
            end
        end
    end,
    hud = function(s)
        if s.phase == "rest" then return "ROKU: CATCHING HER BREATH", false end
        return nil
    end,
}

-- экраны поражения, когда убила Року (у реактора и SUTEGOMA есть ещё свои сцены)
do
    local L = {
        reactor  = { "+ SHE GOT YOU FIRST +", "The reactor never got its chance." },
        critical = { "+ SHE GOT YOU FIRST +", "The reactor never got its chance." },
        meltdown = { "+ SHE GOT YOU FIRST +", "Fast legs. Not fast enough." },
        slippery = { "+ BUTTERFINGERS +", "Should've held on tighter." },
        sutegoma = { "+ SUTEGOMA +", "You were already bleeding. She just finished it.", { 0.09, 0, 0 }, GAME.blood },
        twins    = { "+ TWO OF HER +", "One was hunting you. The other just found you." },
        nofood   = { "+ NO TREATS +", "Trash only buys you a second. She wanted an apple." },
        zoomies  = { "+ TOO FAST +", "She never even needed to catch her breath." },
        razor    = { "+ SHREDDED +", "Those claws were sharper than usual." },
    }
    for id, e in pairs(L) do
        if MUTS[id] then MUTS[id].lose = { title = e[1], sub = e[2], veil = e[3], color = e[4] } end
    end
end

-- порядок в меню: сначала мутаторы игрока, потом старые тестовые
do
    local want = { "reactor", "critical", "meltdown", "slippery", "sutegoma", "twins", "nofood", "zoomies", "razor" }
    local seen, order = {}, {}
    for _, id in ipairs(want) do if MUTS[id] then order[#order + 1] = id; seen[id] = true end end
    for _, id in ipairs(MUT_ORDER) do if not seen[id] then order[#order + 1] = id end end
    for i = 1, #order do MUT_ORDER[i] = order[i] end
end

------------------------------------------------------------------------
-- Разведка для мутаторов (лаборатория): функции с параметрами и переменные
-- игрока, предмета, спавнера предметов, Року (скины C_*)
------------------------------------------------------------------------
local function funcsOf(obj, out, filter)
    local cls = nil
    pcall(function() cls = obj:GetClass() end)
    local guard = 0
    while cls and valid(cls) and guard < 8 do
        local cname = "?"
        pcall(function() cname = cls:GetFullName() end)
        if not cname:find("/Script/") then
            pcall(function()
                cls:ForEachFunction(function(f)
                    local n = f:GetFName():ToString()
                    if not filter or n:lower():find(filter) then
                        local params = {}
                        pcall(function()
                            f:ForEachProperty(function(pr)
                                local pt = "?"
                                pcall(function() pt = pr:GetClass():GetFName():ToString() end)
                                params[#params + 1] = pr:GetFName():ToString() .. ":" .. pt
                            end)
                        end)
                        out[#out + 1] = "  " .. (cname:match("([^%.]+)$") or cname) .. " :: " .. n .. "(" .. table.concat(params, ", ") .. ")"
                    end
                end)
            end)
        end
        local ok, sup = pcall(function() return cls:GetSuperStruct() end)
        cls = ok and sup or nil
        guard = guard + 1
    end
end

scanMutators = function()
    local out = {}
    local function w(x) out[#out + 1] = x end
    local p = getPawn()
    w("== PLAYER functions (all, with parameters)")
    if p then funcsOf(p, out, nil) end
    w("")
    w("== ITEM IN HAND / any throwable: functions and variables")
    local item = valid(R.held) and R.held or nil
    if not item then
        for _, cn in ipairs(ITEM_CLASSES) do
            local a = FindFirstOf(cn)
            if valid(a) then item = a break end
        end
    end
    if item then
        w("  " .. describe(item))
        funcsOf(item, out, nil)
        w("  variables:")
        dumpProps(item, out, "    ", false)
    end
    w("")
    w("== ITEM SPAWNER (first one): functions and variables")
    local sp = FindFirstOf("BP_ItemSpawner_C")
    if valid(sp) then
        funcsOf(sp, out, nil)
        w("  variables:")
        dumpProps(sp, out, "    ", false)
    end
    w("")
    w("== ROKU: skin / costume related functions and variables")
    local r = getRoku()
    if r then
        for _, f in ipairs({ "skin", "costume", "outfit", "mat", "c_", "bunny", "sailor", "dark" }) do funcsOf(r, out, f) end
        w("  variables:")
        dumpProps(r, out, "    ", false)
        pcall(function()
            local mesh = r.Mesh
            local n = mesh:GetNumMaterials()
            for i = 0, n - 1 do w("  Mesh material " .. i .. ": " .. describe(mesh:GetMaterial(i))) end
        end)
    end
    local on, ot = outfitNames()
    w("  outfit tables: " .. table.concat(ot, ", "))
    w("  outfit rows: " .. table.concat(on, ", "))
    if r then w("  CurrentSkin: " .. tostring(currentSkin(r))) end
    w("")
    w("== GAME INSTANCE (skins / difficulty)")
    local gi = FindFirstOf("GI_GON_C")
    if valid(gi) then dumpProps(gi, out, "    ", false) end
    local path = ROOT .. "\\mut_scan.txt"
    local f = io.open(path, "w")
    if not f then return "Could not write mut_scan.txt" end
    f:write(table.concat(out, "\n"))
    f:close()
    log("Lab: mutator scan saved: " .. path)
    return "Saved mut_scan.txt"
end

end)() -- МУТАТОРЫ ИГРОКА

------------------------------------------------------------------------
