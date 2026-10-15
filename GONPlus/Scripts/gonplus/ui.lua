-- ИНТЕРФЕЙС: один виджет — окно выбора по центру + спидран-панель
------------------------------------------------------------------------
UI = {
    widget = nil, pc = nil,
    panel = nil, title = nil, sub = nil, rows = {}, desc = nil, foot = nil,
    hud = nil, hudLines = {},
    open = false, screen = "main", sel = 1, items = {},
    roll = nil,          -- рулетка случайного мутатора
    inputBlocked = false, pausedByMe = false,
}
local MAX_ROWS = 12

local COL = {
    bg     = { R = 0.01, G = 0.012, B = 0.012, A = 0.94 },
    accent = { R = 0.25, G = 1.0,  B = 0.35, A = 1 },
    text   = { R = 0.75, G = 0.78, B = 0.76, A = 1 },
    dim    = { R = 0.42, G = 0.45, B = 0.43, A = 1 },
    sel    = { R = 1, G = 1, B = 1, A = 1 },
    warn   = { R = 1.0, G = 0.4, B = 0.3, A = 1 },
    gold   = { R = 1.0, G = 0.8, B = 0.25, A = 1 },
    good   = { R = 0.4, G = 1.0, B = 0.45, A = 1 },
    bad    = { R = 1.0, G = 0.35, B = 0.3, A = 1 },
    hudBg  = { R = 0, G = 0, B = 0, A = 0.45 },
}

-- стиль самой игры (из ui_scan.txt): Cascadia Code для заголовков и текста,
-- Conthrax SemiBold для кнопок меню, фирменный синий, плюсы по краям "+PAUSED+"
local FONT = {
    main   = "/Game/Variant_Horror/Localization/CASCADIAFONT/CASCADIACODE_Font.CASCADIACODE_Font",
    button = "/Game/Conthrax-SemiBold_Font.Conthrax-SemiBold_Font",
}
local GAME = {
    white  = { R = 1, G = 1, B = 1, A = 1 },
    soft   = { R = 1, G = 1, B = 1, A = 0.75 },   -- как пояснения в меню достижений
    faint  = { R = 1, G = 1, B = 1, A = 0.45 },
    idle   = { R = 1, G = 1, B = 1, A = 0.55 },   -- невыбранный пункт
    blue   = { R = 0.0, G = 0.5, B = 1.0, A = 1 },   -- надписи-подсказки игры
    deep   = { R = 0.0, G = 0.28, B = 1.0, A = 1 },  -- "+ YOU BECAME NOTHING +"
    dim    = { R = 0, G = 0, B = 0, A = 0.35 },      -- лёгкое затемнение под меню
    none   = { R = 0, G = 0, B = 0, A = 0 },
    frame  = { R = 0.02, G = 0.0, B = 0.0, A = 0.72 },  -- окно меню паузы: тёмное, полупрозрачное
    outline = { R = 1, G = 1, B = 1, A = 0.5 },         -- тонкая светлая обводка окна и кнопок
    pillOff = { R = 0, G = 0, B = 0, A = 0.35 },
    pillOn  = { R = 0.0, G = 0.12, B = 0.35, A = 0.6 },
    warn    = { R = 1.0, G = 0.15, B = 0.3, A = 1 },     -- красно-розовый из логотипа GON
    stBlue  = { R = 0.0, G = 0.27, B = 1.0, A = 1 },     -- родная выносливость (синяя)
    hpGreen = { R = 0.42, G = 1.0, B = 0.09, A = 1 },    -- родное здоровье (зелёное)
    blood   = { R = 0.75, G = 0.03, B = 0.1, A = 1 },
}
local fontCache = {}
local function fontObj(which)
    local f = fontCache[which]
    if valid(f) then return f end
    pcall(function() f = StaticFindObject(FONT[which]) end)
    if valid(f) then fontCache[which] = f return f end
    return nil
end

local function construct(path, outer)
    local cls = StaticFindObject(path)
    if not valid(cls) then error("class not found: " .. path) end
    local obj = StaticConstructObject(cls, outer)
    if not valid(obj) then error("could not construct: " .. path) end
    return obj
end
local function setColor(t, c) t:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 }) end
local function styleText(t, size)
    pcall(function() local f = t.Font; f.Size = size; t:SetFont(f) end)
end
-- шрифт игры; если не нашёлся — остаётся обычный, но размер всё равно ставим
local function setFont(t, which, size)
    local fo = fontObj(which)
    local ok = false
    if fo then
        ok = pcall(function()
            local f = t.Font
            f.FontObject = fo
            f.TypefaceFontName = FName("Default")
            if size then f.Size = size end
            t:SetFont(f)
        end)
    end
    if not ok and size then styleText(t, size) end
    return ok
end
local function center(t) pcall(function() t:SetJustification(1) end) end
local function setText(t, s) if valid(t) then t:SetText(FText(s)) end end

local function box(tree, canvas, anchorX, anchorY, alignX, alignY, x, y, borderColor, bgColor)
    local outer = construct("/Script/UMG.Border", tree)
    outer:SetBrushColor(borderColor)
    pcall(function() outer:SetPadding({ Left = 0, Top = 3, Right = 0, Bottom = 0 }) end)
    local inner = construct("/Script/UMG.Border", tree)
    inner:SetBrushColor(bgColor)
    pcall(function() inner:SetPadding({ Left = 22, Top = 14, Right = 22, Bottom = 14 }) end)
    outer:SetContent(inner)
    local vb = construct("/Script/UMG.VerticalBox", tree)
    inner:SetContent(vb)
    local slot = canvas:AddChildToCanvas(outer)
    pcall(function() slot:SetAutoSize(true) end)
    pcall(function()
        slot:SetAnchors({ Minimum = { X = anchorX, Y = anchorY }, Maximum = { X = anchorX, Y = anchorY } })
        slot:SetAlignment({ X = alignX, Y = alignY })
    end)
    slot:SetPosition({ X = x, Y = y })
    return outer, vb, slot
