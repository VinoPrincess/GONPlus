-- Экраны окна выбора.
-- Забег = РЕЖИМ (правила: Normal / Pure stealth / Reactor / SUTEGOMA / Lovesick / Bashful)
-- (Nightmare с 1.1 — сложность ванильной игры, gamecfg.lua)
--       + МУТАТОР (условия: none / один / random / chaos).
-- Выбор запоминается: обычно просто жмёшь START.
------------------------------------------------------------------------
BASES = {
    { id = "normal", name = "Normal",
      desc = "The game as it is: collect the apples and get out." },
    { id = "stealth", name = "Pure stealth",
      desc = "Roku doesn't hunt you. If she SEES you - it's over. No hiding. Running and thrown items make noise." },
    { id = "reactor", name = "Reactor",
      desc = "The reactor is failing: get out before it blows. Three levels - the higher, the less time, the more blackouts and heat." },
    { id = "sutegoma", name = "SUTEGOMA",
      desc = "You are bleeding out: health slowly drains. Heal up from time to time - there are more medkits around." },
    { id = "lovesick", name = "Lovesick",
      desc = "Roku is drunk and very affectionate. Survive until she sobers up. Every hug makes you fall for her; full heart = you lose. No trash, no booze - only gifts to throw at her. Gifts and spanks cool her down." },
    { id = "shy", name = "Bashful",
      desc = "She can't see you, but she feels your gaze. She flickers in and out near you - ahead, behind, around the corner. Don't stare at her, don't come close. She never attacks." },
}
-- с Bashful не работают: вторая Року, беготня, когти, удары и укрытия (она не ходит и не бьёт)
SHY_BLOCK = { twins = true, zoomies = true, razor = true, onehit = true, nohiding = true }
-- режимы-обёртки над мутатором (1.1): Reactor — уровень реактора, SUTEGOMA — кровотечение
REACTOR_NAMES = { "Failure", "Critical failure", "Meltdown" }
function baseMutFor(base, lvl)
    if base == "reactor" then return (REACTOR_LEVELS or {})[lvl or P.selReactor or 1] or "reactor" end
    if base == "sutegoma" then return "sutegoma" end
    return nil
end
-- старые настройки: Nightmare был режимом, Reactor/SUTEGOMA — мутаторами
if P.selBase == "nightmare" then P.selBase = "normal"; P.selMut = "none"; P.gameDiff = 4 end
for i, id in ipairs({ "reactor", "critical", "meltdown" }) do
    if P.selMut == id then P.selBase, P.selMut, P.selReactor = "reactor", "none", i end
end
if P.selMut == "sutegoma" then P.selBase, P.selMut = "sutegoma", "none" end
local function baseInfo(id)
    for i, b in ipairs(BASES) do if b.id == id then return b, i end end
    return BASES[1], 1
end

-- можно ли мутатор с этим режимом
local function mutAllowed(id, base)
    local m = MUTS[id]
    if not m then return false end
    if m.modeOnly then return false end                  -- реактор, SUTEGOMA — теперь режимы
    if base == "reactor" and (id == "zerohour" or id == "heat" or id == "darkness" or id == "blackouts") then return false end
    if base == "sutegoma" and (id == "onehit" or id == "razor") then return false end
    if base == "stealth" and m.noStealth then return false end
    if base == "nightmare" and m.noNightmare then return false end
    if base == "lovesick" and not m.loveOk then return false end
    if base == "shy" and SHY_BLOCK[id] then return false end
    return true
end

MUT_OK = mutAllowed      -- для хаоса (run.lua)

-- ключ рекорда для выбора (режим + мутатор)
local function comboKey(base, rokus, mutKey)
    -- Reactor / SUTEGOMA: ключи как у прежних мутаторов (mut:meltdown...), рекорды не теряются
    local bm = baseMutFor(base)
    if bm then return "mut:" .. bm .. (mutKey and ("/" .. mutKey) or "") end
    if base == "stealth" then return "stealth:" .. tostring(rokus) .. (mutKey and ("/" .. mutKey) or "") end
    if base == "nightmare" then return "nightmare" .. (mutKey and ("/" .. mutKey) or "") end
    if base == "lovesick" then return "lovesick:" .. tostring(P.selLoveMin) .. (mutKey and ("/" .. mutKey) or "") end
    if base == "shy" then return "shy" .. (mutKey and ("/" .. mutKey) or "") end
    if not mutKey and vanillaSelKey then return vanillaSelKey() end
    return mutKey or "normal"
