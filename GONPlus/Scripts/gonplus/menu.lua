-- Экраны окна выбора.
-- Забег = РЕЖИМ (правила: Normal / Pure stealth / Nightmare)
--       + МУТАТОР (условия: none / один / random / chaos).
-- Выбор запоминается: обычно просто жмёшь START.
------------------------------------------------------------------------
BASES = {
    { id = "normal", name = "Normal",
      desc = "The game as it is: collect the apples and get out." },
    { id = "stealth", name = "Pure stealth",
      desc = "Roku doesn't hunt you. If she SEES you - it's over. No hiding. Running and thrown items make noise." },
    { id = "lovesick", name = "Lovesick",
      desc = "Roku is drunk and very affectionate. Survive until she sobers up. Every hug makes you fall for her; full heart = you lose. No trash, no booze - only gifts to throw at her. Gifts and spanks cool her down." },
    { id = "nightmare", name = "Nightmare",
      desc = "Almost impossible. No HUD, lights out, one hit kills, no hiding spots, only a little trash and skulls to throw. She hears you run." },
}
local function baseInfo(id)
    for i, b in ipairs(BASES) do if b.id == id then return b, i end end
    return BASES[1], 1
end

-- можно ли мутатор с этим режимом
local function mutAllowed(id, base)
    local m = MUTS[id]
    if not m then return false end
    if base == "stealth" and m.noStealth then return false end
    if base == "nightmare" and m.noNightmare then return false end
    if base == "lovesick" and not m.loveOk then return false end
    return true
end

-- ключ рекорда для выбора (режим + мутатор)
local function comboKey(base, rokus, mutKey)
    if base == "stealth" then return "stealth:" .. tostring(rokus) .. (mutKey and ("/" .. mutKey) or "") end
    if base == "nightmare" then return "nightmare" .. (mutKey and ("/" .. mutKey) or "") end
    if base == "lovesick" then return "lovesick:" .. tostring(P.selLoveMin) .. (mutKey and ("/" .. mutKey) or "") end
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
        .. (P.selMut ~= "none" and ("  +  " .. selMutName()) or "")
    local bt = (P.selMut ~= "random") and bestText(comboKey(P.selBase, P.selRokus, mutKey), MUTS[P.selMut]) or nil
    items[#items + 1] = { label = "Start", extra = summary .. (bt and ("   " .. bt) or ""),
        desc = "Start the run: " .. summary .. ".",
        act = function()
            if P.selMut == "random" then UI.screen = "random"; UI.sel = 1; UI.roll = nil
            else
                UI.close()
                if P.selMut == "chaos" then startRun("chaos")
                elseif MUTS[P.selMut] then startRun("pick", P.selMut)
                else startRun("none") end
            end
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
    items[#items + 1] = { label = "Settings", desc = "Graphics and FPS, chaos timing, speedrun panel, bars.",
        act = function() UI.screen = "settings"; UI.sel = 1 end }
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
    -- три уровня реактора — одна строка: стрелки / края кнопки меняют уровень, Enter / середина — выбрать
    local lv = REACTOR_LEVELS or {}
    local isLv = {}
    for i, id in ipairs(lv) do isLv[id] = i end
    if UI.reactorFor ~= P.selMut then                 -- уровень по умолчанию = уже выбранный
        UI.reactorFor = P.selMut
        if isLv[P.selMut] then UI.reactorLvl = isLv[P.selMut] end
    end
    UI.reactorLvl = UI.reactorLvl or 1
    local reactorShown = false
    for _, id in ipairs(MUT_ORDER) do
        if isLv[id] then
            if not reactorShown and MUTS[lv[UI.reactorLvl]] then
                reactorShown = true
                local cur = lv[UI.reactorLvl]
                local ok = mutAllowed(cur, P.selBase)
                local short = ({ reactor = "Failure", critical = "Critical failure", meltdown = "Meltdown" })[cur] or MUTS[cur].name
                local bt = bestText(comboKey(P.selBase, P.selRokus, "mut:" .. cur), MUTS[cur])
                if not ok then bt = "not with " .. baseInfo(P.selBase).name end
                items[#items + 1] = { label = "Reactor: " .. short,
                    extra = "< level " .. UI.reactorLvl .. "/" .. #lv .. " >" .. (bt and ("    " .. bt) or ""),
                    desc = MUTS[cur].desc,
                    cycle = function(dir) UI.reactorLvl = (UI.reactorLvl - 1 + dir) % #lv + 1 end,
                    act = function() if ok then choose(cur) else showBanner("+ NOT WITH THIS MODE +", 2) end end }
            end
        else
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
    { key = "labUnlocked",   label = "Developer lab (F1)", bool = true, only = function() return P.labUnlocked end,
      desc = "Full control over the game for testing. Runs with lab cheats don't count for records. Off hides it (7 clicks on +GON+PLUS+ bring it back)." },
}

SCREENS.settings = function()
    local items = {}
    items[1] = { label = "Graphics / FPS", extra = "open",
        desc = "Render scale, shadows, reflections, FPS limit and an FPS counter. For PCs where the game drops frames.",
        act = function() UI.screen = "graphics"; UI.sel = 1 end }
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