end

local function line(tree, vb, str, color, size)
    local t = construct("/Script/UMG.TextBlock", tree)
    t:SetText(FText(str))
    setColor(t, color)
    styleText(t, size)
    vb:AddChildToVerticalBox(t)
    return t
end

-- скруглённая плашка (как кнопки меню паузы игры): RoundedBox с обводкой.
-- Заливка = BrushColor (её меняем при выборе), обводка задаётся один раз.
local ROUNDED_OK = nil
local function roundBrush(border, fill, outline, width, radius)
    local ok, err = pcall(function()
        border:SetBrush({
            DrawAs = 4,                         -- ESlateBrushDrawType::RoundedBox
            TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 },
            ImageSize = { X = 32, Y = 32 },
            OutlineSettings = {
                CornerRadii = { X = radius, Y = radius, Z = radius, W = radius },
                Color = { SpecifiedColor = outline, ColorUseRule = 0 },
                Width = width,
                RoundingType = 0,               -- FixedRadius
                bUseBrushTransparency = false,
            },
        })
    end)
    pcall(function() border:SetBrushColor(fill) end)
    if ROUNDED_OK == nil then
        local da = nil
        pcall(function() da = border.Background.DrawAs end)
        ROUNDED_OK = ok and (da == 4)
        log("UI: rounded brush " .. (ROUNDED_OK and "OK" or ("not applied (SetBrush ok=" .. tostring(ok)
            .. ", DrawAs=" .. tostring(da) .. ", " .. tostring(err) .. ")")))
    end
end

-- Окна фиксированного размера, всё внутри стоит по координатам:
-- окно не прыгает от длины текста, и известно, где каждая кнопка (для мыши).
-- ax/ay — точка экрана, к которой привязано окно; px/py — сдвиг; al — выравнивание окна.
local MENU = {
    w = 1000, h = 830, ax = 0.5, ay = 0.5, alx = 0.5, aly = 0.5, px = 0, py = 0,
    rows = 7, rowX = 180, rowW = 640, rowY = 172, rowH = 58, rowStep = 70,
    tag = "+GON+PLUS+", tagY = 26, titleY = 48, titleH = 70, titleSize = 48, subY = 118, subSize = 18,
    rowFont = "button", rowSize = 26, extraSize = 13, plusSize = 44,
    descSize = 18, descH = 92, footSize = 16,
}
local LABMENU = {
    w = 580, h = 840, ax = 1, ay = 0.5, alx = 1, aly = 0.5, px = -30, py = 0,
    rows = 12, rowX = 30, rowW = 520, rowY = 126, rowH = 42, rowStep = 47,
    tag = "+GON+LAB+", tagY = 14, titleY = 30, titleH = 44, titleSize = 30, subY = 72, subSize = 14,
    rowFont = "main", rowSize = 15, extraSize = 12, plusSize = 30,
    descSize = 14, descH = 60, footSize = 13,
}
-- «Терминал» (Interface: terminal): панель во всю высоту слева, моноширинный шрифт игры,
-- квадратные углы, синяя линия; выбранный пункт — "> ПУНКТ" на синей подсветке
local TERMMENU = {
    w = 620, h = 1000, ax = 0, ay = 0.5, alx = 0, aly = 0.5, px = 0, py = 0,
    rows = 10, rowX = 34, rowW = 540, rowY = 182, rowH = 50, rowStep = 56,
    tag = "GON+ // TERMINAL", tagY = 34, titleY = 62, titleH = 56, titleSize = 34, subY = 120, subSize = 16,
    rowFont = "main", rowSize = 22, extraSize = 13, plusSize = 0,
    descSize = 16, descH = 120, footSize = 13,
    left = true, term = true, radius = 0, pillRadius = 3,
}
-- «Минимал» (Interface: minimal): без окна, как главное меню игры — крупный текст Conthrax
-- прямо поверх затемнённой игры, слева список, справа описание за тонкой линией
local MINMENU = {
    w = 1340, h = 900, ax = 0, ay = 0.5, alx = 0, aly = 0.5, px = 70, py = 0,
    rows = 9, rowX = 40, rowW = 660, rowY = 176, rowH = 56, rowStep = 62,
    tag = "+GON+PLUS+", tagY = 40, titleY = 74, titleH = 50, titleSize = 30, subY = 124, subSize = 16,
    rowFont = "button", rowSize = 30, extraSize = 13, plusSize = 0,
    descSize = 18, descH = 320, footSize = 13,
    descX = 790, descY = 200, descW = 480,
    left = true, minimal = true, uniform = true, radius = 0, pillRadius = 0,
}
local GAME_ROWS = MENU.rows
-- ширина зоны стрелки "<" / ">" на краю кнопки (и для мыши, и для рисования)
ARROW_ZONE = 64

