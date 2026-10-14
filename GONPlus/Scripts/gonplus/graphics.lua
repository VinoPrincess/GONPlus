------------------------------------------------------------------------
-- Графика и FPS (Settings -> Graphics / FPS)
-- Только консольные переменные движка: ничего в файлах игры не меняем.
-- Значение "game" = не трогать (вернуть то, что было у игры до нас).
-- Свои значения мод держит сам: раз в пару секунд сверяет и, если игра
-- их перезаписала (новая карта, своё меню), ставит заново.
------------------------------------------------------------------------
; (function()

-- группы качества, которые меняет строка "Quality". Без GI и отражений:
-- от них у игры включается Lumen (свечение стен, тяжело) — отражения отдельной строкой.
local SG = { "sg.ViewDistanceQuality", "sg.AntiAliasingQuality", "sg.ShadowQuality", "sg.PostProcessQuality",
             "sg.EffectsQuality", "sg.FoliageQuality", "sg.ShadingQuality" }
local function sgAll(lvl) local t = {} for _, n in ipairs(SG) do t[#t + 1] = { n, lvl } end return t end

-- строки экрана: key — настройка в settings.txt (0 = "game"), vals — подписи, set[i] — что ставить
GFX_ROWS = {
    { key = "gfxRes", label = "Render scale",
      vals = { "game", "100%", "90%", "80%", "75%", "70%", "60%", "50%" },
      set = { nil, {{ "r.ScreenPercentage", 100 }}, {{ "r.ScreenPercentage", 90 }}, {{ "r.ScreenPercentage", 80 }},
              {{ "r.ScreenPercentage", 75 }}, {{ "r.ScreenPercentage", 70 }}, {{ "r.ScreenPercentage", 60 }},
              {{ "r.ScreenPercentage", 50 }} },
      desc = "The strongest FPS boost. The game renders fewer pixels and scales the picture up: softer image, much faster." },
    { key = "gfxQuality", label = "Quality",
      vals = { "game", "low", "medium", "high", "epic" },
      set = { nil, sgAll(0), sgAll(1), sgAll(2), sgAll(3) },
      desc = "Overall quality: view distance, shadows, post-processing, effects, shading. Lighting and reflections are not touched here." },
    { key = "gfxShadows", label = "Shadows",
      vals = { "game", "fast", "low" },
      set = { nil, {{ "r.Shadow.Virtual.Enable", 0 }},
              {{ "r.Shadow.Virtual.Enable", 0 }, { "r.ShadowQuality", 2 }, { "r.Shadow.MaxResolution", 1024 }} },
      desc = "Fast: classic shadow maps instead of Unreal 5 virtual shadows (often the main cause of drops on AMD). Low: also blurrier shadows." },
    { key = "gfxReflect", label = "Reflections",
      vals = { "game", "screen", "off" },
      set = { nil, {{ "r.ReflectionMethod", 2 }}, {{ "r.ReflectionMethod", 0 }} },
      desc = "Screen: cheap screen-space reflections instead of Lumen. Off: no reflections at all (fastest)." },
    { key = "gfxFog", label = "Volumetric fog",
      vals = { "game", "off" },
      set = { nil, {{ "r.VolumetricFog", 0 }} },
      desc = "Off: no volumetric fog and light shafts. Faster, a little less atmosphere." },
    { key = "gfxAA", label = "Anti-aliasing",
      vals = { "game", "TSR", "TAA", "FXAA", "off" },
      set = { nil, {{ "r.AntiAliasingMethod", 4 }}, {{ "r.AntiAliasingMethod", 2 }},
              {{ "r.AntiAliasingMethod", 1 }}, {{ "r.AntiAliasingMethod", 0 }} },
      desc = "TSR: best quality, the heaviest. TAA: lighter. FXAA: very light, a bit jaggy. Use TSR or TAA with render scale below 100%." },
    { key = "gfxFx", label = "Effects",
      vals = { "game", "light" },
      set = { nil, {{ "r.MotionBlurQuality", 0 }, { "r.DepthOfFieldQuality", 0 }, { "r.SceneColorFringeQuality", 0 },
                    { "r.LensFlareQuality", 0 }} },
      desc = "Light: no motion blur, depth of field, color fringe and lens flares." },
    { key = "gfxFpsCap", label = "FPS limit",
      vals = { "game", "30", "45", "60", "75", "90", "120", "144" },
      set = { nil, {{ "t.MaxFPS", 30 }}, {{ "t.MaxFPS", 45 }}, {{ "t.MaxFPS", 60 }}, {{ "t.MaxFPS", 75 }},
              {{ "t.MaxFPS", 90 }}, {{ "t.MaxFPS", 120 }}, {{ "t.MaxFPS", 144 }} },
      desc = "A steady limit often feels smoother than jumping between 90 and 30. Pick what your PC holds most of the time." },
}

-- быстрые пресеты: значения строк по порядку GFX_ROWS (индекс в vals минус 1)
local PRESETS = {
    { name = "game",     v = { 0, 0, 0, 0, 0, 0, 0, 0 } },
    { name = "balanced", v = { 3, 0, 1, 1, 0, 2, 1, 0 } },   -- 80%, тени fast, отражения screen, TAA, лёгкие эффекты
    { name = "max FPS",  v = { 6, 1, 2, 2, 1, 2, 1, 0 } },   -- 60%, low, тени low, без отражений и тумана, TAA
}

local function ksl() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
local function cvarGet(name)
    local v = nil
    pcall(function() v = num(ksl():GetConsoleVariableFloatValue(name)) end)
    if v == nil then pcall(function() v = num(ksl():GetConsoleVariableIntValue(name)) end) end
    return v
end
local function cvarSet(name, v)
    local ctx = getPawn() or getPC()
    local ok = pcall(function() ksl():ExecuteConsoleCommand(ctx, name .. " " .. tostring(v), getPC()) end)
    return ok
end
local function gfxLog(msg) print(TAG .. "Graphics: " .. msg .. "\n") end   -- всегда: пригодится в отчётах

-- что было у игры до нас (по имени переменной); пока что-то наше стоит
local ORIG = {}

local function wanted()
    local want, order = {}, {}
    local function add(list)
        for _, p in ipairs(list or {}) do
            if want[p[1]] == nil then order[#order + 1] = p[1] end
            want[p[1]] = p[2]
        end
    end
    -- качество первым: оно переставляет много r.*, а строки ниже уточняют
    for _, r in ipairs(GFX_ROWS) do
        local i = (P[r.key] or 0) + 1
        if r.key == "gfxQuality" then add(r.set[i]) end
    end
    for _, r in ipairs(GFX_ROWS) do
        local i = (P[r.key] or 0) + 1
        if r.key ~= "gfxQuality" then add(r.set[i]) end
    end
    return want, order
end

-- привести переменные к выбранному; quiet = без лога, если ничего не поменялось
function gfxApply(why)
    local want, order = wanted()
    local changed = {}
    -- сначала запоминаем исходные значения всего, что тронем впервые
    for _, n in ipairs(order) do
        if ORIG[n] == nil then ORIG[n] = cvarGet(n) or false end
    end
    for _, n in ipairs(order) do
        local cur = cvarGet(n)
        if cur == nil or math.abs(cur - want[n]) > 0.01 then
            cvarSet(n, want[n])
            changed[#changed + 1] = n .. "=" .. tostring(want[n])
        end
    end
    -- то, что больше не выбрано, — вернуть как было у игры
    for n, o in pairs(ORIG) do
        if want[n] == nil then
            if o ~= false then cvarSet(n, o); changed[#changed + 1] = n .. "=" .. tostring(o) .. " (game)" end
            ORIG[n] = nil
        end
    end
    if #changed > 0 then gfxLog((why or "apply") .. ": " .. table.concat(changed, ", ")) end
end

-- отчёт в лог: что сейчас стоит у игры (для разбора жалоб на FPS)
local SCAN = { "r.ScreenPercentage", "r.AntiAliasingMethod", "r.Shadow.Virtual.Enable", "r.ShadowQuality",
    "r.ReflectionMethod", "r.DynamicGlobalIlluminationMethod", "r.Lumen.DiffuseIndirect.Allow", "r.VolumetricFog",
    "r.Nanite", "r.MotionBlurQuality", "t.MaxFPS", "r.VSync", "sg.ResolutionQuality", "sg.ViewDistanceQuality",
    "sg.AntiAliasingQuality", "sg.ShadowQuality", "sg.GlobalIlluminationQuality", "sg.ReflectionQuality",
    "sg.PostProcessQuality", "sg.TextureQuality", "sg.EffectsQuality", "sg.FoliageQuality", "sg.ShadingQuality" }
function gfxScan()
    local out = {}
    for _, n in ipairs(SCAN) do out[#out + 1] = n .. "=" .. tostring(cvarGet(n)) end
    gfxLog("scan: " .. table.concat(out, ", "))
end

-- какой пресет совпадает с текущими строками
local function presetNow()
    for i, p in ipairs(PRESETS) do
        local same = true
        for j, r in ipairs(GFX_ROWS) do if (P[r.key] or 0) ~= p.v[j] then same = false break end end
        if same then return i end
    end
    return nil
end

local function setPreset(i)
    for j, r in ipairs(GFX_ROWS) do P[r.key] = PRESETS[i].v[j] end
    saveSettings()
    gfxApply("preset " .. PRESETS[i].name)
end

SCREENS.graphics = function()
    local items = {}
    local pi = presetNow()
    items[#items + 1] = { label = "Preset    [" .. (pi and PRESETS[pi].name or "custom") .. "]",
        desc = "Game: everything as the game sets it. Balanced: lighter shadows and reflections, 80% scale. Max FPS: for weak PCs.",
        cycle = function(dir)
            local cur = presetNow() or 1   -- "custom": вправо — balanced, влево — max FPS
            setPreset((cur - 1 + dir) % #PRESETS + 1)
        end }
    for _, r in ipairs(GFX_ROWS) do
        local v = P[r.key] or 0
        items[#items + 1] = { label = r.label .. "    <  " .. r.vals[v + 1] .. "  >", desc = r.desc,
            cycle = function(dir)
                P[r.key] = ((P[r.key] or 0) + dir) % #r.vals
                saveSettings()
                gfxApply(r.label)
            end }
    end
    items[#items + 1] = { label = "FPS counter    " .. (P.gfxFpsShow and "[ON]" or "[off]"),
        desc = "Top left: average FPS and the lowest value of the last 5 seconds.",
        cycle = function() P.gfxFpsShow = not P.gfxFpsShow; saveSettings() end }
    items[#items + 1] = { label = "Reset to game", desc = "All graphics back to what the game set. For the game's own graphics menu to fully take over again, restart the game.",
        act = function() setPreset(1); windowNote("Graphics: as the game sets it") end }
    return "GRAPHICS", "Changes apply at once and are kept between runs.", items,
        "sides / arrows - change    right click / Backspace - back"
end

------------------------------------------------------------------------
-- FPS: по длительности кадра (GetWorldDeltaSeconds) раз в 50 мс
------------------------------------------------------------------------
local FPS = { samples = {} }

-- настоящее время (секунды, без паузы); os.clock — время процессора, для FPS не годится
local function realNow()
    local t = nil
    pcall(function() t = num(statics():GetRealTimeSeconds(getPawn() or getPC())) end)
    return t
end

every(50, function()
    local t = UI.fpsText
    if not valid(t) then return end
    if not P.gfxFpsShow then
        if FPS.on then FPS.on = false; FPS.samples = {}; t:SetVisibility(VIS_HIDE) end
        return
    end
    local now = realNow()
    if not now then return end
    local dt = nil
    pcall(function() dt = num(statics():GetWorldDeltaSeconds(getPawn() or getPC())) end)
    local s = FPS.samples
    if #s > 0 and now < s[#s].t then FPS.samples = {}; s = FPS.samples end   -- новая карта: время с нуля
    if dt and dt > 0.0005 and dt < 2 then s[#s + 1] = { t = now, dt = dt } end
    while #s > 0 and now - s[1].t > 5 do table.remove(s, 1) end
    if now - (FPS.lastShow or -1) < 0.5 and now >= (FPS.lastShow or -1) then return end
    FPS.lastShow = now
    if #s == 0 then return end
    local sum, n, worst = 0, 0, 0
    for i = #s, 1, -1 do
        local e = s[i]
        if now - e.t <= 1 then sum = sum + e.dt; n = n + 1 end
        if e.dt > worst then worst = e.dt end
    end
    if n == 0 then return end
    setText(t, string.format("FPS %d   low %d", math.floor(n / sum + 0.5), math.floor(1 / worst + 0.5)))
    FPS.on = true; t:SetVisibility(VIS_SHOW)
end)

-- держим выбранное: игра может перезаписать при загрузке карты или из своего меню
local function anySet()
    for _, r in ipairs(GFX_ROWS) do if (P[r.key] or 0) ~= 0 then return true end end
    return next(ORIG) ~= nil
end
local scanned = false
every(2000, function()
    if not getPC() then return end
    if not scanned then scanned = true; gfxScan() end
    if anySet() then gfxApply("keep") end
end)

end)()
