------------------------------------------------------------------------
-- РЕЖИМ "BASHFUL" (Скромница). Идея игрока, в духе SCP-096:
--   Року не ходит сама — она как призрак: исчезает и появляется рядом с игроком
--   (то впереди, то сзади, то за углом). Она тебя не видит, но чувствует взгляд.
--   Два способа проиграть:
--     1) смотреть на неё слишком долго (она на экране и ничто её не загораживает);
--     2) подойти слишком близко (рядом и в прямой видимости — за стеной не считается).
--   Шкала смущения наверху: растёт, пока смотришь / стоишь рядом, медленно спадает.
--   Она никогда не бьёт. Победа — как обычно: собрать и выйти.
------------------------------------------------------------------------
; (function()

local SHY = { on = false }
local HEART = "/Game/ROKUv3/anims/cuteanims/cute_hearthands2_Montage.cute_hearthands2_Montage"
local PINK = { R = 1.0, G = 0.45, B = 0.7, A = 1 }

-- числа режима (подобрать после игры)
local CFG = {
    graceStart = 10,              -- с начала забега она не появляется
    showMin = 5, showMax = 10,    -- сколько стоит на месте (к концу короче)
    goneMin = 1.2, goneMax = 3,   -- сколько её нет между появлениями
    distMin = 700, distMax = 1600, -- где появляется (см)
    stareFull = 2.2,              -- секунд взгляда до проигрыша (на 12 м; ближе — быстрее)
    nearDist = 400,               -- "слишком близко" (см)
    nearFull = 1.5,               -- секунд рядом до проигрыша
    decay = 0.1,                  -- спадает за секунду (доля шкалы); было 0.25 — слишком легко
    -- невидима, пока не посмотришь прямо на неё или не подойдёшь (сюрприз за дверью)
    revealCone = 12,              -- градусов от центра экрана
    revealDist = 650,             -- см: ближе — проявляется сама (если ничто не загораживает)
    -- "манящая взгляд": камера сама поворачивается к ней — успей отвернуться
    lureEvery = { 35, 60 },       -- секунд между событиями
    lureTurn = 0.6,               -- за сколько секунд камера доворачивает
    lureDist = { 500, 1500 },     -- только если она не слишком близко и не слишком далеко
}
-- что она делает, когда на неё смотрят (игрок выберет свои из списка её анимаций)
local A = "/Game/ROKUv3/anims/"
local SHY_ANIMS = {
    A .. "lookarounds/lookaround_fingerbite2_Montage.lookaround_fingerbite2_Montage",
    A .. "lookarounds/n_LA_lick1_Montage.n_LA_lick1_Montage",
    A .. "lookarounds/lookaround_triangle_Montage.lookaround_triangle_Montage",
    A .. "lookarounds/lookaround_lookbackL_Montage.lookaround_lookbackL_Montage",
    A .. "lookarounds/lookaround_lookbackR_Montage.lookaround_lookbackR_Montage",
}

local function v3(x, y, z) return { X = x, Y = y, Z = z } end
local function rnd(a, b) return a + math.random() * (b - a) end
local function ksl() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end

-- главная Року (своя у игры; лишние — не наше дело)
local function shyRoku()
    local list = allRokus()
    return list[1]
end

-- камера игрока: положение, вперёд, вправо, вверх
local function camera()
    local pc = getPC(); if not pc then return nil end
    local cam = pc.PlayerCameraManager
    local loc, rot = nil, nil
    pcall(function() loc = cam:GetCameraLocation(); rot = cam:GetCameraRotation() end)
    if not loc or not num(rot and rot.Pitch) then return nil end
    local p, y = math.rad(rot.Pitch), math.rad(rot.Yaw)
    return {
        loc = v3(loc.X, loc.Y, loc.Z),
        fwd = v3(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p)),
        right = v3(-math.sin(y), math.cos(y), 0),
        up = v3(-math.sin(p) * math.cos(y), -math.sin(p) * math.sin(y), math.cos(p)),
    }
end
local function dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end

