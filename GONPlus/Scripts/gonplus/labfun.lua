------------------------------------------------------------------------
-- ЛАБОРАТОРИЯ, новые вкладки: игрок, Року, чувства, предметы, мир.
-- Многое — из FunMenu (наш старый мод) и находки из RokuMenu (PerfectZero / mrdude2x,
-- код не копировали, см. claude/gon-rokumenu-notes.md).
-- Правила те же, что везде: объекты игры между тиками не храним (только адреса),
-- к мозгу Року — только через aiCtrl / ctrlCall. Всё, что влияет на игру, помечает
-- забег как лабораторный (R.cheated) — без рекорда.
------------------------------------------------------------------------
; (function()

local FUN = {
    on = {},            -- id переключателя -> true
    saved = {},         -- исходные значения игрока (гравитация, скорость полёта)
    spawned = {},       -- адреса заспавненного: { addr, cls }
    camAddr = nil, camMode = nil,
    spot = nil,         -- сохранённая точка
    orbitAng = 0, orbitHome = {},
    karmaLast = {}, karmaCool = {},
    stopMontage = {},   -- адреса Року, у которых надо прервать атаку (из хука)
    senses = {},        -- адрес Року -> исходные радиус слуха / размер зрения
    v = {               -- значения, которые меняются стрелками
        fly = 900, speed = 2.0, gravity = 0.2, mySize = 0.5,
        rokuBig = 1.5, rokuSpeed = 1.8, orbitR = 500,
        hear = 1.0, sight = 1.0,
        slowmo = 0.35, light = 6, push = 3000, clones = 8,
        spawnIdx = 1, spawnCount = 1, animIdx = 1, holdIdx = 1,
    },
}
onForgetRefs(function()
    -- новый забег: всё, что держалось на старых объектах, выключено
    FUN.on, FUN.saved, FUN.spawned = {}, {}, {}
    FUN.camAddr, FUN.camMode, FUN.spot = nil, nil, nil
    FUN.orbitHome, FUN.karmaLast, FUN.karmaCool, FUN.stopMontage, FUN.senses = {}, {}, {}, {}, {}
end)

local function status(s) UI.labStatus = s end
local function cheat() R.cheated = true end
local function v3(x, y, z) return { X = x, Y = y, Z = z } end
local function ksl() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end

-- ближайшая к игроку Року
local function nearestRoku()
    local p = getPawn(); if not p then return nil end
    local me = p:K2_GetActorLocation()
    local best, bd = nil, math.huge
    for _, r in ipairs(allRokus()) do
        local l = r:K2_GetActorLocation()
        local d = vlen(l.X - me.X, l.Y - me.Y, l.Z - me.Z)
        if d < bd then best, bd = r, d end
    end
    return best
end

-- взгляд камеры игрока
local function cameraView()
    local pc = getPC(); if not pc then return nil end
    local cam = pc.PlayerCameraManager
    local s = cam:GetCameraLocation()
    local rot = cam:GetCameraRotation()
    local p, y = math.rad(rot.Pitch), math.rad(rot.Yaw)
    return v3(s.X, s.Y, s.Z), v3(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p))
end

-- луч из камеры: точка, нормаль, результат, направление
local function trace(reach)
    local pawn = getPawn(); local start, dir = cameraView()
    if not pawn or not start then return nil end
    local finish = v3(start.X + dir.X * reach, start.Y + dir.Y * reach, start.Z + dir.Z * reach)
    local hit = {}
    local ok = false
    pcall(function()
        ok = ksl():LineTraceSingle(pawn, start, finish, 0, false, {}, 0, hit, true,
            { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
    end)
    if not ok then return nil end
    return hit.ImpactPoint, hit.ImpactNormal, hit, dir
end
local function hitComp(hit)
    local c = nil
    pcall(function() c = hit.Component; if c and c.Get then c = c:Get() end end)
    return valid(c) and c or nil
end

-- точка перед игроком (не дальше стены)
local function spotInFront(dist)
    local start, dir = cameraView(); if not start then return nil end
    local pt = trace(dist)
    if pt then return v3(pt.X - dir.X * 40, pt.Y - dir.Y * 40, pt.Z - dir.Z * 40 + 20) end
    return v3(start.X + dir.X * dist, start.Y + dir.Y * dist, start.Z + dir.Z * dist)
end

local function spawnAt(path, loc, physics)
    local cls = StaticFindObject(path)
    if not valid(cls) then return nil, "not loaded on this level" end
    local p = getPawn(); if not p then return nil, "no player" end
    local a = nil
    pcall(function() a = p:GetWorld():SpawnActor(cls, loc, { Pitch = 0, Yaw = math.random(0, 359), Roll = 0 }) end)
    if not valid(a) then return nil, "spawn failed" end
    if physics then pcall(function() a:K2_GetRootComponent():SetSimulatePhysics(true) end) end
    local cname = ""
    pcall(function() cname = a:GetClass():GetFName():ToString() end)
    FUN.spawned[#FUN.spawned + 1] = { addr = a:GetAddress(), cls = cname }
    return a
end

-- живой объект по адресу (ищем среди объектов его класса)
local function actorAt(addr, cls)
    if not addr then return nil end
    for _, a in ipairs(FindAllOf(cls) or {}) do
        if valid(a) and a:GetAddress() == addr then return a end
    end
    return nil
end

------------------------------------------------------------------------
-- Каждый тик (20 мс): полёт, орбита, камера её глазами, карма, атаки
------------------------------------------------------------------------
local function keyDown(pc, name)
    local ok, res = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(name) }) end)
    return ok and res == true
end

