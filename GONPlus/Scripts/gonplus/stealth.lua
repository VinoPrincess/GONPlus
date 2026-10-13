-- РЕЖИМ "ЧИСТЫЙ СТЕЛС"
--   Року бродит по всей карте и не охотится. Заметила по-настоящему
--   (в поле зрения + луч до игрока) — разворот, её анимация NOTICE,
--   "+ NOTICE +" на экране, смерть. Прятаться нельзя. Бег, брошенные
--   предметы и вентиляции шумят — ближайшая в радиусе идёт проверить.
------------------------------------------------------------------------
local NOTICE_MONTAGE = "/Game/ROKUv3/anims/aggro/NOTICE_Montage.NOTICE_Montage"
local ST = { on = false, n = 1, extras = {}, hiders = {}, graceUntil = 0, caught = false, saved = nil,
             hidersAt = -100, gen = 0 }

local function loadMontage()
    local m = nil
    pcall(function() m = StaticFindObject(NOTICE_MONTAGE) end)
    if valid(m) then return m end
    if LoadAsset then
        pcall(function() m = LoadAsset(NOTICE_MONTAGE) end)
        if valid(m) then return m end
        pcall(function() m = StaticFindObject(NOTICE_MONTAGE) end)
        if valid(m) then return m end
    end
    return nil
end

-- укрытия: выключаем, а родные значения запоминаем
local function setHiders(off)
    if off then
        for _, h in ipairs(FindAllOf("BP_Hider_C") or {}) do
            if valid(h) then
                local addr = h:GetAddress()
                pcall(function()
                    if ST.hiders[addr] == nil then ST.hiders[addr] = { obj = h, was = h.bIsActive } end
                    if h.bIsActive ~= false then h.bIsActive = false end
                end)
            end
        end
    else
        for _, e in pairs(ST.hiders) do
            if valid(e.obj) and e.was ~= nil then pcall(function() e.obj.bIsActive = e.was end) end
        end
        ST.hiders = {}
    end
end

