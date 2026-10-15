-- NIGHTMARE: с 1.1 это 4-я сложность ванильной игры (Normal без мутатора, сложность игры Hard),
-- а не отдельный режим (решение игрока 15.10.2026). Внутри забега по-прежнему R.base = "nightmare".
-- Почти невозможно, но проходимо.
--   * никакого интерфейса — только глючащая надпись режима
--   * из предметов — немного мусора и черепа (и стартовый фонарик)
--   * один удар — смерть
--   * укрытия выключены
--   * весь свет выключен (кроме фонарика в руке)
--   * Року слышит бег, двери и вентиляции и идёт проверить
--   * когда Року замечает — взгляд игрока на миг дёргает к ней
------------------------------------------------------------------------
; (function()
local NM = { on = false }
local KEEP = { BP_PineCone_C = true, BP_T_PackofPines_C = true, BP_T_SumOfNothing_C = true, BP_T_Skull_C = true }
local REMOVE = { "BP_T_Apple_C", "BP_T_Beercan_C", "BP_T_Carrot_C", "BP_T_Flashlight_C", "BP_T_Gstick_C",
    "BP_T_TestTubes_C", "BP_T_WineBottle_C", "BP_T_cowbell_C", "BP_coffee_C", "4pack_of_beer_C",
    "BP_Medikit_C", "BP_RokuMask_C" }
local TRASH_KEEP = 0.2          -- доля мусора, которая остаётся
local HP_MAX = 0.01             -- здоровье: любой удар убивает

local function dist2d(a, me)
    local p = nil
    pcall(function() p = itemPos(a) or a:K2_GetActorLocation() end)
    if not p then return math.huge end
    return vlen(p.X - me.X, p.Y - me.Y, 0)
end

-- убрать лишние предметы; first = первый проход (стартовый фонарик рядом с игроком оставляем)
local function sweepItems(first)
    local pawn = getPawn(); if not pawn then return 0 end
    local me = pawn:K2_GetActorLocation()
    local n = 0
    for _, cn in ipairs(REMOVE) do
        for _, a in ipairs(FindAllOf(cn) or {}) do
            if valid(a) and a ~= R.held then
                local d = dist2d(a, me)
                local keep = false
                -- в руке / прикреплён к кому-то / не в покое — не трогаем
                pcall(function() if valid(a:GetAttachParentActor()) then keep = true end end)
                pcall(function() local st = num(a.State); if st and st ~= 0 then keep = true end end)
                if cn == "BP_T_Flashlight_C" and first and d < 2500 then
                    NM.startLights[a:GetAddress()] = true     -- фонарики у старта остаются
                end
                if NM.startLights[a:GetAddress()] then keep = true end
                if not first and d < 600 then keep = true end -- на глазах не исчезает
                -- уже удалённые игра ещё какое-то время отдаёт в поиске — не считаем их второй раз
                local addr = a:GetAddress()
                if NM.killed[addr] then keep = true end
                if not keep and pcall(function() a:K2_DestroyActor() end) then n = n + 1; NM.killed[addr] = true end
            end
        end
    end
    -- мусор: оставляем примерно каждый пятый
    for _, a in ipairs(FindAllOf("BP_TrashCube_C") or {}) do
        if valid(a) then
            local addr = a:GetAddress()
            if NM.trashSeen[addr] == nil then
                local keep = math.random() < TRASH_KEEP or (not first and dist2d(a, me) < 600)
                NM.trashSeen[addr] = keep
                if not keep and pcall(function() a:K2_DestroyActor() end) then n = n + 1 end
            end
        end
    end
    -- био-образцы (яблоки), разложенные по уровню: в Nightmare их нет — только из черепов.
    -- Чистим только в начале забега, пока работают спавнеры игры: потом яблоки
    -- появляются из разбитых "Сумм ничего", их трогать нельзя
    if (gameNow() or 0) < NM.applesUntil then
        for _, cn in ipairs({ "BP_PineCone_C", "BP_T_PackofPines_C" }) do
            for _, a in ipairs(FindAllOf(cn) or {}) do
                if valid(a) and a ~= R.held then
                    local addr = a:GetAddress()
                    if not NM.killed[addr] and pcall(function() a:K2_DestroyActor() end) then
                        NM.killed[addr] = true; n = n + 1; NM.applesGone = (NM.applesGone or 0) + 1
                    end
                end
            end
        end
    end
    return n
end

-- черепа: ровно SKULLS на уровне (лишние убрать, недостающие положить на места спавнеров)
local SKULLS = 20
local SKULL = "/Game/INTERACTION/BP_T_Skull.BP_T_Skull_C"
local function fixSkulls()
    local list = {}
    for _, a in ipairs(FindAllOf("BP_T_Skull_C") or {}) do
        if valid(a) and not NM.killed[a:GetAddress()] then list[#list + 1] = a end
    end
    local have = #list
    if have > SKULLS then
        -- лишние — случайные
        for i = #list, 2, -1 do local j = math.random(1, i); list[i], list[j] = list[j], list[i] end
        for i = SKULLS + 1, #list do
            local a = list[i]
            if pcall(function() a:K2_DestroyActor() end) then NM.killed[a:GetAddress()] = true end
        end
    elseif have < SKULLS then
        local cls, pawn = itemClass(SKULL), getPawn()
        if cls and pawn then
            for _, l in ipairs(itemSpots(SKULLS - have, 1500)) do
                pcall(function()
                    pawn:GetWorld():SpawnActor(cls, { X = l.X, Y = l.Y, Z = l.Z + 15 }, { Pitch = 0, Yaw = math.random(0, 359), Roll = 0 })
                end)
            end
        end
    end
    local now = 0
    for _, a in ipairs(FindAllOf("BP_T_Skull_C") or {}) do if valid(a) and not NM.killed[a:GetAddress()] then now = now + 1 end end
    log(string.format("Nightmare: skulls %d -> %d (target %d), level apples removed: %d", have, now, SKULLS, NM.applesGone or 0))
end

-- свет: всё выключить (фонарик в руке, свет Року и игрока не трогаем)
-- лампы почти гаснут и светят своим цветом (DARK_LAMP в darkness.lua)
local function lightsOff()
    log("Nightmare: " .. tostring(darkLamps(true, "nightmare")))
end
local function lightsOn()
    darkLamps(false, "nightmare")
end

-- слух: на шум (бег, двери, вентиляции) ближайшая Року идёт проверить сама,
-- потом осматривается и возвращается к своему мозгу
local function investigate(loc, radius, label)
    local best, bd = nil, math.huge
    for _, r in ipairs(allRokus()) do
        local d = math.huge
        pcall(function() local l = r:K2_GetActorLocation(); d = vlen(l.X - loc.X, l.Y - loc.Y, l.Z - loc.Z) end)
        if d < bd then best, bd = r, d end
    end
    if not best or bd > radius then return true end
    local addr = best:GetAddress()
    local g = gameNow() or 0
    local cur = NM.inv[addr]
    if cur and g - cur.t < 5 then return true end                 -- не дёргаем чаще раза в 5 с
    local chasing = false
    ctrlCall(best, function(c) chasing = c.Blackboard:GetValueAsBool(FName("bPlayerDetected")) == true end)
    if chasing then return true end                                -- и так гонится
    brainOff(best)
    local o = origSpeeds(best)
    pcall(function() best.CharacterMovement.MaxWalkSpeed = o.chase * 0.75 end)
    sendTo(best, loc)
    NM.inv[addr] = { dest = { X = loc.X, Y = loc.Y, Z = loc.Z }, t = g }
    log(string.format("Nightmare: Roku heard %s (%.0f cm away), going to check", label, bd))
    return true
end

local function invTick()
    local g = gameNow() or 0
    local live = {}
    for _, r in ipairs(allRokus()) do live[r:GetAddress()] = r end
    local done = {}
    for addr, e in pairs(NM.inv) do
        local r = live[addr]                       -- только живая Року (по адресу), не старая ссылка
        if not r then done[#done + 1] = addr
        elseif not e.looking then
            local l = r:K2_GetActorLocation()
            local arrived = vlen(l.X - e.dest.X, l.Y - e.dest.Y, 0) < 200
            if arrived or g - e.t > 12 or rokuSeesNM(r) then
                ctrlCall(r, function(c) c:StopMovement() end)
                if not rokuSeesNM(r) then playLookAround(r) end
                e.looking, e.until_ = true, g + (rokuSeesNM(r) and 0 or 4)
            end
        elseif g >= e.until_ then
            brainOn(r)
            done[#done + 1] = addr
        end
    end
    for _, a in ipairs(done) do NM.inv[a] = nil end     -- не меняем таблицу во время pairs
end

function rokuSeesNM(r)
    local a, b = false, false
    pcall(function() a = r.bPlayerInVisionBox == true end)
    pcall(function() b = r.bLineTraceHitPlayer == true end)
    return a and b
end

-- заметила: взгляд игрока на миг дёргает к ней
local function snapTo(r)
    local pc, pawn = getPC(), getPawn()
    if not pc or not pawn or not valid(r) then return end
    local me, rl = pawn:K2_GetActorLocation(), r:K2_GetActorLocation()
    local yaw = math.deg(math.atan(rl.Y - me.Y, rl.X - me.X))
    local d = vlen(rl.X - me.X, rl.Y - me.Y, 0)
    local pitch = math.deg(math.atan((rl.Z + 70) - (me.Z + 60), math.max(d, 1)))
    local cur = nil
    pcall(function() cur = pc:GetControlRotation() end)
    if not cur then return end
    local y0, p0 = num(cur.Yaw), num(cur.Pitch)
    if not y0 or not p0 then return end
    if p0 > 180 then p0 = p0 - 360 end
    local dy = ((yaw - y0 + 540) % 360) - 180
    pcall(function() pc:SetIgnoreLookInput(true) end)
    for i = 1, 6 do
        after(i * 30, function()
            local k = i / 6
            pcall(function() pc:SetControlRotation({ Pitch = p0 + (pitch - p0) * k, Yaw = y0 + dy * k, Roll = 0 }) end)
        end)
    end
    after(700, function()
        pcall(function() pc:SetIgnoreLookInput(false) end)
        pcall(function() pc:ResetIgnoreLookInput() end)
    end)
end

-- надпись режима, которая иногда глючит
local GLITCH = { "+ NIGHTMARE +", "+ N1GHTMARE +", "+ NIGHTM4RE +", "+ N GHTMA E +", "+ NIGH_MARE +", "+ ##GHTMARE +", "+ NIGHTMARE+ +" }
local function tagTick()
    local t = UI.nightTag
    if not valid(t) then return end
    local show = NM.on and R.phase == "running"
    t:SetVisibility(show and VIS_SHOW or VIS_HIDE)
    if not show then return end
    local now = os.clock()
    if now >= (NM.glitchUntil or 0) and now >= (NM.nextGlitch or 0) then
        NM.glitchUntil = now + 0.15 + math.random() * 0.35
        NM.nextGlitch = NM.glitchUntil + 2.5 + math.random() * 6
    end
    local glitch = now < (NM.glitchUntil or 0)
    if glitch then
        setText(t, GLITCH[math.random(2, #GLITCH)])
        setColor(t, math.random() < 0.5 and { R = 1, G = 0.15, B = 0.3, A = 0.4 + math.random() * 0.5 } or { R = 1, G = 1, B = 1, A = math.random() * 0.6 })
        pcall(function() UI.nightSlot:SetPosition({ X = -P.hudX + math.random(-8, 8), Y = P.hudY + math.random(-5, 5) }) end)
    else
        setText(t, GLITCH[1])
        setColor(t, { R = 1, G = 1, B = 1, A = 0.35 })
        pcall(function() UI.nightSlot:SetPosition({ X = -P.hudX, Y = P.hudY }) end)
    end
end

nightmareStart = function()
    if NM.on then return end
    NM.on, NM.trashSeen, NM.inv, NM.seen, NM.startLights, NM.killed = true, {}, {}, {}, {}, {}
    NM.dressed, NM.skins = {}, {}
    -- по шагам, с записью в лог: если что-то уронит игру, по логу будет видно что
    NM.applesUntil, NM.applesGone = (gameNow() or 0) + 15, 0
    log("Nightmare: step 1 items")
    local removed = sweepItems(true)
    log("Nightmare: removed " .. removed .. " items")
    NM.nextSweep = (gameNow() or 0) + 3
    after(12000, function() if NM.on then fixSkulls() end end)
    after(300, function()
        if not NM.on then return end
        log("Nightmare: step 2 hiding spots")
        setHiders(true)
        log("Nightmare: step 2 done")
    end)
    after(700, function()
        if not NM.on then return end
        log("Nightmare: step 3 lights")
        lightsOff()
        darkPreset(true, "nightmare")     -- небо, тени, виньетка (darkness.lua)
    end)
    NM.saved = { LAB.noiseSprint, LAB.noiseDoor, LAB.noiseVent, LAB.sprintRadius, LAB.doorRadius, LAB.ventRadius }
    LAB.noiseSprint, LAB.noiseDoor, LAB.noiseVent = true, true, true
    LAB.sprintRadius, LAB.doorRadius, LAB.ventRadius = 2600, 2200, 9000
    NOISE_HOOK = investigate
    local p = getPawn()
    if p then pcall(function() p.health = HP_MAX end) end
end

nightmareStop = function()
    if not NM.on then return end
    NM.on = false
    NOISE_HOOK = nil
    -- только живые Року (свежий поиск по адресу)
    for _, r in ipairs(allRokus()) do
        local addr = r:GetAddress()
        if NM.inv and NM.inv[addr] then brainOn(r) end
        local e = NM.skins and NM.skins[addr]
        if e and e.skin and e.skin ~= "None" then pcall(function() r:ApplyOutfit(FName(e.skin)) end) end
    end
    NM.inv = {}
    setHiders(false)
    lightsOn()
    darkPreset(false, "nightmare")
    NM.skins, NM.dressed = {}, {}           -- наряды вернули выше, в том же проходе по живым Року
    if NM.saved then
        LAB.noiseSprint, LAB.noiseDoor, LAB.noiseVent, LAB.sprintRadius, LAB.doorRadius, LAB.ventRadius = table.unpack(NM.saved)
        NM.saved = nil
    end
    log("Nightmare: stopped")
end

every(100, function()
    tagTick()
    if not NM.on or R.phase ~= "running" then return end
    local p = getPawn(); if not p then return end
    -- один удар: здоровье не выше порога (аптечек нет, а шлепок/лавка не должны спасать)
    pcall(function() if (num(p.health) or 0) > HP_MAX then p.health = HP_MAX end end)
    invTick()
    -- заметила (переход "не видит" -> "видит") — дёрнуть взгляд
    for _, r in ipairs(allRokus()) do
        local addr = r:GetAddress()
        -- в кошмаре Року всегда в наряде Dark (и та, что появится позже, тоже)
        if not NM.dressed[addr] then
            NM.dressed[addr] = true
            local was = nil
            pcall(function() was = r.CurrentSkin:ToString() end)
            NM.skins[addr] = { skin = was }
            local ok = pcall(function() r:ApplyOutfit(FName("Dark")) end)
            log("Nightmare: Roku outfit " .. tostring(was) .. " -> Dark (" .. tostring(ok) .. ")")
        end
        local sees = rokuSeesNM(r)
        if sees and not NM.seen[addr] then
            local g = gameNow() or 0
            if g - (NM.lastSnap or -100) > 6 then NM.lastSnap = g; snapTo(r) end
        end
        NM.seen[addr] = sees
    end
    local g = gameNow() or 0
    if g >= (NM.nextSweep or 0) then
        NM.nextSweep = g + 3
        setHiders(true)
        local n = sweepItems(false)
        if n > 0 then log("Nightmare: removed " .. n .. " more items") end
    end
end)
end)() -- NIGHTMARE

------------------------------------------------------------------------