-- цвета окна: по умолчанию как меню паузы игры, у терминала свои
local THEME_GAME = {
    frame = GAME.frame, outline = GAME.outline, outlineW = 1.5,
    pillOff = GAME.pillOff, pillOn = GAME.pillOn, pillLine = GAME.outline, pillLineW = 2,
    idle = GAME.idle, sel = GAME.blue, tag = GAME.faint, title = GAME.white, sub = GAME.soft,
    desc = GAME.soft, foot = GAME.faint, more = GAME.blue, thumb = GAME.blue,
}
local TERM_BLUE = { R = 0.0, G = 0.5, B = 1.0, A = 1 }
local THEME_TERM = {
    frame = { R = 0.01, G = 0.015, B = 0.03, A = 0.93 }, outline = { R = 0.0, G = 0.5, B = 1.0, A = 0.85 }, outlineW = 1.5,
    pillOff = { R = 0, G = 0, B = 0, A = 0 }, pillOn = { R = 0.0, G = 0.45, B = 1.0, A = 0.22 },
    pillLine = { R = 0, G = 0, B = 0, A = 0 }, pillLineW = 0,
    idle = { R = 1, G = 1, B = 1, A = 0.6 }, sel = GAME.white, tag = TERM_BLUE, title = GAME.white,
    sub = { R = 1, G = 1, B = 1, A = 0.5 }, desc = { R = 1, G = 1, B = 1, A = 0.72 },
    foot = { R = 1, G = 1, B = 1, A = 0.4 }, more = TERM_BLUE, thumb = TERM_BLUE,
}
local NONE = { R = 0, G = 0, B = 0, A = 0 }
local THEME_MIN = {
    frame = NONE, outline = NONE, outlineW = 0,
    pillOff = NONE, pillOn = NONE, pillLine = NONE, pillLineW = 0,
    idle = { R = 1, G = 1, B = 1, A = 0.5 }, sel = GAME.blue, tag = GAME.faint, title = { R = 1, G = 1, B = 1, A = 0.85 },
    sub = { R = 1, G = 1, B = 1, A = 0.5 }, desc = { R = 1, G = 1, B = 1, A = 0.78 },
    foot = { R = 1, G = 1, B = 1, A = 0.4 }, more = GAME.blue, thumb = { R = 1, G = 1, B = 1, A = 0.8 },
    dim = { R = 0, G = 0, B = 0, A = 0.6 },   -- без окна текст читается только на сильнее затемнённой игре
}
MENU.theme, LABMENU.theme, TERMMENU.theme, MINMENU.theme = THEME_GAME, THEME_GAME, THEME_TERM, THEME_MIN

