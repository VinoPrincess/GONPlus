-- GON+ / core.lua: версия, служебное, планировщик, настройки, время, хуки, движок мутаторов.
-- Все файлы gonplus\*.lua склеиваются загрузчиком (main.lua) в один кусок по порядку,
-- поэтому local из этого файла видны в следующих. Порядок файлов важен.

local VERSION = "1.1-dev"
local AUTHOR = "VinoPrincess"
-- лаборатория разработчика (F1): true — открывается 7 кликами по "+GON+PLUS+" в окне выбора;
-- "always" — сразу; false — вырезана совсем
local LAB_ENABLED = true
local TAG = "[GON+] "
-- Тихий лог: игроку — только загрузка и ошибки. Подробности (разведка, шаги режимов)
-- печатаются, когда открыта лаборатория (labUnlocked) или VERBOSE = true.
local VERBOSE = false
local LOG_ALWAYS = { "[Ee]rror", "[Ff]ail", "FAILED", "Loaded", "unlocked", "missing", "not found" }
local function log(msg)
    msg = tostring(msg)
    if GONPLUS_WHERE then msg = GONPLUS_WHERE(msg) end   -- "GONPlus:1234:" -> "lab.lua:56:"
    if not VERBOSE then
        local important = false
        for _, pat in ipairs(LOG_ALWAYS) do if msg:find(pat) then important = true break end end
        if not important then return end
    end
    print(TAG .. msg .. "\n")
end

------------------------------------------------------------------------
-- Служебное
------------------------------------------------------------------------
local VIS_SHOW = 3      -- HitTestInvisible: видно, мышь не ловит
local VIS_HIDE = 1      -- Collapsed

local function valid(o) return o ~= nil and o.IsValid ~= nil and o:IsValid() end

-- Контроллер (мозг) персонажа — только если он настоящий: существует И управляет именно
-- этим персонажем. Голый r.Controller у только что появившейся или пересоздаваемой Року
-- может указывать на недостроенный/удалённый объект, и вызов на нём роняет игру мимо
-- pcall (вылет у тестера: Pure Stealth на 4 Року, StopMovement, 13.10.2026).
local function aiCtrl(r)
    if not valid(r) then return nil end
    local c = nil
    pcall(function() c = r.Controller end)
    if not valid(c) then return nil end
    local mine = false
    pcall(function()
        local p = c.Pawn
        mine = valid(p) and p:GetAddress() == r:GetAddress()
    end)
    return mine and c or nil
end
-- безопасные короткие вызовы
local function ctrlCall(r, fn)
    local c = aiCtrl(r)
    if not c then return false end
    return pcall(fn, c)
end

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then log("Error: " .. tostring(err)) end
    return ok, err
end

local function num(v) if type(v) == "number" then return v end return nil end

