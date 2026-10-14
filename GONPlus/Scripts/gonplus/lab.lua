-- ЛАБОРАТОРИЯ (F1, после 7 кликов по "+GON+PLUS+"): разведка поведения Року. Для разработки, не для игроков.
--   * скан мозга Року -> Mods\GONPlus\roku_scan.txt
--   * журнал игрового зрения (SetPlayerDetected)
--   * "Року бродит": её мозг выключен, ходит по случайным патрульным точкам
--   * дополнительные Року
--   * отладка зрения: наш конус + луч, сравнение с игровым
------------------------------------------------------------------------
local LAB = {
    wander = false, vision = false,
    targets = {},           -- адрес Року -> { dest, lastPos, stillFor }
    points = nil,           -- кэш патрульных точек
    extras = {},            -- заспавненные лабораторией
    det = { value = nil, changes = 0, lastAt = 0, calls = 0 },
    sees = {},              -- адрес -> видит ли (наша проверка), для журнала
    hooked = false,
    born = {},              -- адрес -> когда заспавнена (os.clock)
    stealth = false, caught = 0,
    run = false,            -- Року всегда бегом (как в финале)
    investigateSpeed = 1.6, -- к шуму идёт быстрее обычного шага
    lookTime = 6,           -- сколько секунд осматривается на месте шума
    noiseThrow = true, noiseSprint = false,
    throwRadius = 3000, sprintRadius = 1500,
    flying = {}, noises = 0, trk = {},
    orig = {},              -- адрес Року -> её родные MoveSpeed/chasespeed
    noiseVent = false, noiseDoor = false,
    ventRadius = 6000, doorRadius = 1200,
    flags = {},             -- адрес объекта -> прошлое значение флага
    detKey = {},            -- адрес Року -> последнее состояние "заметила" (для лога)
    heard = {},             -- адрес Року -> последняя точка расследования из её Blackboard
    lastOrder = {},         -- адрес Року -> когда последний раз посылали на шум (время игры)
    orderCooldown = 6,
    world = nil, worldScanAt = nil,
}
onForgetRefs(function()
    LAB.world, LAB.worldScanAt, LAB.flags = nil, nil, {}
    LAB.tracked, LAB.trk, LAB.flying, LAB.watchThrowUntil = {}, {}, {}, nil
    LAB.points, LAB.targets, LAB.heard, LAB.lastOrder = nil, {}, {}, {}
    LAB.orig, LAB.detKey = {}, {}
    LAB.extras = {}
end)

local describe -- задаётся ниже, в разделе скана