local function ghostTick()
    local p, pc = getPawn(), getPC(); if not p or not pc then return end
    local m = p.CharacterMovement
    if m.MovementMode ~= 5 then m:SetMovementMode(5, 0) end
    local rot = pc:GetControlRotation()
    local pitch = rot.Pitch; if pitch > 180 then pitch = pitch - 360 end
    if math.abs(pitch) < 5 then pitch = 0 end
    local yaw = math.rad(rot.Yaw)
    local fx, fy = math.cos(yaw), math.sin(yaw)
    local rx, ry = -fy, fx
    local input = p:GetLastMovementInputVector()
    local fwd = input.X * fx + input.Y * fy
    local side = input.X * rx + input.Y * ry
    local cp, sp = math.cos(math.rad(pitch)), math.sin(math.rad(pitch))
    if keyDown(pc, "LeftAlt") then cp, sp = 1, 0 end
    local s = FUN.v.fly
    local vz = fwd * sp * s
    if keyDown(pc, "SpaceBar") then vz = 500 elseif keyDown(pc, "C") then vz = -500 end
    m.Velocity = v3((fwd * fx * cp + side * rx) * s, (fwd * fy * cp + side * ry) * s, vz)
end

local function orbitTick()
    local p = getPawn(); local r = nearestRoku()
    if not p or not r then return end
    FUN.orbitAng = FUN.orbitAng + 0.04
    local c = p:K2_GetActorLocation()
    local rl = r:K2_GetActorLocation()
    local x = c.X + math.cos(FUN.orbitAng) * FUN.v.orbitR
    local y = c.Y + math.sin(FUN.orbitAng) * FUN.v.orbitR
    -- не в стену: до первой преграды и чуть назад
    local hit = {}
    local blocked = false
    pcall(function()
        blocked = ksl():LineTraceSingle(p, v3(c.X, c.Y, rl.Z), v3(x, y, rl.Z), 0, false, {}, 0, hit, true,
            { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
    end)
    if blocked and hit.ImpactPoint then
        local dx, dy = x - c.X, y - c.Y
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        x, y = hit.ImpactPoint.X - dx / len * 70, hit.ImpactPoint.Y - dy / len * 70
    end
    pcall(function() r:K2_SetActorLocation(v3(x, y, rl.Z), false, {}, true) end)
    local face = math.deg(math.atan(c.Y - y, c.X - x))
    pcall(function() r:K2_SetActorRotation({ Pitch = 0, Yaw = face, Roll = 0 }, true) end)
end

local function eyesTick()
    local r = nearestRoku()
    local cam = actorAt(FUN.camAddr, "CameraActor")
    if not r or not cam then return end
    local rot = r:K2_GetActorRotation()
    local yaw = math.rad(rot.Yaw)
    local loc = nil
    local mesh = r.Mesh
    local sock = valid(mesh) and findHead(mesh)
    if sock then pcall(function() loc = mesh:GetSocketLocation(FName(sock)) end) end
    if not loc then local a = r:K2_GetActorLocation(); loc = v3(a.X, a.Y, a.Z + 75) end
    local x, y = loc.X + math.cos(yaw) * 18, loc.Y + math.sin(yaw) * 18
    pcall(function() cam:K2_SetActorLocationAndRotation(v3(x, y, loc.Z), { Pitch = 0, Yaw = rot.Yaw, Roll = 0 }, false, {}, true) end)
end

-- карма: заметила тебя -> падает (опрос, а не хук: хук на SetPlayerDetected ломался под нагрузкой)
local function karmaTick()
    local now = gameNow() or 0
    for _, r in ipairs(allRokus()) do
        if rokuSettled(r) then
            local addr = r:GetAddress()
            local det = false
            ctrlCall(r, function(c) det = c.Blackboard:GetValueAsBool(FName("bPlayerDetected")) == true end)
            if det and not FUN.karmaLast[addr] and now >= (FUN.karmaCool[addr] or 0) then
                FUN.karmaCool[addr] = now + 4
                pcall(function() r:fallover() end)
                log("Lab: karma - Roku tripped")
            end
            FUN.karmaLast[addr] = det
        end
    end
end

-- "не бьёт". Одного AttackBox мало (проверено в игре: била как обычно), поэтому:
--   1) выключаем все удар- и захват-объёмы (AttackBox, crushbox, GH_* — руки, ноги, голова, грудь, таз);
--   2) здоровье держим полным (если урон всё-таки прошёл другим путём);
--   3) атаки, которые поймал хук PlayAnimMontage, прерываем.
local HIT_PARTS = { "AttackBox", "crushbox", "GH_pelvis", "GH_chest", "GH_Head", "GH_leftarm", "GH_legL", "GH_legR", "GH_rightarm" }
FUN.parts = {}      -- адрес Року -> { часть -> родное SetCollisionEnabled }
onForgetRefs(function() FUN.parts = {} end)
local function harmlessParts(r, off)
    local addr = r:GetAddress()
    FUN.parts[addr] = FUN.parts[addr] or {}
    local saved = FUN.parts[addr]
    for _, n in ipairs(HIT_PARTS) do
        pcall(function()
            local c = r[n]
            if not valid(c) then return end
            if off then
                if saved[n] == nil then saved[n] = num(c:GetCollisionEnabled()) or 1 end
                c:SetCollisionEnabled(0)
                pcall(function() c:SetGenerateOverlapEvents(false) end)
            elseif saved[n] ~= nil then
                c:SetCollisionEnabled(saved[n])
                pcall(function() c:SetGenerateOverlapEvents(true) end)
            end
        end)
    end
    if not off then FUN.parts[addr] = nil end
end
local function harmlessTick()
    for _, r in ipairs(allRokus()) do harmlessParts(r, true) end
    local p = getPawn()
    if p then pcall(function() if (num(p.health) or 1) < 1 then p.health = 1.0 end end) end
    for addr in pairs(FUN.stopMontage) do
        local r = rokuAt(addr)
        if r then pcall(function() r:StopAnimMontage(nil) end) end
    end
    FUN.stopMontage = {}
end

local ATTACK_WORDS = { "atk", "attack", "swipe", "kick", "stab", "slash", "strikedown", "stomp" }
local hookTried = false
local function ensureAttackHook()
    if hookTried then return end
    hookTried = true
    -- внутри хука: только читаем имена и ставим флажок; Року трогаем потом, в тике
    local ok, err = pcall(function()
        RegisterHook("/Script/Engine.Character:PlayAnimMontage", function(ctx, montage, rate)
            if not FUN.on.harmless then return end
            pcall(function()
                local ch = ctx:get()
                if not ch:GetFullName():find("Rokuv3", 1, true) then return end
                local n = montage:get():GetFName():ToString():lower()
                for _, w in ipairs(ATTACK_WORDS) do
                    if n:find(w, 1, true) then
                        rate:set(0.0)
                        FUN.stopMontage[ch:GetAddress()] = true
                        return
                    end
                end
            end)
        end)
    end)
    log("Lab: attack animation hook " .. (ok and "ready" or ("failed: " .. tostring(err))))
