------------------------------------------------------------------------
-- Всплывающие подсказки игры (Settings -> Game pop-ups).
-- Мешают режимам: "BEGI" при погоне, "откройте паузу, чтобы прочитать" у записок,
-- названия предметов при подборе. Прячем их прозрачностью (RenderOpacity = 0):
-- SetVisibility на чужих виджетах бывало роняло игру (см. заметки RokuMenu).
--
-- Какие именно виджеты — узнаём в игре: с открытой лабораторией мод пишет в лог
-- каждую новую надпись игры: "Game text: <виджет>.<надпись> = '...'".
-- Сразу прячем экранные подсказки игры WST_* (из ui_scan: SHE KNOWS, LOOK AT ME...).
------------------------------------------------------------------------
; (function()

-- что прятать: класс виджета игры (начало имени) и, если нужно, только одну надпись в нём
GAME_POPUPS = {
    { widget = "WST_" },          -- экранные подсказки: SHE KNOWS, RUN, LOOK AT ME...
}

local seen = {}          -- для лога: уже записанные надписи
local hidden = {}        -- адреса спрятанных, чтобы вернуть, когда настройку включат

-- "...UI_Horror_C_0.WidgetTree.TextBlock_12" -> "UI_Horror", "TextBlock_12"
local function ownerOf(fullName)
    local cls, name = fullName:match("([%w_]+)_C_%d+%.WidgetTree%.([%w_]+)$")
    return cls, name
end

local function matches(cls, name)
    for _, h in ipairs(GAME_POPUPS) do
        if cls:sub(1, #h.widget) == h.widget and (not h.text or h.text == name) then return true end
    end
    return false
end

local function setOpacity(w, a)
    pcall(function() w:SetRenderOpacity(a) end)
end

every(250, function()
    if not getPawn() then return end
    local hide = P.gamePopups == false
    -- целые виджеты-подсказки (WST_*)
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        if valid(w) then
            local cls = ""
            pcall(function() cls = w:GetClass():GetFName():ToString():gsub("_C$", "") end)
            if cls ~= "" and matches(cls, nil) then
                local addr = w:GetAddress()
                if hide then setOpacity(w, 0); hidden[addr] = "w"
                elseif hidden[addr] then setOpacity(w, 1); hidden[addr] = nil end
            end
        end
    end
    -- отдельные надписи (если в списке есть text = "...")
    local any = false
    for _, h in ipairs(GAME_POPUPS) do if h.text then any = true end end
    if any then
        for _, t in ipairs(FindAllOf("TextBlock") or {}) do
            if valid(t) then
                local cls, name = ownerOf(t:GetFullName())
                if cls and matches(cls, name) then
                    local addr = t:GetAddress()
                    if hide then setOpacity(t, 0); hidden[addr] = "t"
                    elseif hidden[addr] then setOpacity(t, 1); hidden[addr] = nil end
                end
            end
        end
    end
end)
onForgetRefs(function() hidden = {} end)

-- разведка (только с открытой лабораторией): какие надписи показывает игра
every(1000, function()
    if not P.labUnlocked or not getPawn() then return end
    for _, t in ipairs(FindAllOf("TextBlock") or {}) do
        if valid(t) then
            local cls, name = ownerOf(t:GetFullName())
            if cls then
                local txt = ""
                pcall(function() txt = t:GetText():ToString() end)
                if type(txt) == "string" and txt:match("%S") then
                    local key = cls .. "." .. name .. "=" .. txt
                    if not seen[key] then
                        seen[key] = true
                        local vis = "?"
                        pcall(function() vis = tostring(t:IsVisible()) end)
                        log("Game text: " .. cls .. "." .. name .. " = '" .. txt:gsub("\n", " / ") .. "' (visible " .. vis .. ")")
                    end
                end
            end
        end
    end
end)

end)()
