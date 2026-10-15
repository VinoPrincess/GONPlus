------------------------------------------------------------------------
-- РЕЖИМ SUTEGOMA: ты истекаешь кровью. Здоровье — ресурс (идеи VinoPrincess, 15.10.2026).
--   * кровь идёт всегда; больше аптечек на уровне
--   * КРОВОПОТЕРЯ: шкала копится при беге (вся выносливость за раз = полная), спадает чуть
--     медленнее, чем возвращается выносливость; полная — кровь идёт в 4 раза быстрее (HEMORRHAGE)
--   * АПТЕЧКА = ПЕРЕВЯЗКА: лечит вдвое меньше, но на время останавливает кровь и обнуляет шкалу
--     ("рана слишком серьёзная для аптечки — можно только отсрочить неизбежное")
--   * УДАР РОКУ открывает рану: шкала резко растёт, перевязка срывается
--   * УКРЫТИЕ: прижимаешь рану — кровь почти стоит, шкала спадает быстрее
--   * СЛАБОСТЬ: ниже 30% здоровья края экрана темнеют в такт пульсу, ниже 15% камеру ведёт
--   * ЗАПАХ КРОВИ: Року бродит сама и далеко (в комплексе и так пахнет чужой кровью, твоя теряется);
--     иногда проверяет места, где ты был недавно ("кровь ещё свежая"); при кровотечении (HEMORRHAGE)
--     или если долго стоишь на месте — запах устойчивый, и она идёт прямо к тебе.
--     Увидела — гонится своим мозгом; потеряла на 8 с — снова бродит.
------------------------------------------------------------------------
; (function()
local function rnd(a, b) return a + math.random() * (b - a) end
local function sees(r)
    local a, b = false, false
    pcall(function() a = r.bPlayerInVisionBox == true end)
    pcall(function() b = r.bLineTraceHitPlayer == true end)
    return a and b
end
local function chasing(r)
    local bb = false
    ctrlCall(r, function(c) bb = c.Blackboard:GetValueAsBool(FName("bPlayerDetected")) == true end)
    return bb or sees(r)
end

local MEDKIT = "/Game/INTERACTION/BP_Medikit.BP_Medikit_C"
SUTE = {
    bleed = 1 / 300,        -- в покое: от полного здоровья до нуля за 5 минут
    bloodMax = 4,           -- полная шкала: кровь идёт во столько раз быстрее
    drain = 0.8,            -- шкала спадает: доля от скорости восстановления выносливости
    healK = 0.5,            -- аптечка лечит вдвое меньше...
    bandage = 35,           -- ...но останавливает кровь на столько секунд
    hitBlood = 0.5,         -- удар Року: +50% шкалы
    hideK = 0.25,           -- в укрытии кровь идёт в 4 раза медленнее
    hideDrain = 2,          -- и шкала спадает вдвое быстрее
    weak = 0.30, faint = 0.15,
    -- запах крови
    trailEvery = 5, trailKeep = 180,           -- след: точка раз в 5 с, помним 3 минуты
    visit = { 50, 90 }, fresh = { 25, 80 },     -- раз в 50-90 с проверяет место, где ты был 25-80 с назад
    stillR = 400, stillT = 40,                  -- стоишь в радиусе 4 м 40 с — запах устойчивый
    scentCool = 25,
}

local function vdist(a, b) return vlen(a.X - b.X, a.Y - b.Y, 0) end

-- Року идёт на запах (наша бродилка из лаборатории: дойдёт, осмотрится, потом дальше бродит)
local function sendScent(r, dest, why)
    local addr = r:GetAddress()
    local l = r:K2_GetActorLocation()
    LAB.targets[addr] = { dest = { X = dest.X, Y = dest.Y, Z = dest.Z }, lastPos = { X = l.X, Y = l.Y, Z = l.Z },
        lastG = gameNow() or 0, stillFor = 0, investigate = true }
    local ok = sendTo(r, dest)
    log(string.format("SUTEGOMA: Roku follows the blood (%s), %.0f cm away, MoveTo=%s", why, vdist(l, dest), tostring(ok)))
end

local function scentTick(s, dt, g, me)
    -- след игрока
    if g - (s.trailAt or -100) >= SUTE.trailEvery then
        s.trailAt = g
        s.trail[#s.trail + 1] = { X = me.X, Y = me.Y, Z = me.Z, t = g }
        while #s.trail > 0 and g - s.trail[1].t > SUTE.trailKeep do table.remove(s.trail, 1) end
    end
    -- стоит на месте?
    if not s.stillPos or vdist(me, s.stillPos) > SUTE.stillR then s.stillPos, s.stillSince = { X = me.X, Y = me.Y }, g end
    local still = g - (s.stillSince or g) >= SUTE.stillT
    local strong = (s.blood or 0) >= 0.999 or still
    for _, r in ipairs(allRokus()) do
        local addr = r:GetAddress()
        local k = s.rk[addr]
        if not k then
            if not rokuSettled(r) then goto continue end
            k = { mode = "wander" }
            s.rk[addr] = k
            LAB.wanderOnly[addr] = true
            LAB.targets[addr] = nil
            brainOff(r)
            log("SUTEGOMA: Roku roams on her own - your blood is lost among the others")
        end
        if k.mode == "wander" then
            if sees(r) then
                LAB.wanderOnly[addr] = nil
                LAB.targets[addr] = nil
                local o = origSpeeds(r)
                setIf(r, "MoveSpeed", o.move); setIf(r, "chasespeed", o.chase)
                pcall(function() r.CharacterMovement.MaxWalkSpeed = o.move end)
                brainOn(r)
                k.mode, k.lost = "hunt", 0
                log("SUTEGOMA: she sees you")
            elseif strong and g >= (s.scentCool or 0) then
                s.scentCool = g + SUTE.scentCool
                sendScent(r, me, still and "you stood still" or "hemorrhage")
                -- при кровотечении уже горит HEMORRHAGE ("она чует") — второй надписью не перебиваем
                if still then flash("+ FRESH BLOOD +", 2.2, GAME.blood, "You've been here too long. She can smell you.") end
            elseif g >= (s.nextVisit or 0) then
                s.nextVisit = g + rnd(SUTE.visit[1], SUTE.visit[2])
                local pick = nil
                for i = #s.trail, 1, -1 do
                    local a = g - s.trail[i].t
                    if a >= SUTE.fresh[1] and a <= SUTE.fresh[2] then pick = s.trail[i]; if math.random() < 0.35 then break end end
                end
                if pick then sendScent(r, pick, string.format("old trail, %.0f s", g - pick.t)) end
            end
        elseif k.mode == "hunt" then
            if chasing(r) then k.lost = 0 else k.lost = (k.lost or 0) + dt end
            if k.lost >= 8 then
                brainOff(r)
                LAB.wanderOnly[addr] = true
                LAB.targets[addr] = nil
                k.mode = "wander"
                s.nextVisit = g + rnd(SUTE.visit[1], SUTE.visit[2]) * 0.5
                log("SUTEGOMA: she lost you, back to roaming")
            end
        end
        ::continue::
    end
end

local function scentStop(s)
    for _, r in ipairs(allRokus()) do
        local addr = r:GetAddress()
        if s.rk and s.rk[addr] then
            if s.rk[addr].mode == "wander" then brainOn(r) end
            local o = LAB.orig[addr]
            if o then
                setIf(r, "MoveSpeed", o.move); setIf(r, "chasespeed", o.chase)
                pcall(function() r.CharacterMovement.MaxWalkSpeed = o.move end)
            end
        end
    end
    LAB.wander = false
    LAB.wanderOnly = nil
    LAB.targets = {}
end

-- слабость: пульс по краям экрана и лёгкое покачивание камеры
local FX = { cams = nil, saved = {}, on = false, lastSway = nil }
local function fxCams()
    if not FX.cams then FX.cams = PLAYER_CAMS and PLAYER_CAMS() or {} end
    return FX.cams
end
local function fxOff()
    if not FX.on then return end
    FX.on = false
    for _, c in ipairs(FX.cams or {}) do
        local e = FX.saved[c:GetAddress()]
        if valid(c) and e then
            pcall(function()
                local pp = c.PostProcessSettings
                pp.VignetteIntensity = e.v or 0.4
                pp.bOverride_VignetteIntensity = e.o == true
            end)
        end
    end
    FX.saved, FX.cams, FX.lastSway = {}, nil, nil
end
onForgetRefs(function() FX.cams, FX.saved, FX.on, FX.lastSway = nil, {}, false, nil end)

every(50, function()
    local p = getPawn()
    if not (ACTIVE.sutegoma and R.phase == "running" and p and not (UI.open and UI.kind ~= "lab")) then fxOff() return end
    local hp = num(p.health) or 1
    if hp >= SUTE.weak then fxOff() return end
    local t = os.clock()
    local k = 1 - hp / SUTE.weak                         -- 0 на границе, 1 у нуля
    local bpm = 70 + 70 * k
    local ph = (t * bpm / 60) % 1
    local beat = math.exp(-ph * 9) + 0.6 * math.exp(-math.max(0, ph - 0.22) * 9) * (ph > 0.22 and 1 or 0)
    local v = 0.6 + 1.2 * k + 0.9 * beat * (0.4 + 0.6 * k)
    for _, c in ipairs(fxCams()) do
        if valid(c) then
            pcall(function()
                local pp = c.PostProcessSettings
                local a = c:GetAddress()
                if not FX.saved[a] then FX.saved[a] = { o = pp.bOverride_VignetteIntensity, v = num(pp.VignetteIntensity) } end
                pp.bOverride_VignetteIntensity = true
                pp.VignetteIntensity = v
            end)
        end
    end
    FX.on = true
    -- почти без сил: камеру медленно ведёт (добавка к повороту, мышь работает)
    if hp < SUTE.faint then
        local pc = getPC()
        local amp = 1.4 * (1 - hp / SUTE.faint)
        local yaw, pitch = math.sin(t * 0.9) * amp, math.sin(t * 1.3 + 1) * amp * 0.5
        if FX.lastSway and pc then
            local dy, dp = yaw - FX.lastSway[1], pitch - FX.lastSway[2]
            pcall(function()
                local cur = pc:GetControlRotation()
                pc:SetControlRotation({ Pitch = num(cur.Pitch) + dp, Yaw = num(cur.Yaw) + dy, Roll = 0 })
            end)
        end
        FX.lastSway = { yaw, pitch }
    else
        FX.lastSway = nil
    end
end)

mutator {
    id = "sutegoma", name = "SUTEGOMA", tags = { "health" }, noNightmare = true, modeOnly = true,
    desc = "You are bleeding out. Running makes it worse, medkits only buy time, and she follows the blood.",
    on = function(s)
        s.medkits, s.blood, s.trail, s.rk = 0, 0, {}, {}
        s.nextVisit = (gameNow() or 0) + rnd(SUTE.visit[1], SUTE.visit[2])
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
        -- Року бродит сама: наша бродилка, только для тех, кого запишем (wanderOnly)
        LAB.wanderOnly, LAB.targets, LAB.wander = {}, {}, true
    end,
    event = function(s, name)
        if name == "heal" then s.healAt = gameNow() or 0
        elseif name == "damage" then s.hitPending = true end
    end,
    tick = function(s, dt)
        local p = getPawn(); if not p then return end
        local hp = num(p.health); if not hp then return end
        dt = dt or 0.25
        local g = gameNow() or 0
        -- кровопотеря от бега: по расходу выносливости
        local sm, st = nil, nil
        pcall(function() sm = num(p["Sprint Meter"]) end)
        pcall(function() st = num(p["Sprint Time"]) end)
        st = (st and st > 0) and st or 5
        local hiding = false
        pcall(function() hiding = p.bIsHiding == true end)
        local drainK = SUTE.drain * (hiding and SUTE.hideDrain or 1)
        if sm and s.lastSM then
            local d = sm - s.lastSM
            if d < -0.0001 then
                s.blood = math.min(1, s.blood + (-d) / st)                 -- вся выносливость = вся шкала
            elseif d > 0.0001 then
                s.regen = (s.regen or d / dt) * 0.8 + (d / dt) * 0.2      -- скорость восстановления выносливости
                s.blood = math.max(0, s.blood - d / st * drainK)
            elseif sm >= st - 0.01 then                                   -- выносливость полная, шкала ещё нет
                s.blood = math.max(0, s.blood - (s.regen or st / 4) / st * drainK * dt)
            end
        end
        s.lastSM = sm
        -- удар Року: рана открывается
        if s.hitPending then
            s.hitPending = false
            s.blood = math.min(1, s.blood + SUTE.hitBlood)
            if s.bandUntil then
                s.bandUntil = nil
                flash("+ THE WOUND OPENS +", 2, GAME.blood, "The bandage didn't hold.")
            end
            log("SUTEGOMA: hit - the wound opens")
        end
        -- аптечка: лечит вдвое меньше, но перевязывает
        if s.healAt then
            if s.lastHp and hp > s.lastHp + 0.01 then
                local gain = hp - s.lastHp
                hp = s.lastHp + gain * SUTE.healK
                s.bandUntil = g + SUTE.bandage
                s.blood, s.healAt = 0, nil
                flash("+ BANDAGED +", 2.4, GAME.blood, "It won't hold for long.")
                log(string.format("SUTEGOMA: medkit +%.0f%% (halved), bleeding stopped for %d s", gain * SUTE.healK * 100, SUTE.bandage))
            elseif g - s.healAt > 2 then s.healAt = nil end
        end
        if s.bandUntil and g >= s.bandUntil then
            s.bandUntil = nil
            flash("+ BLEEDING AGAIN +", 2, GAME.blood, "The bandage is soaked through.")
        end
        if s.blood >= 0.999 and not s.fullWarned then
            s.fullWarned = true
            flash("+ HEMORRHAGE +", 2.4, GAME.blood, "Stop running. She can smell your blood now.")
        elseif s.blood < 0.6 then s.fullWarned = false end
        -- кровь
        if not s.bandUntil then
            local rate = SUTE.bleed * (1 + (SUTE.bloodMax - 1) * s.blood)
            if hiding then rate = rate * SUTE.hideK end
            hp = hp - rate * dt
        end
        if topMeter and R.phase == "running" then
            if s.blood > 0.01 then topMeter(s.blood, "+ BLOOD LOSS +", GAME.blood) else topMeter(nil) end
        end
        -- запах крови
        if R.phase == "running" then
            local me = nil
            pcall(function() local l = p:K2_GetActorLocation(); me = { X = l.X, Y = l.Y, Z = l.Z } end)
            if me then scentTick(s, dt, g, me) end
        end
        if hp <= 0.001 then
            if not s.dead then
                s.dead = true
                p.health = 0.001
                log("SUTEGOMA: bled out")
                DEATH_SCENE({ title = "+ BLED OUT +", sub = "SUTEGOMA", veil = { 0.09, 0.0, 0.0 }, color = GAME.blood,
                    fadeIn = 2.2, hold = 4, result = "dead" })
            end
            return
        end
        p.health = hp
        s.lastHp = hp
    end,
    off = function(s)
        if topMeter then topMeter(nil) end
        scentStop(s)
        fxOff()
    end,
    hud = function(s)
        if s.bandUntil then
            return string.format("BANDAGED  %ds", math.max(0, math.ceil(s.bandUntil - (gameNow() or 0)))), false
        end
        local p = getPawn()
        local hp = p and num(p.health) or 0
        return string.format("BLEEDING  %d%%", math.floor(hp * 100 + 0.5)), hp < 0.3
    end,
    lose = { title = "+ SUTEGOMA +", sub = "You were already bleeding. She just finished it.", veil = { 0.09, 0, 0 }, color = GAME.blood },
}

end)() -- SUTEGOMA