end

every(20, function()
    if not next(FUN.on) or not getPawn() then return end
    if FUN.on.ghost then safe(ghostTick) end
    if FUN.on.orbit then safe(orbitTick) end
    if FUN.camMode == "eyes" then safe(eyesTick) end
end)
every(100, function()
    if not next(FUN.on) or not getPawn() then return end
    if FUN.on.karma then safe(karmaTick) end
    if FUN.on.harmless then safe(harmlessTick) end
    if FUN.on.maskInf then local p = getPawn(); pcall(function() if p.MaskLength < 99999 then p.MaskLength = 100000 end end) end
end)
-- новые Року (Twins, Pure Stealth) тоже получают "размер / скорость / чувства"
every(1000, function()
    if not next(FUN.on) or not getPawn() then return end
    for _, r in ipairs(allRokus()) do
        if rokuSettled(r) then
            if FUN.on.rokuBig then pcall(function() r:SetActorScale3D(v3(FUN.v.rokuBig, FUN.v.rokuBig, FUN.v.rokuBig)) end) end
            if FUN.on.rokuTiny then pcall(function() r:SetActorScale3D(v3(0.35, 0.35, 0.35)) end) end
            if FUN.on.hear or FUN.on.sight then applySenses(r) end
        end
    end
end)

------------------------------------------------------------------------
-- Чувства Року: слух — сфера HearingSphere, зрение — коробка VisionBox (в длину ~13 м)
------------------------------------------------------------------------
function applySenses(r)
    local addr = r:GetAddress()
    local s = FUN.senses[addr]
    if not s then
        s = {}
        pcall(function() s.hear = r.HearingSphere:GetUnscaledSphereRadius() end)
        pcall(function() local e = r.VisionBox:GetUnscaledBoxExtent(); s.box = v3(e.X, e.Y, e.Z) end)
        FUN.senses[addr] = s
    end
    local hk = FUN.on.hear and FUN.v.hear or 1
    local sk = FUN.on.sight and FUN.v.sight or 1
    if s.hear then pcall(function() r.HearingSphere:SetSphereRadius(math.max(1, s.hear * hk), true) end) end
    if s.box then pcall(function() r.VisionBox:SetBoxExtent(v3(s.box.X, math.max(1, s.box.Y * sk), s.box.Z), true) end) end
end
local function sensesAll() for _, r in ipairs(allRokus()) do applySenses(r) end end

------------------------------------------------------------------------
-- Времени Року: заморозка / быстрее / меньше
------------------------------------------------------------------------
local function rokuTime()
    for _, r in ipairs(allRokus()) do
        local t = 1.0
        if FUN.on.freeze then t = 0
        else
            if FUN.on.rokuTiny then t = t * 0.6 end
            if FUN.on.rokuFast then t = t * FUN.v.rokuSpeed end
        end
        pcall(function() r.CustomTimeDilation = t end)
    end
end

------------------------------------------------------------------------
-- Камера Року
------------------------------------------------------------------------
local function parkPlayer(on)
    local p = getPawn(); if not p then return end
    local m = p.CharacterMovement
    if on then
        pcall(function() p:SetActorEnableCollision(false) end)
        if not FUN.on.ghost then pcall(function() m:SetMovementMode(0, 0) end) end
        pcall(function() m.Velocity = v3(0, 0, 0) end)
    elseif not FUN.on.ghost then
        pcall(function() p:SetActorEnableCollision(true) end)
        pcall(function() m:SetMovementMode(1, 0) end)
    end
end
local function camStop()
    local p, pc = getPawn(), getPC()
    if pc and p then pcall(function() pc:SetViewTargetWithBlend(p, 0.4, 0, 0, false) end) end
    local cam = actorAt(FUN.camAddr, "CameraActor")
    if cam then pcall(function() cam:K2_DestroyActor() end) end
    if FUN.camMode then parkPlayer(false) end
    FUN.camAddr, FUN.camMode = nil, nil
    FUN.on.camEyes, FUN.on.camBehind = nil, nil
    return "Back to your eyes"
end
local function camStart(mode)
    local p, pc, r = getPawn(), getPC(), nearestRoku()
    if not p or not r then return "Roku not found" end
    local was = FUN.camMode
    if was then
        local cam = actorAt(FUN.camAddr, "CameraActor")
        if cam then pcall(function() cam:K2_DestroyActor() end) end
    end
    local cls = StaticFindObject("/Script/Engine.CameraActor")
    local cam = nil
    pcall(function() cam = p:GetWorld():SpawnActor(cls, r:K2_GetActorLocation(), { Pitch = 0, Yaw = 0, Roll = 0 }) end)
    if not valid(cam) then return "Camera spawn failed" end
    pcall(function() cam.CameraComponent.bConstrainAspectRatio = false end)
    pcall(function() cam.CameraComponent:SetFieldOfView(95) end)
    if mode == "behind" then
        pcall(function()
            cam:K2_AttachToActor(r, FName("None"), 2, 2, 1, false)
            cam:K2_SetActorRelativeLocation(v3(-280, 0, 130), false, {}, true)
            cam:K2_SetActorRelativeRotation({ Pitch = -15, Yaw = 0, Roll = 0 }, false, {}, true)
        end)
    end
    FUN.camAddr, FUN.camMode = cam:GetAddress(), mode
    if mode == "eyes" then eyesTick() end
    pcall(function() pc:SetViewTargetWithBlend(cam, 0.4, 0, 0, false) end)
    if not was then parkPlayer(true) end
    FUN.on.camEyes, FUN.on.camBehind = mode == "eyes" or nil, mode == "behind" or nil
    return mode == "eyes" and "Her eyes" or "Following Roku"
end