local function buildGameMenu(tree, canvas, L)
    L = L or MENU
    local T = L.theme or THEME_GAME
    local v = { rows = {}, game = true, L = L }
    local big = L ~= LABMENU      -- окно выбора (у лаборатории всё компактнее)
    -- выравнивание текста: по центру (стиль игры) или влево (терминал)
    local function align(t) if L.left then pcall(function() t:SetJustification(0) end) else center(t) end end
    local HALIGN = L.left and 1 or 2
    -- рамка окна: тёмная полупрозрачная, тонкая светлая обводка, большие скругления
    local frame = construct("/Script/UMG.Border", tree)
    roundBrush(frame, T.frame, T.outline, T.outlineW, L.radius or (L == MENU and 36 or 24))
    pcall(function() frame:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
    local slot = canvas:AddChildToCanvas(frame)
    pcall(function() slot:SetAutoSize(false) end)
    pcall(function()
        slot:SetAnchors({ Minimum = { X = L.ax, Y = L.ay }, Maximum = { X = L.ax, Y = L.ay } })
        slot:SetAlignment({ X = L.alx, Y = L.aly })
    end)
    slot:SetPosition({ X = L.px, Y = L.py })
    slot:SetSize({ X = L.w, Y = L.h })
    v.panel, v.slot = frame, slot

    local cv = construct("/Script/UMG.CanvasPanel", tree)
    frame:SetContent(cv)
    v.cv = cv
    pcall(function() frame:SetClipping(1) end)       -- ClipToBounds: страница при анимации не вылезает за рамку

    local function place(widget, x, y, w, h)
        local s2 = cv:AddChildToCanvas(widget)
        pcall(function() s2:SetAutoSize(false) end)
        s2:SetPosition({ X = x, Y = y })
        s2:SetSize({ X = w, Y = h })
        return s2
    end
    local function text(font, size, color, y, h, x, w)
        local t = construct("/Script/UMG.TextBlock", tree)
        t:SetText(FText(""))
        setColor(t, color)
        setFont(t, font, size)
        align(t)
        -- влево: отступ как у списка
        if L.left and not x then x, w = L.rowX, L.w - L.rowX * 2 end
        place(t, x or 0, y, w or L.w, h)
        return t
    end

    -- подпись мода в духе "+GOD+OF+NOTHING+" под логотипом
    v.tag = text("main", 14, T.tag, L.tagY, 24)
    pcall(function() local f = v.tag.Font; f.LetterSpacing = L.term and 250 or 450; v.tag:SetFont(f) end)
    if L.minimal then
        -- заголовок разрядкой, как "+GOD+OF+NOTHING+" под логотипом игры
        pcall(function() local f = v.tag.Font; f.LetterSpacing = 600; v.tag:SetFont(f) end)
    end
    setText(v.tag, L.tag)
    v.title = text("main", L.titleSize, T.title, L.titleY, L.titleH)
    if L.minimal then pcall(function() local f = v.title.Font; f.LetterSpacing = 350; v.title:SetFont(f) end) end
    v.sub = text("main", L.subSize, T.sub, L.subY, 30)
    -- "+" в углу окна, как у меню паузы
    if (L.plusSize or 0) > 0 then
        local plus = text("button", L.plusSize, GAME.white, 6, L.plusSize + 20, L.w - L.plusSize - 40, L.plusSize + 20)
        setText(plus, "+")
    end

    -- Список — в настоящем ScrollBox движка: колёсико мыши он крутит сам (у колёсика нет
    -- кода клавиши, поймать его из Lua нельзя). Все кнопки существуют сразу, лишние скрыты.
    local MAXROWS = 40
    local listH = L.rows * L.rowStep - (L.rowStep - L.rowH)
    local sbox = construct("/Script/UMG.ScrollBox", tree)
    pcall(function() sbox:SetScrollBarVisibility(VIS_HIDE) end)          -- своя полоса справа
    pcall(function() sbox:SetAnimateWheelScrolling(false) end)
    pcall(function() sbox:SetConsumeMouseWheel(1) end)                    -- Always
    -- шаг колёсика: движок листает на 32 единицы * множитель; так один щелчок = одна кнопка
    local mult = L.rowStep / 32
    local okMult = pcall(function() sbox:SetWheelScrollMultiplier(mult) end)
    if not okMult then pcall(function() sbox.WheelScrollMultiplier = mult end) end
    sbox:SetVisibility(0)                                                  -- ловит колёсико
    place(sbox, L.rowX, L.rowY, L.rowW, listH)
    local vlist = construct("/Script/UMG.VerticalBox", tree)
    sbox:AddChild(vlist)
    v.sbox, v.listH = sbox, listH

    for i = 1, MAXROWS do
        local pill = construct("/Script/UMG.Border", tree)
        -- радиус = половина высоты: полностью круглые края, как кнопки игры
        roundBrush(pill, T.pillOff, T.pillLine, T.pillLineW, L.pillRadius or (L.rowH / 2))
        pcall(function() pill:SetPadding({ Left = 0, Top = 1, Right = 0, Bottom = 1 }) end)
        pcall(function() pill:SetHorizontalAlignment(0); pill:SetVerticalAlignment(0) end)
        -- внутри кнопки: подпись + стрелки "<" ">" по краям (у пунктов, которые листаются):
        -- сразу видно, что края меняют значение, а середина — выбрать
        local ov = construct("/Script/UMG.Overlay", tree)
        pill:SetContent(ov)
        local inner = construct("/Script/UMG.VerticalBox", tree)
        local ins = ov:AddChildToOverlay(inner)
        pcall(function()
            ins:SetHorizontalAlignment(HALIGN); ins:SetVerticalAlignment(2)
            ins:SetPadding({ Left = L.left and 14 or 24, Top = 0, Right = 24, Bottom = 0 })
        end)
        local arrows = {}
        for k, side in ipairs({ -1, 1 }) do
            local t = construct("/Script/UMG.TextBlock", tree)
            t:SetText(FText(side < 0 and "<" or ">"))
            setFont(t, "main", math.max(14, L.rowSize - 4)); center(t); setColor(t, T.idle)
            local sb = construct("/Script/UMG.SizeBox", tree)
            pcall(function() sb:SetWidthOverride(ARROW_ZONE) end)
            sb:SetContent(t)
            local as = ov:AddChildToOverlay(sb)
            pcall(function()
                as:SetVerticalAlignment(2)
                if L.left then
                    -- текст слева: обе стрелки справа, "<" перед ">"
                    as:SetHorizontalAlignment(3)
                    as:SetPadding({ Left = 0, Top = 0, Right = side < 0 and ARROW_ZONE or 0, Bottom = 0 })
                else
                    as:SetHorizontalAlignment(side < 0 and 1 or 3)
                end
            end)
            t:SetVisibility(VIS_HIDE)
            arrows[k] = t
        end
        local main = construct("/Script/UMG.TextBlock", tree)
        setFont(main, L.rowFont, L.rowSize); align(main); setColor(main, T.idle)
        local ms = inner:AddChildToVerticalBox(main)
        pcall(function() ms:SetHorizontalAlignment(HALIGN) end)
        local extra = construct("/Script/UMG.TextBlock", tree)
        setFont(extra, "main", L.extraSize); align(extra); setColor(extra, T.sub)
        local es = inner:AddChildToVerticalBox(extra)
        pcall(function() es:SetHorizontalAlignment(HALIGN) end)
        -- в терминале подпись под пунктом с отступом под "> "
        if L.left then pcall(function() es:SetPadding({ Left = 28, Top = 0, Right = 0, Bottom = 0 }) end) end
        local sz = construct("/Script/UMG.SizeBox", tree)
        pcall(function() sz:SetHeightOverride(L.rowH) end)
        sz:SetContent(pill)
        local vs = vlist:AddChildToVerticalBox(sz)
        pcall(function() vs:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = L.rowStep - L.rowH }) end)
        sz:SetVisibility(VIS_HIDE)
        v.rows[i] = { box = sz, pill = pill, main = main, extra = extra, arrowL = arrows[1], arrowR = arrows[2] }
    end

    -- "ещё выше / ещё ниже": видно, что список длиннее; наведение листает, клик — страницу
    local listEnd = L.rowY + L.rows * L.rowStep - (L.rowStep - L.rowH)
    v.moreUp = text("main", 14, T.more, L.rowY - 22, 20, L.rowX, L.rowW)
    v.moreDown = text("main", 14, T.more, listEnd + 2, 20, L.rowX, L.rowW)
    v.moreUpY, v.moreDownY = L.rowY - 22, listEnd + 2
    v.moreUp:SetVisibility(VIS_HIDE); v.moreDown:SetVisibility(VIS_HIDE)

    -- полоса прокрутки справа от списка: дорожка + бегунок (клик по дорожке — туда, можно тянуть)
    local sb = { x = L.rowX + L.rowW + (big and 18 or 10), y = L.rowY, w = L.minimal and 3 or (big and 10 or 8),
                 h = listEnd - L.rowY }
    local sbR = (L.term or L.minimal) and 1 or sb.w / 2
    sb.track = construct("/Script/UMG.Border", tree)
    roundBrush(sb.track, L.minimal and { R = 1, G = 1, B = 1, A = 0.15 } or { R = 0, G = 0, B = 0, A = 0.35 },
        L.minimal and NONE or (L.term and T.outline or GAME.outline), L.minimal and 0 or 1, sbR)
    place(sb.track, sb.x, sb.y, sb.w, sb.h)
    sb.thumb = construct("/Script/UMG.Border", tree)
    roundBrush(sb.thumb, T.thumb, { R = 0, G = 0, B = 0, A = 0 }, 0, sbR)
    sb.thumbSlot = place(sb.thumb, sb.x, sb.y, sb.w, 40)
    sb.track:SetVisibility(VIS_HIDE); sb.thumb:SetVisibility(VIS_HIDE)
    v.sb = sb

    -- кнопка "назад" в левом нижнем углу (у главного экрана её нет)
    local bk = { x = L.term and L.rowX or 36, w = big and 170 or 130, h = big and 44 or 36 }
    bk.y = L.h - bk.h - 22
    bk.pill = construct("/Script/UMG.Border", tree)
    roundBrush(bk.pill, T.pillOff, L.minimal and NONE or (L.term and T.outline or GAME.outline),
        L.minimal and 0 or (L.term and 1 or 2), (L.term or L.minimal) and 3 or bk.h / 2)
    pcall(function() bk.pill:SetHorizontalAlignment(2); bk.pill:SetVerticalAlignment(2) end)
    bk.text = construct("/Script/UMG.TextBlock", tree)
    setFont(bk.text, L.rowFont, big and 20 or 15); center(bk.text); setColor(bk.text, T.idle)
    bk.text:SetText(FText("BACK"))
    bk.pill:SetContent(bk.text)
    place(bk.pill, bk.x, bk.y, bk.w, bk.h)
    bk.pill:SetVisibility(VIS_HIDE)
    v.back = bk
    local descY = L.descY or (listEnd + 26)
    v.desc = text("main", L.descSize, T.desc, descY, L.descH, L.descX or (L.left and L.rowX or 40), L.descW or (L.left and L.rowW or (L.w - 80)))
    if L.descX then
        -- тонкая линия слева от описания
        local ln = construct("/Script/UMG.Border", tree)
        pcall(function() ln:SetBrushColor({ R = 1, G = 1, B = 1, A = 0.3 }) end)
        place(ln, L.descX - 22, descY - 6, 1, L.descH)
    end
    pcall(function() v.desc:SetAutoWrapText(true) end)
    -- подсказка внизу — правее кнопки "назад"
    local footX = bk.x + bk.w + 24
    v.foot = text("main", L.footSize, T.foot, L.h - L.footSize - 30, L.footSize + 12, footX, L.w - footX - 30)
    pcall(function() v.foot:SetAutoWrapText(true) end)
    frame:SetVisibility(VIS_HIDE)
    return v
