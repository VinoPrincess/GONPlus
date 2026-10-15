------------------------------------------------------------------------
-- Настройки самой игры в меню GON+ (вместо главного меню игры) и быстрый старт.
--   * наряд Року         — как экран Customize: ApplyOutfit + SG_progress.SelectedOutfit;
--   * сложность          — только для "ванильной" игры (Normal без мутатора); режимы и мутаторы
--                          GON+ всегда идут на Normal. Сложность игра читает при загрузке уровня
--                          (GI_GON.GI_Difficulty -> спавнеры SpawnItem_easy/_hard, HARDMODE игрока),
--                          поэтому при несовпадении START один раз перезапускает уровень;
--   * чувствительность   — mouseSEN игрока + GI_GON.MouseSensitivity + SG_settings;
--   * быстрый старт      — при запуске игры сами жмём её START в главном меню (один раз за запуск).
-- Разведка 15.10.2026: слоты сохранений "SG_progress" и "SettingsSlot", см. gon-mainmenu-saves.md.
------------------------------------------------------------------------
; (function()

local SLOT_PROGRESS, SLOT_SETTINGS = "SG_progress", "SettingsSlot"

-- строки DT_Outfits; flag — переменная "открыто" в SG_progress (нет flag — открыт всегда)
local OUTFITS = {
    { row = "base",       save = "Base", name = "Base" },
    { row = "Topless",    name = "Shirt-off",  flag = "U_topless" },
    { row = "Bottomless", name = "Bottomless", flag = "U_bottomless" },
    { row = "Bikini",     name = "Bikini",     flag = "U_bikini" },
    { row = "Source",     name = "Source",     flag = "U_source" },
    { row = "Bunny1",     name = "Bunny 1",    flag = "U_bunny1" },
    { row = "Bunny2",     name = "Bunny 2",    flag = "U_bunny2" },
    { row = "Sailor1",    name = "Sailor 1",   flag = "U_sailor1" },
    { row = "Sailor2",    name = "Sailor 2",   flag = "U_sailor2" },
    { row = "Shibari",    name = "Shibari",    flag = "U_shibari" },
    { row = "Cowmeat",    name = "Cowmeat",    flag = "U_SkinA1" },
    { row = "Dark",       name = "Dark",       flag = "U_SkinA2" },
}
local DIFFS = { { name = "Easy", flag = "U_easymode" }, { name = "Normal" }, { name = "Hard", flag = "U_hardmode" } }

------------------------------------------------------------------------
-- сохранения игры
------------------------------------------------------------------------
local function sgLoad(slot)
    local sg = nil
    pcall(function() sg = statics():LoadGameFromSlot(slot, 0) end)
    if valid(sg) then return sg end
    return nil
end
local function sgSave(sg, slot)
    local ok = false
    pcall(function() ok = statics():SaveGameToSlot(sg, slot, 0) end)
    return ok
end
local function str(v)
    if type(v) == "string" then return v end
    local s = nil
    pcall(function() s = v:ToString() end)
    return type(s) == "string" and s or nil
end

-- прогресс читаем не чаще раза в 2 с (меню перерисовывается часто)
local PROG = { sg = nil, at = -10 }
local function progress()
    local now = os.clock()
    if not PROG.sg or not valid(PROG.sg) or now - PROG.at > 2 then
        PROG.sg, PROG.at = sgLoad(SLOT_PROGRESS), now
    end
    return PROG.sg
end
onForgetRefs(function() PROG.sg = nil end)

local function unlocked(entry)
    if not entry.flag then return true end
    local sg = progress()
    if not sg then return true end
    local v = nil
    pcall(function() v = sg[entry.flag] end)
    return v ~= false
end

local function gi()
    local g = nil
    pcall(function() g = FindFirstOf("GI_GON_C") end)
    if valid(g) then return g end
    return nil
end

------------------------------------------------------------------------
-- наряд
------------------------------------------------------------------------
local function outfitIndex(name)
    if not name then return nil end
    name = name:lower()
    for i, o in ipairs(OUTFITS) do
        if o.row:lower() == name or (o.save and o.save:lower() == name) then return i end
    end
    return nil
end

local function currentOutfit()
    local r = getRoku()
    local s = nil
    if r then pcall(function() s = r.CurrentSkin:ToString() end) end
    local i = outfitIndex(s)
    if not i then
        local sg = progress()
        if sg then pcall(function() i = outfitIndex(str(sg.SelectedOutfit)) end) end
    end
    return i or 1
end

local function setOutfit(i)
    local o = OUTFITS[i]
    -- на Року сразу (кроме Nightmare: там она в Dark по правилам режима)
    if not (R.base == "nightmare" and R.phase == "running") then
        local r = getRoku()
        if r then pcall(function() r:ApplyOutfit(FName(o.row)) end) end
    end
    -- и в сохранение игры, как делает её экран Customize
    local sg = progress()
    local saved = false
    if sg then
        pcall(function() sg.SelectedOutfit = o.save or o.row end)
        saved = sgSave(sg, SLOT_PROGRESS)
    end
    log("Game settings: outfit " .. o.row .. (saved and " (saved)" or " (not saved)"))
end

------------------------------------------------------------------------
-- сложность
------------------------------------------------------------------------
function gameDifficulty()
    local g = gi()
    local d = nil
    if g then pcall(function() d = num(g.GI_Difficulty) end) end
    if d and d >= 1 and d <= 3 then return math.floor(d) end
    return nil
end

local function isVanilla() return P.selBase == "normal" and (P.selMut == "none" or P.selMut == "") end

-- выбор игрока для ванильной игры; 0 = ещё не выбирал -> берём из сохранения игры
local function vanillaDiff()
    if (P.gameDiff or 0) < 1 or P.gameDiff > 3 then
        local d = nil
        local sg = progress()
        if sg then pcall(function() d = num(sg.Difficulty) end) end
        d = d or gameDifficulty() or 2
        if d < 1 or d > 3 then d = 2 end
        P.gameDiff = math.floor(d)
    end
    return P.gameDiff
end
local function wantedDiff() return isVanilla() and vanillaDiff() or 2 end

local DIFF = { pending = nil, last = nil }

-- START: нужна другая сложность — ставим её и перезапускаем уровень (true = перезапуск пошёл)
function diffGate()
    local cur, want = gameDifficulty(), wantedDiff()
    if not cur or cur == want then return false end
    if DIFF.last and DIFF.last.want == want and os.clock() - DIFF.last.t < 30 then
        log("Game settings: difficulty " .. want .. " did not stick after a restart, starting as is (" .. cur .. ")")
        return false
    end
    local g = gi()
    local ok = g and pcall(function() g.GI_Difficulty = want end)
    if not ok then return false end
    DIFF.pending = { base = P.selBase, mut = P.selMut, t = os.clock() }
    DIFF.last = { want = want, t = os.clock() }
    log("Game settings: difficulty " .. cur .. " -> " .. want .. ", restarting the level")
    UI.close()
    pcall(function()
        StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(getPawn() or getPC(), "RestartLevel", getPC())
    end)
    return true
end

-- новый забег после такого перезапуска: сразу стартуем то, что было выбрано
function diffResume()
    local p = DIFF.pending
    DIFF.pending = nil
    if not p or os.clock() - p.t > 60 or p.base ~= P.selBase or p.mut ~= P.selMut then return false end
    after(400, function()
        if R.phase == "choosing" and UI.open and startSelected then
            log("Game settings: difficulty switched, starting the run")
            startSelected()
            if UI.open then refreshUI() end   -- Random: открылся экран рулетки
        end
    end)
    return true
end

local function diffSuffix(d)
    if d == 1 then return "@easy" elseif d == 3 then return "@hard" end
    return ""
end
-- ключ рекорда ванильной игры: normal / normal@easy / normal@hard
function vanillaRecordSuffix(d) return diffSuffix(d) end
function vanillaSelSuffix() return isVanilla() and diffSuffix(vanillaDiff()) or "" end

------------------------------------------------------------------------
-- чувствительность мыши
------------------------------------------------------------------------
local function sensNow()
    local s = nil
    local p = getPawn()
    if p then pcall(function() s = num(p.mouseSEN) end) end
    if not s then local g = gi(); if g then pcall(function() s = num(g.MouseSensitivity) end) end end
    return s or 1
end
local function setSensitivity(v)
    v = math.max(0.1, math.min(3, math.floor(v * 10 + 0.5) / 10))
    local p = getPawn()
    if p then pcall(function() p.mouseSEN = v end) end
    local g = gi()
    if g then pcall(function() g.MouseSensitivity = v end) end
    local sg = sgLoad(SLOT_SETTINGS)
    local saved = false
    if sg then
        pcall(function() sg.mouseSEN = v end)
        saved = sgSave(sg, SLOT_SETTINGS)
    end
    log(string.format("Game settings: mouse sensitivity %.1f%s", v, saved and " (saved)" or " (not saved)"))
end

------------------------------------------------------------------------
-- строки меню
------------------------------------------------------------------------
-- главный экран: наряд и (для ванильной игры) сложность
function gameMainItems(items)
    local ci = currentOutfit()
    local locked = 0
    for _, o in ipairs(OUTFITS) do if not unlocked(o) then locked = locked + 1 end end
    items[#items + 1] = { label = "Roku: " .. OUTFITS[ci].name, extra = "her outfit",
        desc = "Same as the game's Customize menu: changes at once and is saved for the game too."
            .. (locked > 0 and (" Locked outfits (" .. locked .. ") are skipped - unlock them in the game.") or ""),
        cycle = function(dir)
            local i = currentOutfit()
            for _ = 1, #OUTFITS do
                i = (i - 1 + dir) % #OUTFITS + 1
                if unlocked(OUTFITS[i]) then break end
            end
            setOutfit(i)
        end }
    if isVanilla() then
        local d = vanillaDiff()
        local cur = gameDifficulty()
        items[#items + 1] = { label = "Difficulty: " .. DIFFS[d].name,
            extra = (cur and cur ~= d) and "the level restarts on START" or "only for Normal without mutators",
            desc = "Easy: lots of items. Hard: fewer items, no medkits from shelves, less health, Roku stays closer. "
                .. "Records are kept apart for each difficulty. GON+ modes and mutators always play on Normal.",
            cycle = function(dir)
                local i = vanillaDiff()
                for _ = 1, 3 do
                    i = (i - 1 + dir) % 3 + 1
                    if unlocked(DIFFS[i]) then break end
                end
                P.gameDiff = i
                saveSettings()
                local sg = progress()
                if sg then
                    pcall(function() sg.Difficulty = i end)
                    sgSave(sg, SLOT_PROGRESS)
                end
            end }
    end
end

-- Settings: быстрый старт и мышь
function gameSettingsItems(items)
    items[#items + 1] = { label = "Quick start    " .. (P.quickStart and "[ON]" or "[off]"),
        desc = "Launching the game skips its main menu and goes straight to this window. Only once per launch: "
            .. "if you quit to the main menu yourself, it stays there.",
        cycle = function() P.quickStart = not P.quickStart; saveSettings() end }
    items[#items + 1] = { label = string.format("Mouse sensitivity    <  %d%%  >", math.floor(sensNow() * 100 + 0.5)),
        desc = "The game's own setting (same as in its Options). Saved for the game too.",
        cycle = function(dir)
            if R.base == "shy" and R.phase == "running" then
                windowNote("Not during Bashful - she changes it herself", 3)
                return
            end
            setSensitivity(sensNow() + dir * 0.1)
        end }
end

------------------------------------------------------------------------
-- быстрый старт: в главном меню игры один раз за запуск жмём её START
------------------------------------------------------------------------
local QS = { done = false, seen = nil }
local START_EVENT = "BndEvt__UI_MainMenu_Button_Start_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature"
every(500, function()
    if QS.done then return end
    if getPawn() then QS.done = true return end      -- уже в игре: в этот запуск больше не трогаем меню
    if not P.quickStart then return end
    local w = nil
    pcall(function() w = FindFirstOf("WBP_Main_C") end)
    if not valid(w) then return end
    local inView = false
    pcall(function() inView = w:IsInViewport() == true end)
    if not inView then return end
    QS.seen = QS.seen or os.clock()
    if os.clock() - QS.seen < 0.5 then return end    -- пусть меню достроится (оно само грузит сохранения)
    QS.done = true
    local ok, err = pcall(function() w[START_EVENT](w) end)
    log("Quick start: pressing the game's START " .. (ok and "ok" or ("failed: " .. tostring(err))))
end)

end)()