------------------------------------------------------------------------
-- Списки: предметы, анимации, "в руках у Року"
------------------------------------------------------------------------
local SPAWN = {
    { "Medikit", "/Game/INTERACTION/BP_Medikit.BP_Medikit_C" },
    { "Roku mask", "/Game/INTERACTION/BP_RokuMask.BP_RokuMask_C" },
    { "Flashlight", "/Game/INTERACTION/BP_T_Flashlight.BP_T_Flashlight_C" },
    { "Glow stick", "/Game/INTERACTION/BP_T_Gstick.BP_T_Gstick_C" },
    { "Apple", "/Game/INTERACTION/BP_T_Apple.BP_T_Apple_C" },
    { "Carrot", "/Game/INTERACTION/BP_T_Carrot.BP_T_Carrot_C" },
    { "Coffee", "/Game/INTERACTION/BP_coffee.BP_coffee_C" },
    { "Beer can", "/Game/INTERACTION/BP_T_Beercan.BP_T_Beercan_C" },
    { "Beer 4-pack", "/Game/INTERACTION/4pack_of_beer.4pack_of_beer_C" },
    { "Wine bottle", "/Game/INTERACTION/BP_T_WineBottle.BP_T_WineBottle_C" },
    { "Pine cone", "/Game/INTERACTION/BP_PineCone.BP_PineCone_C" },
    { "Cowbell", "/Game/INTERACTION/BP_T_cowbell.BP_T_cowbell_C" },
    { "Test tubes", "/Game/INTERACTION/BP_T_TestTubes.BP_T_TestTubes_C" },
    { "Skull", "/Game/INTERACTION/BP_T_Skull.BP_T_Skull_C" },
    { "Trash cube", "/Game/INTERACTION/BP_TrashCube.BP_TrashCube_C" },
}
local A = "/Game/ROKUv3/"
local ANIMS = {
    { "Fall over (drunk)", A .. "Roku_Interaction/roku_drunk_anims/roku_fallover_Montage.roku_fallover_Montage" },
    { "Fall over (stagger)", A .. "Roku_Interaction/roku_drunk_anims/roku_fallover_stagger_Montage.roku_fallover_stagger_Montage" },
    { "Bump", A .. "Roku_Interaction/generic_bump_Montage.generic_bump_Montage" },
    { "Hit: pine to face", A .. "Roku_Interaction/MHIT_pine_face_Montage.MHIT_pine_face_Montage" },
    { "Hit: apple to face", A .. "Roku_Interaction/MHIT_apple_facefbx_Montage.MHIT_apple_facefbx_Montage" },
    { "Hit: carrot to face", A .. "Roku_Interaction/MHIT_carrot_face_Montage.MHIT_carrot_face_Montage" },
    { "Hit: cowbell to face", A .. "Roku_Interaction/MHIT_cowbell_face2_Montage.MHIT_cowbell_face2_Montage" },
    { "Hit: wine bottle", A .. "Roku_Interaction/MHIT_wine_Montage.MHIT_wine_Montage" },
    { "Hit: beer", A .. "Roku_Interaction/mhit_beer_Montage.mhit_beer_Montage" },
    { "Spanked", A .. "Roku_Interaction/roku_drunk_anims/ass_spank_Montage.ass_spank_Montage" },
    { "Skull: catch", A .. "Roku_Interaction/skullball/aa_skullcatch_init_Montage.aa_skullcatch_init_Montage" },
    { "Heart hands", A .. "anims/cuteanims/cute_hearthands2_Montage.cute_hearthands2_Montage" },
    { "Notice!", A .. "anims/aggro/NOTICE_Montage.NOTICE_Montage" },
    { "Look around", A .. "anims/lookarounds/lookaround1_Montage.lookaround1_Montage" },
    { "Look around: angry", A .. "anims/lookarounds/n_LOOKAROUND_ANGRY_Montage.n_LOOKAROUND_ANGRY_Montage" },
    { "Look around: finger bite", A .. "anims/lookarounds/lookaround_fingerbite2_Montage.lookaround_fingerbite2_Montage" },
    { "Look around: lick", A .. "anims/lookarounds/n_LA_lick1_Montage.n_LA_lick1_Montage" },
    { "Investigate", A .. "anims/investigations/r_investigate1_Montage.r_investigate1_Montage" },
    { "Attack: slash", A .. "anims/aggro/N_ATK_SLASH_Montage.N_ATK_SLASH_Montage" },
    { "Attack: heart", A .. "anims/aggro/aggro_v2/ATK_HEART_Montage.ATK_HEART_Montage" },
    { "Attack: stomp", A .. "anims/aggro/aggro_v2/ATK_STOMP_Montage.ATK_STOMP_Montage" },
}
-- реквизит Року для анимаций попадания: брошенное яблоко исчезает при касании, а у неё
-- во рту/в руке появляется закреплённая копия, чтобы реакция MHIT_* выглядела правильно.
-- Это не "предмет в руках" — просто показать реквизит (для исследований).
local HOLD = { { "Apple", "AppleVis" }, { "Carrot", "carrotVIS" }, { "Glow stick", "GStickVis" } }

------------------------------------------------------------------------
-- Строки вкладок
------------------------------------------------------------------------
local function onoff(v) return v and "[ON]" or "[off]" end
local function fmt(f, x) return string.format(f, x) end

-- переключатель; val = { key, step, min, max, fmt } — меняется стрелками/краями кнопки
local function toggle(id, label, desc, on, off, val, isCheat)
    local it = { desc = desc }
    local valTxt = val and ("  " .. fmt(val[5], FUN.v[val[1]])) or ""
    it.label = label .. "    " .. onoff(FUN.on[id]) .. valTxt
    if val and val.oneshot then
        -- действие со значением (сила толчка, сколько копий): без [ON]/[off]
        it.label = label .. "    <  " .. fmt(val[5], FUN.v[val[1]]) .. "  >"
        it.act = function()
            if isCheat ~= false then cheat() end
            local ok, res = pcall(on); status(ok and (res or "Done") or ("Error: " .. tostring(res)))
        end
    else it.act = function()
        if FUN.on[id] then
            FUN.on[id] = nil
            local ok, res = pcall(off); status(ok and (res or (label .. " off")) or ("Error: " .. tostring(res)))
        else
            FUN.on[id] = true
            if isCheat ~= false then cheat() end
            local ok, res = pcall(on)
            if not ok then FUN.on[id] = nil end
            status(ok and (res or (label .. " on")) or ("Error: " .. tostring(res)))
        end
    end end
    if val then
        it.cycle = function(dir)
            local k = val[1]
            local x = FUN.v[k] + dir * val[2]
            x = math.floor(x / val[2] + 0.5) * val[2]
            FUN.v[k] = math.max(val[3], math.min(val[4], x))
            if FUN.on[id] and val.update then pcall(val.update) end
            status(label .. ": " .. fmt(val[5], FUN.v[k]))
        end
    end
    return it
