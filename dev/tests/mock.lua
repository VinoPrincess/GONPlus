--[[
  GON+ — заглушки UE4SS для проверки мода без игры.
  Не знают смысла переменных игры: ловят синтаксис, ошибки Lua, логику меню и режимов.
  Использование (из теста):  dofile(TESTS .. "/mock.lua");  LOAD(MOD);  ... check(cond, "что проверяем") ...;  DONE()
]]
ITEMPOS = { X = 1000, Y = 0, Z = 100 }
BBLOC = { X = 0, Y = 0, Z = 10000 }
DETECT = false
VENT_ACTIVE = false
SIM_NOW = 0
os.clock = function() return SIM_NOW / 1000 end
VEL = { X = 0, Y = 0, Z = 0 }
-- Заглушки UE4SS для GON+: время игры, пауза, персонаж, Року, шишки
local mt = {}
local function M(name) return setmetatable({ __n = name }, mt) end

GAME_T, PAUSED = 100.0, false
PAWN_ADDR = 1
PAWN = { health = 1.0, pinecollected = 0, IsMaskOn = false, CharacterMovement = { GravityScale = 1.0 } }
ROKU = { CustomTimeDilation = 1.0 }
TEXTS = {}

mt.__index = function(t, k)
    if k == "IsValid" then return function() return true end end
    if k == "GetAddress" then return function() return tostring(t) end end
    if k == "GetTimeSeconds" then return function() return GAME_T end end
    if k == "SetGamePaused" then return function(_, _, v) PAUSED = v; print("  [pause=" .. tostring(v) .. "]") end end
    if k == "SetText" then return function(self, s) TEXTS[self] = s end end
    if k == "Font" then return { Size = 10 } end
    if k == "Pawn" then return PAWN_OBJ end
    if k == "GetFullName" then return function() return "Mock_" .. t.__n end end
    if k == "GetVelocity" then return function() return VEL end end
    if k == "K2_GetComponentLocation" then return function() return { X = ITEMPOS.X, Y = ITEMPOS.Y, Z = ITEMPOS.Z } end end
    if k == "bIsActive" then return VENT_ACTIVE end
    if k == "GetValueAsVector" then return function() return BBLOC end end
    if k == "GetValueAsBool" then return function(_, n) if tostring(n) == "bPlayerDetected" then return DETECT end return false end end
    if k == "SetValueAsVector" then return function(_, n, v) BB_SET = (BB_SET or "") .. n .. ";" end end
    if k == "MoveSpeed" then return 150.0 end
    if k == "chasespeed" then return 480.0 end
    if k == "CharacterMovement" then CM = CM or setmetatable({ MaxWalkSpeed = 150.0 }, { __index = function() return nil end }); return CM end
    if k == "PlayAnimMontage" then return function() LOOKS = (LOOKS or 0) + 1 end end
    if k == "K2_GetActorLocation" then return function() return { X = 1000 + math.random(0, 5), Y = 0, Z = 0 } end end
    if k == "GetActorForwardVector" then return function() return { X = -1, Y = 0, Z = 0 } end end
    if k == "GetCameraLocation" then return function() return { X = 0, Y = 0, Z = 60 } end end
    if k == "MoveToLocation" then return function() MOVES = (MOVES or 0) + 1; return 1 end end
    if k == "LineTraceSingle" then return function() return false end end
    if k == "DoesSocketExist" then return function() return true end end
    if k == "GetSocketLocation" then return function() return { X = 1000, Y = 0, Z = 170 } end end
    if k == "GetSocketRotation" then return function() return { Pitch = 0, Yaw = 170, Roll = 0 } end end
    if k == "GetActorEyesViewPoint" then return function(_, l, r) l.X, l.Y, l.Z = 1000, 0, 160; r.Pitch, r.Yaw, r.Roll = 0, 180, 0 end end
    if k == "ForEach" then return function(_, fn) for i = 1, 3 do fn(i, { get = function() return M("wp" .. i) end }) end end end
    if k == "StopLogic" then return function() BRAIN_OFF = true end end
    if k == "RestartLogic" then return function() BRAIN_OFF = false end end
    local m = M(t.__n .. "." .. k)
    rawset(t, k, m)
    return m
end
mt.__call = function(self) return M(self.__n .. "()") end

