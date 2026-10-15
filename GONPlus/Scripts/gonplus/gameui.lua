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
-- Только с открытой лабораторией: пока игрок в главном меню (нет персонажа), дописываем в
-- mainmenu_scan.txt каждый новый экран (Options/Customize/Achievements), GameInstance и сохранения.
------------------------------------------------------------------------
local menuScanned = {}         -- класс виджета -> уже записан
local menuLines = nil
local function valStr(v)
    local s = tostring(v)
    if type(v) == "userdata" then
        pcall(function() s = "\"" .. v:ToString() .. "\"" end)          -- FString/FText/FName
        if s == tostring(v) then pcall(function() s = v:GetFullName() end) end
    end
    return s
end
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
                        pcall(function() v = valStr(obj[n]) end)
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

local function menuSave()
    local fh = io.open(ROOT .. "\\mainmenu_scan.txt", "w")
    if fh then fh:write(table.concat(menuLines, "\n")); fh:close() end
end

-- Пока игрок в главном меню, каждые 2 с смотрим, какие виджеты на экране.
-- Каждый новый класс (Options, Customize, Achievements...) дописываем в файл один раз,
-- плюс заново пишем GameInstance и все SaveGame-объекты (там скины/сложность/ачивки).
every(2000, function()
    if not P.labUnlocked or getPawn() then return end
    local pc = getPC(); if not pc then return end
    local added = 0
    local out = {}
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        if valid(w) then
            local full = ""
            pcall(function() full = w:GetClass():GetFullName() end)
            local vis = true
            pcall(function() vis = w:IsVisible() == true end)
            if full:find("/Game/", 1, true) and vis and not menuScanned[full] then
                local inView = false
                pcall(function() inView = w:IsInViewport() == true end)
                menuScanned[full] = true
                added = added + 1
                out[#out + 1] = "== Widget" .. (inView and " (viewport)" or "") .. ": " .. full
                dumpFuncs(w, out, true)
            end
        end
    end
    if added == 0 then return end
    if not menuLines then
        menuLines = {}
        local lvl = "?"
        pcall(function() lvl = StaticFindObject("/Script/Engine.Default__GameplayStatics"):GetCurrentLevelName(pc, true):ToString() end)
        menuLines[1] = "== Map: " .. tostring(lvl)
    end
    for _, l in ipairs(out) do menuLines[#menuLines + 1] = l end
    menuLines[#menuLines + 1] = "== State after " .. added .. " new widget(s), t=" .. string.format("%.0f", os.clock())
    for _, gi in ipairs({ "GI_GON_C" }) do
        local g = nil
        pcall(function() g = FindFirstOf(gi) end)
        menuLines[#menuLines + 1] = "== GameInstance " .. gi .. ": " .. (valid(g) and g:GetFullName() or "not found")
        if valid(g) then dumpFuncs(g, menuLines, true) end
    end
    for _, sg in ipairs(FindAllOf("SaveGame") or {}) do
        if valid(sg) then
            menuLines[#menuLines + 1] = "== SaveGame: " .. sg:GetFullName()
            dumpFuncs(sg, menuLines, true)
        end
    end
    menuSave()
    log("Main menu scan: +" .. added .. " widgets -> mainmenu_scan.txt (" .. #menuLines .. " lines)")
end)

end)()
