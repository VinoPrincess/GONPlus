------------------------------------------------------------------------
-- Всплывающие подсказки игры (Settings -> Game pop-ups).
-- Мешают режимам: "+RUN+" при погоне, "+ NOTE ACQUIRED + PAUSE TO READ +" у записок,
-- названия предметов при подборе ("FLASHLIGHT", "JAR OF BIO SAMPLES").
-- Разведка в игре 15.10.2026 показала: всё это — один виджет игры WB_ToolTip_C
-- (/Game/Variant_Horror/Localization/WB_ToolTip, надпись ToolTip_Text_Block);
-- на каждое сообщение игра создаёт новый. Прячем прозрачностью (RenderOpacity = 0):
-- SetVisibility на чужих виджетах бывало роняло игру (см. заметки RokuMenu).
--
-- Урок той же разведки: опрос ВСЕХ надписей (их ~1700) раз в секунду давал лаги и,
-- видимо, вылет после перезапуска уровня (трогали надписи старого, умирающего уровня).
-- Поэтому здесь — только точный класс подсказки, и только когда настройка выключена.
------------------------------------------------------------------------
; (function()

GAME_POPUPS = { "WB_ToolTip_C" }

-- Шаблон надписи подсказки: из него игра делает каждую новую подсказку.
-- Делаем прозрачным сам шаблон — новые подсказки рождаются уже невидимыми (без мелькания).
-- Опрос ниже остаётся как подстраховка.
local TEMPLATES = { "/Game/Variant_Horror/Localization/WB_ToolTip.WB_ToolTip_C:WidgetTree.ToolTip_Text_Block" }
local templateState = nil
local function setTemplates(hide)
    if templateState == hide then return end
    for _, path in ipairs(TEMPLATES) do
        local t = nil
        pcall(function() t = StaticFindObject(path) end)
        if valid(t) then
            pcall(function() t.RenderOpacity = hide and 0 or 1 end)
            pcall(function() t:SetRenderOpacity(hide and 0 or 1) end)
            log("Game pop-ups: template " .. (hide and "hidden" or "restored"))
        end
    end
    templateState = hide
end

local hidden = {}        -- адреса спрятанных, чтобы вернуть, когда настройку включат

every(250, function()
    if not getPawn() then return end
    local hide = P.gamePopups == false
    setTemplates(hide)
    if not hide and not next(hidden) then return end
    for _, cls in ipairs(GAME_POPUPS) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            if valid(w) then
                local addr = w:GetAddress()
                if hide then
                    pcall(function() if (num(w:GetRenderOpacity()) or 1) > 0 then w:SetRenderOpacity(0) end end)
                    hidden[addr] = true
                elseif hidden[addr] then
                    pcall(function() w:SetRenderOpacity(1) end); hidden[addr] = nil
                end
            end
        end
    end
    if not hide then hidden = {} end
end)
onForgetRefs(function() hidden = {}; templateState = nil end)

end)()