-- персонаж: обычная таблица, но с IsValid/GetAddress
PAWN_OBJ = setmetatable(PAWN, { __index = function(t, k)
    if k == "IsValid" then return function() return PAWN_ALIVE end end
    if k == "GetAddress" then return function() return PAWN_ADDR end end
    return M("pawn")[k]
end })
PAWN.CharacterMovement = setmetatable(PAWN.CharacterMovement, { __index = function() return nil end })
PAWN_ALIVE = true
ROKU.MoveSpeed, ROKU.chasespeed = 150.0, 480.0
ROKU.CharacterMovement = { MaxWalkSpeed = 150.0 }
ROKU_M = M("roku")
ROKU_OBJ = setmetatable(ROKU, { __index = function(t, k)
    if k == "IsValid" then return function() return true end end
    if k == "GetAddress" then return function() return "roku1" end end
    return ROKU_M[k]
end })

Key = setmetatable({}, { __index = function(_, k) return k end })
FText = function(s) return s end
FName = function(s) return s end
FindFirstOf = function(n)
    if n == "BP_Rokuv3_C" then return ROKU_OBJ end
    return M(n)
end
FindAllOf = function(n)
    if n == "BP_Rokuv3_C" then return { ROKU_OBJ } end
    WORLD = WORLD or {}
    WORLD[n] = WORLD[n] or M(n)
    return { WORLD[n] }
end
StaticFindObject = function(n) return M(n) end
StaticConstructObject = function() return M("obj") end

