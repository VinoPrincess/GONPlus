-- Клавиши окна выбора
------------------------------------------------------------------------
local function onKey(key, fn)
    RegisterKeyBind(key, function()
        gameThread(function()
            if not UI.open then return end
            menuAnimSkip()
            UI.hoverZone = 0            -- клавиатура: подсветку стрелки от мыши снимаем
            safe(fn)
            refreshUI()
        end)
    end)
end

onKey(Key.UP_ARROW, function() UI.sel = UI.sel - 1; if UI.sel < 1 then UI.sel = #UI.items end; UI.ensureSel = true end)
onKey(Key.DOWN_ARROW, function() UI.sel = UI.sel + 1; if UI.sel > #UI.items then UI.sel = 1 end; UI.ensureSel = true end)
local labNumChange = nil -- задаётся в разделе лаборатории
onKey(Key.LEFT_ARROW, function()
    if labNumChange then labNumChange(-1) end
    local it = UI.items[UI.sel]
    if it and it.setting and not it.setting.bool then changeSetting(it.setting, -1) end
    if it and it.cycle then it.cycle(-1) end
end)
onKey(Key.RIGHT_ARROW, function()
    if labNumChange then labNumChange(1) end
    local it = UI.items[UI.sel]
    if it and it.setting and not it.setting.bool then changeSetting(it.setting, 1) end
    if it and it.cycle then it.cycle(1) end
end)
onKey(Key.RETURN, function()
    local it = UI.items[UI.sel]
    if not it then return end
    if it.setting then
        if it.setting.bool or it.setting.choices then changeSetting(it.setting, 1) end
    elseif it.cycle and not it.act then
        it.cycle(1)
    elseif it.act then
        it.act()
    end
end)
local function goBack()
    if UI.screen == "graphics" then UI.screen = "settings"; UI.sel = 1
    elseif UI.screen == "pick" or UI.screen == "settings" then UI.screen = "main"; UI.sel = 1 end
    if UI.kind == "lab" then UI.close() end
    -- со случайного назад нельзя: никаких перевыборов
end
onKey(Key.BACKSPACE, goBack)

------------------------------------------------------------------------
-- Мышь в окне выбора: наведение выбирает, клик — как Enter, правый клик — назад.
-- Окно фиксированного размера по центру, так что где кнопки — известно заранее.
------------------------------------------------------------------------
local function mouseInMenu()
    local pc = getPC(); if not pc then return nil end
    local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    if not valid(wll) then return nil end
    local mx, my, vw, vh
    local ok = pcall(function()
        local m = wll:GetMousePositionOnViewport(pc)
        local size = wll:GetViewportSize(pc)
        local scale = wll:GetViewportScale(pc)
        if not scale or scale <= 0 then scale = 1 end
        mx, my = m.X, m.Y
        vw, vh = size.X / scale, size.Y / scale
    end)
    if not ok or not mx or not vw or vw < 10 then return nil end
    if not UI.mouseLogged then
        UI.mouseLogged = true
        log(string.format("Mouse: viewport %.0f x %.0f (slate units), mouse at %.0f, %.0f", vw, vh, mx, my))
    end
    local L = (UI.view and UI.view.L) or MENU
    local left = vw * L.ax + L.px - L.w * L.alx
    local top = vh * L.ay + L.py - L.h * L.aly
    return mx - left, my - top, L
end

-- номер пункта под мышью и где по ширине кнопки (0..1)
local function itemAtMouse()
    local x, y, L = mouseInMenu()
    if not x then return nil end
    if x < L.rowX or x > L.rowX + L.rowW then return nil end
    local listH = UI.view.listH or (L.rows * L.rowStep)
    if y < L.rowY or y > L.rowY + listH then return nil end              -- вне видимой части списка
    local yy = y - L.rowY + (UI.scrollPx or 0)
    local idx = math.floor(yy / L.rowStep) + 1
    if yy - (idx - 1) * L.rowStep > L.rowH then return nil end            -- в промежутке
    if not UI.items[idx] then return nil end
    return idx, (x - L.rowX) / L.rowW, arrowZoneAt(L, x - L.rowX)
end

local function chooserOpen() return UI.open and UI.view and UI.view.L end

-- мышь над полосой прокрутки? -> y внутри окна (зона шире самой полосы, чтобы легко попасть)
local function scrollbarAtMouse()
    local x, y = mouseInMenu()
    local sb = UI.view and UI.view.sb
    if not x or not sb or not UI.view.sbLong then return nil end
    if x < sb.x - 14 or x > sb.x + sb.w + 14 then return nil end
    if y < sb.y - 6 or y > sb.y + sb.h + 6 then return nil end
    return y
end

-- мышь над кнопкой "назад"?
local function backAtMouse()
    local x, y = mouseInMenu()
    local bk = UI.view and UI.view.back
    if not x or not bk or not canGoBack() then return false end
    return x >= bk.x and x <= bk.x + bk.w and y >= bk.y and y <= bk.y + bk.h
end

-- мышь над надписью "+GON+PLUS+" (секретные клики)?
local function tagAtMouse()
    local x, y, L = mouseInMenu()
    if not x or UI.kind == "lab" then return false end
    if y < L.tagY - 4 or y > L.tagY + 26 then return false end
    if L.left then return x >= L.rowX - 10 and x <= L.rowX + 320 end   -- терминал: надпись слева
    return math.abs(x - L.w / 2) <= 160
end

-- бегунок под мышь: y — середина бегунка
local function scrollTo(y)
    local sb = UI.view.sb
    local th = sb.thumbH or 40
    local k = (y - sb.y - th / 2) / math.max(1, sb.h - th)
    k = math.max(0, math.min(1, k))
    menuSetScroll(k * menuMaxScroll())
    menuClampSel()
    refreshUI()
end

-- зажата ли левая кнопка мыши (для перетаскивания бегунка), если игра это скажет
local function leftHeld()
    local pc = getPC(); if not pc then return false end
    local held = false
    pcall(function() held = pc:IsInputKeyDown({ KeyName = FName("LeftMouseButton") }) == true end)
    return held
end

-- короткое сообщение вместо подзаголовка окна (игра на паузе — баннеры не идут)
function windowNote(text, sec)
    UI.note, UI.noteUntil = text, os.clock() + (sec or 2)
    refreshUI()
end

-- секретные клики: 7 подряд по "+GON+PLUS+" открывают лабораторию (F1)
local function secretClick()
    local t = os.clock()
    if t - (UI.tagLast or 0) > 1.5 then UI.tagClicks = 0 end
    UI.tagLast = t
    UI.tagClicks = (UI.tagClicks or 0) + 1
    local left = 7 - UI.tagClicks
    if P.labUnlocked then
        if UI.tagClicks >= 3 then windowNote("Developer lab is already on: F1", 2); UI.tagClicks = 0 end
    elseif left <= 0 then
        UI.tagClicks = 0
        P.labUnlocked = true
        VERBOSE = true
        saveSettings()
        windowNote("Developer lab unlocked: press F1 in a run", 3)
        log("Lab unlocked")
    elseif left <= 3 then
        windowNote(string.format("%d...", left), 0.8)
    end
end

-- колёсико крутит сам ScrollBox; следим за его сдвигом и двигаем выбор и нашу полосу
every(33, function()
    if not chooserOpen() or not UI.view.sbox then return end
    local cur = nil
    pcall(function() cur = UI.view.sbox:GetScrollOffset() end)
    if type(cur) ~= "number" then return end
    if math.abs(cur - (UI.scrollPx or 0)) > 0.5 then
        if not UI.wheelLogged then UI.wheelLogged = true; log("Menu scrolled by the list itself (mouse wheel)") end
        UI.scrollPx = cur
        menuClampSel()
        refreshUI()
    end
end)

-- наведение: только когда мышь сдвинулась, чтобы не мешать стрелкам
every(33, function()
    if not chooserOpen() then UI.lastMouse = nil return end
    if menuAnimBusy() then return end               -- пока окно едет, наведение не трогаем
    local x, y = mouseInMenu()
    if not x then return end
    -- сообщение в подзаголовке истекло
    if UI.note and os.clock() >= (UI.noteUntil or 0) then UI.note = nil; refreshUI() end
    -- тянешь бегунок
    if UI.dragging then
        if leftHeld() then scrollTo(y) else UI.dragging = false end
    end
    -- подсветка кнопки "назад"
    local hot = backAtMouse()
    if hot ~= (UI.backHot == true) then UI.backHot = hot; refreshUI() end
    local lm = UI.lastMouse
    if lm and math.abs(x - lm.x) < 1 and math.abs(y - lm.y) < 1 then return end
    UI.lastMouse = { x = x, y = y }
    if not lm then return end            -- первый замер после открытия
    local idx, _, zone = itemAtMouse()
    -- подсветка стрелки под мышью: видно, что клик сейчас поменяет значение
    zone = (idx and rowHasArrows(UI.items[idx])) and zone or 0
    if (idx and idx ~= UI.sel) or zone ~= (UI.hoverZone or 0) then
        if idx then UI.sel = idx end
        UI.hoverZone = zone
        refreshUI()
    end
end)

if Key.LEFT_MOUSE_BUTTON then
    RegisterKeyBind(Key.LEFT_MOUSE_BUTTON, function()
        gameThread(function()
            if not chooserOpen() then return end
            menuAnimSkip()
            safe(function()
                if backAtMouse() then goBack() return end
                if tagAtMouse() then secretClick() return end
                local sy = scrollbarAtMouse()
                if sy then scrollTo(sy); UI.dragging = true return end
                local idx, frac, zone = itemAtMouse()
                if not idx then return end
                UI.sel = idx
                local it = UI.items[idx]
                -- стрелки по краям ("<" ">") меняют значение; середина — выбрать / включить,
                -- а если выбирать нечего — тоже листает вперёд
                if it.setting then
                    if it.setting.bool then changeSetting(it.setting, 1)
                    else changeSetting(it.setting, zone ~= 0 and zone or 1) end
                elseif it.cycle and it.act and zone == 0 then
                    it.act()
                elseif it.cycle then
                    it.cycle(zone ~= 0 and zone or 1)
                elseif it.labNum and labNumChange then
                    labNumChange(frac < 0.5 and -1 or 1)
                elseif it.act then
                    it.act()
                end
            end)
            refreshUI()
        end)
    end)
end
if Key.RIGHT_MOUSE_BUTTON then
    RegisterKeyBind(Key.RIGHT_MOUSE_BUTTON, function()
        gameThread(function()
            if not chooserOpen() then return end
            menuAnimSkip()
            safe(goBack)
            refreshUI()
        end)
    end)
end

------------------------------------------------------------------------
