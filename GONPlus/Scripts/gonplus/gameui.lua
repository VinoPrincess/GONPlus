------------------------------------------------------------------------
-- Всплывающие подсказки игры (Settings -> Game pop-ups).
-- Мешают режимам: "+RUN+" при погоне, "+ NOTE ACQUIRED + PAUSE TO READ +" у записок,
-- названия предметов при подборе ("FLASHLIGHT", "JAR OF BIO SAMPLES").
--
-- Разведка 15.10.2026: у всех трёх надпись называется ToolTip_Text_Block, но виджеты
-- разные (WB_ToolTip_C — только названия предметов; RUN и записка — другие классы).
-- Поэтому ловим ЛЮБОЙ виджет игры, который выводится на экран (хук AddToViewport),
-- и если у него есть надпись ToolTip_Text_Block — это подсказка:
--   * сам виджет — прозрачный (RenderOpacity = 0; SetVisibility на чужих виджетах бывало роняло игру);
--   * его шаблон надписи в классе — тоже прозрачный, чтобы следующие рождались невидимыми.
-- Урок той же разведки: опрос всех ~1700 надписей раз в секунду давал лаги и, видимо,
-- вылет после перезапуска уровня — поэтому никаких переборов всех надписей.
------------------------------------------------------------------------
; (function()

local POPUP_TEXT = "ToolTip_Text_Block"
local classes = { WB_ToolTip_C = "/Game/Variant_Horror/Localization/WB_ToolTip.WB_ToolTip_C" }  -- имя -> путь класса
local queue = {}            -- виджеты из хука, обработаем в тике
local hidden = {}           -- адреса спрятанных
local templates = {}        -- путь шаблона -> спрятан ли

local function isPopup(w)
    local t = nil
    pcall(function() t = w[POPUP_TEXT] end)
    return valid(t)
end

local function setTemplate(classPath, hide)
    local key = classPath .. ":WidgetTree." .. POPUP_TEXT
    if templates[key] == hide then return end
    local t = nil
    pcall(function() t = StaticFindObject(key) end)
    if valid(t) then
        pcall(function() t.RenderOpacity = hide and 0 or 1 end)
        pcall(function() t:SetRenderOpacity(hide and 0 or 1) end)
        log("Game pop-ups: template " .. (hide and "hidden" or "restored") .. " - " .. key)
    end
    templates[key] = hide
end

local function hideWidget(w, hide)
    pcall(function() if (num(w:GetRenderOpacity()) or 1) ~= (hide and 0 or 1) then w:SetRenderOpacity(hide and 0 or 1) end end)
end

-- хук: только складываем виджет в очередь (внутри хука ничего у игры не вызываем)
local hooked = false
local function ensureHook()
    if hooked then return end
    hooked = true
    for _, fn in ipairs({ "/Script/UMG.UserWidget:AddToViewport", "/Script/UMG.UserWidget:AddToPlayerScreen" }) do
        local ok, err = pcall(function()
            RegisterHook(fn, function(ctx) pcall(function() queue[#queue + 1] = ctx:get() end) end)
        end)
        log("Game pop-ups: hook " .. fn .. " " .. (ok and "ready" or ("failed: " .. tostring(err))))
    end
end

every(50, function()
    if #queue == 0 then return end
    local list = queue
    queue = {}
    for _, w in ipairs(list) do
        if valid(w) and isPopup(w) then
            local name, path = "?", nil
            pcall(function()
                local c = w:GetClass()
                name = c:GetFName():ToString()
                path = c:GetFullName():match("^%S+%s+(.+)$")
            end)
            if not classes[name] then
                classes[name] = path or ""
                log("Game pop-ups: found pop-up widget " .. name)
            end
            if P.gamePopups == false then
                hideWidget(w, true)
                hidden[w:GetAddress()] = true
                if path then setTemplate(path, true) end
            end
        end
    end
end)

-- подстраховка и возврат: 4 раза в секунду проходим только по известным классам подсказок
every(250, function()
    if not getPawn() then return end
    ensureHook()
    local hide = P.gamePopups == false
    for _, path in pairs(classes) do
        if path ~= "" then setTemplate(path, hide) end
    end
    if not hide and not next(hidden) then return end
    for name in pairs(classes) do
        for _, w in ipairs(FindAllOf(name) or {}) do
            if valid(w) then
                local addr = w:GetAddress()
                if hide then hideWidget(w, true); hidden[addr] = true
                elseif hidden[addr] then hideWidget(w, false); hidden[addr] = nil end
            end
        end
    end
    if not hide then hidden = {} end
end)
onForgetRefs(function() hidden, queue, templates = {}, {}, {} end)

------------------------------------------------------------------------
-- Разведка главного меню игры (для будущего "сразу в игру" и настроек/скинов/ачивок в нашем меню).
-- Только с открытой лабораторией: когда игрок в главном меню (нет персонажа), один раз пишем
-- mainmenu_scan.txt — какие виджеты на экране, их функции (кнопки!) и переменные GameInstance.
------------------------------------------------------------------------
local menuScanned = false
local function dumpFuncs(obj, out, withProps)
    local cls = nil
    pcall(function() cls = obj:GetClass() end)
    local guard = 0
    while cls and valid(cls) and guard < 6 do
        local cname = "?"
        pcall(function() cname = cls:GetFullName() end)
        if cname:find("/Game/", 1, true) then
            out[#out + 1] = "  -- " .. cname
            pcall(function()
                cls:ForEachFunction(function(f)
                    local params = {}
                    pcall(function()
                        f:ForEachProperty(function(pr) params[#params + 1] = pr:GetFName():ToString() end)
                    end)
                    out[#out + 1] = "    fn " .. f:GetFName():ToString() .. "(" .. table.concat(params, ", ") .. ")"
                end)
            end)
            if withProps then
                pcall(function()
                    cls:ForEachProperty(function(pr)
                        local n = pr:GetFName():ToString()
                        local v = "?"
                        pcall(function() v = tostring(obj[n]) end)
                        out[#out + 1] = "    var " .. n .. " = " .. v
                    end)
                end)
            end
        end
        local ok, sup = pcall(function() return cls:GetSuperStruct() end)
        cls = ok and sup or nil
        guard = guard + 1
    end
end

every(3000, function()
    if menuScanned or not P.labUnlocked or getPawn() then return end
    local pc = getPC(); if not pc then return end
    local out = {}
    local lvl = "?"
    pcall(function() lvl = StaticFindObject("/Script/Engine.Default__GameplayStatics"):GetCurrentLevelName(pc, true):ToString() end)
    out[#out + 1] = "== Map: " .. tostring(lvl)
    local found = 0
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        if valid(w) then
            local inView = false
            pcall(function() inView = w:IsInViewport() == true end)
            local full = ""
            pcall(function() full = w:GetClass():GetFullName() end)
            if inView and full:find("/Game/", 1, true) then
                found = found + 1
                out[#out + 1] = "== Widget on screen: " .. full
                dumpFuncs(w, out, true)
            end
        end
    end
    if found == 0 then return end          -- меню ещё не построилось — подождём
    for _, gi in ipairs({ "GI_GON_C" }) do
        local g = nil
        pcall(function() g = FindFirstOf(gi) end)
        out[#out + 1] = "== GameInstance " .. gi .. ": " .. (valid(g) and g:GetFullName() or "not found")
        if valid(g) then dumpFuncs(g, out, true) end
    end
    menuScanned = true
    local path = ROOT .. "\\mainmenu_scan.txt"
    local fh = io.open(path, "w")
    if fh then fh:write(table.concat(out, "\n")); fh:close() end
    log("Main menu scan saved: mainmenu_scan.txt (" .. found .. " widgets, " .. #out .. " lines)")
end)

end)()