local now, queue, loops, binds = 0, {}, {}, {}
HOOKS = {}
ExecuteInGameThread = function(fn) fn() end
ExecuteWithDelay = function(ms, fn) queue[#queue + 1] = { at = now + ms, fn = fn } end
LoopAsync = function(ms, fn) loops[#loops + 1] = { every = ms, next = now + ms, fn = fn } end
LoopInGameThreadWithDelay = function(ms, fn) loops[#loops + 1] = { every = ms, next = now + ms, fn = fn } end
function KILL_LOOPS() for i = #loops, 1, -1 do loops[i] = nil end end
RegisterKeyBind = function(k, fn) binds[k] = fn end
RegisterHook = function(p, fn) HOOKS[p:match(":(%w+)$")] = fn end

function run(ms)
    local stop = now + ms
    while now < stop do
        now = now + 1
        SIM_NOW = now
        if not PAUSED then GAME_T = GAME_T + 0.001 end
        for _, l in ipairs(loops) do if now >= l.next then l.next = now + l.every; l.fn() end end
        local i = 1
        while i <= #queue do
            if queue[i].at <= now then local q = table.remove(queue, i); q.fn() else i = i + 1 end
        end
    end
end
function key(k) binds[k](); run(30) end
function hudTexts()
    local out = {}
    for _, s in pairs(TEXTS) do out[#out + 1] = s end
    table.sort(out)
    return out
end
function hasText(pat)
    for _, s in pairs(TEXTS) do if tostring(s):find(pat) then return s end end
    return nil
end

PAWN.bIsHiding = false
ROKU.bPlayerInVisionBox, ROKU.bLineTraceHitPlayer = false, false
CALLS = {}
local pm = getmetatable(PAWN_OBJ).__index
getmetatable(PAWN_OBJ).__index = function(t, k)
    if k == "PlayerDeath" then return function() CALLS[#CALLS+1] = "PlayerDeath"; PAWN_ADDR = PAWN_ADDR + 1; PAWN.bIsHiding = false end end
    if k == "K2_GetActorLocation" then return function() return { X = 0, Y = 0, Z = 0 } end end
    return pm(t, k)
end
local rm = getmetatable(ROKU_OBJ).__index
getmetatable(ROKU_OBJ).__index = function(t, k)
    if k == "K2_SetActorRotation" then return function(_, r) CALLS[#CALLS+1] = string.format("RokuRot yaw=%.0f", r.Yaw) end end
    if k == "PlayAnimMontage" then return function(_, m) CALLS[#CALLS+1] = "Montage " .. tostring(m.__n) end end
    return rm(t, k)
end

-- контроллер Року управляет самой Року (как в игре): aiCtrl() проверяет c.Pawn
do
    local old = getmetatable(ROKU_OBJ).__index
    local CTRL = setmetatable({ __n = "AIC_Roku" }, { __index = function(t, k)
        if k == "Pawn" then return ROKU_OBJ end
        if k == "GetAddress" then return function() return "ctrl1" end end
        return old(ROKU_OBJ, k)
    end })
    getmetatable(ROKU_OBJ).__index = function(t, k)
        if k == "Controller" then return CTRL end
        return old(t, k)
    end
end

-- ScrollBox хранит сдвиг (колёсико крутит его сам)
SBOXES = {}
do
    local sco = StaticConstructObject
    StaticConstructObject = function(cls, ...)
        local o = sco(cls, ...)
        if cls and tostring(rawget(cls, "__n")):find("ScrollBox") then
            SBOXES[#SBOXES + 1] = o
            rawset(o, "off", 0)
            rawset(o, "GetScrollOffset", function(self) return self.off end)
            rawset(o, "SetScrollOffset", function(self, v) self.off = v end)
        end
        return o
    end
end
function WHEEL(px) for _, s in ipairs(SBOXES) do s.off = math.max(0, s.off + px) end run(80) end

-- лог мода собираем (и показываем, если TEST_VERBOSE=1)
LOGS = {}
do
    local realPrint = print
    local loud = os.getenv("TEST_VERBOSE") == "1"
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        local s = table.concat(parts, "\t"):gsub("\n$", "")
        LOGS[#LOGS + 1] = s
        if loud then realPrint(s) end
    end
    REAL_PRINT = realPrint
end
function logHas(pat) for _, s in ipairs(LOGS) do if s:find(pat) then return s end end end
function logCount(pat) local n = 0 for _, s in ipairs(LOGS) do if s:find(pat) then n = n + 1 end end return n end

-- запуск мода: подробный лог (как при открытой лаборатории), чистые настройки и рекорды
function LOAD(mainPath, settings)
    for _, f in ipairs({ "\\home\\claude\\GONPlus\\settings.txt", "\\home\\claude\\GONPlus\\records.txt" }) do os.remove(f) end
    local root = mainPath:gsub("/", "\\"):match("^(.*)\\[Ss]cripts\\[^\\]+$") or "."
    SETTINGS_FILE = root .. "\\settings.txt"
    local f = io.open(SETTINGS_FILE, "w")
    f:write(settings or "labUnlocked=1\n")
    f:close()
    dofile(mainPath)
end

-- помощники по меню
function SEL() for _, t in pairs(TEXTS) do t = tostring(t); if t:find("^%+ [A-Z]") and not t:find("NOTICE") and not t:find("OOPS") then return t end end end
function has(exact) for _, t in pairs(TEXTS) do if tostring(t) == exact then return true end end end
function goto_(label) for _ = 1, 40 do if has("+ " .. label .. " +") then return true end key("DOWN_ARROW") end error("no menu item: " .. label) end
function TITLE() return hasText("^%+  ") end

-- проверки
local passed, failed = 0, {}
function check(cond, what)
    if cond then passed = passed + 1 else failed[#failed + 1] = what end
end
function DONE(name)
    local errs = logCount("[Ee]rror") + logCount("FAILED")
    if errs > 0 then failed[#failed + 1] = errs .. " error line(s) in the mod log, e.g.: " .. tostring(logHas("[Ee]rror") or logHas("FAILED")) end
    if #failed == 0 then
        REAL_PRINT(string.format("PASS  %-12s %d checks", name, passed))
        os.exit(0)
    else
        REAL_PRINT(string.format("FAIL  %-12s %d ok, %d failed:", name, passed, #failed))
        for _, f in ipairs(failed) do REAL_PRINT("        - " .. f) end
        os.exit(1)
    end
end

-- где стоит Року (тест двигает её, чтобы подойти/уйти)
ROKU_POS = { X = 1000, Y = 0, Z = 0 }
do
    local old = getmetatable(ROKU_OBJ).__index
    getmetatable(ROKU_OBJ).__index = function(t, k)
        if k == "K2_GetActorLocation" then return function() return { X = ROKU_POS.X, Y = ROKU_POS.Y, Z = ROKU_POS.Z } end end
        return old(t, k)
    end
end
function SEES(on) ROKU.bPlayerInVisionBox, ROKU.bLineTraceHitPlayer = on, on end

-- выбрать режим в окне выбора: "NORMAL", "PURE STEALTH", "LOVESICK", "NIGHTMARE"
function setMode(name)
    goto_("MODE: NORMAL")                         -- выбранная строка рисуется "+ ... +"
    for _ = 1, 6 do
        if has("+ MODE: " .. name .. " +") then return true end
        key("RIGHT_ARROW")
    end
    error("mode not found: " .. name)
end
function startRun() goto_("START"); key("RETURN"); run(2000) end