-- ничто не загораживает точку to (попали в саму Року или дошли почти до неё — видно)
local function clearLine(from, to, roku)
    local pawn = getPawn(); if not pawn then return false end
    local hit = {}
    local blocked = false
    local ok = pcall(function()
        blocked = ksl():LineTraceSingle(pawn, from, to, 0, false, {}, 0, hit, true,
            { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
    end)
    if not ok then return false end
    if not blocked then return true end
    local owner = nil
    pcall(function()
        local c = hit.Component
        if c and c.Get then c = c:Get() end
        owner = c:GetOwner()
    end)
    if valid(owner) and owner:GetAddress() == roku:GetAddress() then return true end
    local d = vlen(to.X - from.X, to.Y - from.Y, to.Z - from.Z)
    local hd = num(hit.Distance)
    return hd ~= nil and hd >= d - 40
end

-- точки Року, по которым проверяем взгляд: голова и середина тела
local function rokuPoints(r)
    local pts = {}
    local a = r:K2_GetActorLocation()
    pts[#pts + 1] = v3(a.X, a.Y, a.Z)
    local mesh = r.Mesh
    local sock = valid(mesh) and findHead(mesh)
    if sock then pcall(function() local h = mesh:GetSocketLocation(FName(sock)); pts[#pts + 1] = v3(h.X, h.Y, h.Z) end) end
    if #pts == 1 then pts[2] = v3(a.X, a.Y, a.Z + 70) end
    return pts
end

-- видит ли игрок Року: в кадре (примерно экран 16:9) и не загорожена. Возвращает расстояние или nil.
local H_HALF, V_HALF = math.rad(43), math.rad(27)
local function seenAt(r, cam)
    for _, p in ipairs(rokuPoints(r)) do
        local v = v3(p.X - cam.loc.X, p.Y - cam.loc.Y, p.Z - cam.loc.Z)
        local f = dot(v, cam.fwd)
        if f > 30 then
            local h = math.abs(math.atan(dot(v, cam.right), f))
            local vv = math.abs(math.atan(dot(v, cam.up), f))
            if h < H_HALF and vv < V_HALF and clearLine(cam.loc, p, r) then
                return vlen(v.X, v.Y, v.Z)
            end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Появления
------------------------------------------------------------------------
local function setShown(r, on)
    pcall(function() r:SetActorHiddenInGame(not on) end)
    pcall(function() r:SetActorEnableCollision(on) end)
end

-- точка рядом с игроком: сзади / сбоку / впереди (впереди — подальше)
local function pickSpot(cam, me)
    local roll = math.random()
    local want = roll < 0.45 and "behind" or (roll < 0.75 and "side" or "front")
    local k = math.min(1, ((gameNow() or 0) - (SHY.t0 or 0)) / 600)     -- за 10 минут подбирается ближе
    local dmin = CFG.distMin * (1 - 0.25 * k)
    local dmax = CFG.distMax * (1 - 0.25 * k)
    local best, bestScore = nil, -1
    for _ = 1, 24 do
        local p = randomNavPoint(v3(me.X, me.Y, me.Z), dmax)
        if p then
            local dx, dy = p.X - me.X, p.Y - me.Y
            local d = vlen(dx, dy, 0)
            local zd = math.abs(p.Z - me.Z)
            if d >= dmin and zd < 300 then
                local c = (dx * cam.fwd.X + dy * cam.fwd.Y) / math.max(1, d)
                local kind = c < -0.3 and "behind" or (c > 0.5 and "front" or "side")
                if want == "front" and d < 900 then kind = "near-front" end
                local score = (kind == want and 2 or 0) + math.random()
                if score > bestScore then best, bestScore = p, score end
                if kind == want then break end
            end
        end
    end
    return best, want
end

local function appear(r)
    local cam, p = camera(), getPawn()
    if not cam or not p then return false end
    local me = p:K2_GetActorLocation()
    local spot, kind = pickSpot(cam, me)
    if not spot then return false end
    local loc = v3(spot.X, spot.Y, spot.Z + 95)
    pcall(function() r:K2_SetActorLocation(loc, false, {}, true) end)
    local yaw = math.deg(math.atan(me.Y - loc.Y, me.X - loc.X))
    pcall(function() r:K2_SetActorRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }, false) end)
    -- стоит там, но невидима: проявится, когда посмотришь прямо на неё или подойдёшь
    pcall(function() r:SetActorEnableCollision(true) end)
    pcall(function() r:SetActorHiddenInGame(true) end)
    SHY.revealed, SHY.animDone = false, false
    log(string.format("Bashful: appeared %s, %.0f m away", kind, vlen(loc.X - me.X, loc.Y - me.Y, 0) / 100))
    return true
end

-- проявиться: мигнула пару раз, как призрак
local function reveal(r, why)
    if SHY.revealed then return end
    SHY.revealed = true
    local addr = r:GetAddress()
    pcall(function() r:SetActorHiddenInGame(false) end)
    for i, on in ipairs({ false, true, false, true }) do
        after(i * 60, function()
            local rr = rokuAt(addr)
            if rr and SHY.on and SHY.state == "shown" and SHY.revealed then pcall(function() rr:SetActorHiddenInGame(not on) end) end
        end)
    end
    log("Bashful: revealed (" .. why .. ")")
end

-- угол (градусы) между взглядом камеры и направлением на точку
local function angleTo(cam, p)
    local v = v3(p.X - cam.loc.X, p.Y - cam.loc.Y, p.Z - cam.loc.Z)
    local d = math.max(1, vlen(v.X, v.Y, v.Z))
    local c = math.max(-1, math.min(1, dot(v, cam.fwd) / d))
    return math.deg(math.acos(c)), d
end

-- "манящая взгляд": плавно довернуть камеру на неё
local function lureTick(g, r)
    local L = SHY.lure; if not L then return end
    local pc = getPC(); if not pc then SHY.lure = nil return end
    local k = math.min(1, (g - L.t0) / CFG.lureTurn)
    local e = 1 - (1 - k) * (1 - k)
    local dy = ((L.to.Yaw - L.from.Yaw + 540) % 360) - 180
    local rot = { Pitch = L.from.Pitch + (L.to.Pitch - L.from.Pitch) * e, Yaw = L.from.Yaw + dy * e, Roll = 0 }
    pcall(function() pc:SetControlRotation(rot) end)
    if k >= 1 then SHY.lure = nil end
end
local function startLure(g, r, cam)
    local pc = getPC(); if not pc then return false end
    local from = nil
    pcall(function() local c = pc:GetControlRotation(); from = { Pitch = num(c.Pitch) or 0, Yaw = num(c.Yaw) or 0 } end)
    if not from then return false end
    if from.Pitch > 180 then from.Pitch = from.Pitch - 360 end
    local pts = rokuPoints(r)
    local h = pts[2] or pts[1]
    local dx, dy, dz = h.X - cam.loc.X, h.Y - cam.loc.Y, h.Z - cam.loc.Z
    local to = { Yaw = math.deg(math.atan(dy, dx)), Pitch = math.deg(math.atan(dz, math.max(1, vlen(dx, dy, 0)))) }
    SHY.lure = { t0 = g, from = from, to = to }
    reveal(r, "lure")
    flash("+ LOOK AT ME +", 2, PINK)
    log("Bashful: lure - the camera turns to her")
    return true
end

------------------------------------------------------------------------
-- Шкала
------------------------------------------------------------------------
local function meter(frac, label)
    local m = UI.meter; if not m or not valid(m.fill) then return end
    local show = frac ~= nil
    for _, w in ipairs({ m.track, m.fill, m.text }) do
        if valid(w) then pcall(function() w:SetVisibility(show and VIS_SHOW or VIS_HIDE) end) end
    end
    if not show then return end
    pcall(function() m.fillSlot:SetSize({ X = math.max(1, m.w * math.min(1, frac)), Y = m.h }) end)
    local a = frac > 0.6 and (0.6 + 0.4 * math.abs(math.sin(os.clock() * 8))) or 1
    pcall(function() m.fill:SetBrushColor({ R = PINK.R, G = PINK.G, B = PINK.B, A = a }) end)
    setText(m.text, label)
end

local function lose(why)
    if SHY.lost then return end
    SHY.lost = true
    local r = shyRoku()
    if r then
        setShown(r, true)
        local p = getPawn()
        if p then
            local me, l = p:K2_GetActorLocation(), r:K2_GetActorLocation()
            pcall(function() r:K2_SetActorRotation({ Pitch = 0, Yaw = math.deg(math.atan(me.Y - l.Y, me.X - l.X)), Roll = 0 }, false) end)
        end
        local m = StaticFindObject(HEART)
        if valid(m) then pcall(function() r:PlayAnimMontage(m, 1.0, FName("None")) end) end
    end
    log("Bashful: lost - " .. why)
    after(1200, function()
        if not SHY.on then return end
        if why == "stare" then
            defeat({ title = "+ SHE BLUSHED +", sub = "You stared. She felt every second of it.",
                veil = { 0.3, 0.02, 0.14 }, color = PINK, fadeIn = 1.8, hold = 4, scripted = true, result = "caught" })
        else
            defeat({ title = "+ TOO CLOSE +", sub = "Personal space. She asked so nicely.",
                veil = { 0.3, 0.02, 0.14 }, color = PINK, fadeIn = 1.8, hold = 4, scripted = true, result = "caught" })
        end
    end)
end

------------------------------------------------------------------------
-- Старт / стоп / тик
------------------------------------------------------------------------
shyStart = function()
    local g = gameNow() or 0
    SHY.on, SHY.lost, SHY.t0 = true, false, g
    SHY.stare, SHY.near = 0, 0
    SHY.state, SHY.until_ = "gone", g + CFG.graceStart
    SHY.addr, SHY.lure, SHY.revealed = nil, nil, false
    SHY.nextLure = g + CFG.graceStart + rnd(CFG.lureEvery[1], CFG.lureEvery[2])
    log("Bashful: started")
end

shyStop = function()
    if not SHY.on then return end
    SHY.on = false
    meter(nil)
    local r = SHY.addr and rokuAt(SHY.addr)
    if r then
        setShown(r, true)
        pcall(function() r.AttackBox:SetCollisionEnabled(1) end)
        brainOn(r)
    end
    SHY.addr = nil
    log("Bashful: stopped")
end
onForgetRefs(function() SHY.addr = nil end)
function shyActive() return SHY.on end

every(50, function()
    if not SHY.on or R.phase ~= "running" or SHY.lost then return end
    local p = getPawn(); local r = shyRoku()
    if not p or not r or not rokuSettled(r) then return end
    local g = gameNow() or 0
    local dt = SHY.lastT and math.min(0.2, math.max(0, g - SHY.lastT)) or 0.05
    SHY.lastT = g
    if dt <= 0 then return end         -- пауза

    -- своя Року: мозг выключен, не бьёт, стоит на месте
    if SHY.addr ~= r:GetAddress() then
        SHY.addr = r:GetAddress()
        brainOff(r)
        pcall(function() r.AttackBox:SetCollisionEnabled(0) end)
        setShown(r, false)
        SHY.state, SHY.until_ = "gone", math.max(SHY.until_ or 0, g + 2)
        log("Bashful: took over Roku")
    end
    local running = false
    ctrlCall(r, function(c) running = c.BrainComponent:IsRunning() == true end)
    if running then brainOff(r) end

    -- исчезла / появилась
    if g >= SHY.until_ then
        local k = math.min(1, (g - SHY.t0) / 600)
        if SHY.state == "gone" then
            if appear(r) then
                SHY.state = "shown"
                SHY.until_ = g + rnd(CFG.showMin, CFG.showMax) * (1 - 0.4 * k)
            else
                SHY.until_ = g + 1
            end
        elseif not SHY.lure then
            setShown(r, false)
            SHY.state, SHY.revealed = "gone", false
            SHY.until_ = g + rnd(CFG.goneMin, CFG.goneMax)
        end
    end
    lureTick(g, r)

    -- шкалы: взгляд и близость
    local stareUp, nearUp = false, false
    if SHY.state == "shown" then
        local cam = camera()
        if cam then
            -- проявиться: смотришь прямо на неё или подошёл, и ничто не загораживает
            if not SHY.revealed then
                for _, pt in ipairs(rokuPoints(r)) do
                    local ang, dist = angleTo(cam, pt)
                    if (ang < CFG.revealCone or dist < CFG.revealDist) and clearLine(cam.loc, pt, r) then
                        reveal(r, ang < CFG.revealCone and "looked" or "close")
                        break
                    end
                end
            end
            -- "манящая взгляд"
            if not SHY.lure and g >= SHY.nextLure then
                local l = r:K2_GetActorLocation()
                local d = vlen(l.X - cam.loc.X, l.Y - cam.loc.Y, 0)
                local ok = d >= CFG.lureDist[1] and d <= CFG.lureDist[2] and clearLine(cam.loc, v3(l.X, l.Y, l.Z), r)
                if ok and startLure(g, r, cam) then
                    SHY.nextLure = g + rnd(CFG.lureEvery[1], CFG.lureEvery[2])
                else
                    SHY.nextLure = g + 2
                end
            end
            local d = SHY.revealed and seenAt(r, cam) or nil
            if d then
                -- на неё смотрят: смущённо что-нибудь делает (один раз за появление)
                if not SHY.animDone then
                    SHY.animDone = true
                    local m = StaticFindObject(SHY_ANIMS[math.random(1, #SHY_ANIMS)])
                    if valid(m) then pcall(function() r:PlayAnimMontage(m, 1.0, FName("None")) end) end
                end
                stareUp = true
                local speed = math.max(0.5, math.min(3, 1200 / d))
                SHY.stare = SHY.stare + dt * speed / CFG.stareFull
            end
            local me, l = p:K2_GetActorLocation(), r:K2_GetActorLocation()
            local nd = vlen(me.X - l.X, me.Y - l.Y, me.Z - l.Z)
            if nd < CFG.nearDist and clearLine(cam.loc, v3(l.X, l.Y, l.Z), r) then
                nearUp = true
                SHY.near = SHY.near + dt / CFG.nearFull * (nd < CFG.nearDist / 2 and 2 or 1)
            end
        end
    end
    if not stareUp then SHY.stare = math.max(0, SHY.stare - dt * CFG.decay) end
    if not nearUp then SHY.near = math.max(0, SHY.near - dt * CFG.decay) end

    local top = math.max(SHY.stare, SHY.near)
    if top > 0.01 then
        meter(top, SHY.near > SHY.stare and "+ TOO CLOSE +" or "+ DON'T STARE +")
    else
        meter(nil)
    end
    if SHY.stare >= 1 then lose("stare") elseif SHY.near >= 1 then lose("near") end
end)

end)()