end

-- Спидран-панель: строки и их стиль (размер — при hudSize 18)
HUD_ORDER = { "pines", "time", "delta", "mode", "chaos", "best" }
HUD_STYLE = {
    pines = { font = "button", size = 34, color = GAME.white, gap = 0 },
    time  = { font = "main",   size = 26, color = GAME.white, gap = 2 },
    delta = { font = "main",   size = 18, color = GAME.blue,  gap = 2 },
    mode  = { font = "main",   size = 16, color = GAME.soft,  gap = 0 },
    chaos = { font = "main",   size = 20, color = GAME.blue,  gap = 0 },
    best  = { font = "main",   size = 14, color = GAME.faint, gap = 0 },
}

-- Полоски: как у игры — выносливость синяя, здоровье зелёное.
-- Три вида (настройка barsStyle; ещё terminal — см. BARS_LAYOUT.term):
--   по центру внизу — широкое тонкое здоровье и под ним узкая выносливость (прячется, когда полная)
--   в углу слева — как у игры: выносливость сверху, здоровье снизу
local BARS_LAYOUT = {
    center = { ax = 0.5, hp = { w = 440, h = 14, y = -78, inset = 3 }, st = { w = 300, h = 8, y = -56, inset = 2 } },
    corner = { ax = 0,   x = 48, st = { w = 300, h = 20, y = -98, inset = 4 }, hp = { w = 300, h = 20, y = -64, inset = 4 } },
    -- терминал: слева внизу тонкие квадратные полоски, слева "HP"/"ST", справа проценты
    -- минимал: две тонкие линии по центру внизу, без рамок
    line   = { ax = 0.5, line = true, hp = { w = 380, h = 4, y = -50, inset = 0 }, st = { w = 380, h = 3, y = -40, inset = 0 } },
    term   = { ax = 0,   x = 92, term = true, hp = { w = 260, h = 12, y = -78, inset = 2 }, st = { w = 260, h = 12, y = -54, inset = 2 } },
}
function barsGeom()
    return BARS_LAYOUT[P.barsStyle] or BARS_LAYOUT.corner
end

function buildBars(tree, canvas)
    local b = {}
    local clear = { R = 0, G = 0, B = 0, A = 0 }
    local function piece(fill, outline, ow, h)
        local br = construct("/Script/UMG.Border", tree)
        roundBrush(br, fill, outline, ow, h / 2)
        local s2 = canvas:AddChildToCanvas(br)
        pcall(function() s2:SetAutoSize(false) end)
        br:SetVisibility(VIS_HIDE)
        return br, s2
    end
    for _, k in ipairs({ "hp", "st" }) do
        local e = {}
        local h = 20
        e.frame, e.frameSlot = piece({ R = 0, G = 0, B = 0, A = 0.35 }, GAME.outline, 2, h)
        if k == "hp" then e.trail, e.trailSlot = piece({ R = 1, G = 1, B = 1, A = 0.55 }, clear, 0, h) end
        e.fill, e.fillSlot = piece(k == "hp" and GAME.hpGreen or GAME.stBlue, clear, 0, h)
        -- подписи терминала: "HP" слева от полоски, "72%" справа
        for _, part in ipairs({ "name", "num" }) do
            local t = construct("/Script/UMG.TextBlock", tree)
            t:SetText(FText(part == "name" and (k == "hp" and "HP" or "ST") or ""))
            setColor(t, { R = 1, G = 1, B = 1, A = 0.75 })
            setFont(t, "main", 14)
            local s2 = canvas:AddChildToCanvas(t)
            pcall(function() s2:SetAutoSize(true) end)
            t:SetVisibility(VIS_HIDE)
            e[part], e[part .. "Slot"] = t, s2
        end
        b[k] = e
    end
    -- подпись над здоровьем (кровотечение, влюблённость)
    local t = construct("/Script/UMG.TextBlock", tree)
    t:SetText(FText(""))
    setColor(t, GAME.warn)
    setFont(t, "main", 14)
    b.labelSlot = canvas:AddChildToCanvas(t)
    pcall(function() b.labelSlot:SetAutoSize(true) end)
    t:SetVisibility(VIS_HIDE)
    b.label = t
    b.trailV, b.trailHold = 1, 0
    b.tree = tree
    UI.bars = b
    layoutBars()
    return b