end

local function bestText(key, m)
    local b = key and RECORDS[key]
    if not b then return nil end
    if key:find("^lovesick") then
        if b.win then return string.format("best: TOGETHER, love %d%%", 100 - b.pines) end
        return "best: lasted " .. fmtTime(b.time)
    end
    if m and m.countdown and b.win and m.limit then return "best: " .. fmtTime(m.limit - b.time) .. " left" end
    return string.format("best: %s%d apples %s", b.win and "WIN " or "", b.pines, fmtTime(b.time))
end

local function mutLabel(id)
    local m = MUTS[id]
    local s = m.name
    local bt = bestText(comboKey(P.selBase, P.selRokus, "mut:" .. id), m)
    if not mutAllowed(id, P.selBase) then s = s .. "   not with " .. baseInfo(P.selBase).name
    elseif bt then s = s .. "   " .. bt end
    return s
end

local function selMutName()
    local s = P.selMut
    if s == "none" or s == "" then return "None" end
    if s == "random" then return "Random" end
    if s == "chaos" then return "Chaos" end
    return MUTS[s] and MUTS[s].name or "None"
end

local SCREENS = {}

-- старт выбранного забега (кнопка START; и после перезапуска уровня ради сложности)
function startSelected()
    if P.selMut == "random" then UI.screen = "random"; UI.sel = 1; UI.roll = nil
    else
        UI.close()
        if P.selMut == "chaos" then startRun("chaos")
        elseif MUTS[P.selMut] then startRun("pick", P.selMut)
        else startRun("none") end
    end
end