end
-- действие; list = { key, names } — выбор стрелками
local function action(label, desc, fn, list, isCheat)
    local it = { desc = desc }
    it.label = label .. (list and ("    <  " .. list[2][FUN.v[list[1]]] .. "  >") or "")
    it.act = function()
        if isCheat ~= false then cheat() end
        local ok, res = pcall(fn); status(ok and (res or "Done") or ("Error: " .. tostring(res)))
    end
    if list then
        it.cycle = function(dir)
            local k, n = list[1], #list[2]
            FUN.v[k] = (FUN.v[k] - 1 + dir) % n + 1
        end
    end
    return it
end
local function names(t) local o = {} for i, e in ipairs(t) do o[i] = e[1] end return o end
local SPAWN_N, ANIM_N, HOLD_N = names(SPAWN), names(ANIMS), names(HOLD)

local function rokusDo(fn, msg)
    local n = 0
    for _, r in ipairs(allRokus()) do if pcall(fn, r) then n = n + 1 end end
    if n == 0 then return "Roku not found" end
    return msg .. (n > 1 and (" (" .. n .. " Rokus)") or "")
end
local function brainAll(on)
    for _, r in ipairs(allRokus()) do if on then brainOn(r) else brainOff(r) end end
end

LAB_EXTRA_TABS = {
    { id = "player", name = "Player", items = function() return {
        toggle("ghost", "Ghost (fly through walls)", "W + look to fly. Hold Space / C - up / down, hold Alt - same height. Arrows - speed.",
            function()
                local p = getPawn(); local m = p.CharacterMovement
                pcall(function() p:SetActorEnableCollision(false) end)
                m:SetMovementMode(5, 0)
                pcall(function() m.BrakingDecelerationFlying = 4000 end)
                FUN.saved.fly = FUN.saved.fly or m.MaxFlySpeed
                m.MaxFlySpeed = 3000
                return "Ghost on"
            end,
            function()
                local p = getPawn(); if not p then return end
                pcall(function() p:SetActorEnableCollision(true) end)
                pcall(function() p.CharacterMovement:SetMovementMode(1, 0) end)
                if FUN.saved.fly then pcall(function() p.CharacterMovement.MaxFlySpeed = FUN.saved.fly end) end
                return "Walking"
            end, { "fly", 100, 300, 3000, "speed %d" }),
        toggle("maskInf", "Roku mask, no time limit", "The game's own mask, but it never runs out.",
            function() local p = getPawn(); FUN.saved.maskLen = FUN.saved.maskLen or p.MaskLength; p.MaskLength = 100000; p:MaskOn() end,
            function()
                local p = getPawn(); if not p then return end
                pcall(function() p:MaskOff() end)
                if FUN.saved.maskLen then pcall(function() p.MaskLength = FUN.saved.maskLen end) end
                pcall(function() p.IsMaskOn = false end)
            end),
        action("Heal me", "The game's own healing.", function() getPawn():HealUp(); return "Healed" end),
        toggle("speed", "Super speed", "You live faster than the world.",
            function() getPawn().CustomTimeDilation = FUN.v.speed end,
            function() local p = getPawn(); if p then p.CustomTimeDilation = 1 end end,
            { "speed", 0.25, 1.25, 4.0, "x%.2f", update = function() getPawn().CustomTimeDilation = FUN.v.speed end }),
        toggle("gravity", "Moon gravity", "Falling becomes slow and floaty.",
            function() local m = getPawn().CharacterMovement; FUN.saved.grav = FUN.saved.grav or m.GravityScale; m.GravityScale = FUN.v.gravity end,
            function() local p = getPawn(); if p and FUN.saved.grav then p.CharacterMovement.GravityScale = FUN.saved.grav end end,
            { "gravity", 0.05, 0.05, 0.8, "%.2f g", update = function() getPawn().CharacterMovement.GravityScale = FUN.v.gravity end }),
        toggle("mySize", "My size", "Shrink or grow yourself.",
            function() local s = FUN.v.mySize; getPawn():SetActorScale3D(v3(s, s, s)) end,
            function() local p = getPawn(); if p then p:SetActorScale3D(v3(1, 1, 1)) end end,
            { "mySize", 0.1, 0.2, 2.0, "x%.1f", update = function() local s = FUN.v.mySize; getPawn():SetActorScale3D(v3(s, s, s)) end }),
        action("Teleport where I look", "Jump to the point under your crosshair.", function()
            local pt, n, _, dir = trace(5000)
            if not pt then return "Too far" end
            getPawn():K2_SetActorLocation(v3(pt.X + n.X * 60 - dir.X * 30, pt.Y + n.Y * 60 - dir.Y * 30,
                pt.Z + math.max(n.Z, 0) * 95 + 10), false, {}, true)
            return "Blink!"
        end),
        action("Save this spot", "Remember where you stand.", function()
            local l = getPawn():K2_GetActorLocation(); FUN.spot = v3(l.X, l.Y, l.Z); return "Spot saved"
        end, nil, false),
        action("Scan input  -> input_scan.txt", "For Bashful: finds mouse sensitivity / look rate settings on the controller, the player and the game settings.", function()
            local out = {}
            local function dumpObj(title, obj)
                out[#out + 1] = "== " .. title .. ": " .. (valid(obj) and obj:GetFullName() or "not found")
                if not valid(obj) then return end
                local cls = nil; pcall(function() cls = obj:GetClass() end)
                local guard = 0
                while cls and valid(cls) and guard < 10 do
                    local cname = "?"; pcall(function() cname = cls:GetFName():ToString() end)
                    pcall(function()
                        cls:ForEachProperty(function(pr)
                            local n = pr:GetFName():ToString()
                            local l = n:lower()
                            for _, w in ipairs({ "sens", "scale", "mouse", "look", "turn", "input", "rate", "invert", "aim" }) do
                                if l:find(w, 1, true) then
                                    local v = "?"; pcall(function() v = tostring(obj[n]) end)
                                    out[#out + 1] = "  [" .. cname .. "] " .. n .. " = " .. v
                                    break
                                end
                            end
                        end)
                    end)
                    local ok, sup = pcall(function() return cls:GetSuperStruct() end)
                    cls = ok and sup or nil
                    guard = guard + 1
                end
            end
            dumpObj("PlayerController", getPC())
            dumpObj("Player", getPawn())
            local gus = nil; pcall(function() gus = FindFirstOf("GameUserSettings") end)
            dumpObj("GameUserSettings", gus)
            for _, cls in ipairs({ "EnhancedInputLocalPlayerSubsystem", "EnhancedPlayerInput", "PlayerInput" }) do
                local o = nil; pcall(function() o = FindFirstOf(cls) end)
                dumpObj(cls, o)
            end
            local path = ROOT .. "\\input_scan.txt"
            local fh = io.open(path, "w"); if not fh then return "Could not write input_scan.txt" end
            fh:write(table.concat(out, "\n")); fh:close()
            return "Saved input_scan.txt (" .. #out .. " lines)"
        end, nil, false),
        action("Return to saved spot", "Teleport back to the saved spot.", function()
            if not FUN.spot then return "No spot saved yet" end
            getPawn():K2_SetActorLocation(FUN.spot, false, {}, true); return "Back again"
        end),
    } end },

    { id = "rokufun", name = "Roku", items = function() return {
        toggle("freeze", "Freeze Rokus", "They stop dead (time stops for them, brain off).",
            function() rokuTime(); brainAll(false); return "Frozen" end,
            function()
                rokusDo(function(r) r:StopAnimMontage(nil) end, "")
                rokuTime(); if not FUN.on.sleep and not FUN.on.orbit then brainAll(true) end
                return "Unfrozen"
            end),
        action("Pull Roku to me", "The nearest Roku appears right in front of you.", function()
            local p, r = getPawn(), nearestRoku(); if not r then return "Roku not found" end
            local loc, f, rl = p:K2_GetActorLocation(), p:GetActorForwardVector(), r:K2_GetActorLocation()
            local x, y = loc.X + f.X * 250, loc.Y + f.Y * 250
            r:K2_SetActorLocation(v3(x, y, math.max(rl.Z, loc.Z)), false, {}, true)
            r:K2_SetActorRotation({ Pitch = 0, Yaw = math.deg(math.atan(loc.Y - y, loc.X - x)), Roll = 0 }, true)
            return "Hello, Roku"
        end),
        toggle("sleep", "AI asleep", "Their brains are off: they stand still, animations still play.",
            function() brainAll(false); rokusDo(function(r) ctrlCall(r, function(c) c:StopMovement() end) end, ""); return "Asleep" end,
            function() if not FUN.on.freeze and not FUN.on.orbit then brainAll(true) end; return "Awake" end),
        toggle("camEyes", "Camera: her eyes", "See through the nearest Roku's eyes. You stay safe and still.",
            function() return camStart("eyes") end, function() return camStop() end, nil, false),
        toggle("camBehind", "Camera: behind her", "Follow the nearest Roku like a third-person camera.",
            function() return camStart("behind") end, function() return camStop() end, nil, false),
        toggle("rokuBig", "Big Rokus", "Too big and they get stuck.",
            function() FUN.on.rokuTiny = nil; rokuTime(); local s = FUN.v.rokuBig; return rokusDo(function(r) r:SetActorScale3D(v3(s, s, s)) end, "Big") end,
            function() return rokusDo(function(r) r:SetActorScale3D(v3(1, 1, 1)) end, "Normal size") end,
            { "rokuBig", 0.1, 1.1, 3.0, "x%.1f", update = function() local s = FUN.v.rokuBig; rokusDo(function(r) r:SetActorScale3D(v3(s, s, s)) end, "") end }),
        toggle("rokuTiny", "Tiny Rokus", "Small and a bit slow.",
            function() FUN.on.rokuBig = nil; rokuTime(); return rokusDo(function(r) r:SetActorScale3D(v3(0.35, 0.35, 0.35)) end, "Tiny") end,
            function() rokuTime(); return rokusDo(function(r) r:SetActorScale3D(v3(1, 1, 1)) end, "Normal size") end),
        toggle("rokuFast", "Hyper Rokus", "They live faster than the world. Good luck.",
            function() rokuTime(); return "Hyper" end, function() rokuTime(); return "Normal speed" end,
            { "rokuSpeed", 0.2, 1.2, 4.0, "x%.1f", update = rokuTime }),
        toggle("rokuHidden", "Invisible Rokus", "You can't see them. They can still see you.",
            function() return rokusDo(function(r) r:SetActorHiddenInGame(true) end, "Where are they?..") end,
            function() return rokusDo(function(r) r:SetActorHiddenInGame(false) end, "Visible") end),
        toggle("orbit", "Roku orbit", "The nearest Roku circles around you and can't come closer.",
            function()
                local r = nearestRoku(); if not r then error("Roku not found") end
                local h = r:K2_GetActorLocation(); FUN.orbitHome = { addr = r:GetAddress(), loc = v3(h.X, h.Y, h.Z) }
                brainOff(r); return "Round and round"
            end,
            function()
                local r = FUN.orbitHome.addr and rokuAt(FUN.orbitHome.addr)
                if r then
                    pcall(function() r:K2_SetActorLocation(FUN.orbitHome.loc, false, {}, true) end)
                    local addr = r:GetAddress()
                    after(500, function()
                        local rr = rokuAt(addr)
                        if rr and not FUN.on.freeze and not FUN.on.sleep and not FUN.on.orbit then brainOn(rr) end
                    end)
                end
                FUN.orbitHome = {}
                return "Orbit stopped"
            end, { "orbitR", 100, 200, 1500, "radius %d" }),
        action("Animation", "< > choose, middle / Enter - the nearest Roku plays it. Attacks can hurt up close!", function()
            local r = nearestRoku(); if not r then return "Roku not found" end
            local e = ANIMS[FUN.v.animIdx]
            local m = StaticFindObject(e[2])
            if not valid(m) then return e[1] .. ": not loaded on this level" end
            r:PlayAnimMontage(m, 1.0, FName("None"))
            return "Roku: " .. e[1]
        end, { "animIdx", ANIM_N }, false),
        action("Fall over", "The game's own drunk fall.", function() return rokusDo(function(r) r:fallover() end, "Timber!") end, nil, false),
        action("Turn to me", "She turns to look at you. Careful.", function() return rokusDo(function(r) r:Turn2Player() end, "She's looking...") end, nil, false),
        toggle("drunk", "Drunk (game's own)", "The game's drunk mode, normally from beer.",
            function() return rokusDo(function(r) r:DrunkMode() end, "Drunk") end,
            function() return rokusDo(function(r) r:DrunkClear() end, "Sober") end),
        toggle("late", "Late-game speed", "The speed she normally gets near the end of the game.",
            function() return rokusDo(function(r) r:LATEGAMESPEED() end, "Late-game Rokus") end,
            function() return rokusDo(function(r) r:NormalSpeed() end, "Normal speed") end),
        toggle("cowbell", "Cowbell", "The game's cowbell event (the bell on Roku).",
            function() return rokusDo(function(r) r:cb_event() end, "Ding!") end,
            function() return rokusDo(function(r) r:cb_off() end, "Bell off") end, nil, false),
        action("Show hit prop", "< > choose: shows the prop the game uses in hit reactions (a thrown apple ends up in her mouth). Research only.", function()
            local r = nearestRoku(); if not r then return "Roku not found" end
            local e = HOLD[FUN.v.holdIdx]
            r[e[2]](r)
            return "Prop shown: " .. e[1]
        end, { "holdIdx", HOLD_N }, false),
    } end },

    { id = "senses", name = "Senses", items = function() return {
        toggle("hear", "Hearing", "Size of her hearing sphere. x0 - deaf, x3 - hears everything.",
            function() sensesAll(); return "Hearing x" .. FUN.v.hear end, function() sensesAll(); return "Hearing normal" end,
            { "hear", 0.25, 0, 4, "x%.2f", update = sensesAll }),
        toggle("sight", "Vision range", "How far she sees (normally ~13 m). x0.25 - near-sighted, x3 - eagle eyes.",
            function() sensesAll(); return "Vision x" .. FUN.v.sight end, function() sensesAll(); return "Vision normal" end,
            { "sight", 0.25, 0.25, 4, "x%.2f", update = sensesAll }),
        toggle("senseless", "Senses off", "The game's own switch: she neither sees nor hears.",
            function() return rokusDo(function(r) r.bSensesEnabled = false end, "Senses off") end,
            function() return rokusDo(function(r) r.bSensesEnabled = true end, "Senses on") end),
        action("Forget me", "Cancels the chase and wipes what she knows about you.", function()
            return rokusDo(function(r)
                ctrlCall(r, function(c) c:CancelChase() end)
                ctrlCall(r, function(c) c.PerceptionComponent:ForgetAll() end)
                pcall(function() r:SetPlayerDetected(false) end)
            end, "She forgot you")
        end),
        toggle("harmless", "Can't hurt you", "Her hit and grab boxes are off, your health stays full, attack animations are cut short (hook). Check the log for 'attack animation hook'.",
            function() ensureAttackHook(); harmlessTick(); return "Harmless" end,
            function() return rokusDo(function(r) harmlessParts(r, false) end, "Dangerous again") end),
        toggle("karma", "Karma: spotted = she falls", "Every time a Roku notices you, she trips (4 s cooldown).",
            function() FUN.karmaLast = {}; return "Karma on" end, function() return "Karma off" end),
        action("Vision down / up", "The game's own VISION DOWN, then VISION UP after 5 s.", function()
            rokusDo(function(r) r["VISION DOWN"](r) end, "")
            after(5000, function() for _, r in ipairs(allRokus()) do pcall(function() r["VISION UP"](r) end) end end)
            return "Vision down for 5 s"
        end),
    } end },

    { id = "items", name = "Items", items = function() return {
        action("Spawn", "< > choose, middle / Enter - spawn in front of you.", function()
            local e = SPAWN[FUN.v.spawnIdx]
            local made, err = 0, nil
            for i = 1, FUN.v.spawnCount do
                local loc = spotInFront(170); if not loc then break end
                loc.Z = loc.Z + (i - 1) * 25
                local a, e2 = spawnAt(e[2], loc, true)
                if a then made = made + 1 else err = e2 end
            end
            if made == 0 then return e[1] .. ": " .. (err or "failed") end
            return "Spawned " .. made .. " x " .. e[1]
        end, { "spawnIdx", SPAWN_N }),
        (function()
            local it = { label = "Amount    <  " .. FUN.v.spawnCount .. "  >", desc = "How many to spawn at once." }
            it.cycle = function(dir) FUN.v.spawnCount = math.max(1, math.min(20, FUN.v.spawnCount + dir)) end
            return it
        end)(),
        toggle("pushNow", "Force push", "Look at a loose object and blast it away. Arrows - power.",
            function()
                local pt, _, hit, dir = trace(1500); if not pt then return "Nothing there" end
                local c = hitComp(hit); if not c then return "Can't grab that" end
                local phys = false
                pcall(function() phys = c:IsSimulatingPhysics(FName("None")) end)
                if not phys then
                    local cn = ""; pcall(function() cn = c:GetOwner():GetClass():GetFullName() end)
                    if cn:find("/Game/INTERACTION/", 1, true) then pcall(function() c:SetSimulatePhysics(true) end); phys = true end
                end
                if not phys then return "That doesn't move" end
                local s = FUN.v.push
                c:AddImpulse(v3(dir.X * s, dir.Y * s, dir.Z * s + s * 0.2), FName("None"), true)
                return "Yeet!"
            end, function() end, { "push", 500, 500, 15000, "power %d", oneshot = true }),
        toggle("cloneNow", "Clone fountain", "Look at an object: copies burst out of it. Arrows - how many.",
            function()
                local pt, _, hit = trace(1500); if not pt then return "Nothing there" end
                local c = hitComp(hit); if not c then return "Can't copy that" end
                local actor = c:GetOwner(); if not valid(actor) then return "Can't copy that" end
                local cls = actor:GetClass()
                local o = actor:K2_GetActorLocation()
                local origin = v3(o.X, o.Y, o.Z + 40)
                for i = 1, FUN.v.clones do
                    after(i * 120, function()
                        local p = getPawn(); if not p or not valid(cls) then return end
                        local a = nil
                        pcall(function() a = p:GetWorld():SpawnActor(cls, origin, { Pitch = 0, Yaw = math.random(0, 359), Roll = 0 }) end)
                        if not valid(a) then return end
                        local cname = ""; pcall(function() cname = a:GetClass():GetFName():ToString() end)
                        FUN.spawned[#FUN.spawned + 1] = { addr = a:GetAddress(), cls = cname }
                        pcall(function()
                            local root = a:K2_GetRootComponent()
                            root:SetSimulatePhysics(true)
                            local ang, side = math.random() * math.pi * 2, 120 + math.random() * 180
                            root:AddImpulse(v3(math.cos(ang) * side, math.sin(ang) * side, 450 + math.random() * 200), FName("None"), true)
                        end)
                    end)
                end
                return "Fountain! (" .. FUN.v.clones .. ")"
            end, function() end, { "clones", 1, 1, 30, "%d pcs", oneshot = true }),
        action("Delete what I look at", "Removes an item or anything you spawned. Never Roku, notes, doors or vents.", function()
            local pt, _, hit = trace(1500); if not pt then return "Nothing there" end
            local c = hitComp(hit); if not c then return "Can't delete that" end
            local actor = c:GetOwner(); if not valid(actor) then return "Can't delete that" end
            local cn = ""; pcall(function() cn = actor:GetClass():GetFullName() end)
            for _, prot in ipairs({ "BP_NotePickup", "BP_T_SumOfNothing", "BP_Rokuv3", "BP_Door", "BP_Gate", "BP_Vent", "BP_Hider" }) do
                if cn:find(prot, 1, true) then return "Better not: the game needs this" end
            end
            local mine = false
            for _, s in ipairs(FUN.spawned) do if s.addr == actor:GetAddress() then mine = true end end
            local phys = false; pcall(function() phys = c:IsSimulatingPhysics(FName("None")) end)
            if not mine and not phys and not cn:find("/Game/INTERACTION/", 1, true) then return "Only items can be deleted" end
            actor:K2_DestroyActor()
            return "Deleted"
        end),
        action("Delete everything I spawned", "Cleans up all spawned and cloned objects.", function()
            local n = 0
            for _, s in ipairs(FUN.spawned) do
                local a = actorAt(s.addr, s.cls)
                if a then pcall(function() a:K2_DestroyActor() end); n = n + 1 end
            end
            FUN.spawned = {}
            return "Removed " .. n
        end, nil, false),
        action("Shake the Sum of Nothing", "The nearest Sum of Nothing drops a pine cone (counts for score!).", function()
            local me = getPawn():K2_GetActorLocation()
            local best, bd = nil, math.huge
            for _, s in ipairs(FindAllOf("BP_T_SumOfNothing_C") or {}) do
                if valid(s) then
                    local l = s:K2_GetActorLocation()
                    local d = vlen(l.X - me.X, l.Y - me.Y, l.Z - me.Z)
                    if d < bd then best, bd = s, d end
                end
            end
            if not best then return "No Sum of Nothing here" end
            best:SpawnPine()
            return "Pine!"
        end),
    } end },

    { id = "world", name = "World", items = function() return {
        toggle("slowmo", "Slow motion", "The whole world slows down.",
            function() statics():SetGlobalTimeDilation(getPawn(), FUN.v.slowmo) end,
            function() local p = getPawn(); if p then statics():SetGlobalTimeDilation(p, 1) end end,
            { "slowmo", 0.05, 0.1, 0.9, "x%.2f", update = function() statics():SetGlobalTimeDilation(getPawn(), FUN.v.slowmo) end }),
        toggle("light", "Mega flashlight", "The lights right at your eyes get much stronger.",
            function()
                local cam = cameraView(); if not cam then error("no camera") end
                FUN.saved.lights = {}
                for _, cls in ipairs({ "SpotLightComponent", "PointLightComponent", "RectLightComponent" }) do
                    for _, l in ipairs(FindAllOf(cls) or {}) do
                        local ok, loc = pcall(function() return l:K2_GetComponentLocation() end)
                        if ok and loc and vlen(loc.X - cam.X, loc.Y - cam.Y, loc.Z - cam.Z) < 250 then
                            local base = num(l.Intensity) or 0
                            FUN.saved.lights[#FUN.saved.lights + 1] = { addr = l:GetAddress(), cls = cls, base = base }
                            pcall(function() l:SetIntensity(base * FUN.v.light) end)
                        end
                    end
                end
                if #FUN.saved.lights == 0 then FUN.on.light = nil; return "No light near you" end
                return "Let there be light (" .. #FUN.saved.lights .. ")"
            end,
            function()
                for _, e in ipairs(FUN.saved.lights or {}) do
                    local l = actorAt(e.addr, e.cls); if l then pcall(function() l:SetIntensity(e.base) end) end
                end
                FUN.saved.lights = nil
                return "Flashlight normal"
            end, { "light", 1, 2, 30, "x%d", update = function()
                for _, e in ipairs(FUN.saved.lights or {}) do
                    local l = actorAt(e.addr, e.cls); if l then pcall(function() l:SetIntensity(e.base * FUN.v.light) end) end
                end
            end }),
        action("Everything off", "Switches every Player / Roku / Senses / Items / World toggle off.", function()
            local n = 0
            for _, tab in ipairs(LAB_EXTRA_TABS) do
                for _, it in ipairs(tab.items()) do
                    if it.label:find("%[ON%]") then pcall(it.act); n = n + 1 end
                end
            end
            camStop()
            return "Switched off: " .. n
        end, nil, false),
    } end },
}

end)()