end

-- расставить полоски под выбранный вид
function layoutBars()
    local b = UI.bars; if not b then return end
    local L = barsGeom()
    for _, k in ipairs({ "hp", "st" }) do
        local e, g = b[k], L[k]
        local x = (L.ax == 0.5) and (-g.w / 2) or L.x
        e.g = { x = x, y = g.y, w = g.w, h = g.h, inset = g.inset }
        local function put(slot, px, py, w, h)
            if not slot then return end
            pcall(function()
                slot:SetAnchors({ Minimum = { X = L.ax, Y = 1 }, Maximum = { X = L.ax, Y = 1 } })
                slot:SetAlignment({ X = 0, Y = 0 })
                slot:SetPosition({ X = px, Y = py })
                slot:SetSize({ X = w, Y = h })
            end)
        end
        put(e.frameSlot, x, g.y, g.w, g.h)
        put(e.trailSlot, x + g.inset, g.y + g.inset, g.w - g.inset * 2, g.h - g.inset * 2)
        put(e.fillSlot, x + g.inset, g.y + g.inset, g.w - g.inset * 2, g.h - g.inset * 2)
        -- подписи терминала (у других видов спрятаны в updateBars)
        for _, part in ipairs({ "name", "num" }) do
            local s2 = e[part .. "Slot"]
            if s2 then pcall(function()
                s2:SetAnchors({ Minimum = { X = L.ax, Y = 1 }, Maximum = { X = L.ax, Y = 1 } })
                s2:SetAlignment({ X = 0, Y = 0.5 })
                s2:SetPosition({ X = part == "name" and (x - 40) or (x + g.w + 12), Y = g.y + g.h / 2 })
            end) end
        end
        -- скругление под новую высоту (терминал — квадратные углы, синяя обводка)
        local term = L.term
        for _, part in ipairs({ "frame", "trail", "fill" }) do
            local w = e[part]
            if valid(w) then
                local fill = nil
                local flat = term or L.line
                if part == "frame" then
                    if L.line then
                        roundBrush(w, { R = 1, G = 1, B = 1, A = 0.15 }, { R = 0, G = 0, B = 0, A = 0 }, 0, 0)
                    else
                        roundBrush(w, { R = 0, G = 0, B = 0, A = term and 0.5 or 0.35 }, term and { R = 0, G = 0.5, B = 1, A = 0.8 } or GAME.outline,
                            term and 1 or (P.barsStyle == "center" and 1.5 or 2), term and 0 or g.h / 2)
                    end
                else roundBrush(w, part == "trail" and { R = 1, G = 1, B = 1, A = 0.55 } or (k == "hp" and GAME.hpGreen or GAME.stBlue), { R = 0, G = 0, B = 0, A = 0 }, 0, flat and 0 or (g.h - g.inset * 2) / 2) end
            end
        end
    end
    -- подпись: над верхней полоской
    local top = (b.hp.g.y < b.st.g.y) and b.hp.g or b.st.g
    pcall(function()
        b.labelSlot:SetAnchors({ Minimum = { X = L.ax, Y = 1 }, Maximum = { X = L.ax, Y = 1 } })
        if L.ax == 0.5 then
            b.labelSlot:SetAlignment({ X = 0.5, Y = 1 }); b.labelSlot:SetPosition({ X = 0, Y = top.y - 4 })
            b.label:SetJustification(1)
        else
            b.labelSlot:SetAlignment({ X = 0, Y = 1 }); b.labelSlot:SetPosition({ X = top.x + 6, Y = top.y - 4 })
        end
    end)
end

-- какое окно сейчас на экране: меню (выбор) или лаборатория
local function useView(kind)
    local v = UI.views and UI.views[kind]
    if not v then return false end
    for k, other in pairs(UI.views) do
        if k ~= kind and valid(other.panel) then other.panel:SetVisibility(VIS_HIDE) end
    end
    if UI.view ~= v then
        -- сменился стиль окна: новый список прокручиваем туда же, а выбранный пункт держим на виду
        -- (иначе опрос колёсика увидит другую прокрутку и уведёт выбор)
        if v.sbox then pcall(function() v.sbox:SetScrollOffset(UI.scrollPx or 0) end) end
        UI.ensureSel = true
    end
    UI.view = v
    UI.panel, UI.panelSlot = v.panel, v.slot
    UI.title, UI.sub, UI.desc, UI.foot = v.title, v.sub, v.desc, v.foot
    return true
end