SCREENS.main = function()
    -- выбор мог стать неподходящим (мутатор удалён / несовместим с режимом)
    if P.selMut ~= "none" and P.selMut ~= "random" and P.selMut ~= "chaos" and not mutAllowed(P.selMut, P.selBase) then
        P.selMut = "none"
    end
    if P.selBase == "lovesick" and (P.selMut == "random" or P.selMut == "chaos") then P.selMut = "none" end
    local base = baseInfo(P.selBase)
    local items = {}
    local mutKey = (P.selMut == "chaos" and "chaos") or (MUTS[P.selMut] and ("mut:" .. P.selMut)) or nil
    local summary = base.name .. (P.selBase == "stealth" and (" (" .. P.selRokus .. " Roku)") or "")
        .. (P.selBase == "reactor" and (": " .. (REACTOR_NAMES[P.selReactor] or "")) or "")
        .. (P.selMut ~= "none" and ("  +  " .. selMutName()) or "")
    local bt = (P.selMut ~= "random") and bestText(comboKey(P.selBase, P.selRokus, mutKey),
        MUTS[P.selMut] or MUTS[baseMutFor(P.selBase) or ""]) or nil
    items[#items + 1] = { label = "Start", extra = summary .. (bt and ("   " .. bt) or ""),
        desc = "Start the run: " .. summary .. ".",
        act = function()
            -- другая сложность игры (gamecfg.lua): уровень перезапустится и забег стартует сам
            if diffGate and diffGate() then return end
            startSelected()
        end }
    items[#items + 1] = { label = "Mode: " .. base.name, extra = "click left / right side to change",
        desc = base.desc, cycle = function(dir)
            local _, i = baseInfo(P.selBase)
            P.selBase = BASES[(i - 1 + dir) % #BASES + 1].id
            saveSettings()
        end }
    if P.selBase == "lovesick" then
        items[#items + 1] = { label = "Time: " .. P.selLoveMin .. " min", extra = "survive this long",
            desc = "Last 2 minutes: she always knows where you are.",
            cycle = function(dir)
                local opts = { 4, 6, 8, 10, 12 }
                local i = 3
                for k, v in ipairs(opts) do if v == P.selLoveMin then i = k end end
                P.selLoveMin = opts[(i - 1 + dir) % #opts + 1]; saveSettings()
            end }
    end
    if P.selBase == "reactor" then
        local lv = P.selReactor or 1
        local id = baseMutFor("reactor", lv)
        items[#items + 1] = { label = "Level: " .. (REACTOR_NAMES[lv] or "?"), extra = "how bad it is",
            desc = MUTS[id] and MUTS[id].desc or "",
            cycle = function(dir) P.selReactor = ((P.selReactor or 1) - 1 + dir) % 3 + 1; saveSettings() end }
    end
    if P.selBase == "stealth" then
        items[#items + 1] = { label = "Rokus: " .. P.selRokus, extra = "1 is the default; more is harder",
            desc = P.selRokus == 1 and "One Roku wanders the whole map." or (P.selRokus .. " Rokus wander on their own. Any of them ends the run on sight."),
            cycle = function(dir) P.selRokus = (P.selRokus - 1 + dir) % 4 + 1; saveSettings() end }
    end
    items[#items + 1] = { label = "Mutator: " .. selMutName(), extra = "open the list",
        desc = P.selMut == "chaos" and string.format("A random mutator every %d s. Warning %d s before each change.", P.chaosInterval, P.chaosWarn)
            or (P.selMut == "random" and "Fate picks one mutator when you start. No rerolls.")
            or (MUTS[P.selMut] and MUTS[P.selMut].desc) or "No mutator.",
        act = function() UI.screen = "pick"; UI.sel = 1 end }
    if gameMainItems then gameMainItems(items) end   -- наряд Року, сложность (gamecfg.lua)
    items[#items + 1] = { label = "Settings", desc = "Graphics and FPS, quick start, mouse, chaos timing, speedrun panel, bars.",
        act = function() UI.screen = "settings"; UI.sel = 1 end }
    -- выход из игры сразу (раньше: забег -> пауза -> выйти -> выйти). Второй клик за 3 с — подтверждение.
    local armed = UI.quitArmed and os.clock() < UI.quitArmed
    items[#items + 1] = { label = armed and "Quit game   click again to quit" or "Quit game",
        desc = "Closes the game right away. Click twice so it can't happen by accident.",
        act = function()
            if UI.quitArmed and os.clock() < UI.quitArmed then
                log("Quit game from the GON+ menu")
                local pc = getPC()
                local ok = pcall(function()
                    StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):QuitGame(pc, pc, 0, false)
                end)
                if not ok then
                    pcall(function() StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(pc, "quit", pc) end)
                end
            else
                UI.quitArmed = os.clock() + 3
                windowNote("Click QUIT GAME again to close the game", 3)
            end
        end }
    return "NEW RUN", "Mode + mutator. Your choice is remembered.", items, "click / Enter - choose    sides / arrows - change"
end

SCREENS.pick = function()
    local items = {}
    local function choose(v) P.selMut = v; saveSettings(); UI.screen = "main"; UI.sel = 1 end
    items[1] = { label = "None", desc = "No mutator.", act = function() choose("none") end }
    if P.selBase ~= "lovesick" then
        items[2] = { label = "Random", desc = "Fate picks one mutator when you start. No rerolls.", act = function() choose("random") end }
        items[3] = { label = "Chaos", extra = bestText(comboKey(P.selBase, P.selRokus, "chaos")),
            desc = string.format("A random mutator every %d s. Warning %d s before each change.", P.chaosInterval, P.chaosWarn),
            act = function() choose("chaos") end }
    end
    for _, id in ipairs(MUT_ORDER) do
        if not MUTS[id].modeOnly then
            local ok = mutAllowed(id, P.selBase)
            items[#items + 1] = { label = mutLabel(id), desc = MUTS[id].desc,
                act = function() if ok then choose(id) else showBanner("+ NOT WITH THIS MODE +", 2) end end }
        end
    end
    return "MUTATORS", "Pick one for the run", items, "click / Enter - pick    right click / Backspace - back"
end

SCREENS.random = function()
    local items = {}
    if not UI.roll then
        -- рулетка: 1.4 с перебора, потом результат (только подходящие к режиму)
        local pool = {}
        for _, id in ipairs(MUT_ORDER) do if mutAllowed(id, P.selBase) then pool[#pool + 1] = id end end
        UI.roll = { result = pool[math.random(1, #pool)], spin = 0, done = false, shown = pool[1], pool = pool }
        local function spin()
            local r = UI.roll
            if not r or r.done or not UI.open then return end
            r.spin = r.spin + 1
            r.shown = r.pool[(r.spin % #r.pool) + 1]
            if r.spin >= 16 then r.done = true; r.shown = r.result end
            refreshUI()
            if not r.done then after(60 + r.spin * 6, spin) end
        end
        after(60, spin)
    end
    local r = UI.roll
    if not r.done and not schedulerAlive() then r.done = true; r.shown = r.result end
    local m = MUTS[r.shown]
    if r.done then
        items[1] = { label = m.name, desc = m.desc,
            act = function() UI.close(); startRun("random", r.result) end }
        return "YOUR MUTATOR", "No rerolls. Good luck.", items, "click / Enter - start"
    end
    items[1] = { label = m.name .. "   rolling...", desc = "Click or Enter - stop the wheel",
        act = function() r.done = true; r.shown = r.result end }
    return "RANDOM MUTATOR", "Rolling...", items, " "
end

-- подписи короткие (шрифт кнопок широкий), подробности — в desc под списком
local SETTING_ROWS = {
    { key = "chaosInterval", label = "Chaos interval", step = 10, min = 20, max = 600, fmt = "%d s",
      desc = "Chaos mode: how often the mutator changes." },
    { key = "chaosWarn",     label = "Chaos warning", step = 1, min = 0, max = 15, fmt = "%d s",
      desc = "Chaos mode: countdown shown before the mutator changes." },
    { key = "graceSec",      label = "Chaos safe time", step = 1, min = 0, max = 10, fmt = "%d s",
      desc = "Chaos mode: no damage for this long right after a change." },
    { key = "hud",           label = "Speedrun panel", bool = true,
      desc = "Run time, apples and splits against your best run (top right corner)." },
    { key = "hudSize",       label = "Panel size", step = 1, min = 10, max = 40, fmt = "%d",
      desc = "Speedrun panel: text size." },
    { key = "hudX",          label = "Panel position X", step = 10, min = 0, max = 1500, fmt = "%d",
      desc = "Speedrun panel: distance from the right edge of the screen." },
    { key = "hudY",          label = "Panel position Y", step = 10, min = 0, max = 1000, fmt = "%d",
      desc = "Speedrun panel: distance from the top of the screen." },
    { key = "ownBars",       label = "GON+ bars", bool = true,
      desc = "GON+ health and stamina bars instead of the game's own (they change color with modes)." },
    { key = "uiStyle",       label = "Interface", choices = { { "game", "game" }, { "term", "terminal" }, { "min", "minimal" } },
      desc = "Game: windows like the game's pause menu. Terminal: a side panel like a computer in the complex. Minimal: no window, big text like the game's main menu. Bars switch to match." },
    { key = "uiAnim",        label = "Animations", bool = true,
      desc = "Game style: pages slide up and down inside the frame. Terminal: the panel slides off the screen and comes back. Minimal: text drifts away and the new page fades in." },
    { key = "barsStyle",     label = "Bars", choices = { { "corner", "corner" }, { "center", "center" }, { "term", "terminal" }, { "line", "lines" } },
      desc = "Corner: like the game. Center: wide bars at the bottom, stamina hides when full. Terminal: thin square bars with numbers. Lines: two thin lines at the bottom." },
    { key = "gamePopups",    label = "Game pop-ups", bool = true,
      desc = "The game's own pop-up hints: +RUN+ when she chases you, item names, NOTE ACQUIRED - PAUSE TO READ. Off hides them - they clash with the modes." },
    { key = "labUnlocked",   label = "Developer lab (F1)", bool = true, only = function() return P.labUnlocked end,
      desc = "Full control over the game for testing. Runs with lab cheats don't count for records. Off hides it (7 clicks on +GON+PLUS+ bring it back)." },
}

SCREENS.settings = function()
    local items = {}
    items[1] = { label = "Graphics / FPS", extra = "open",
        desc = "Render scale, shadows, reflections, FPS limit and an FPS counter. For PCs where the game drops frames.",
        act = function() UI.screen = "graphics"; UI.sel = 1 end }
    if gameSettingsItems then gameSettingsItems(items) end   -- быстрый старт, мышь (gamecfg.lua)
    for _, r in ipairs(SETTING_ROWS) do
      if not r.only or r.only() then
        local v = P[r.key]
        local val
        if r.choices then
            val = "<  " .. tostring(v) .. "  >"
            for _, c in ipairs(r.choices) do if c[1] == v then val = "<  " .. c[2] .. "  >" end end
        elseif r.vals then val = "[" .. r.vals[v and 2 or 1] .. "]"
        elseif r.bool then val = v and "[ON]" or "[off]"
        else val = "<  " .. string.format(r.fmt, v) .. "  >" end
        items[#items + 1] = { label = r.label .. "    " .. val, setting = r,
            desc = r.desc or (r.bool and "Enter - switch" or "left/right - change") }
      end
    end
    return "SETTINGS", "GON+ v" .. VERSION .. " by " .. AUTHOR, items, "sides / arrows - change    right click / Backspace - back"
end

-- размер шрифта кнопки под длину подписи: длинная подпись не вылезает за кнопку,
-- а с подписью снизу (значение, подсказка) — чуть мельче, чтобы обе строки влезли по высоте
function fitRowFont(r, s, hasExtra, L)
    local wide = L.rowFont == "button" and 1.15 or 0.62   -- ширина буквы в долях размера
    local avail = L.rowW - 58
    local size = math.floor(avail / (math.max(1, #s) * wide))
    -- терминал: один размер у всех строк (с подписью и без), иначе строки "прыгают"
    size = math.min(size, (hasExtra or L.term or L.uniform) and (L.rowSize - 6) or L.rowSize)
    size = math.max(size, 12)
    if r.fontSize ~= size then
        r.fontSize = size
        setFont(r.main, L.rowFont, size)
    end
end

-- заголовок в стиле игры: "+ PAUSED +"
local function gameTitle(s)
    s = tostring(s or ""):upper():gsub("^%+%s*", ""):gsub("%s*%+$", "")
    return "+  " .. s .. "  +"
end

-- "Fragile   best: 3 pines 01:23" -> "FRAGILE" + мелкая строка "best: 3 pines 01:23"
local function splitLabel(label)
    local main, extra = tostring(label):match("^(.-)%s%s%s+(.+)$")
    if not main then main, extra = tostring(label), "" end
    main = main:gsub("^%s+", ""):gsub("%s+$", "")
    return main:upper(), extra
end

-- прокрутка списка окна (в единицах окна)
function menuMaxScroll()
    local v = UI.view; if not v or not v.L or not v.listH then return 0 end
    local content = #(UI.items or {}) * v.L.rowStep - (v.L.rowStep - v.L.rowH)
    return math.max(0, content - v.listH)
end
function menuSetScroll(px)
    local v = UI.view; if not v or not v.sbox then return end
    px = math.max(0, math.min(px, menuMaxScroll()))
    UI.scrollPx = px
    pcall(function() v.sbox:SetScrollOffset(px) end)
end
-- после прокрутки колёсиком/полосой: выбор остаётся на видимой целиком кнопке
function menuClampSel()
    local v = UI.view; if not v or not v.L then return end
    local L, cur = v.L, UI.scrollPx or 0
    local first = math.ceil(cur / L.rowStep - 0.001) + 1
    local last = math.floor((cur + v.listH - L.rowH) / L.rowStep + 0.001) + 1
    if last < first then last = first end
    if UI.sel < first then UI.sel = first end
    if UI.sel > last then UI.sel = math.max(1, last) end
    if UI.sel > #UI.items then UI.sel = #UI.items end
end

-- у пункта есть "листать": стрелки по краям кнопки
function rowHasArrows(it)
    if not it then return false end
    if it.cycle then return true end
    local s = it.setting
    return s ~= nil and not s.bool
end
-- где мышь по ширине кнопки: -1 левая стрелка, 1 правая, 0 середина (x — от левого края кнопки)
function arrowZoneAt(L, x)
    local z = ARROW_ZONE or 64
    if L.left then
        if x >= L.rowW - z then return 1 end
        if x >= L.rowW - 2 * z then return -1 end
        return 0
    end
    if x <= z then return -1 end
    if x >= L.rowW - z then return 1 end
    return 0
end

function canGoBack()
    return UI.kind == "lab" or UI.screen == "pick" or UI.screen == "settings" or UI.screen == "graphics"
end

------------------------------------------------------------------------
-- Анимации окна выбора (Settings -> Animations)
--   стиль игры: страница внутри рамки уезжает вверх/вниз, новая въезжает с другой стороны
--   терминал:   вся панель уезжает за левый край и возвращается уже с новым экраном
-- Смена экрана = две фазы: "out" (старое уезжает, содержимое не трогаем) и "in" (новое въезжает).
-- Любая клавиша/клик во время "out" сразу доводит анимацию до конца — ввод не теряется.
------------------------------------------------------------------------
; (function()
local OUT, IN, OPEN, CLOSE = 0.11, 0.17, 0.22, 0.16   -- секунды
local SLIDE = 70                                     -- на сколько едет страница в стиле игры
local DEPTH = { main = 0, pick = 1, settings = 1, random = 1, graphics = 2 }

local function now()
    local t = nil
    pcall(function() t = num(statics():GetRealTimeSeconds(getPC())) end)
    return t or os.clock()
end
local function easeOut(k) k = 1 - k; return 1 - k * k * k end
local function easeIn(k) return k * k * k end

local function setT(w, x, y) if valid(w) then pcall(function() w:SetRenderTranslation({ X = x, Y = y }) end) end end
local function setO(w, a) if valid(w) then pcall(function() w:SetRenderOpacity(a) end) end end

local function reset()
    for _, v in pairs(UI.views or {}) do
        setT(v.panel, 0, 0); setO(v.panel, 1)
        setT(v.cv, 0, 0); setO(v.cv, 1)
    end
end

-- как выглядит окно при прогрессе k (0..1) текущей фазы
local function apply(a, k)
    local v = UI.view; if not v or not v.L then return end
    local term = v.L.term
    if term then
        local off = -(v.L.w + 40)
        if a.phase == "out" or a.phase == "close" then setT(v.panel, off * easeIn(k), 0)
        else setT(v.panel, off * (1 - easeOut(k)), 0) end
        return
    end
    -- минимал: текст уплывает влево и гаснет, новый проявляется справа (вперёд) / слева (назад)
    local mx, my = 0, 1
    if v.L.minimal then mx, my = 1, 0 end
    local dist = v.L.minimal and 50 or SLIDE
    if a.phase == "out" then
        local d = -a.dir * dist * easeIn(k)
        setT(v.cv, d * mx, d * my); setO(v.cv, 1 - k)
    elseif a.phase == "in" then
        local d = a.dir * dist * (1 - easeOut(k))
        setT(v.cv, d * mx, d * my); setO(v.cv, k)
        if a.open then setO(v.panel, math.min(1, k * 1.6)) end
    elseif a.phase == "close" then
        setO(v.panel, 1 - k)
    end
end

local function enabled() return P.uiAnim and UI.kind ~= "lab" end

-- вызывается из refreshUI: true = содержимое сейчас не обновлять (старое ещё уезжает)
function menuAnimGate()
    local key = UI.kind .. ":" .. UI.screen
    local prev = UI.animKey
    if prev == key then return UI.anim ~= nil and UI.anim.phase == "out" end
    UI.animKey = key
    if not enabled() or (prev and prev:find("^lab")) then UI.anim = nil; reset() return false end
    if prev == nil then
        UI.anim = { phase = "in", t0 = now(), dir = 1, open = true }
        apply(UI.anim, 0)
        return false
    end
    if UI.anim and UI.anim.phase == "out" then return true end   -- уже уезжает: приедет новое
    local a, b = prev:match(":(.*)$"), UI.screen
    UI.anim = { phase = "out", t0 = now(), dir = ((DEPTH[b] or 1) >= (DEPTH[a] or 0)) and 1 or -1 }
    apply(UI.anim, 0)
    return true
end

-- закрытие окна: true = панель пока не прятать (уезжает/гаснет)
function menuAnimClose()
    UI.animKey = nil
    if not enabled() or not UI.view or not UI.view.L then UI.anim = nil; reset() return false end
    UI.anim = { phase = "close", t0 = now(), dir = 1 }
    return true
end
function menuAnimClosing() return UI.anim ~= nil and UI.anim.phase == "close" end

-- ввод во время анимации: довести до конца сразу
function menuAnimSkip()
    local a = UI.anim
    if not a or a.phase == "close" then return end
    UI.anim = nil
    reset()
    if a.phase == "out" then refreshUI() end
end
function menuAnimBusy() return UI.anim ~= nil end

every(10, function()
    local a = UI.anim; if not a then return end
    local dur = a.phase == "out" and OUT or (a.phase == "close" and CLOSE or (a.open and OPEN or IN))
    local k = (now() - a.t0) / dur
    if k < 1 then apply(a, math.max(0, k)) return end
    if a.phase == "out" then
        UI.anim = { phase = "in", t0 = now(), dir = a.dir }
        apply(UI.anim, 0)
        refreshUI()                 -- теперь новое содержимое
    elseif a.phase == "close" then
        UI.anim = nil
        reset()
        refreshUI()                 -- спрятать окно
    else
        UI.anim = nil
        reset()
    end
end)
end)()

refreshUI = function()
    if not valid(UI.widget) then return end
    -- окно
    if UI.open then
        local title, sub, items, foot = SCREENS[UI.screen]()
        local game = UI.kind ~= "lab"
        useView(game and (P.uiStyle == "term" and "term" or (P.uiStyle == "min" and "min" or "game")) or "lab")
        if menuAnimGate() then goto content_done end
        local term = UI.view.L and UI.view.L.term
        local minimal = UI.view.L and UI.view.L.minimal
        local T = (UI.view.L and UI.view.L.theme) or {}
        -- затемнение под окном: у минимала сильнее (окна нет)
        local dimC = T.dim or GAME.dim
        if UI.dimC ~= dimC and valid(UI.dim) then UI.dimC = dimC; pcall(function() UI.dim:SetColorAndOpacity(dimC) end) end
        if minimal then
            -- "+NEW+RUN+" как "+GOD+OF+NOTHING+"
            title = "+" .. tostring(title or ""):upper():gsub("^%+%s*", ""):gsub("%s*%+$", ""):gsub("%s+", "+") .. "+"
        elseif term then
            title = tostring(title or ""):upper():gsub("^%+%s*", ""):gsub("%s*%+$", "")
        else
            title = gameTitle(title)
        end
        UI.items = items
        if UI.sel > #items then UI.sel = #items end
        if UI.sel < 1 then UI.sel = 1 end
        if UI.note then sub = UI.note end
        setText(UI.title, title); setText(UI.sub, sub); setText(UI.foot, foot)
        local rows = UI.view.rows
        local n = #rows
        local off = 0
        local v = UI.view
        local L = v.L
        -- прокрутка в пикселях (ScrollBox): новый экран — с начала;
        -- выбор стрелками — список подъезжает, чтобы выбранная кнопка была видна целиком
        if L and v.sbox then
            if UI.offScreen ~= UI.screen or UI.offKind ~= UI.kind then
                UI.offScreen, UI.offKind = UI.screen, UI.kind
                menuSetScroll(0)
            end
            if UI.ensureSel then
                UI.ensureSel = false
                local top = (UI.sel - 1) * L.rowStep
                local cur = UI.scrollPx or 0
                if top < cur then menuSetScroll(top)
                elseif top + L.rowH > cur + v.listH then menuSetScroll(top + L.rowH - v.listH) end
            end
            off = UI.scrollPx or 0
        end
        -- полоса прокрутки: видна, только если список длиннее окна
        if v.sb and L then
            local sb = v.sb
            local maxOff = menuMaxScroll()
            local long = maxOff > 0
            v.sbLong = long
            sb.track:SetVisibility(long and VIS_SHOW or VIS_HIDE)
            sb.thumb:SetVisibility(long and VIS_SHOW or VIS_HIDE)
            if long then
                local th = math.max(36, math.floor(sb.h * v.listH / (v.listH + maxOff)))
                local ty = sb.y + math.floor((sb.h - th) * math.min(1, off / maxOff) + 0.5)
                sb.thumbH = th
                pcall(function() sb.thumbSlot:SetPosition({ X = sb.x, Y = ty }); sb.thumbSlot:SetSize({ X = sb.w, Y = th }) end)
            end
        end
        -- кнопка "назад": где есть куда возвращаться
        if v.back then
            local can = canGoBack()
            v.back.pill:SetVisibility(can and VIS_SHOW or VIS_HIDE)
            if can then
                setText(v.back.text, UI.kind == "lab" and "CLOSE" or "BACK")
                local hot = UI.backHot == true
                pcall(function() v.back.pill:SetBrushColor(hot and (T.pillOn or GAME.pillOn) or (T.pillOff or GAME.pillOff)) end)
                setColor(v.back.text, hot and (T.sel or GAME.blue) or (T.idle or GAME.idle))
            end
        end
        for i = 1, n do
            local idx = UI.view.L and i or (i + off)
            local r, it = rows[i], items[idx]
            if UI.view.L then
                if it then
                    r.box:SetVisibility(VIS_SHOW)
                    local main, extra = splitLabel(it.label)
                    if it.extra then extra = it.extra end
                    local on = idx == UI.sel
                    -- стрелки по краям: у пунктов, которые листаются
                    local arrows = rowHasArrows(it)
                    if arrows then
                        -- "<  game  >" в подписи больше не нужен: стрелки уже на кнопке
                        extra = extra:gsub("^<%s*", ""):gsub("%s*>$", "")
                        if extra == "click left / right side to change" then extra = "" end
                    end
                    if r.arrowL then
                        local hz = on and UI.hoverZone or 0
                        for side, a in pairs({ [-1] = r.arrowL, [1] = r.arrowR }) do
                            a:SetVisibility(arrows and VIS_SHOW or VIS_HIDE)
                            if arrows then
                                local hot = hz == side
                                setColor(a, hot and (T.sel or GAME.blue) or (on and (T.idle or GAME.idle) or { R = 1, G = 1, B = 1, A = 0.3 }))
                                pcall(function() a:SetRenderScale({ X = hot and 1.35 or 1, Y = hot and 1.35 or 1 }) end)
                            end
                        end
                    end
                    -- выбранная кнопка: синий текст в плюсах, синеватая заливка
                    -- в терминале: "> ПУНКТ" белым на синей подсветке
                    local shown
                    if term then shown = (on and "> " or "  ") .. main
                    elseif minimal then shown = on and ("— " .. main) or main
                    else shown = on and ("+ " .. main .. " +") or main end
                    fitRowFont(r, shown, extra ~= "", UI.view.L)
                    setText(r.main, shown)
                    setColor(r.main, on and (T.sel or GAME.blue) or (T.idle or GAME.idle))
                    pcall(function() r.pill:SetBrushColor(on and (T.pillOn or GAME.pillOn) or (T.pillOff or GAME.pillOff)) end)
                    setText(r.extra, extra)
                    r.extra:SetVisibility(extra ~= "" and VIS_SHOW or VIS_HIDE)
                else
                    r.box:SetVisibility(VIS_HIDE)
                end
            elseif valid(r) then
                if it then
                    r:SetVisibility(VIS_SHOW)
                    setText(r, (idx == UI.sel and ">> " or "    ") .. it.label)
                    setColor(r, idx == UI.sel and COL.sel or COL.text)
                else
                    r:SetVisibility(VIS_HIDE)
                end
            end
        end
        local cur = items[UI.sel]
        setText(UI.desc, cur and cur.desc or "")
        ::content_done::
    end
    if not UI.view then useView("game") end
    -- окно ловит мышь (Visible): тогда колёсико и нажатия доходят до нашего виджета
    -- (закрывается с анимацией — пока видно, но мышь уже не ловит)
    local closing = not UI.open and menuAnimClosing()
    if valid(UI.panel) then UI.panel:SetVisibility(UI.open and 0 or (closing and 3 or VIS_HIDE)) end
    if valid(UI.dim) then UI.dim:SetVisibility(((UI.open or closing) and UI.kind ~= "lab") and VIS_SHOW or VIS_HIDE) end
end

openChooser = function()
    if not ensureUI() then return end
    UI.open, UI.screen, UI.sel, UI.roll, UI.kind = true, "main", 1, nil, "chooser"
    applyPause()
    refreshUI()
end

UI.close = function()
    menuAnimClose()
    UI.open = false
    UI.roll = nil
    applyPause()
    refreshUI()
end

local function changeSetting(r, dir)
    if r.choices then
        local n, cur = #r.choices, 1
        for i, c in ipairs(r.choices) do if c[1] == P[r.key] then cur = i end end
        P[r.key] = r.choices[(cur - 1 + (dir or 1)) % n + 1][1]
        -- стиль окна тянет за собой полоски (потом их можно поменять отдельно)
        if r.key == "uiStyle" then
            if P.uiStyle == "term" then P.barsStyle = "term"
            elseif P.uiStyle == "min" then P.barsStyle = "line"
            elseif P.barsStyle == "term" or P.barsStyle == "line" then P.barsStyle = "center" end
        end
    elseif r.bool then P[r.key] = not P[r.key]
    else
        local v = P[r.key] + dir * r.step
        P[r.key] = math.max(r.min, math.min(r.max, v))
    end
    saveSettings()
    P.barsCenter = P.barsStyle == "center"
    if (r.key == "barsStyle" or r.key == "uiStyle") and layoutBars then layoutBars() end
    if r.key == "labUnlocked" then VERBOSE = P.labUnlocked == true end
    -- размер и место панели применяем сразу
    if UI.hudSlot then pcall(function() UI.hudSlot:SetPosition({ X = -P.hudX, Y = P.hudY }) end) end
    for k, t in pairs(UI.hudLines) do
        local st = HUD_STYLE[k]
        if st and valid(t) then setFont(t, st.font, math.floor(st.size * P.hudSize / 18 + 0.5)) end
    end
end

------------------------------------------------------------------------
