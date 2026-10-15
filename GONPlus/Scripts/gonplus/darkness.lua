------------------------------------------------------------------------
-- ТЕМНОТА. Выключить лампы уровня мало: освещение UE5 (Lumen — отражённый
-- свет, небесный свет, автоэкспозиция "глаза", который привыкает к темноте)
-- всё равно оставляет картинку довольно светлой. Способы сделать темнее:
--   lamps    — лампы уровня (только для проверки; реактор и Nightmare гасят их сами)
--   sky      — небесный и "солнечный" свет уровня (SkyLight, DirectionalLight)
--   exposure — экспозиция камеры игрока: на N ступеней темнее экспозиции уровня (и фонарик тоже)
--   fog      — туман: чёрный (съедает даль) или выключен совсем
--   shadows  — цветокоррекция: гамма < 1, тени проваливаются, фонарик остаётся ярким
--   vignette — тёмные края экрана
-- (Lumen-отражения в игре и так выключены: r.Lumen.DiffuseIndirect.Allow = 0 — скан 13.10.2026)
-- Каждый способ включается отдельно: darkSet(name, true/false, arg).
-- Всё возвращается само при смене персонажа (смерть, рестарт).
------------------------------------------------------------------------
; (function() -- свой кусок: внутренние local не съедают лимит 200 главного куска
DARK = { active = {}, pawn = nil }

local function inLevel(c)
    local full = ""
    pcall(function() full = c:GetFullName() end)
    return full:find("PersistentLevel", 1, true) ~= nil and not full:find("Default__", 1, true)
end

local function skyLights()
    local out = {}
    for _, cn in ipairs({ "SkyLightComponent", "DirectionalLightComponent" }) do
        for _, l in ipairs(FindAllOf(cn) or {}) do
            if valid(l) and inLevel(l) then out[#out + 1] = l end
        end
    end
    return out
end

-- камеры, принадлежащие игроку (первое лицо)
local function playerCams()
    local p = getPawn(); if not p then return {} end
    local pa = p:GetAddress()
    local out = {}
    for _, c in ipairs(FindAllOf("CameraComponent") or {}) do
        if valid(c) then
            local owner = nil
            pcall(function() owner = c:GetOwner() end)
            if valid(owner) and owner:GetAddress() == pa then out[#out + 1] = c end
        end
    end
    return out
end

-- экспозиция уровня: включённый безграничный PostProcessVolume с заданной компенсацией
function levelExposure()
    local best, bestPrio = nil, -1e9
    for _, v in ipairs(FindAllOf("PostProcessVolume") or {}) do
        if valid(v) and inLevel(v) then
            local en, unb, prio, ob, b = false, false, 0, false, nil
            pcall(function() en = v.bEnabled == true end)
            pcall(function() unb = v.bUnbound == true end)
            pcall(function() prio = num(v.Priority) or 0 end)
            pcall(function() ob = v.Settings.bOverride_AutoExposureBias == true end)
            pcall(function() b = num(v.Settings.AutoExposureBias) end)
            if en and unb and ob and b and prio >= bestPrio then best, bestPrio = b, prio end
        end
    end
    return best or 0
end

local function ksl() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
local function cvarInt(name)
    local v = nil
    pcall(function() v = ksl():GetConsoleVariableIntValue(name) end)
    return num(v)
end
local function console(cmd)
    local ok = pcall(function() ksl():ExecuteConsoleCommand(getPawn(), cmd, getPC()) end)
    log("Dark: console '" .. cmd .. "' -> " .. tostring(ok))
end

-- поменять настройки пост-обработки камеры игрока; set(pp, e) пишет, e хранит старое
local function camPP(st, set, restore)
    st.cams = {}
    local report = {}
    for _, c in ipairs(playerCams()) do
        local e = { c = c }
        local ok, err = pcall(function() set(c.PostProcessSettings, e) end)
        st.cams[#st.cams + 1] = e
        report[#report + 1] = tostring(ok) .. (ok and "" or (" " .. tostring(err)))
    end
    st.restore = restore
    return #st.cams .. " cameras (" .. table.concat(report, "; ") .. ")"
end
local function camPPOff(st)
    for _, e in ipairs(st.cams or {}) do
        if valid(e.c) then pcall(function() st.restore(e.c.PostProcessSettings, e) end) end
    end
end

local METHODS = {
    -- туман: свой цвет рассеяния светит сам по себе. "black" — чёрный туман (съедает даль),
    -- "off" — туман спрятан совсем
    fog = {
        on = function(st, mode)
            st.list = {}
            for _, f in ipairs(FindAllOf("ExponentialHeightFogComponent") or {}) do
                if valid(f) and inLevel(f) then
                    local e = { c = f, mode = mode }
                    if mode == "off" then
                        pcall(function() f:SetVisibility(false, false) end)
                    else
                        pcall(function() local c = f.FogInscatteringLuminance; e.lum = { R = c.R, G = c.G, B = c.B, A = c.A } end)
                        pcall(function() local c = f.FogInscatteringColor; e.col = { R = c.R, G = c.G, B = c.B, A = c.A } end)
                        pcall(function() local c = f.DirectionalInscatteringLuminance; e.dir = { R = c.R, G = c.G, B = c.B, A = c.A } end)
                        local black = { R = 0, G = 0, B = 0, A = 1 }
                        pcall(function() f:SetFogInscatteringColor(black) end)
                        pcall(function() f.FogInscatteringLuminance = black end)
                        pcall(function() f:SetDirectionalInscatteringColor(black) end)
                        pcall(function() f:SetVolumetricFog(false) end)
                        pcall(function() f:MarkRenderStateDirty() end)
                    end
                    st.list[#st.list + 1] = e
                end
            end
            return #st.list .. " fog components -> " .. tostring(mode)
        end,
        off = function(st)
            for _, e in ipairs(st.list or {}) do
                if valid(e.c) then
                    if e.mode == "off" then
                        pcall(function() e.c:SetVisibility(true, false) end)
                    else
                        if e.col then pcall(function() e.c:SetFogInscatteringColor(e.col) end) end
                        if e.lum then pcall(function() e.c.FogInscatteringLuminance = e.lum end) end
                        if e.dir then pcall(function() e.c:SetDirectionalInscatteringColor(e.dir) end) end
                        pcall(function() e.c:SetVolumetricFog(true) end)
                        pcall(function() e.c:MarkRenderStateDirty() end)
                    end
                end
            end
        end,
    },
    -- тени: гамма < 1 давит тёмные и средние тона, яркое (пятно фонарика) почти не трогает
    shadows = {
        on = function(st, gamma)
            gamma = gamma or 0.6
            return "gamma " .. gamma .. ": " .. camPP(st, function(pp, e)
                e.o = pp.bOverride_ColorGamma
                local g = pp.ColorGamma; e.g = { X = g.X, Y = g.Y, Z = g.Z, W = g.W }
                pp.bOverride_ColorGamma = true
                pp.ColorGamma = { X = 1, Y = 1, Z = 1, W = gamma }
            end, function(pp, e)
                pp.ColorGamma = e.g
                pp.bOverride_ColorGamma = e.o == true
            end)
        end,
        off = camPPOff,
    },
    -- виньетка: края экрана тонут в темноте
    vignette = {
        on = function(st, k)
            k = k or 1.0
            return "vignette " .. k .. ": " .. camPP(st, function(pp, e)
                e.o, e.v = pp.bOverride_VignetteIntensity, num(pp.VignetteIntensity)
                pp.bOverride_VignetteIntensity = true
                pp.VignetteIntensity = k
            end, function(pp, e)
                pp.VignetteIntensity = e.v or 0.4
                pp.bOverride_VignetteIntensity = e.o == true
            end)
        end,
        off = camPPOff,
    },
    -- лампы уровня: яркость = доля от родной (0 = выключены), цвет из DARK_LAMP_COLORS
    -- (nil — свой цвет лампы). Используют Nightmare и лаборатория; у реактора свои лампы.
    lamps = {
        on = function(st, arg)
            arg = arg or { frac = 0 }
            local frac = arg.frac or 0
            local col = arg.color and DARK_LAMP_COLORS[arg.color] or nil
            st.list = {}
            for _, l in ipairs(levelLights()) do
                local int = nil
                pcall(function() int = num(l.Intensity) end)
                if int and int > 0 then
                    local e = { c = l, int = int }
                    if col then
                        pcall(function() local c = l.LightColor; e.col = { R = c.R / 255, G = c.G / 255, B = c.B / 255, A = 1 } end)
                        pcall(function() l:SetLightColor({ R = col[1], G = col[2], B = col[3], A = 1 }, true) end)
                    end
                    pcall(function() l:SetIntensity(int * frac) end)
                    st.list[#st.list + 1] = e
                end
            end
            return string.format("%d level lamps at %.1f%%, color %s", #st.list, frac * 100, tostring(arg.color or "own"))
        end,
        off = function(st)
            for _, e in ipairs(st.list or {}) do
                if valid(e.c) then
                    pcall(function() e.c:SetIntensity(e.int) end)
                    if e.col then pcall(function() e.c:SetLightColor(e.col, true) end) end
                end
            end
        end,
    },
    sky = {
        on = function(st)
            st.list = {}
            for _, l in ipairs(skyLights()) do
                local int = nil
                pcall(function() int = num(l.Intensity) end)
                if int and int > 0 then
                    st.list[#st.list + 1] = { c = l, int = int }
                    pcall(function() l:SetIntensity(0) end)
                end
            end
            return #st.list .. " sky/sun lights off"
        end,
        off = function(st)
            for _, e in ipairs(st.list or {}) do
                if valid(e.c) then pcall(function() e.c:SetIntensity(e.int) end) end
            end
        end,
    },
    exposure = {
        -- stops: на сколько ступеней темнее уровня (1 ступень = примерно вдвое темнее).
        -- Уровень сам задаёт ручную экспозицию (+13 у Lvl_Sandbox3), поэтому считаем от неё,
        -- а не ставим абсолютное число (абсолютное -2 = на 15 ступеней темнее = чёрный экран).
        on = function(st, stops)
            stops = stops or 2
            local base = levelExposure()
            local bias = base - stops
            st.cams = {}
            local report = {}
            for _, c in ipairs(playerCams()) do
                local e = { c = c }
                local ok = pcall(function()
                    local pp = c.PostProcessSettings
                    e.ob, e.bias = pp.bOverride_AutoExposureBias, num(pp.AutoExposureBias)
                    pp.bOverride_AutoExposureBias = true
                    pp.AutoExposureBias = bias
                end)
                local now = nil
                pcall(function() now = num(c.PostProcessSettings.AutoExposureBias) end)
                pcall(function() e.w = num(c.PostProcessBlendWeight); c.PostProcessBlendWeight = 1.0 end)
                st.cams[#st.cams + 1] = e
                report[#report + 1] = string.format("%s write=%s readback=%s", c:GetFName():ToString(), tostring(ok), tostring(now))
            end
            return #st.cams .. " player cameras, level " .. base .. " -> " .. bias .. " (" .. table.concat(report, "; ") .. ")"
        end,
        off = function(st)
            for _, e in ipairs(st.cams or {}) do
                if valid(e.c) then
                    pcall(function()
                        local pp = e.c.PostProcessSettings
                        pp.AutoExposureBias = e.bias or 0
                        pp.bOverride_AutoExposureBias = e.ob == true
                    end)
                    if e.w then pcall(function() e.c.PostProcessBlendWeight = e.w end) end
                end
            end
        end,
    },
}

function darkSet(name, on, arg)
    local m = METHODS[name]; if not m then return "unknown method " .. tostring(name) end
    local st = DARK.active[name]
    if on then
        if st then pcall(m.off, st) end           -- переключение силы: сначала вернуть
        st = { arg = arg }
        local ok, res = pcall(m.on, st, arg)
        DARK.active[name] = st
        local p = getPawn(); DARK.pawn = p and p:GetAddress() or nil
        local msg = "Dark " .. name .. " ON: " .. (ok and tostring(res) or ("error " .. tostring(res)))
        log(msg)
        return msg
    elseif st then
        pcall(m.off, st)
        DARK.active[name] = nil
        log("Dark " .. name .. " off")
        return "Dark " .. name .. " off"
    end
    return "Dark " .. name .. " was off"
end
-- Пресет "настоящая темнота" (выбран игроком 13.10.2026 в лаборатории):
-- лампы гасит сам режим/мутатор, плюс небо, тени (гамма 0.55) и виньетка.
-- Туман и экспозицию не трогаем (экспозиция гасит и фонарик).
DARK_PRESET = { { "sky" }, { "shadows", 0.75 }, { "vignette", 1.0 } }

-- лампы в Nightmare: чуть-чуть светят своим цветом (настраивается в лаборатории)
DARK_LAMP_COLORS = {
    red    = { 1.0, 0.06, 0.04 },
    blood  = { 0.55, 0.0, 0.02 },
    amber  = { 1.0, 0.42, 0.06 },
    green  = { 0.35, 1.0, 0.2 },
    cyan   = { 0.1, 0.8, 1.0 },
    blue   = { 0.12, 0.25, 1.0 },
    purple = { 0.55, 0.12, 1.0 },
}
DARK_LAMP_ORDER = { "own", "red", "blood", "amber", "green", "cyan", "blue", "purple" }
DARK_LAMP_LEVELS = { 0, 0.002, 0.005, 0.01, 0.02, 0.03, 0.05, 0.08, 0.12, 0.2 }
DARK_LAMP = { frac = 0.01, color = "red" }
function darkLampArg() return { frac = DARK_LAMP.frac, color = DARK_LAMP.color ~= "own" and DARK_LAMP.color or nil } end
DARK.users = {}
-- кто держит темноту (реактор, Nightmare): выключается, только когда отпустили все
function darkPreset(on, who)
    DARK.users[who or "?"] = on or nil
    local want = next(DARK.users) ~= nil
    for _, m in ipairs(DARK_PRESET) do
        if want ~= darkIsOn(m[1]) then darkSet(m[1], want, m[2]) end
    end
end

-- лампы уровня с владельцами (Nightmare, мутатор Darkness): гаснут, пока держит хоть один
DARK.lampUsers = {}
function darkLamps(on, who)
    DARK.lampUsers[who or "?"] = on or nil
    local want = next(DARK.lampUsers) ~= nil
    if want and not darkIsOn("lamps") then return darkSet("lamps", true, darkLampArg()) end
    if not want and darkIsOn("lamps") then return darkSet("lamps", false) end
    return "lamps unchanged"
end

function darkIsOn(name) return DARK.active[name] ~= nil end
function darkArg(name) local st = DARK.active[name]; return st and st.arg end
function darkAllOff()
    for name in pairs(DARK.active) do darkSet(name, false) end
end

-- новый персонаж (смерть, рестарт уровня): всё вернуть, особенно настройку консоли
every(500, function()
    if not next(DARK.active) then return end
    local p = getPawn()
    local addr = p and p:GetAddress() or nil
    if addr ~= DARK.pawn then
        log("Dark: new character - restoring")
        DARK.users, DARK.lampUsers = {}, {}
        darkAllOff()
    end
end)

-- разведка: что в уровне отвечает за "светло даже без ламп"
function darkScan()
    local path = ROOT .. "\\dark_scan.txt"
    local f = io.open(path, "w"); if not f then return "cannot write dark_scan.txt" end
    local function w(s) f:write(s .. "\n") end
    local function field(o, k) local v = "?"; pcall(function() v = tostring(o[k]) end) return v end
    w("GON+ darkness scan " .. os.date())
    for _, cn in ipairs({ "SkyLightComponent", "DirectionalLightComponent", "ExponentialHeightFogComponent",
                          "PointLightComponent", "SpotLightComponent", "RectLightComponent" }) do
        local all = FindAllOf(cn) or {}
        local lvl = 0
        for _, c in ipairs(all) do if valid(c) and inLevel(c) then lvl = lvl + 1 end end
        w(string.format("\n== %s: %d total, %d in level", cn, #all, lvl))
        if cn == "SkyLightComponent" or cn == "DirectionalLightComponent" or cn == "ExponentialHeightFogComponent" then
            for _, c in ipairs(all) do
                if valid(c) and inLevel(c) then
                    w("  " .. c:GetFullName())
                    w("    Intensity=" .. field(c, "Intensity") .. " Mobility=" .. field(c, "Mobility")
                        .. " bVisible=" .. field(c, "bVisible") .. " FogDensity=" .. field(c, "FogDensity")
                        .. " IndirectLightingIntensity=" .. field(c, "IndirectLightingIntensity"))
                end
            end
        end
    end
    local function ppDump(label, pp)
        local keys = { "bOverride_AutoExposureMethod", "AutoExposureMethod", "bOverride_AutoExposureBias", "AutoExposureBias",
            "bOverride_AutoExposureMinBrightness", "AutoExposureMinBrightness", "bOverride_AutoExposureMaxBrightness",
            "AutoExposureMaxBrightness", "bOverride_DynamicGlobalIlluminationMethod", "DynamicGlobalIlluminationMethod",
            "bOverride_IndirectLightingIntensity", "IndirectLightingIntensity", "bOverride_LumenSceneLightingQuality",
            "bOverride_ColorGamma", "bOverride_ColorGain", "bOverride_VignetteIntensity", "VignetteIntensity" }
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. field(pp, k) end
        w("    " .. label .. ": " .. table.concat(parts, " "))
    end
    local vols = FindAllOf("PostProcessVolume") or {}
    w(string.format("\n== PostProcessVolume: %d", #vols))
    for _, v in ipairs(vols) do
        if valid(v) then
            w("  " .. v:GetFullName() .. " bUnbound=" .. field(v, "bUnbound") .. " Priority=" .. field(v, "Priority")
                .. " BlendWeight=" .. field(v, "BlendWeight") .. " bEnabled=" .. field(v, "bEnabled"))
            pcall(function() ppDump("Settings", v.Settings) end)
        end
    end
    local cams = playerCams()
    w(string.format("\n== Player cameras: %d", #cams))
    for _, c in ipairs(cams) do
        w("  " .. c:GetFullName() .. " PostProcessBlendWeight=" .. field(c, "PostProcessBlendWeight"))
        pcall(function() ppDump("PostProcessSettings", c.PostProcessSettings) end)
    end
    w("\n== Console variables")
    for _, cv in ipairs({ "r.DynamicGlobalIlluminationMethod", "r.ReflectionMethod", "r.EyeAdaptationQuality",
                          "r.Lumen.DiffuseIndirect.Allow", "r.SkyLight.RealTimeReflectionCapture", "r.ShadowQuality" }) do
        w("  " .. cv .. " = " .. tostring(cvarInt(cv)))
    end
    f:close()
    log("Dark scan written: " .. path)
    return "Saved dark_scan.txt"
end
end)() -- DARKNESS