local function buildUI()
    local pc = getPC(); if not pc then return false end
    local uwCls = StaticFindObject("/Script/CommonUI.CommonUserWidget")
    if not valid(uwCls) then uwCls = StaticFindObject("/Script/UMG.UserWidget") end
    local w = StaticConstructObject(uwCls, pc)
    if not valid(w) then return false end
    local tree = construct("/Script/UMG.WidgetTree", w)
    w.WidgetTree = tree
    local canvas = construct("/Script/UMG.CanvasPanel", tree)
    tree.RootWidget = canvas
    pcall(function() w:SetOwningPlayer(pc) end)

    -- затемнение под окном выбора, как у экрана смерти игры
    do
        local dim = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree)
        dim:SetColorAndOpacity(GAME.dim)
        local ds = canvas:AddChildToCanvas(dim)
        ds:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
        pcall(function() ds:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
        dim:SetVisibility(VIS_HIDE)
        UI.dim = dim
    end

    -- окно лаборатории: в том же стиле, справа, компактнее
    UI.views = { lab = buildGameMenu(tree, canvas, LABMENU) }

    -- окно выбора в стиле меню паузы игры
    UI.views.game = buildGameMenu(tree, canvas)
    -- то же окно в стиле «терминал» (Settings -> Interface)
    UI.views.term = buildGameMenu(tree, canvas, TERMMENU)
    UI.views.min = buildGameMenu(tree, canvas, MINMENU)

    -- окно данных лаборатории (слева сверху)
    local lab, lvb = box(tree, canvas, 0, 0, 0, 0, 30, 30, COL.gold, COL.hudBg)
    UI.labLines = {}
    for i = 1, 8 do UI.labLines[i] = line(tree, lvb, "", COL.text, 14) end
    lab:SetVisibility(VIS_HIDE)
    UI.labBox = lab

    -- спидран-панель в стиле игры: без рамки, справа сверху, выравнивание вправо.
    -- Счётчик яблок — шрифтом кнопок, как родной "0/66" (родной прячем)
    do
        local hvb = construct("/Script/UMG.VerticalBox", tree)
        local hslot = canvas:AddChildToCanvas(hvb)
        pcall(function() hslot:SetAutoSize(true) end)
        pcall(function()
            hslot:SetAnchors({ Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } })
            hslot:SetAlignment({ X = 1, Y = 0 })
        end)
        hslot:SetPosition({ X = -P.hudX, Y = P.hudY })
        UI.hudSlot = hslot
        UI.hudLines = {}
        for _, key in ipairs(HUD_ORDER) do
            local st = HUD_STYLE[key]
            local t = construct("/Script/UMG.TextBlock", tree)
            t:SetText(FText(""))
            setColor(t, st.color)
            setFont(t, st.font, math.floor(st.size * P.hudSize / 18 + 0.5))
            pcall(function() t:SetJustification(2) end)
            local s2 = hvb:AddChildToVerticalBox(t)
            pcall(function() s2:SetHorizontalAlignment(3); s2:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = st.gap or 0 }) end)
            UI.hudLines[key] = t
        end
        hvb:SetVisibility(VIS_HIDE)
        UI.hud = hvb
    end

    -- надпись режима Nightmare (иногда глючит)
    do
        local t = construct("/Script/UMG.TextBlock", tree)
        t:SetText(FText("+ NIGHTMARE +"))
        setColor(t, { R = 1, G = 1, B = 1, A = 0.35 })
        setFont(t, "main", 18)
        local ns = canvas:AddChildToCanvas(t)
        pcall(function() ns:SetAutoSize(true) end)
        ns:SetAnchors({ Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } })
        ns:SetAlignment({ X = 1, Y = 0 })
        ns:SetPosition({ X = -P.hudX, Y = P.hudY })
        t:SetVisibility(VIS_HIDE)
        UI.nightTag, UI.nightSlot = t, ns
    end

    -- шкала режима (Bashful: "смущение"): сверху по центру — подпись и полоска
    do
        local m = {}
        local function piece(fill, x, y, w, h)
            local b = construct("/Script/UMG.Border", tree)
            roundBrush(b, fill, { R = 0, G = 0, B = 0, A = 0 }, 0, 2)
            local s = canvas:AddChildToCanvas(b)
            pcall(function()
                s:SetAutoSize(false)
                s:SetAnchors({ Minimum = { X = 0.5, Y = 0 }, Maximum = { X = 0.5, Y = 0 } })
                s:SetAlignment({ X = 0, Y = 0 })
                s:SetPosition({ X = x, Y = y }); s:SetSize({ X = w, Y = h })
            end)
            b:SetVisibility(VIS_HIDE)
            return b, s
        end
        m.w, m.h, m.y = 360, 6, 96
        m.track = piece({ R = 1, G = 1, B = 1, A = 0.18 }, -m.w / 2, m.y, m.w, m.h)
        m.fill, m.fillSlot = piece({ R = 1, G = 0.45, B = 0.7, A = 1 }, -m.w / 2, m.y, 1, m.h)
        local t = construct("/Script/UMG.TextBlock", tree)
        t:SetText(FText(""))
        setColor(t, { R = 1, G = 0.6, B = 0.8, A = 1 })
        setFont(t, "main", 16)
        center(t)
        local ts = canvas:AddChildToCanvas(t)
        pcall(function()
            ts:SetAutoSize(true)
            ts:SetAnchors({ Minimum = { X = 0.5, Y = 0 }, Maximum = { X = 0.5, Y = 0 } })
            ts:SetAlignment({ X = 0.5, Y = 1 }); ts:SetPosition({ X = 0, Y = m.y - 6 })
        end)
        t:SetVisibility(VIS_HIDE)
        m.text = t
        UI.meter = m
    end

    -- счётчик FPS (Settings -> Graphics), слева сверху
    do
        local t = construct("/Script/UMG.TextBlock", tree)
        t:SetText(FText(""))
        setColor(t, { R = 1, G = 1, B = 1, A = 0.75 })
        setFont(t, "main", 16)
        local fs = canvas:AddChildToCanvas(t)
        pcall(function() fs:SetAutoSize(true) end)
        pcall(function() fs:SetPosition({ X = 14, Y = 8 }) end)
        t:SetVisibility(VIS_HIDE)
        UI.fpsText = t
    end

    -- крупная надпись посреди экрана, как подсказки игры ("SHE KNOWS")
    do
        local t = construct("/Script/UMG.TextBlock", tree)
        t:SetText(FText(""))
        setColor(t, { R = GAME.blue.R, G = GAME.blue.G, B = GAME.blue.B, A = 0 })
        setFont(t, "main", 56)
        center(t)
        local fs = canvas:AddChildToCanvas(t)
        pcall(function() fs:SetAutoSize(true) end)
        fs:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        fs:SetAlignment({ X = 0.5, Y = 0.5 })
        fs:SetPosition({ X = 0, Y = -260 })
        t:SetVisibility(VIS_HIDE)
        UI.flash = t
        -- подпись под ней: что сейчас будет (подписи режимов и мутаторов, TAGLINE в run.lua)
        local s2 = construct("/Script/UMG.TextBlock", tree)
        s2:SetText(FText(""))
        setColor(s2, { R = 1, G = 1, B = 1, A = 0 })
        setFont(s2, "main", 26)
        center(s2)
        local ss = canvas:AddChildToCanvas(s2)
        pcall(function() ss:SetAutoSize(true) end)
        ss:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        ss:SetAlignment({ X = 0.5, Y = 0.5 })
        ss:SetPosition({ X = 0, Y = -205 })
        s2:SetVisibility(VIS_HIDE)
        UI.flashSub = s2
    end

    -- свои полоски здоровья и выносливости (на месте родных, в их стиле)
    UI.bars = buildBars(tree, canvas)

    local imgCls = StaticFindObject("/Script/UMG.Image")
    -- полная тьма на миг (мутатор Blackouts): поверх всего, кроме экранов поражения
    do
        local b = StaticConstructObject(imgCls, tree)
        b:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0 })
        local bs = canvas:AddChildToCanvas(b)
        bs:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        bs:SetAlignment({ X = 0.5, Y = 0.5 })
        bs:SetPosition({ X = 0, Y = 0 })
        bs:SetSize({ X = 12000, Y = 12000 })
        b:SetVisibility(VIS_HIDE)
        UI.blind = b
    end

    -- затемнение экрана и надпись поимки (поверх всего)
    local veil = StaticConstructObject(imgCls, tree)
    veil:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0 })
    local vs = canvas:AddChildToCanvas(veil)
    vs:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
    vs:SetAlignment({ X = 0.5, Y = 0.5 })
    vs:SetPosition({ X = 0, Y = 0 })
    vs:SetSize({ X = 12000, Y = 12000 })
    veil:SetVisibility(VIS_HIDE)
    UI.veil = veil
    local notice = construct("/Script/UMG.TextBlock", tree)
    notice:SetText(FText("+ NOTICE +"))
    setColor(notice, { R = GAME.deep.R, G = GAME.deep.G, B = GAME.deep.B, A = 0 })
    setFont(notice, "main", 96)
    pcall(function() notice:SetJustification(1) end)
    local ns = canvas:AddChildToCanvas(notice)
    pcall(function() ns:SetAutoSize(true) end)
    ns:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
    ns:SetAlignment({ X = 0.5, Y = 0.5 })
    ns:SetPosition({ X = 0, Y = -40 })
    notice:SetVisibility(VIS_HIDE)
    UI.notice = notice
    for _, k in ipairs({ "loseSub", "loseStats" }) do
        local t = construct("/Script/UMG.TextBlock", tree)
        t:SetText(FText(""))
        setColor(t, { R = 1, G = 1, B = 1, A = 0 })
        setFont(t, "main", k == "loseSub" and 24 or 18)
        pcall(function() t:SetJustification(1) end)
        local ts = canvas:AddChildToCanvas(t)
        pcall(function() ts:SetAutoSize(true) end)
        ts:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        ts:SetAlignment({ X = 0.5, Y = 0.5 })
        ts:SetPosition({ X = 0, Y = k == "loseSub" and 50 or 110 })
        t:SetVisibility(VIS_HIDE)
        UI[k] = t
    end

    w:AddToViewport(60)
    UI.widget, UI.pc = w, pc
    -- новый контроллер: старые пауза и блокировка к нему не относятся
    UI.inputBlocked, UI.pausedByMe, UI.inputMode = false, false, nil
    log("UI built")
    return true