-- где поставить новую Року: случайная патрульная точка, далеко от игрока и от других Року
-- (точки появления Року из игры стоят кучно — все вылезали в одном месте)
local function stealthSpot()
    local pawn = getPawn(); if not pawn then return nil end
    local me = pawn:K2_GetActorLocation()
    local others = {}
    for _, r in ipairs(allRokus()) do
        pcall(function() local l = r:K2_GetActorLocation(); others[#others + 1] = { X = l.X, Y = l.Y } end)
    end
    local function score(c)
        local s = vlen(c.X - me.X, c.Y - me.Y, 0)
        for _, o in ipairs(others) do s = math.min(s, vlen(c.X - o.X, c.Y - o.Y, 0) * 1.5) end
        return s
    end
    local pts = patrolPoints()
    -- сначала ищем "хорошую" случайную точку: не ближе 30 м к игроку и ~20 м к другим
    for _ = 1, 40 do
        if #pts == 0 then break end
        local c = pts[math.random(1, #pts)]
        if score(c) >= 3000 then return c end
    end
    -- не нашлась — лучшая из случайных патрульных и игровых точек появления
    local cands = {}
    for _ = 1, math.min(40, #pts) do cands[#cands + 1] = pts[math.random(1, #pts)] end
    for _, s in ipairs(FindAllOf("BP_RokuSpawn_C") or {}) do
        if valid(s) then pcall(function() local l = s:K2_GetActorLocation(); cands[#cands + 1] = { X = l.X, Y = l.Y, Z = l.Z } end) end
    end
    local best, bs = nil, -1
    for _, c in ipairs(cands) do
        local sc = score(c)
        if sc > bs then best, bs = c, sc end
    end
    return best
end

local function spawnStealthRoku()
    local pawn = getPawn(); if not pawn then return false end
    local cls = StaticFindObject("/Game/ROKUv3/BP_Rokuv3.BP_Rokuv3_C")
    if not valid(cls) then log("Stealth: Roku class not loaded") return false end
    local loc = stealthSpot()
    if not loc then log("Stealth: no spot for an extra Roku") return false end
    local a = nil
    pcall(function()
        a = pawn:GetWorld():SpawnActor(cls, { X = loc.X, Y = loc.Y, Z = loc.Z + 120 }, { Pitch = 0, Yaw = math.random(0, 359), Roll = 0 })
    end)
    if not valid(a) then log("Stealth: SpawnActor failed") return false end
    ST.extras[#ST.extras + 1] = a
    LAB.born[a:GetAddress()] = os.clock()
    log(string.format("Stealth: extra Roku spawned at (%.0f, %.0f)", loc.X, loc.Y))
    after(1500, function()
        if not valid(a) then return end
        local has = false
        has = aiCtrl(a) ~= nil
        if not has then pcall(function() a:SpawnDefaultController() end) end
    end)
    return true
end

local function hideCaughtUI()
    for _, w in ipairs({ UI.veil, UI.notice }) do
        if valid(w) then pcall(function() w:SetVisibility(VIS_HIDE) end) end
    end
end

local function setPlayerInput(block)
    local pc = getPC(); if not pc then return end
    pcall(function() pc:SetIgnoreMoveInput(block) end)
    pcall(function() pc:SetIgnoreLookInput(block) end)
    if not block then
        pcall(function() pc:ResetIgnoreMoveInput() end)
        pcall(function() pc:ResetIgnoreLookInput() end)
    end
end

stealthStart = function(n)
    ST.gen = ST.gen + 1
    local gen = ST.gen
    ST.on, ST.n, ST.caught = true, math.max(1, math.min(4, n or 1)), false
    ST.extras, ST.hidersAt = {}, -100
    ST.graceUntil = (gameNow() or 0) + 4
    ST.saved = {
        noiseThrow = LAB.noiseThrow, noiseSprint = LAB.noiseSprint, noiseVent = LAB.noiseVent,
        noiseDoor = LAB.noiseDoor, run = LAB.run, stealth = LAB.stealth,
    }
    LAB.noiseThrow, LAB.noiseSprint, LAB.noiseVent, LAB.noiseDoor = true, true, true, false
    LAB.run, LAB.stealth, LAB.pauseWander = false, false, false
    LAB.lastOrder = {}
    setWander(true)
    setHiders(true)
    hideCaughtUI()
    -- своя Року в игре появляется не сразу, а по триггеру после выхода из лифта.
    -- Поэтому дополнительные ставим только когда она уже на карте: n-1 штук
    ST.wantExtras = ST.n - 1
    ST.extrasQueued = false
    log("Stealth: started with " .. ST.n .. " Roku")
end

stealthStop = function(result)
    if not ST.on then return end
    ST.on = false
    ST.gen = ST.gen + 1
    LAB.pauseWander = false
    setWander(false)
    -- после поимки лишние Року стоят до перезапуска: сцена не ломается
    if not ST.caught then
        for _, a in ipairs(ST.extras) do
            if valid(a) then
                ctrlCall(a, function(c) c:K2_DestroyActor() end)
                pcall(function() a:K2_DestroyActor() end)
            end
        end
    end
    ST.extras = {}
    setHiders(false)
    if ST.saved then
        for k, v in pairs(ST.saved) do LAB[k] = v end
        ST.saved = nil
    end
    log("Stealth: stopped (" .. tostring(result) .. ")")
end

local function stealthCaught(r, why, text)
    if ST.caught or not ST.on then return end
    ST.caught = true
    LAB.pauseWander = true
    local pawn = getPawn()
    log("Stealth: CAUGHT (" .. why .. ")")
    setPlayerInput(true)

    -- все Року замирают
    for _, x in ipairs(allRokus()) do ctrlCall(x, function(c) c:StopMovement() end) end

    if r and valid(r) and pawn then
        local rl, me = r:K2_GetActorLocation(), pawn:K2_GetActorLocation()
        local yaw = math.deg(math.atan(me.Y - rl.Y, me.X - rl.X))
        pcall(function() r:K2_SetActorRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }, false) end)
        local m = loadMontage()
        local played = false
        if m then played = pcall(function() r:PlayAnimMontage(m, 1.0, FName("None")) end) end
        if not played then playLookAround(r) end
        log("Stealth: NOTICE montage " .. (m and "found" or "NOT found") .. ", played=" .. tostring(played))
        -- камера игрока — на неё
        pcall(function()
            local camZ = me.Z + 60
            local d = vlen(rl.X - me.X, rl.Y - me.Y, 0)
            local pitch = math.deg(math.atan((rl.Z + 70) - camZ, math.max(d, 1)))
            getPC():SetControlRotation({ Pitch = pitch, Yaw = yaw + 180, Roll = 0 })
        end)
    end

    local hid = why == "hid"
    defeat({
        title = text or "+ NOTICE +",
        sub = hid and "There is nowhere to hide from her. Not this time." or "She saw you. That's all it takes.",
        color = GAME.deep, veil = { 0, 0, 0 }, fadeIn = 2.4, hold = 3.5, scripted = true, result = "caught",
    })
end

local function isOurExtra(r)
    local addr = r:GetAddress()
    for _, a in ipairs(ST.extras) do
        if valid(a) and a:GetAddress() == addr then return true end
    end
    return false
end

-- ждём родную Року игры, потом добавляем остальных по одной
local function queueExtras()
    if ST.extrasQueued or (ST.wantExtras or 0) <= 0 then return end
    local native = 0
    for _, r in ipairs(allRokus()) do if not isOurExtra(r) then native = native + 1 end end
    if native == 0 then return end
    ST.extrasQueued = true
    local gen = ST.gen
    log(string.format("Stealth: the game's Roku is here (%d), adding %d more", native, ST.wantExtras))
    for i = 1, ST.wantExtras do
        after(2000 + (i - 1) * 2000, function()
            if ST.on and ST.gen == gen and not ST.caught then spawnStealthRoku() end
        end)
    end
end

local function stealthTick()
    if not ST.on or ST.caught or R.phase ~= "running" then return end
    local pawn = getPawn(); if not pawn then return end
    local g = gameNow() or 0
    queueExtras()
    if g - ST.hidersAt >= 1 then ST.hidersAt = g; setHiders(true) end
    if g < ST.graceUntil then return end
    local hiding = false
    pcall(function() hiding = pawn.bIsHiding == true end)
    if hiding then stealthCaught(nil, "hid", "+ NO HIDING +") return end
    for i, r in ipairs(allRokus()) do
        local inBox, trace = false, false
        pcall(function() inBox = r.bPlayerInVisionBox == true end)
        pcall(function() trace = r.bLineTraceHitPlayer == true end)
        if inBox and trace then stealthCaught(r, "seen by Roku #" .. i) return end
    end
end

every(100, function() if ST.on then stealthTick() end end)