local function allRokus()
    local out = {}
    for _, r in ipairs(FindAllOf("BP_Rokuv3_C") or {}) do
        if valid(r) then out[#out + 1] = r end
    end
    return out
end

-- Живая Року по адресу (или nil). Саму Року между тиками НЕ храним — только адрес:
-- если игра её удалила, обращение к старой ссылке роняет игру мимо pcall.
local function rokuAt(addr)
    if not addr then return nil end
    for _, r in ipairs(allRokus()) do
        if r:GetAddress() == addr then return r end
    end
    return nil
end

local function vlen(x, y, z) return math.sqrt(x * x + y * y + z * z) end

local function rotToDir(rot)
    local p, y = math.rad(rot.Pitch or 0), math.rad(rot.Yaw or 0)
    return { X = math.cos(p) * math.cos(y), Y = math.cos(p) * math.sin(y), Z = math.sin(p) }
end

local function angleTo(dir, from, to)
    local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
    local d = vlen(dx, dy, dz)
    if d < 1 then return 0 end
    local dot = (dir.X * dx + dir.Y * dy + dir.Z * dz) / (d * vlen(dir.X, dir.Y, dir.Z))
    return math.deg(math.acos(math.max(-1, math.min(1, dot))))
end

local headSocket = nil
local function findHead(mesh)
    if headSocket then return headSocket end
    for _, n in ipairs({ "head", "Head", "HEAD", "head_01", "Bip001-Head", "mixamorig:Head", "Bip01_Head" }) do
        local ok, yes = pcall(function() return mesh:DoesSocketExist(FName(n)) end)
        if ok and yes then headSocket = n return n end
    end
    pcall(function()
        mesh:GetAllSocketNames():ForEach(function(_, e)
            local n = e:get():ToString()
            if not headSocket and n:lower():find("head") then headSocket = n end
        end)
    end)
    return headSocket
end

-- точка и направление взгляда: три способа, чтобы сравнить
local function rokuViews(r)
    local v = {}
    pcall(function()
        local loc = r:K2_GetActorLocation()
        v.actor = { loc = { X = loc.X, Y = loc.Y, Z = loc.Z + 70 }, dir = r:GetActorForwardVector() }
    end)
    pcall(function()
        local mesh = r.Mesh
        local sock = valid(mesh) and findHead(mesh)
        if sock then
            local loc = mesh:GetSocketLocation(FName(sock))
            local rot = mesh:GetSocketRotation(FName(sock))
            v.head = { loc = { X = loc.X, Y = loc.Y, Z = loc.Z }, dir = rotToDir(rot), rot = rot }
        end
    end)
    pcall(function()
        local loc, rot = {}, {}
        r:GetActorEyesViewPoint(loc, rot)
        if num(loc.X) and num(rot.Yaw) then
            v.eyes = { loc = { X = loc.X, Y = loc.Y, Z = loc.Z }, dir = rotToDir(rot) }
        end
    end)
    return v
end

-- не перекрыт ли луч от глаз Року до игрока
local function lineOfSight(from, to, pawn)
    local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local hit = {}
    local blocked = ksl:LineTraceSingle(pawn, from, to, 0, false, {}, 0, hit, true,
        { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
    if not blocked then return true end
    local owner = nil
    pcall(function()
        local c = hit.Component
        if c and c.Get then c = c:Get() end
        owner = c:GetOwner()
    end)
    if valid(owner) and owner:GetAddress() == pawn:GetAddress() then return true end
    -- попали во что-то у самого игрока (оружие, руки)
    local d = vlen(to.X - from.X, to.Y - from.Y, to.Z - from.Z)
    local hd = num(hit.Distance)
    return hd ~= nil and hd >= d - 60
end

-- игровое зрение: только запоминаем значение (внутри хука ничего не вызываем)
local function labHook()
    if LAB.hooked then return end
    local ok = pcall(function()
        RegisterHook("/Game/ROKUv3/BP_Rokuv3.BP_Rokuv3_C:SetPlayerDetected", function(_, det)
            pcall(function()
                local v = det:get() == true
                LAB.det.calls = LAB.det.calls + 1
                -- несколько Року: каждая каждый кадр шлёт своё false, поэтому
                -- "true" от любой запоминаем отдельно и не даём его затереть
                if v then LAB.det.anyTrue = true end
                if v ~= LAB.det.value then
                    LAB.det.value = v
                    LAB.det.changes = LAB.det.changes + 1
                    LAB.det.flip = true
                end
            end)
        end)
    end)
    LAB.hooked = ok
end

local function patrolPoints()
    if LAB.points and #LAB.points > 0 then return LAB.points end
    local pts = {}
    -- патрульные точки игры — акторы BP_Waypoint_C
    for _, w in ipairs(FindAllOf("BP_Waypoint_C") or {}) do
        if valid(w) then
            pcall(function() local l = w:K2_GetActorLocation(); pts[#pts + 1] = { X = l.X, Y = l.Y, Z = l.Z } end)
        end
    end
    LAB.points = pts
    log("Lab: " .. #pts .. " patrol points (BP_Waypoint_C) found")
    return pts
end

-- запасной вариант: случайная достижимая точка навигации
local function randomNavPoint(origin, radius)
    local out = nil
    pcall(function()
        local nav = StaticFindObject("/Script/NavigationSystem.Default__NavigationSystemV1")
        local res = {}
        local ok = nav:K2_GetRandomReachablePointInRadius(getPawn(), origin, res, radius, nil, nil)
        if ok and num(res.X) then out = { X = res.X, Y = res.Y, Z = res.Z } end
    end)
    return out
end

local function pickDest(r)
    local pts = patrolPoints()
    if #pts > 0 then return pts[math.random(1, #pts)] end
    local l = r:K2_GetActorLocation()
    return randomNavPoint({ X = l.X, Y = l.Y, Z = l.Z }, 5000)
end

local function sendTo(r, dest)
    local ctrl = aiCtrl(r)
    if not ctrl then return false end
    local ok, res = pcall(function()
        return ctrl:MoveToLocation(dest, 80, true, true, true, false, nil, true)
    end)
    return ok, res
end

local function brainOff(r)
    ctrlCall(r, function(c) c.BrainComponent:StopLogic("GON+ lab") end)
    ctrlCall(r, function(c) c:StopMovement() end)
end
local function brainOn(r)
    ctrlCall(r, function(c) c:StopMovement() end)
    ctrlCall(r, function(c) c.BrainComponent:RestartLogic() end)
end

-- осмотр на месте: одна из её же анимаций "огляделась"
local function playLookAround(r)
    local list = {}
    pcall(function()
        r.LookAroundMontages:ForEach(function(_, e)
            local m = e:get()
            if valid(m) then list[#list + 1] = m end
        end)
    end)
    if #list == 0 then return false end
    local ok = pcall(function() r:PlayAnimMontage(list[math.random(1, #list)], 1.0, FName("None")) end)
    return ok
end

-- скорость: шагом (её MoveSpeed) или всегда бегом (chasespeed), если включено
-- её родные скорости запоминаем один раз, потом подменяем ЕЁ переменные MoveSpeed/chasespeed:
-- тогда её собственный скрипт сам ставит нужную скорость, и никакой борьбы "бег-шаг"
local function origSpeeds(r)
    local addr = r:GetAddress()
    local o = LAB.orig[addr]
    if not o then
        o = { move = num(r.MoveSpeed) or 150, chase = num(r.chasespeed) or 480 }
        LAB.orig[addr] = o
    end
    return o
end

local function setIf(obj, field, v)
    pcall(function()
        if math.abs((num(obj[field]) or -1) - v) > 0.5 then obj[field] = v end
    end)
end

-- режимы: бродит+шагом / бродит+бегом / свой мозг+бегом / всё как было
local function applySpeedMode(r, investigating)
    local o = origSpeeds(r)
    local move, chase
    if LAB.run then move, chase = o.chase, o.chase
    elseif LAB.wander then move, chase = o.move, o.move
    else move, chase = o.move, o.chase end
    setIf(r, "MoveSpeed", move)
    setIf(r, "chasespeed", chase)
    if LAB.wander then
        local want = LAB.run and o.chase or (investigating and o.move * LAB.investigateSpeed or o.move)
        pcall(function() setIf(r.CharacterMovement, "MaxWalkSpeed", want) end)
    elseif LAB.run then
        pcall(function() setIf(r.CharacterMovement, "MaxWalkSpeed", o.chase) end)
    end
end

local function restoreSpeeds()
    for _, r in ipairs(allRokus()) do
        local o = LAB.orig[r:GetAddress()]
        if o then
            setIf(r, "MoveSpeed", o.move)
            setIf(r, "chasespeed", o.chase)
            pcall(function() r.CharacterMovement.MaxWalkSpeed = o.move end)
        end
    end
end
local lockSpeed = applySpeedMode

local WANDER_STEP = 0.5   -- секунд между тиками бродилки (по времени игры)

local function wanderTick()
    if LAB.pauseWander then return end   -- сцена поимки: все стоят
    -- на паузе (FunMenu, меню игры) время игры стоит — и мы ничего не считаем
    local g = gameNow()
    if not g then return end
    if LAB.lastGame and g - LAB.lastGame < 0.05 then return end
    LAB.lastGame = g

    for i, r in ipairs(allRokus()) do
        local addr = r:GetAddress()
        if LAB.wanderOnly and not LAB.wanderOnly[addr] then goto continue end   -- "Двойняшки": бродит только вторая
        local born = LAB.born[addr]
        if born and os.clock() - born < 3 then goto continue end   -- новенькой даём освоиться
        if not rokuSettled(r) then goto continue end                -- и родной игры тоже
        local st = LAB.targets[addr]
        local l = r:K2_GetActorLocation()
        local pos = { X = l.X, Y = l.Y, Z = l.Z }
        lockSpeed(r, st and st.investigate)
        local need = not st
        if st then
            if st.waitUntil then                         -- стоит и осматривается
                if g < st.waitUntil then goto continue end
                st.waitUntil = nil
                need = true; st.why = "done looking"
            else
                local dd = vlen(pos.X - st.dest.X, pos.Y - st.dest.Y, 0)
                local moved = vlen(pos.X - st.lastPos.X, pos.Y - st.lastPos.Y, 0)
                local dt = g - (st.lastG or g)
                st.stillFor = (moved < 10 * math.max(dt, 0.1) / 0.5) and (st.stillFor + dt) or 0
                st.lastPos, st.lastG = pos, g
                if dd < 150 then
                    if st.investigate then
                        -- дошла до шума: осматривается, потом снова бродит
                        ctrlCall(r, function(c) c:StopMovement() end)
                        playLookAround(r)
                        st.investigate = false
                        st.waitUntil = g + LAB.lookTime
                        log(string.format("Lab: Roku #%d reached the noise, looking around", i))
                        goto continue
                    end
                    need = true; st.why = "arrived"
                elseif st.stillFor >= 4 then
                    need = true; st.why = "stuck"
                end
            end
        end
        if need then
            if not st then brainOff(r) end
            local dest = pickDest(r)
            if dest then
                local ok, res = sendTo(r, dest)
                log(string.format("Lab: Roku #%d -> (%.0f, %.0f) %s, MoveTo=%s%s", i, dest.X, dest.Y,
                    st and st.why or "start", tostring(ok), ok and (" result " .. tostring(res)) or (" error " .. tostring(res))))
                LAB.targets[addr] = { dest = dest, lastPos = pos, lastG = g, stillFor = 0 }
            else
                log("Lab: no destination found for Roku #" .. i)
            end
        end
        ::continue::
    end
end

local function setWander(on)
    LAB.wander = on
    if on then
        LAB.targets = {}
        LAB.points = nil
        LAB.lastGame = nil
        wanderTick()
    else
        for _, r in ipairs(allRokus()) do brainOn(r) end
        if LAB.run then
            for _, r in ipairs(allRokus()) do applySpeedMode(r) end
        else
            restoreSpeeds()
        end
        LAB.targets = {}
        log("Lab: wander off, Roku brains restarted")
    end
end

------------------------------------------------------------------------
-- ШУМ: событие в точке -> ближайшая Року (в радиусе) идёт проверить
------------------------------------------------------------------------
-- её собственное расследование: пишем точку шума в её Blackboard (работает с обычным мозгом)
local function nativeInvestigate(r, loc)
    local ok = pcall(function()
        local c = aiCtrl(r); if not c then return end
        local bb = c.Blackboard
        bb:SetValueAsVector(FName("InvestigationLocation"), loc)
        bb:SetValueAsBool(FName("bShouldInvestigate"), true)
        bb:SetValueAsBool(FName("bInvestigationActive"), true)
        bb:SetValueAsBool(FName("CancelInvestigation"), false)
    end)
    pcall(function() r.InvestigationLocation = loc end)
    -- через 2 с смотрим, что она с этим сделала (для разведки)
    after(2000, function()
        if not valid(r) then return end
        local inv, act, bbloc = "?", "?", "?"
        pcall(function() inv = tostring(r.bIsInvestigating) end)
        pcall(function()
            local c = aiCtrl(r); if not c then return end
        local bb = c.Blackboard
            act = tostring(bb:GetValueAsBool(FName("bInvestigationActive")))
            local v = bb:GetValueAsVector(FName("InvestigationLocation"))
            bbloc = string.format("(%.0f, %.0f)", v.X, v.Y)
        end)
        log("Lab native investigate check: bIsInvestigating=" .. inv .. " bb.bInvestigationActive=" .. act .. " bb.InvestigationLocation=" .. bbloc)
    end)
    return ok
end

local function makeNoise(loc, radius, label)
    if NOISE_HOOK and label ~= "item landed" then return NOISE_HOOK(loc, radius, label) end
    -- брошенные предметы родной мозг Року слышит сам (так было в игре изначально),
    -- наш приказ только перезаписал бы ей точку
    if label == "item landed" and not LAB.wander then return end
    local best, bd, bi = nil, math.huge, 0
    for i, r in ipairs(allRokus()) do
        local d = math.huge
        pcall(function() local l = r:K2_GetActorLocation(); d = vlen(l.X - loc.X, l.Y - loc.Y, l.Z - loc.Z) end)
        if d < bd then best, bd, bi = r, d, i end
    end
    if not best or bd > radius then
        log(string.format("Lab noise '%s' at (%.0f, %.0f): nobody within %d cm (nearest %.0f)", label, loc.X, loc.Y, radius, bd))
        return
    end
    -- не дёргаем одну и ту же Року чаще раза в 6 с: иначе она бесконечно
    -- перезапускает расследование и никуда не доходит
    local g = gameNow() or 0
    local baddr = best:GetAddress()
    if g - (LAB.lastOrder[baddr] or -100) < LAB.orderCooldown then return end
    LAB.lastOrder[baddr] = g
    LAB.noises = LAB.noises + 1
    if LAB.wander then
        local addr = best:GetAddress()
        local ok = sendTo(best, loc)
        LAB.targets[addr] = { dest = { X = loc.X, Y = loc.Y, Z = loc.Z }, lastPos = { X = 0, Y = 0, Z = 0 },
            lastG = gameNow(), stillFor = 0, investigate = true }
        log(string.format("Lab noise '%s' at (%.0f, %.0f): Roku #%d (%.0f cm away) goes to check [our brain], MoveTo=%s", label, loc.X, loc.Y, bi, bd, tostring(ok)))
    else
        local ok = nativeInvestigate(best, loc)
        log(string.format("Lab noise '%s' at (%.0f, %.0f): Roku #%d (%.0f cm away) told to investigate [her brain], blackboard=%s", label, loc.X, loc.Y, bi, bd, tostring(ok)))
    end
end

------------------------------------------------------------------------
-- События мира: вентиляции и двери. Следим за их флагами (без хуков)
------------------------------------------------------------------------
local function worldTick()
    local g = gameNow() or 0
    if not LAB.world or g - (LAB.worldScanAt or -100) > 15 then   -- раз в 15 с обновляем список
        LAB.world = { vents = FindAllOf("BP_Vent_C") or {}, doors = FindAllOf("BP_Door_C") or {} }
        LAB.worldScanAt = g
    end
    local function watch(list, flagName, enabled, radius, label)
        for _, a in ipairs(list) do
            if valid(a) then
                local addr = a:GetAddress()
                local v = nil
                pcall(function() v = a[flagName] end)
                local was = LAB.flags[addr]
                LAB.flags[addr] = v
                if enabled and was == false and v == true then
                    local l = a:K2_GetActorLocation()
                    makeNoise({ X = l.X, Y = l.Y, Z = l.Z }, radius, label)
                end
            end
        end
    end
    watch(LAB.world.vents, "bIsActive", LAB.noiseVent, LAB.ventRadius, "vent opened")
    watch(LAB.world.doors, "bIsOpen", LAB.noiseDoor, LAB.doorRadius, "door opened")
end

-- где предмет на самом деле: физикой двигается его меш, а не сам актор
local function itemPos(a)
    local p = nil
    for _, f in ipairs({ "Mesh", "StaticMesh", "StaticMeshComponent" }) do
        pcall(function()
            local c = a[f]
            if valid(c) then local l = c:K2_GetComponentLocation(); p = { X = l.X, Y = l.Y, Z = l.Z } end
        end)
        if p then return p end
    end
    pcall(function() local l = a:K2_GetRootComponent():K2_GetComponentLocation(); p = { X = l.X, Y = l.Y, Z = l.Z } end)
    if p then return p end
    pcall(function() local l = a:K2_GetActorLocation(); p = { X = l.X, Y = l.Y, Z = l.Z } end)
    return p
end

-- брошенный предмет: следим за летящими предметами, шум там, где упал
-- наш мозг подслушивает её собственный слух: если игра записала ей в Blackboard
-- новую точку расследования, ведём её туда сами (дальность и реакция — как в оригинале)
local function hearingTick()
    if not LAB.wander then return end
    local g = gameNow() or 0
    for i, r in ipairs(allRokus()) do
        local addr = r:GetAddress()
        local loc, should = nil, false
        pcall(function()
            local c = aiCtrl(r); if not c then return end
        local bb = c.Blackboard
            local v = bb:GetValueAsVector(FName("InvestigationLocation"))
            if num(v.X) and math.abs(v.X) < 1e7 then loc = { X = v.X, Y = v.Y, Z = v.Z } end
            should = bb:GetValueAsBool(FName("bShouldInvestigate")) == true
                or bb:GetValueAsBool(FName("bInvestigationActive")) == true
        end)
        local last = LAB.heard[addr]
        if loc and (not last or vlen(loc.X - last.X, loc.Y - last.Y, 0) > 100) then
            LAB.heard[addr] = loc
            if last then          -- первая запись — просто запоминаем, что там было
                local st = LAB.targets[addr]
                if st and should ~= nil then
                    sendTo(r, loc)
                    LAB.targets[addr] = { dest = loc, lastPos = { X = 0, Y = 0, Z = 0 }, lastG = g, stillFor = 0, investigate = true }
                    LAB.lastOrder[addr] = g
                    LAB.noises = LAB.noises + 1
                    log(string.format("Lab: Roku #%d HEARD something (her own hearing) at (%.0f, %.0f), going to check [our brain]", i, loc.X, loc.Y))
                end
            end
        end
    end
end

local function noiseTick()
    hearingTick()
    local g = gameNow() or 0
    if LAB.noiseThrow and LAB.watchThrowUntil and g < LAB.watchThrowUntil then
        for _, a in ipairs(LAB.tracked or {}) do
            if valid(a) then
                local addr = a:GetAddress()
                local pos = itemPos(a)
                local tr = LAB.trk[addr]
                if pos then
                    if not tr then
                        tr = { last = pos, lastG = g, start = pos, maxSpeed = 0, slowFor = 0 }
                        LAB.trk[addr] = tr
                    else
                        local dt = g - tr.lastG
                        if dt > 0.01 then
                            local speed = vlen(pos.X - tr.last.X, pos.Y - tr.last.Y, pos.Z - tr.last.Z) / dt
                            tr.maxSpeed = math.max(tr.maxSpeed, speed)
                            if speed > 250 then LAB.flying[addr] = true end
                            if LAB.flying[addr] and speed < 20 then tr.slowFor = tr.slowFor + dt else tr.slowFor = 0 end
                            tr.last, tr.lastG = pos, g
                            if LAB.flying[addr] and tr.slowFor >= 0.3 then
                                local spot = { X = pos.X, Y = pos.Y, Z = pos.Z }
                                log(string.format("Lab throw: item landed at (%.0f, %.0f), max speed %.0f cm/s", spot.X, spot.Y, tr.maxSpeed))
                                LAB.watchThrowUntil, LAB.flying, LAB.tracked, LAB.trk = nil, {}, {}, {}   -- одно приземление на бросок
                                -- запасной вариант: если её собственный слух за 1.5 с не отреагировал
                                local before = LAB.noises
                                after(1500, function()
                                    if LAB.noises == before then makeNoise(spot, LAB.throwRadius, "item landed") end
                                end)
                                break
                            end
                        end
                    end
                end
            end
        end
    elseif LAB.watchThrowUntil and g >= LAB.watchThrowUntil then
        -- так и не "упал": пишем, что видели, чтобы понять почему
        for addr, tr in pairs(LAB.trk) do
            log(string.format("Lab throw: no landing detected (moved %.0f cm, max speed %.0f cm/s, flying=%s)",
                vlen(tr.last.X - tr.start.X, tr.last.Y - tr.start.Y, tr.last.Z - tr.start.Z), tr.maxSpeed, tostring(LAB.flying[addr] == true)))
        end
        LAB.watchThrowUntil, LAB.flying, LAB.tracked, LAB.trk = nil, {}, {}, {}
    end

    -- бег: раз в секунду шум вокруг игрока
    if LAB.noiseSprint and g - (LAB.lastSprintNoise or 0) >= 1 then
        local p = getPawn()
        if p then
            local v = nil
            pcall(function() v = p:GetVelocity() end)
            local speed = v and vlen(v.X or 0, v.Y or 0, 0) or 0
            if speed > 350 then
                LAB.lastSprintNoise = g
                local l = p:K2_GetActorLocation()
                makeNoise({ X = l.X, Y = l.Y, Z = l.Z }, LAB.sprintRadius, "footsteps")
            end
        end
    end
end

-- классы предметов из скана объектов (BP_ThrowableBase_C сам по себе не ищется: в игре только наследники)
local ITEM_CLASSES = { "BP_T_Apple_C", "BP_T_Beercan_C", "BP_T_Carrot_C", "BP_T_Flashlight_C", "BP_T_Gstick_C",
    "BP_T_PackofPines_C", "BP_T_Skull_C", "BP_T_TestTubes_C", "BP_T_WineBottle_C", "BP_T_cowbell_C",
    "BP_TrashCube_C", "BP_PineCone_C", "BP_coffee_C", "4pack_of_beer_C", "BP_Medikit_C", "BP_T_SumOfNothing_C",
    "BP_ThrowableBase_C" }

onThrowLab = function(obj)
    if not LAB.wander then return end     -- родной мозг слышит предметы сам
    LAB.watchThrowUntil = (gameNow() or 0) + 6
    LAB.tracked, LAB.flying, LAB.trk = {}, {}, {}
    if valid(obj) then
        LAB.tracked[1] = obj
        log("Lab throw: tracking the thrown item from the hook: " .. describe(obj))
        return
    end
    -- запасной путь: предметы рядом с игроком
    local p = getPawn(); if not p then return end
    local me = p:K2_GetActorLocation()
    for _, cname in ipairs(ITEM_CLASSES) do
        for _, a in ipairs(FindAllOf(cname) or {}) do
            if valid(a) and #LAB.tracked < 12 then
                pcall(function()
                    local l = a:K2_GetActorLocation()
                    if vlen(l.X - me.X, l.Y - me.Y, l.Z - me.Z) < 500 then LAB.tracked[#LAB.tracked + 1] = a end
                end)
            end
        end
    end
    log("Lab throw: item from the hook not available, tracking " .. #LAB.tracked .. " item(s) near the player")
end

local function spawnExtra()
    local pawn = getPawn(); if not pawn then return "No player" end
    local cls = StaticFindObject("/Game/ROKUv3/BP_Rokuv3.BP_Rokuv3_C")
    if not valid(cls) then return "Roku class not loaded" end
    local me = pawn:K2_GetActorLocation()
    local loc = nil
    local pts = patrolPoints()
    for _ = 1, 20 do                          -- подальше от игрока
        local p = #pts > 0 and pts[math.random(1, #pts)] or randomNavPoint({ X = me.X, Y = me.Y, Z = me.Z }, 6000)
        if p and vlen(p.X - me.X, p.Y - me.Y, 0) > 2000 then loc = p break end
        loc = p
    end
    if not loc then return "No spot to spawn" end
    log(string.format("Lab spawn: step 1 SpawnActor at (%.0f, %.0f, %.0f)", loc.X, loc.Y, loc.Z))
    local a = pawn:GetWorld():SpawnActor(cls, { X = loc.X, Y = loc.Y, Z = loc.Z + 120 }, { Pitch = 0, Yaw = math.random(0, 359), Roll = 0 })
    if not valid(a) then log("Lab spawn: SpawnActor failed") return "Spawn failed" end
    log("Lab spawn: step 2 actor alive: " .. describe(a))
    local addr = a:GetAddress()
    LAB.extras[#LAB.extras + 1] = addr        -- только адрес
    LAB.born[addr] = os.clock()
    -- контроллер — только если игра не дала свой, и не сразу
    after(1500, function()
        a = rokuAt(addr)
        if not a then log("Lab spawn: actor gone before controller check") return end
        local has = false
        has = aiCtrl(a) ~= nil
        log("Lab spawn: step 3 controller from game: " .. tostring(has))
        if not has then
            pcall(function() a:SpawnDefaultController() end)
            has = aiCtrl(a) ~= nil
            log("Lab spawn: step 4 SpawnDefaultController -> " .. tostring(has))
        end
    end)
    return "Extra Roku #" .. #LAB.extras .. " spawned (see console)"
end

local function removeExtras()
    local n = 0
    for _, addr in ipairs(LAB.extras) do
        local a = rokuAt(addr)
        if a then
            ctrlCall(a, function(c) c:K2_DestroyActor() end)
            pcall(function() a:K2_DestroyActor() end); n = n + 1
        end
    end
    LAB.extras = {}
    LAB.targets = {}
    return "Removed " .. n
end

------------------------------------------------------------------------
-- Скан мозга Року
------------------------------------------------------------------------
describe = function(v)
    if type(v) == "userdata" or type(v) == "table" then
        local ok, n = pcall(function() return v:GetFullName() end)
        if ok and n then return n end
    end
    return tostring(v)
end

local function dumpProps(obj, out, indent, withEngine)
    local cls = nil
    pcall(function() cls = obj:GetClass() end)
    local guard = 0
    while cls and valid(cls) and guard < 12 do
        local cname = cls:GetFullName()
        local engine = cname:find("/Script/") ~= nil
        if withEngine or not engine then
            pcall(function()
                cls:ForEachProperty(function(prop)
                    local n = prop:GetFName():ToString()
                    local v = "?"
                    pcall(function() v = describe(obj[n]) end)
                    out[#out + 1] = indent .. n .. " = " .. v
                end)
            end)
        end
        local ok, sup = pcall(function() return cls:GetSuperStruct() end)
        cls = ok and sup or nil
        guard = guard + 1
    end
end

local function dumpBlackboard(bb, out)
    local asset = nil
    for _, f in ipairs({ "DefaultBlackboardAsset", "BlackboardAsset" }) do
        pcall(function() if valid(bb[f]) then asset = bb[f] end end)
        if asset then break end
    end
    if not asset then out[#out + 1] = "  (blackboard asset not readable)"; return end
    out[#out + 1] = "  asset: " .. describe(asset)
    local guard = 0
    while valid(asset) and guard < 5 do
        pcall(function()
            asset.Keys:ForEach(function(_, e)
                local entry = e:get()
                local name = entry.EntryName:ToString()
                local ktype = "?"
                pcall(function() ktype = entry.KeyType:GetClass():GetFName():ToString() end)
                local val = "?"
                local fn = ({ BlackboardKeyType_Object = "GetValueAsObject", BlackboardKeyType_Vector = "GetValueAsVector",
                    BlackboardKeyType_Bool = "GetValueAsBool", BlackboardKeyType_Float = "GetValueAsFloat",
                    BlackboardKeyType_Int = "GetValueAsInt", BlackboardKeyType_Enum = "GetValueAsEnum",
                    BlackboardKeyType_Name = "GetValueAsName", BlackboardKeyType_String = "GetValueAsString",
                    BlackboardKeyType_Rotator = "GetValueAsRotator", BlackboardKeyType_Class = "GetValueAsClass" })[ktype]
                if fn then
                    pcall(function()
                        local r = bb[fn](bb, FName(name))
                        if type(r) == "table" and r.X then val = string.format("(%.0f, %.0f, %.0f)", r.X, r.Y, r.Z)
                        elseif type(r) == "table" and r.Yaw then val = string.format("(P %.0f, Y %.0f)", r.Pitch, r.Yaw)
                        else val = describe(r) end
                    end)
                end
                out[#out + 1] = string.format("  key %-28s %-30s = %s", name, ktype, val)
            end)
        end)
        local parent = nil
        pcall(function() parent = asset.Parent end)
        asset = valid(parent) and parent or nil
        if asset then out[#out + 1] = "  parent asset: " .. describe(asset) end
        guard = guard + 1
    end
end

local function scanRoku()
    local out = {}
    local function w(s) out[#out + 1] = s end
    local rs = allRokus()
    w("Rokus in level: " .. #rs)
    local r = rs[1]
    if not r then return "Roku not found" end
    w("== ROKU " .. describe(r))
    pcall(function() w("  MaxWalkSpeed = " .. tostring(r.CharacterMovement.MaxWalkSpeed)) end)
    pcall(function() w("  CustomTimeDilation = " .. tostring(r.CustomTimeDilation)) end)
    pcall(function() local l = r:K2_GetActorLocation(); w(string.format("  location = (%.0f, %.0f, %.0f)", l.X, l.Y, l.Z)) end)
    for _, n in ipairs({ "bPlayerInVisionBox", "bLineTraceHitPlayer", "bIsChasing", "bSensesEnabled", "visionchecker", "MoveSpeed", "chasespeed", "bLateSpeed" }) do
        pcall(function() w("  " .. n .. " = " .. describe(r[n])) end)
    end
    pcall(function()
        local vb = r.VisionBox
        local e = vb:GetScaledBoxExtent()
        local l = vb:GetRelativeLocation()
        w(string.format("  VisionBox extent (%.0f, %.0f, %.0f) at relative (%.0f, %.0f, %.0f), attached to %s",
            e.X, e.Y, e.Z, l.X, l.Y, l.Z, describe(vb:GetAttachParent())))
    end)
    pcall(function()
        local hs = r.HearingSphere
        w("  HearingSphere radius = " .. tostring(hs:GetScaledSphereRadius()))
    end)
    w("-- game-side variables:")
    dumpProps(r, out, "  ", false)

    local mesh = nil
    pcall(function() mesh = r.Mesh end)
    if valid(mesh) then
        w("-- sockets/bones with head/eye/neck:")
        pcall(function()
            mesh:GetAllSocketNames():ForEach(function(_, e)
                local n = e:get():ToString()
                local l = n:lower()
                if l:find("head") or l:find("eye") or l:find("neck") then w("  " .. n) end
            end)
        end)
    end

    local ctrl = nil
    ctrl = aiCtrl(r)
    w("")
    w("== CONTROLLER " .. describe(ctrl))
    if valid(ctrl) then
        w("-- all variables (game + engine):")
        dumpProps(ctrl, out, "  ", true)
        local brain = nil
        pcall(function() brain = ctrl.BrainComponent end)
        w("")
        w("== BRAIN " .. describe(brain))
        if valid(brain) then
            for _, f in ipairs({ "DefaultBehaviorTreeAsset", "TreeStartInfo" }) do
                pcall(function() w("  " .. f .. " = " .. describe(brain[f])) end)
            end
            pcall(function() w("  IsRunning = " .. tostring(brain:IsRunning())) end)
            pcall(function() w("  IsPaused = " .. tostring(brain:IsPaused())) end)
        end
        local bb = nil
        pcall(function() bb = ctrl.Blackboard end)
        w("")
        w("== BLACKBOARD " .. describe(bb))
        if valid(bb) then dumpBlackboard(bb, out) end
        local perc = nil
        pcall(function() perc = ctrl.PerceptionComponent end)
        w("")
        w("== PERCEPTION " .. describe(perc))
        if valid(perc) then
            pcall(function()
                perc.SensesConfig:ForEach(function(_, e)
                    local cfg = e:get()
                    w("  sense " .. describe(cfg))
                    dumpProps(cfg, out, "    ", true)
                end)
            end)
        end
    end

    for _, cname in ipairs({ "PawnSensingComponent", "AIPerceptionComponent" }) do
        for _, c in ipairs(FindAllOf(cname) or {}) do
            if valid(c) then
                w("")
                w("== " .. cname .. " " .. describe(c))
                if cname == "PawnSensingComponent" then dumpProps(c, out, "  ", true) end
            end
        end
    end

    w("")
    w("== BEHAVIOR TREE NODES (blueprint tasks / services / decorators in memory)")
    for _, base in ipairs({ "BTTask_BlueprintBase", "BTService_BlueprintBase", "BTDecorator_BlueprintBase" }) do
        local seen = {}
        for _, n in ipairs(FindAllOf(base) or {}) do
            if valid(n) then
                local c = "?"
                pcall(function() c = n:GetClass():GetFullName() end)
                seen[c] = (seen[c] or 0) + 1
            end
        end
        for c, k in pairs(seen) do w(string.format("  %s x%d", c, k)) end
    end
    for _, n in ipairs(FindAllOf("BehaviorTree") or {}) do
        if valid(n) then w("  tree asset: " .. describe(n)) end
    end

    w("")
    local pts = patrolPoints()
    w("== PATROL POINTS: " .. #pts)
    for i = 1, math.min(#pts, 10) do w(string.format("  (%.0f, %.0f, %.0f)", pts[i].X, pts[i].Y, pts[i].Z)) end

    w("")
    w("== VIEW POINTS (actor / head socket / GetActorEyesViewPoint)")
    local v = rokuViews(r)
    for _, k in ipairs({ "actor", "head", "eyes" }) do
        local e = v[k]
        if e then w(string.format("  %-5s loc (%.0f, %.0f, %.0f) dir (%.2f, %.2f, %.2f)", k, e.loc.X, e.loc.Y, e.loc.Z, e.dir.X, e.dir.Y, e.dir.Z))
        else w("  " .. k .. ": not available") end
    end
    w("  head socket: " .. tostring(headSocket))

    local path = ROOT .. "\\roku_scan.txt"
    local f = io.open(path, "w")
    if not f then return "Could not write roku_scan.txt" end
    f:write(table.concat(out, "\n"))
    f:close()
    log("Lab: Roku scan saved: " .. path)
    return "Saved roku_scan.txt (" .. #out .. " lines)"
end

------------------------------------------------------------------------
-- Отладка зрения: что "видит" наша проверка и что говорит игра
------------------------------------------------------------------------
local function flag(r, name)
    local v = nil
    pcall(function() v = r[name] end)
    if v == true then return "YES" elseif v == false then return "no " end
    return " ? "
end

local function visionTick()
    local pawn = getPawn()
    if not pawn then return end
    local me = pawn:K2_GetActorLocation()
    local lines = {}
    for i, r in ipairs(allRokus()) do
        if i > 5 then break end
        local d = 0
        pcall(function() local l = r:K2_GetActorLocation(); d = vlen(l.X - me.X, l.Y - me.Y, l.Z - me.Z) end)
        local inBox, trace, chase = flag(r, "bPlayerInVisionBox"), flag(r, "bLineTraceHitPlayer"), flag(r, "bIsChasing")
        lines[#lines + 1] = string.format("#%d  %5.0f cm   in vision box %s   trace %s   chasing %s   senses %s",
            i, d, inBox, trace, chase, flag(r, "bSensesEnabled"))
        local key = inBox .. trace .. chase
        local addr = r:GetAddress()
        if LAB.sees[addr] ~= key then
            LAB.sees[addr] = key
            log(string.format("Lab vision: Roku #%d dist %.0f inBox=%s trace=%s chasing=%s", i, d, inBox, trace, chase))
        end
    end
    lines[#lines + 1] = string.format("spotted by the game: %d time(s)   noises sent: %d   %s",
        LAB.seenCount or 0, LAB.noises, LAB.run and "[RUN]" or "[walk]")
    if LAB.stealth then lines[#lines + 1] = string.format("STEALTH TEST: caught %d time(s)", LAB.caught) end
    for i = 1, 8 do
        local t = UI.labLines[i]
        if valid(t) then
            setText(t, lines[i] or "")
            t:SetVisibility(lines[i] and VIS_SHOW or VIS_HIDE)
        end
    end
end

------------------------------------------------------------------------
-- Скан интерактивных объектов: вентиляции, двери, укрытия, спавнеры предметов
------------------------------------------------------------------------
local INTERACT_WORDS = { "vent", "door", "gate", "hid", "spawn", "shelf", "cabinet", "drawer", "locker",
                         "loot", "pickup", "item", "crate", "box", "trap", "note", "sumof" }

local function scanInteract()
    local out = {}
    local function w(x) out[#out + 1] = x end
    local counts, first = {}, {}
    for _, a in ipairs(FindAllOf("Actor") or {}) do
        if valid(a) then
            local c = "?"
            pcall(function() c = a:GetClass():GetFullName() end)
            if c:find("/Game/") then
                counts[c] = (counts[c] or 0) + 1
                first[c] = first[c] or a
            end
        end
    end
    local names = {}
    for c in pairs(counts) do names[#names + 1] = c end
    table.sort(names)
    w("== ALL GAME ACTOR CLASSES IN LEVEL")
    for _, c in ipairs(names) do w(string.format("  %-90s x%d", c, counts[c])) end

    w("")
    w("== INTERESTING CLASSES: functions and variables of the first instance")
    for _, c in ipairs(names) do
        local lc = c:lower()
        local hit = false
        for _, word in ipairs(INTERACT_WORDS) do if lc:find(word, 1, true) then hit = true break end end
        if hit and not lc:find("rokuv3") and not lc:find("horrorcharacter") then
            local a = first[c]
            w("")
            w("-- " .. c .. "   (x" .. counts[c] .. ")")
            pcall(function() local l = a:K2_GetActorLocation(); w(string.format("   first at (%.0f, %.0f, %.0f)", l.X, l.Y, l.Z)) end)
            local cls = a:GetClass()
            local guard = 0
            while cls and valid(cls) and guard < 8 do
                local cname = cls:GetFullName()
                if not cname:find("/Script/") then
                    local fns = {}
                    pcall(function() cls:ForEachFunction(function(f) fns[#fns + 1] = f:GetFName():ToString() end) end)
                    table.sort(fns)
                    w("   functions (" .. (cname:match("([^%.]+)$") or cname) .. "): " .. table.concat(fns, ", "))
                end
                local ok, sup = pcall(function() return cls:GetSuperStruct() end)
                cls = ok and sup or nil
                guard = guard + 1
            end
            w("   variables:")
            dumpProps(a, out, "     ", false)
        end
    end
    local path = ROOT .. "\\interact_scan.txt"
    local f = io.open(path, "w")
    if not f then return "Could not write interact_scan.txt" end
    f:write(table.concat(out, "\n"))
    f:close()
    log("Lab: interact scan saved: " .. path)
    return "Saved interact_scan.txt (" .. #names .. " classes)"
end

------------------------------------------------------------------------
-- Скан стиля интерфейса игры: шрифты, размеры, цвета, обводки, картинки
------------------------------------------------------------------------
local function colStr(c)
    local ok, r = pcall(function() return string.format("(%.2f %.2f %.2f a%.2f)", c.R, c.G, c.B, c.A) end)
    return ok and r or "?"
end

local function scanUIStyle()
    local out = {}
    local function w(x) out[#out + 1] = x end
    local function full(o) local n = "?"; pcall(function() n = o:GetFullName() end); return n end

    w("== FONT ASSETS loaded")
    for _, cn in ipairs({ "Font", "FontFace" }) do
        for _, f in ipairs(FindAllOf(cn) or {}) do
            if valid(f) then w("  [" .. cn .. "] " .. full(f)) end
        end
    end

    -- текст: группируем по шрифту/размеру/цвету, по 4 примера
    local groups, order = {}, {}
    local notice = {}
    for _, cn in ipairs({ "TextBlock", "RichTextBlock" }) do
        for _, t in ipairs(FindAllOf(cn) or {}) do
            if valid(t) then
                local fn = full(t)
                if fn:find("/Game/") and not fn:find("GONPlus") then
                    local font, face, size, spacing, outline, color, shadow, text = "?", "?", "?", "?", "", "?", "", ""
                    pcall(function() font = full(t.Font.FontObject) end)
                    pcall(function() face = t.Font.TypefaceFontName:ToString() end)
                    pcall(function() size = tostring(t.Font.Size) end)
                    pcall(function() spacing = tostring(t.Font.LetterSpacing) end)
                    pcall(function()
                        local os_ = t.Font.OutlineSettings
                        if (os_.OutlineSize or 0) > 0 then outline = " outline=" .. tostring(os_.OutlineSize) .. colStr(os_.OutlineColor) end
                    end)
                    pcall(function() color = colStr(t.ColorAndOpacity.SpecifiedColor) end)
                    pcall(function()
                        local so = t.ShadowOffset
                        local sc = t.ShadowColorAndOpacity
                        if sc.A > 0 then shadow = string.format(" shadow=(%.0f,%.0f)%s", so.X, so.Y, colStr(sc)) end
                    end)
                    pcall(function() text = t:GetText():ToString() end)
                    if text == "" then pcall(function() text = t.Text:ToString() end) end
                    local key = font:match("([^%.]+)$") .. " / " .. face .. " / size " .. size .. " / spacing " .. spacing .. " / " .. color .. outline .. shadow
                    local g = groups[key]
                    if not g then g = { n = 0, ex = {} }; groups[key] = g; order[#order + 1] = key end
                    g.n = g.n + 1
                    if #g.ex < 4 and text ~= "" then g.ex[#g.ex + 1] = '"' .. text:sub(1, 40) .. '"  <- ' .. (fn:match("/Game/[^%s]+") or fn) end
                    if text:upper():find("NOTICE") or text:find("^%s*%+") then notice[#notice + 1] = key .. "   " .. text .. "   " .. fn end
                end
            end
        end
    end
    table.sort(order, function(a, b) return groups[a].n > groups[b].n end)
    w("")
    w("== TEXT STYLES used by the game (font / typeface / size / letter spacing / color / outline / shadow)")
    for _, k in ipairs(order) do
        w(string.format("  x%-4d %s", groups[k].n, k))
        for _, e in ipairs(groups[k].ex) do w("          " .. e) end
    end
    w("")
    w("== TEXTS LIKE '+ NOTICE +'")
    for _, x in ipairs(notice) do w("  " .. x) end

    -- картинки и рамки: какие текстуры/материалы и цвета
    w("")
    w("== IMAGES / BORDERS / BUTTONS (game widgets)")
    local seen = {}
    for _, cn in ipairs({ "Image", "Border", "Button", "ProgressBar" }) do
        for _, im in ipairs(FindAllOf(cn) or {}) do
            if valid(im) then
                local fn = full(im)
                if fn:find("/Game/") and not fn:find("GONPlus") then
                    local res, tint = "none", "?"
                    pcall(function()
                        local b = (cn == "Image") and im.Brush or (cn == "Border" and im.Background) or nil
                        if cn == "Button" then b = im.WidgetStyle.Normal end
                        if cn == "ProgressBar" then b = im.WidgetStyle.FillImage end
                        if b then
                            if valid(b.ResourceObject) then res = full(b.ResourceObject) end
                            tint = colStr(b.TintColor.SpecifiedColor)
                        end
                    end)
                    local extra = ""
                    pcall(function() if cn == "Image" then extra = " color=" .. colStr(im.ColorAndOpacity) end end)
                    pcall(function() if cn == "Border" then extra = " brushColor=" .. colStr(im.BrushColor) end end)
                    pcall(function() if cn == "ProgressBar" then extra = " fill=" .. colStr(im.FillColorAndOpacity) end end)
                    local line = string.format("  [%s] %s  tint=%s%s", cn, res, tint, extra)
                    if not seen[line] then seen[line] = true; w(line .. "   <- " .. (fn:match("/Game/[^%s]+") or fn)) end
                end
            end
        end
    end

    w("")
    w("== WIDGET CLASSES in memory (/Game/)")
    local wc = {}
    for _, cls in ipairs(FindAllOf("WidgetBlueprintGeneratedClass") or {}) do
        if valid(cls) then local n = full(cls); if n:find("/Game/") then wc[#wc + 1] = n end end
    end
    table.sort(wc)
    for _, n in ipairs(wc) do w("  " .. n) end

    local path = ROOT .. "\\ui_scan.txt"
    local f = io.open(path, "w")
    if not f then return "Could not write ui_scan.txt" end
    f:write(table.concat(out, "\n"))
    f:close()
    log("Lab: UI style scan saved: " .. path)
    return "Saved ui_scan.txt (" .. #order .. " text styles)"
end

SCREENS.lab = function()
    local function onoff(v) return v and "[ON]" or "[off]" end
    -- время: перемотка таймеров забега и мутаторов, ускорение мира
    local function skip(sec)
        if sec <= 0 then return end
        if R.t0 then R.t0 = R.t0 - sec end
        if R.chaos and R.chaos.nextAt then R.chaos.nextAt = R.chaos.nextAt - sec end
        for _, id in ipairs(ACTIVE_LIST) do
            local st = MUTS[id].state
            if st and st.t0 then st.t0 = st.t0 - sec end
        end
        if loveSkip then loveSkip(sec) end
        UI.labStatus = "Skipped " .. fmtTime(sec)
    end
    local function countdownLeft()
        if loveActive and loveActive() then return loveLeft() end
        for _, id in ipairs(ACTIVE_LIST) do
            local m = MUTS[id]
            if m.countdown then local ok, l = pcall(m.countdown, m.state); if ok then return l end end
        end
        return nil
    end
    local left = countdownLeft()
    local function skipTo(target)
        local l = countdownLeft()
        if not l then UI.labStatus = "No countdown running" return end
        skip(l - target)
    end
    LAB.timeScale = LAB.timeScale or 1
    local items = {
        { label = "Skip 1 minute" .. (left and ("    " .. fmtTime(left) .. " left") or ""),
          desc = "Moves the run timer, the reactor countdown and chaos forward by a minute.",
          act = function() skip(60) end },
        { label = "Skip to 5:05 left", desc = "Reactor: jump to just before the 5-minute mark (red lights).",
          act = function() skipTo(305) end },
        { label = "Skip to 1:05 left", desc = "Reactor: jump to just before the last minute (alarm).",
          act = function() skipTo(65) end },
        { label = "Skip to 0:15 left", desc = "Reactor: almost boom.",
          act = function() skipTo(15) end },
        { label = "Reactor: blackout now", desc = "Critical / Meltdown: the next power failure starts right away.",
          act = function()
              for _, id in ipairs(ACTIVE_LIST) do
                  local m = MUTS[id]
                  if m.reactor and m.state and m.state.nextBlack then m.state.nextBlack = 0; UI.labStatus = "Blackout coming" return end
              end
              UI.labStatus = "No Critical / Meltdown running"
          end },
        { label = "Preview Nightmare darkness    " .. onoff(LAB.nmPreview),
          desc = "Everything at once: dimmed colored lamps + sky off + shadows 0.75 + vignette. Tune lamps below.",
          act = function()
              LAB.nmPreview = not LAB.nmPreview
              darkPreset(LAB.nmPreview, "lab")
              UI.labStatus = darkSet("lamps", LAB.nmPreview, darkLampArg())
          end },
        { label = "Dark: level lamps dimmed    " .. onoff(darkIsOn("lamps")),
          desc = "The level's lamps at the brightness and color below (this is what Nightmare does).",
          act = function() UI.labStatus = darkSet("lamps", not darkIsOn("lamps"), darkLampArg()) end },
        { label = string.format("Lamps brightness    %s%%", (string.format("%.1f", DARK_LAMP.frac * 100):gsub("%.0$", ""))),
          desc = "Share of their normal brightness: 0 / 0.2 / 0.5 / 1 / 2 / 3 / 5 / 8 / 12 / 20 %. Sides or arrows change; applies live.",
          cycle = function(dir)
              local L, i = DARK_LAMP_LEVELS, 1
              for k, v in ipairs(L) do if v == DARK_LAMP.frac then i = k end end
              DARK_LAMP.frac = L[math.max(1, math.min(#L, i + dir))]
              if darkIsOn("lamps") then UI.labStatus = darkSet("lamps", true, darkLampArg()) end
          end },
        { label = "Lamps color    " .. DARK_LAMP.color,
          desc = "own (their usual white) / red / blood / amber / green / cyan / blue / purple. Applies live.",
          cycle = function(dir)
              local L, i = DARK_LAMP_ORDER, 1
              for k, v in ipairs(L) do if v == DARK_LAMP.color then i = k end end
              DARK_LAMP.color = L[(i - 1 + dir) % #L + 1]
              if darkIsOn("lamps") then UI.labStatus = darkSet("lamps", true, darkLampArg()) end
          end },
        { label = "Dark: sky & sun light off    " .. onoff(darkIsOn("sky")),
          desc = "SkyLight / DirectionalLight of the level: the ambient light that stays without lamps.",
          act = function() UI.labStatus = darkSet("sky", not darkIsOn("sky")) end },
        { label = "Dark: camera exposure    " .. (darkIsOn("exposure") and ("-" .. (LAB.darkStops or 1) .. " stops") or "[off]"),
          desc = "Darker than the level's own exposure: off -> -1 -> -2 -> -3 -> off. Each step is about twice as dark (flashlight too).",
          act = function()
              local nxt = not darkIsOn("exposure") and 1 or ((LAB.darkStops or 1) < 3 and (LAB.darkStops or 1) + 1 or nil)
              LAB.darkStops = nxt or LAB.darkStops
              UI.labStatus = nxt and darkSet("exposure", true, nxt) or darkSet("exposure", false)
          end },
        { label = "Dark: fog    " .. (darkIsOn("fog") and ("[" .. LAB.darkFog .. "]") or "[normal]"),
          desc = "The level's fog glows by itself. normal -> black (eats the distance) -> off (no fog) -> normal.",
          act = function()
              local nxt = not darkIsOn("fog") and "black" or (LAB.darkFog == "black" and "off" or nil)
              if darkIsOn("fog") then darkSet("fog", false) end
              LAB.darkFog = nxt or LAB.darkFog
              UI.labStatus = nxt and darkSet("fog", true, nxt) or "Dark fog normal"
          end },
        { label = "Dark: crush shadows    " .. (darkIsOn("shadows") and ("gamma " .. tostring(darkArg("shadows"))) or "[off]"),
          desc = "Color grading: darks sink, bright stays bright (flashlight). off -> 0.75 -> 0.55 -> 0.4 -> 0.3 -> off. Nightmare uses 0.75.",
          act = function()
              local steps = { 0.75, 0.55, 0.4, 0.3 }
              local nxt = nil
              if not darkIsOn("shadows") then nxt = steps[1]
              else for i, v in ipairs(steps) do if v == darkArg("shadows") then nxt = steps[i + 1] end end end
              LAB.darkGamma = nxt or LAB.darkGamma
              UI.labStatus = nxt and darkSet("shadows", true, nxt) or darkSet("shadows", false)
          end },
        { label = "Dark: strong vignette    " .. onoff(darkIsOn("vignette")),
          desc = "Dark screen edges (the level uses 0.1, this sets 1.0).",
          act = function() UI.labStatus = darkSet("vignette", not darkIsOn("vignette"), 1.0) end },
        { label = "Scan darkness  -> dark_scan.txt", desc = "Sky/sun lights, fog, post process volumes, player camera exposure, console values.",
          act = function() UI.labStatus = darkScan() end },
        { label = "World speed    x" .. LAB.timeScale,
          desc = "Everything runs faster (x1 / x2 / x4 / x8): the world, Roku, timers. Click again to change.",
          act = function()
              local nxt = { [1] = 2, [2] = 4, [4] = 8, [8] = 1 }
              LAB.timeScale = nxt[LAB.timeScale] or 1
              local pc = getPC()
              pcall(function() statics():SetGlobalTimeDilation(pc, LAB.timeScale) end)
              UI.labStatus = "World speed x" .. LAB.timeScale
          end },
        { label = "Win now (game's VICTORY)", desc = "Cheat: calls the game's own victory. The run is marked as lab - no record.",
          act = function()
              local p = getPawn(); if not p then return end
              R.cheated = true
              local ok = pcall(function() p:VICTORY() end)
              UI.labStatus = "VICTORY -> " .. tostring(ok)
          end },
        { label = "+10 apples", desc = "Cheat: adds 10 to the apple counter (no record for this run).",
          act = function()
              local p = getPawn(); if not p then return end
              R.cheated = true
              pcall(function() p.pinecollected = math.min(66, (num(p.pinecollected) or 0) + 10) end)
          end },
        { label = "God mode    " .. onoff(LAB.god), desc = "Cheat: health stays full (no record for this run).",
          act = function() LAB.god = not LAB.god; if LAB.god then R.cheated = true end end },
        { label = "Invisible to Roku    " .. onoff(LAB.invis), desc = "Cheat: like the mask, but forever (no record for this run).",
          act = function()
              LAB.invis = not LAB.invis
              if LAB.invis then R.cheated = true
              else local p = getPawn(); if p then pcall(function() p.IsMaskOn = false end) end end
          end },
        { label = "Die now (see the defeat screen)", desc = "Calls the game's death - to look at this mode's defeat screen.",
          act = function() local p = getPawn(); if p then UI.close(); pcall(function() p:PlayerDeath() end) end end },
        { label = "Roku wanders (brain off)    " .. onoff(LAB.wander),
          desc = "Her AI is stopped; she walks between the game's patrol points.",
          act = function() setWander(not LAB.wander); UI.labStatus = LAB.wander and "Wander ON" or "Wander off" end },
        { label = "Rokus always RUN (late-game style)    " .. onoff(LAB.run),
          desc = "Off: they walk at their patrol speed even after spotting you. On: chase speed all the time.",
          act = function()
              LAB.run = not LAB.run
              if LAB.run or LAB.wander then
                  for _, r in ipairs(allRokus()) do applySpeedMode(r) end
              else
                  restoreSpeeds()
              end
              UI.labStatus = LAB.run and "Rokus run" or "Rokus walk"
          end },
        { label = "Noise: thrown items    " .. onoff(LAB.noiseThrow),
          desc = "Her own brain hears items by itself. With our brain we follow her hearing; this is the fallback.",
          act = function() LAB.noiseThrow = not LAB.noiseThrow end },
        { label = "Noise: vent opened    " .. onoff(LAB.noiseVent),
          desc = "When a vent activates, the nearest Roku within 60 m comes to check it.",
          act = function() LAB.noiseVent = not LAB.noiseVent end },
        { label = "Noise: door opened    " .. onoff(LAB.noiseDoor),
          desc = "Every opened door makes noise (12 m). Can be a lot - test it.",
          act = function() LAB.noiseDoor = not LAB.noiseDoor end },
        { label = "Noise: sprinting    " .. onoff(LAB.noiseSprint),
          desc = "Running makes noise every second (15 m): the nearest Roku comes to check.",
          act = function() LAB.noiseSprint = not LAB.noiseSprint end },
        { label = "Stealth test (caught = message)    " .. onoff(LAB.stealth),
          desc = "Like the planned mode, but nobody dies: being spotted only shows CAUGHT and counts it.",
          act = function()
              LAB.stealth = not LAB.stealth
              LAB.caught = 0
              if LAB.stealth and not LAB.wander then setWander(true) end
              LAB.vision = LAB.vision or LAB.stealth
              UI.labStatus = LAB.stealth and "Stealth test ON" or "Stealth test off"
          end },
        { label = "Vision debug    " .. onoff(LAB.vision),
          desc = "Top-left: the game's own vision flags for each Roku.",
          act = function() LAB.vision = not LAB.vision end },
        { label = "Spawn extra Roku (" .. #LAB.extras .. " now)", desc = "One at a time. Every step goes to the console.",
          act = function() UI.labStatus = spawnExtra() end },
        { label = "Remove extra Rokus", desc = "Deletes the ones the lab spawned.",
          act = function() UI.labStatus = removeExtras() end },
        { label = "Scan Roku brain  -> roku_scan.txt", desc = "Controller, behavior tree, blackboard, vision flags, patrol points.",
          act = function() UI.labStatus = scanRoku() end },
        { label = "Scan objects  -> interact_scan.txt", desc = "Vents, doors, hiding spots, item spawners: their functions and variables.",
          act = function() UI.labStatus = scanInteract() end },
        { label = "Scan game UI style  -> ui_scan.txt", desc = "Fonts, sizes, colors, outlines and textures of the game's own menus. Best done in the pause menu and after visiting the main menu.",
          act = function() UI.labStatus = scanUIStyle() end },
        { label = "Scan for mutators  -> mut_scan.txt", desc = "Player and item functions (for Slippery Hands), item spawner, Roku skins. Hold an item while scanning.",
          act = function() UI.labStatus = scanMutators and scanMutators() or "not ready" end },
    }
    -- вкладки: раскладываем пункты по разделам по началу подписи
    local TABS = { { id = "run", name = "Run" }, { id = "dark", name = "Darkness" },
                   { id = "roku", name = "Roku" }, { id = "scan", name = "Scans" } }
    local function tabOf(lbl)
        if lbl:find("^Scan darkness") or lbl:find("^Reactor: blackout") or lbl:find("^Preview Nightmare")
            or lbl:find("^Dark:") or lbl:find("^Lamps ") then return "dark" end
        if lbl:find("^Scan") then return "scan" end
        if lbl:find("^Skip") or lbl:find("^World speed") or lbl:find("^Win now") or lbl:find("^%+10")
            or lbl:find("^God mode") or lbl:find("^Invisible") or lbl:find("^Die now") then return "run" end
        return "roku"
    end
    LAB.tab = LAB.tab or "run"
    local ti = 1
    for i, t in ipairs(TABS) do if t.id == LAB.tab then ti = i end end
    local shown = { { label = "Section:  < " .. TABS[ti].name .. " >  " .. ti .. "/" .. #TABS,
        desc = "Run: time and cheats.  Darkness: lights and look.  Roku: her brain, noise, spawns.  Scans: files for research.",
        cycle = function(dir)
            LAB.tab = TABS[(ti - 1 + dir) % #TABS + 1].id
            UI.sel = 1
        end } }
    for _, it in ipairs(items) do
        if tabOf(it.label) == LAB.tab then shown[#shown + 1] = it end
    end
    items = shown
    return "GON+ LAB", UI.labStatus or "Game is NOT paused here", items, "click / Enter    right click / F1 - close"
end

-- "заметила": опрос каждой Року (без хука на SetPlayerDetected — его вызывают
-- каждый кадр, и под такой нагрузкой хук в UE4SS ломался и ронял наш цикл)
local function detectTick()
    local any = false
    for i, r in ipairs(allRokus()) do
        local bb, inBox, trace = false, false, false
        ctrlCall(r, function(c) bb = c.Blackboard:GetValueAsBool(FName("bPlayerDetected")) == true end)
        pcall(function() inBox = r.bPlayerInVisionBox == true end)
        pcall(function() trace = r.bLineTraceHitPlayer == true end)
        local seen = bb or (inBox and trace)
        local addr = r:GetAddress()
        local key = tostring(bb) .. tostring(inBox and trace)
        if LAB.detKey[addr] ~= key then
            LAB.detKey[addr] = key
            log(string.format("Lab detect: Roku #%d blackboard bPlayerDetected=%s, box+trace=%s", i, tostring(bb), tostring(inBox and trace)))
        end
        if seen then any = true end
    end
    LAB.det.value = any
    if any then LAB.det.anyTrue = true end
end

do
    every(100, function()
        if LAB_ENABLED and (LAB.vision or LAB.stealth) and getPawn() then detectTick() end
    end)
    every(500, function()
        if LAB.wander and getPawn() then wanderTick() end
    end)
    every(100, function()
        if getPawn() then noiseTick() end
    end)
    every(500, function()
        if getPawn() and (LAB.noiseVent or LAB.noiseDoor) then worldTick() end
    end)
    -- "всегда бегом" и для обычного мозга (и для новых Року)
    every(1000, function()
        if LAB.run and not LAB.wander and getPawn() then
            for _, r in ipairs(allRokus()) do applySpeedMode(r) end
        end
    end)
    every(100, function()
        if not valid(UI.labBox) then return end
        local show = LAB.vision and getPawn() ~= nil
        UI.labBox:SetVisibility(show and VIS_SHOW or VIS_HIDE)
        if show then visionTick() end
        if LAB.det.anyTrue then
            LAB.det.anyTrue = false
            local g = gameNow() or 0
            if g - (LAB.lastCaught or -100) >= 3 then       -- одна поимка, а не каждую секунду погони
                LAB.lastCaught = g
                LAB.seenCount = (LAB.seenCount or 0) + 1
                if LAB.stealth then
                    LAB.caught = LAB.caught + 1
                    showBanner("CAUGHT!  (lab test #" .. LAB.caught .. ")", 3)
                    log("Lab stealth: CAUGHT #" .. LAB.caught)
                else
                    log("Lab: a Roku spotted the player (#" .. LAB.seenCount .. ")")
                end
            end
        end
    end)

    -- F1 (не F10: там консоль UE4SS). Работает, только если лабораторию открыли
    -- секретными кликами по "+GON+PLUS+" (P.labUnlocked) или LAB_ENABLED = "always".
    if LAB_ENABLED then RegisterKeyBind(Key.F1, function()
        gameThread(function()
            safe(function()
                if not (P.labUnlocked or LAB_ENABLED == "always") then return end
                if UI.open and UI.kind == "chooser" then return end    -- окно выбора важнее
                if not getPawn() or not ensureUI() then return end
                if UI.open then UI.close() return end
                UI.open, UI.kind, UI.screen, UI.sel = true, "lab", "lab", 1
                applyPause()
                refreshUI()
            end)
        end)
    end) end

end

------------------------------------------------------------------------
