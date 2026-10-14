--[[
  GON+ — режимы, мутаторы и рекорды для GON: God of Nothing (UE4SS, Lua)

  Читов нет: игрок только выбирает режим, мутатор и настраивает интерфейс.
  Окно выбора открывается в начале каждого забега (мышь или стрелки + Enter).

  Этот файл — только загрузчик. Код лежит в Scripts\gonplus\ по разделам:
    core        версия, служебное, планировщик, настройки, время, хуки, движок мутаторов
    run         рекорды и забег (старт, конец, новый персонаж)
    ui          виджет окна, стиль, полоски, пауза
    menu        экраны окна выбора (главный, мутаторы, настройки)
    hud         спидран-панель, главный цикл, всплывающие надписи
    input       клавиши и мышь в окне
    lab         лаборатория F1 (открывается 7 кликами по "+GON+PLUS+")
    labfun      вкладки лаборатории: игрок, Року, чувства, предметы, мир (бывший FunMenu)
    stealth     режим Pure Stealth
    endscreens  экраны поражения и победы
    darkness    настоящая темнота (лампы, небо, тени, виньетка) для Nightmare и реактора
    graphics    Settings -> Graphics: разрешение рендера, тени, отражения, лимит и счётчик FPS
    mutators    мутаторы игрока
    nightmare   режим Nightmare
    lovesick    режим Lovesick
    finish      последние хвосты и сообщение "Loaded"

  Файлы склеиваются в один кусок кода по порядку из FILES: local из раннего
  файла видны в поздних (как будто это один большой файл). Ошибки в логе
  показываются как "имя.lua:строка".
]]

local FILES = { "core", "run", "ui", "menu", "hud", "input", "lab", "labfun", "stealth",
                "endscreens", "darkness", "graphics", "mutators", "nightmare", "lovesick", "finish" }

local function say(m) print("[GON+] " .. tostring(m) .. "\n") end

local self = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
local scripts = self:match("^(.*)[/\\][^/\\]+$") or "."
GONPLUS_ROOT = (scripts:gsub("/", "\\"):match("^(.*)\\[Ss]cripts$")) or "."

local parts, map, line = {}, {}, 1
for _, name in ipairs(FILES) do
    local f = io.open(scripts .. "/gonplus/" .. name .. ".lua", "r")
    if not f then say("FAILED: missing file Scripts\\gonplus\\" .. name .. ".lua - reinstall the mod") return end
    local s = f:read("a"); f:close()
    s = s:gsub("^\239\187\191", "")            -- BOM, если редактор добавил
    if s:sub(-1) ~= "\n" then s = s .. "\n" end
    local n = select(2, s:gsub("\n", ""))
    map[#map + 1] = { first = line, last = line + n - 1, name = name }
    parts[#parts + 1] = s
    line = line + n
end

local function where(l)
    for _, m in ipairs(map) do
        if l >= m.first and l <= m.last then return m.name .. ".lua:" .. (l - m.first + 1) end
    end
    return "?:" .. l
end
GONPLUS_WHERE = function(msg)
    return (tostring(msg):gsub("GONPlus:(%d+):", function(l) return where(tonumber(l)) .. ":" end))
end

local chunk, err = load(table.concat(parts), "=GONPlus")
if not chunk then say("FAILED to load: " .. GONPLUS_WHERE(err)) return end
local ok, e = xpcall(chunk, debug.traceback)
if not ok then say("FAILED to start: " .. GONPLUS_WHERE(e)) end