-- Ссылки на объекты игры, которые мод держит между кадрами (виджеты HUD, списки
-- вентиляций, предметы и т.п.). На каждом новом забеге (новый персонаж, перезапуск
-- уровня) всё это забываем и ищем заново: старые объекты игра удаляет, и обращение
-- к удалённому объекту роняет игру (вылет 13.10.2026 после перезапуска уровня).
local REF_RESETS = {}
local function onForgetRefs(fn) REF_RESETS[#REF_RESETS + 1] = fn end
local ROKU_SEEN = {}            -- адрес Року -> когда впервые увидели (время игры)
local function forgetGameRefs()
    ROKU_SEEN = {}
    for _, fn in ipairs(REF_RESETS) do pcall(fn) end
end

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = deepcopy(v) end
    return r
end

local function modRoot()
    if GONPLUS_ROOT then return GONPLUS_ROOT end   -- задаёт загрузчик main.lua
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", ""):gsub("/", "\\")
    return src:match("^(.*)\\[Ss]cripts\\[^\\]+$") or "."
end
local ROOT = modRoot()

-- всё через EngineTick, если есть: работает и на паузе
local function gameThread(fn)
    if EngineTickAvailable and EGameThreadMethod then
        ExecuteInGameThread(fn, EGameThreadMethod.EngineTick)
    else
        ExecuteInGameThread(fn)
    end
end
-- ОДИН планировщик на весь мод: один фоновый цикл раз в 20 мс передаёт управление
-- в игровой поток, а там уже по своим часам выполняются все задачи и отложенные вызовы.
-- Раньше было 4 фоновых цикла + ExecuteWithDelay на каждый чих: ~36 переходов между
-- потоками в секунду, и в логе появлялись странные ошибки (гонки). Теперь — 50, но
-- все короткие и строго по одному.
local JOBS, TIMERS = {}, {}
local function nowMs() return os.clock() * 1000 end

local function after(ms, fn)
    TIMERS[#TIMERS + 1] = { at = nowMs() + ms, fn = fn }
end
local function every(ms, fn)
    JOBS[#JOBS + 1] = { every = ms, next = nowMs() + ms, fn = fn }
end

local function schedulerTick()
    local t = nowMs()
    for _, j in ipairs(JOBS) do
        if t >= j.next then
            j.next = t + j.every
            safe(j.fn)
        end
    end
    if #TIMERS > 0 then
        local due, keep = {}, {}
        for _, tm in ipairs(TIMERS) do
            if t >= tm.at then due[#due + 1] = tm else keep[#keep + 1] = tm end
        end
        TIMERS = keep
        for _, tm in ipairs(due) do safe(tm.fn) end
    end
end

local lastTickAt = nowMs()
SCHED_MODE = "?"

-- Главное: цикл в ИГРОВОМ потоке (LoopInGameThreadWithDelay). Фоновые потоки
-- (LoopAsync, ExecuteWithDelay) выполняют Lua параллельно с игровым потоком на одном
-- состоянии Lua — отсюда "Ref was not function", "функция вместо объекта" и замолкания
-- мода. Если этой функции в сборке UE4SS нет — старый способ как запасной.
if LoopInGameThreadWithDelay then
    SCHED_MODE = "game thread"
    LoopInGameThreadWithDelay(25, function()
        lastTickAt = nowMs()
        safe(schedulerTick)
    end)
else
    SCHED_MODE = "async fallback (old UE4SS)"
    local tickQueued, loopGen = false, 0
    local function startLoop()
        loopGen = loopGen + 1
        local myGen = loopGen
        tickQueued = false
        LoopAsync(50, function()
            if myGen ~= loopGen then return true end
            if not tickQueued then
                tickQueued = true
                gameThread(function()
                    tickQueued = false
                    lastTickAt = nowMs()
                    safe(schedulerTick)
                end)
            end
            return false
        end)
    end
    startLoop()
    -- сторож только для запасного способа
    local function watchdog()
        ExecuteWithDelay(1000, function()
            if nowMs() - lastTickAt > 2500 then
                print("[GON+] Scheduler was silent for " .. math.floor(nowMs() - lastTickAt) .. " ms, restarting it\n")
                lastTickAt = nowMs()
                startLoop()
            end
            watchdog()
        end)
    end
    watchdog()
end

-- тикает ли сейчас планировщик (на паузе цикл игрового потока может стоять)
local function schedulerAlive() return nowMs() - lastTickAt < 400 end

local function statics() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end

local function getPC()
    local pc = nil
    pcall(function() pc = FindFirstOf("PlayerController") end)
    if valid(pc) then return pc end
    return nil
end

local function getPawn()
    local pc = getPC()
    if not pc then return nil end
    local p = nil
    pcall(function() p = pc.Pawn end)
    if valid(p) then return p end
    return nil
end

local function getRoku()
    local r = FindFirstOf("BP_Rokuv3_C")
    if valid(r) then return r end
    return nil
end

local function fmtTime(sec, cs)
    if not sec then return "--:--" end
    local neg = sec < 0
    sec = math.abs(sec)
    local m = math.floor(sec / 60)
    local s = sec - m * 60
    local out
    if cs then out = string.format("%02d:%05.2f", m, s)
    else out = string.format("%02d:%02d", m, math.floor(s)) end
    return (neg and "-" or "") .. out
end

------------------------------------------------------------------------
-- Настройки (Mods\GONPlus\settings.txt)
------------------------------------------------------------------------
local DEFAULTS = {
    chaosInterval = 60,     -- секунд между сменами в хаосе
    chaosWarn     = 5,      -- за сколько секунд предупреждать о смене
    graceSec      = 3,      -- сколько секунд после смены в хаосе урон не проходит
    hud           = true,   -- спидран-панель
    hudSize       = 18,
    hudX          = 40,     -- отступ от правого края
    hudY          = 30,     -- отступ сверху
    ownBars       = true,   -- свои полоски здоровья/выносливости вместо родных
    barsCenter    = true,   -- (старое) полоски по центру; теперь barsStyle
    barsStyle     = "",     -- полоски: corner (как у игры) / center / term; "" = взять из barsCenter
    uiStyle       = "game", -- окно выбора: game (как меню паузы) / term (терминал слева)
    uiAnim        = true,   -- анимации окна выбора
    gamePopups    = true,   -- всплывающие подсказки самой игры (BEGI, названия предметов...)
    lastMode      = "",     -- (старое, не используется)
    lastMut       = "",
    selBase       = "normal", -- выбранный режим: normal / stealth / nightmare
    selRokus      = 1,        -- Року в Pure stealth
    selMut        = "none",   -- none / random / chaos / id мутатора
    selLoveMin    = 8,        -- минут в Lovesick
    labUnlocked   = false,    -- лаборатория открыта секретными кликами
    -- графика (Settings -> Graphics): 0 = как у игры, иначе номер варианта (graphics.lua)
    gfxRes        = 0,
    gfxQuality    = 0,
    gfxShadows    = 0,
    gfxReflect    = 0,
    gfxFog        = 0,
    gfxAA         = 0,
    gfxFx         = 0,
    gfxFpsCap     = 0,
    gfxFpsShow    = false,    -- счётчик FPS слева сверху
}
local P = deepcopy(DEFAULTS)
local SETTINGS_PATH = ROOT .. "\\settings.txt"

local function saveSettings()
    local f = io.open(SETTINGS_PATH, "w")
    if not f then return end
    local keys = {}
    for k in pairs(DEFAULTS) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = P[k]
        if type(v) == "boolean" then v = v and "1" or "0" end
        f:write(k .. "=" .. tostring(v) .. "\n")
    end
    f:close()
end

local function loadSettings()
    local f = io.open(SETTINGS_PATH, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k and DEFAULTS[k] ~= nil then
            local d = DEFAULTS[k]
            if type(d) == "boolean" then P[k] = (v == "1" or v == "true")
            elseif type(d) == "number" then P[k] = tonumber(v) or d
            else P[k] = v end
        end
    end
    f:close()
end
loadSettings()
if P.barsStyle ~= "corner" and P.barsStyle ~= "center" and P.barsStyle ~= "term" and P.barsStyle ~= "line" then
    P.barsStyle = P.barsCenter and "center" or "corner"
end
if P.uiStyle ~= "term" and P.uiStyle ~= "min" then P.uiStyle = "game" end
VERBOSE = VERBOSE or P.labUnlocked == true

------------------------------------------------------------------------
-- Время. Своё время забега идёт по времени игры (на паузе стоит)
-- и начинается, когда игрок нажал "Старт" в окне выбора.
------------------------------------------------------------------------
local function gameNow()
    local t = nil
    local pawn = getPawn()
    pcall(function() t = num(statics():GetTimeSeconds(pawn or getPC())) end)
    return t
end

-- Року, которую мы видим меньше 3 с (времени игры), не трогаем: игра ещё собирает ей мозг
local function rokuSettled(r)
    local addr = nil
    pcall(function() addr = r:GetAddress() end)
    if not addr then return false end
    local now = gameNow() or os.clock()
    local t = ROKU_SEEN[addr]
    if not t then ROKU_SEEN[addr] = now return false end
    return now - t >= 3
end

------------------------------------------------------------------------
-- Хуки игры: внутри только флажки (правило: никаких вызовов игры в хуке)
------------------------------------------------------------------------
local PLAYER = "/Game/Variant_Horror/Blueprints/BP_HorrorCharacter.BP_HorrorCharacter_C:"
local HOOKS = {
    death   = PLAYER .. "PlayerDeath",
    victory = PLAYER .. "VICTORY",
    damage  = PLAYER .. "TakeDamage",
    pickup  = "/Game/INTERACTION/BP_ThrowableBase.BP_ThrowableBase_C:Pickup",
    throw   = "/Game/INTERACTION/BP_ThrowableBase.BP_ThrowableBase_C:Throw",
    spank   = PLAYER .. "EventSpank",
}
local pending, hooked = {}, {}

local function hookLoop()
    local left = 0
    for name, path in pairs(HOOKS) do
        if not hooked[name] then
            local ok = pcall(function()
                RegisterHook(path, function(self)
                    pending[name] = true
                    if name == "throw" then
                        -- сам брошенный предмет: только запоминаем, вызываем его потом, в игровом цикле
                        pcall(function() pending.thrownObj = self:get() end)
                    elseif name == "pickup" then
                        pcall(function() pending.pickedObj = self:get() end)
                    end
                end)
            end)
            if ok then hooked[name] = true else left = left + 1 end
        end
    end
    if left > 0 then after(3000, hookLoop) else log("Hooks ready") end
end
gameThread(hookLoop)

------------------------------------------------------------------------
-- МУТАТОРЫ
-- Каждый мутатор обязан полностью убирать за собой в off():
-- хаос и будущее смешивание держатся на этом.
--   tags  — что мутатор трогает; мутаторы с общим тегом вместе не включаются
--   fun   — "для фана": без рекордов
--   chaos — может ли выпасть в хаосе (по умолчанию да)
--   on(), off(), tick(dt) — tick раз в 0.25 с, пока забег идёт
--   event(name) — события игры (pickup, throw, damage)
------------------------------------------------------------------------
local MUT_ORDER = {}
local MUTS = {}
local function mutator(m)
    MUTS[m.id] = m
    MUT_ORDER[#MUT_ORDER + 1] = m.id
    m.state = {}
end


-- Бритвенные когти: весь урон в полтора раза больше
mutator {
    id = "razor", name = "Razor Claws", tags = { "damage" },
    desc = "Roku's hits deal 50% more damage.",
    on = function(s) s.last = nil end,
    tick = function(s)
        local p = getPawn(); if not p then return end
        local hp = num(p.health); if not hp then return end
        if s.last and hp < s.last - 0.005 then      -- удар, а не медленная потеря (кровотечение)
            local extra = (s.last - hp) * 0.5
            -- не доводим до нуля сами: смерть пусть засчитывает игра своим ударом
            hp = math.max(0.01, hp - extra)
            p.health = hp
        end
        s.last = hp
    end,
    off = function(s) s.last = nil end,
}



-- движок
local ACTIVE = {}      -- id -> true
local ACTIVE_LIST = {} -- порядок включения

local function conflicts(id)
    local m = MUTS[id]
    for aid in pairs(ACTIVE) do
        for _, t1 in ipairs(MUTS[aid].tags or {}) do
            for _, t2 in ipairs(m.tags or {}) do
                if t1 == t2 then return aid end
            end
        end
    end
    return nil
end

local function enableMut(id)
    local m = MUTS[id]
    if not m or ACTIVE[id] then return false end
    local c = conflicts(id)
    if c then log("Mutator " .. id .. " conflicts with " .. c) return false end
    m.state = {}
    if m.on then
        local ok, err = pcall(m.on, m.state)
        if not ok then log("Mutator " .. id .. " on() failed: " .. tostring(err)) end
    end
    ACTIVE[id] = true
    ACTIVE_LIST[#ACTIVE_LIST + 1] = id
    log("Mutator ON: " .. id)
    return true
end

local function disableMut(id)
    local m = MUTS[id]
    if not m or not ACTIVE[id] then return end
    if m.off then
        local ok, err = pcall(m.off, m.state)
        if not ok then log("Mutator " .. id .. " off() failed: " .. tostring(err)) end
    end
    ACTIVE[id] = nil
    for i, a in ipairs(ACTIVE_LIST) do
        if a == id then table.remove(ACTIVE_LIST, i) break end
    end
    log("Mutator OFF: " .. id)
end

local function disableAll()
    local ids = {}
    for _, id in ipairs(ACTIVE_LIST) do ids[#ids + 1] = id end
    for i = #ids, 1, -1 do disableMut(ids[i]) end
end

local function tickMuts(dt)
    for _, id in ipairs(ACTIVE_LIST) do
        local m = MUTS[id]
        if m and m.tick then
            local ok, err = pcall(m.tick, m.state, dt)
            if not ok then log("Mutator " .. id .. " tick failed: " .. tostring(err)) end
        end
    end
end

local function eventMuts(name)
    for _, id in ipairs(ACTIVE_LIST) do
        local m = MUTS[id]
        if m and m.event then pcall(m.event, m.state, name) end
    end
end

local function activeNames()
    local n = {}
    for _, id in ipairs(ACTIVE_LIST) do n[#n + 1] = MUTS[id].name end
    if #n == 0 then return "none" end
    return table.concat(n, " + ")
end

------------------------------------------------------------------------