end

local function ensureUI()
    if valid(UI.widget) and valid(UI.pc) then return true end
    local ok, res = pcall(buildUI)
    if not ok then log("UI build failed: " .. tostring(res)) return false end
    return res
end

------------------------------------------------------------------------
-- Пауза и блокировка управления, пока открыто окно
------------------------------------------------------------------------
applyPause = function()
    local pc = getPC(); if not pc then return end
    local open = UI.open
    local lab = open and UI.kind == "lab"
    local pause = open and not lab                 -- лаборатория игру не останавливает
    local mode = (not open) and "game" or (lab and "lab" or "menu")
    if mode ~= UI.inputMode then
        pcall(function() pc:SetIgnoreMoveInput(pause) end)
        pcall(function() pc:SetIgnoreLookInput(open) end)
        if not open then
            pcall(function() pc:ResetIgnoreMoveInput() end)
            pcall(function() pc:ResetIgnoreLookInput() end)
        end
        pcall(function() pc.bShowMouseCursor = open end)
        local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        if valid(wbl) then
            if mode == "menu" then
                local ok = pcall(function() wbl:SetInputMode_UIOnlyEx(pc, UI.widget, 0, true) end)
                if not ok then pcall(function() wbl:SetInputMode_GameAndUIEx(pc, UI.widget, 0, false, true) end) end
            elseif mode == "lab" then
                -- клавиши идут и в игру (можно ходить), мышь — в окно
                pcall(function() wbl:SetInputMode_GameAndUIEx(pc, UI.widget, 0, false, true) end)
            else
                pcall(function() wbl:SetInputMode_GameOnly(pc, true) end)
            end
        end
        UI.inputMode = mode
        UI.inputBlocked = pause
    end
    if pause ~= UI.pausedByMe then
        pcall(function() statics():SetGamePaused(pc, pause) end)
        UI.pausedByMe = pause
    end
end

------------------------------------------------------------------------
