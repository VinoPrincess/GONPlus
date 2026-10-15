------------------------------------------------------------------------
-- ЭКРАН ПОРАЖЕНИЯ: свой для каждого режима и мутатора.
-- Экран затемняется до конца (ничего не видно), крупная надпись в стиле игры,
-- строка-подпись и итоги забега; потом тает и открывает экран смерти игры.
--   o.title, o.sub, o.veil {r,g,b}, o.color (цвет надписи), o.white (вспышка),
--   o.fadeIn (с), o.hold (с), o.scripted (смерть делает мод: endRun + PlayerDeath),
--   o.result (для записи забега)
------------------------------------------------------------------------
function defeat(o)
    if UI.defeatOn or not valid(UI.veil) then return end
    UI.defeatOn = true
    UI.defeatGen = (UI.defeatGen or 0) + 1
    local gen = UI.defeatGen
    local vr = o.veil or { 0, 0, 0 }
    local tc = o.color or GAME.deep
    local pawn = getPawn()
    local addr = pawn and pawn:GetAddress()
    if o.scripted then setPlayerInput(true) end
    log("Defeat screen: " .. tostring(o.title))

    local function stats()
        local mode = runLabel()
        return string.format("TIME %s      APPLES %d/66      %s", fmtTime(runTime(), true), R.pines or 0, mode)
    end
    setText(UI.notice, o.title or "")
    setText(UI.loseSub, o.sub or "")
    setText(UI.loseStats, stats())
    for _, w in ipairs({ UI.veil, UI.notice, UI.loseSub, UI.loseStats }) do
        if valid(w) then pcall(function() w:SetVisibility(VIS_SHOW) end) end
    end
    local function paint(veilA, textA, whiteK)
        local wk = whiteK or 0
        pcall(function()
            UI.veil:SetColorAndOpacity({ R = vr[1] + (1 - vr[1]) * wk, G = vr[2] + (1 - vr[2]) * wk, B = vr[3] + (1 - vr[3]) * wk, A = veilA })
        end)
        pcall(function() setColor(UI.notice, { R = tc.R, G = tc.G, B = tc.B, A = textA }) end)
        pcall(function() setColor(UI.loseSub, { R = 1, G = 1, B = 1, A = 0.8 * textA }) end)
        pcall(function() setColor(UI.loseStats, { R = 1, G = 1, B = 1, A = 0.45 * textA }) end)
    end

    local fadeIn = (o.fadeIn or 1.5) * 1000
    local steps = 30
    for i = 0, steps do
        after(fadeIn * i / steps, function()
            if UI.defeatGen ~= gen then return end
            local a = i / steps
            local wk = o.white and math.max(0, 1 - a * 1.6) or 0     -- белая вспышка уходит в цвет экрана
            paint(o.white and 1 or math.min(1, a * 1.15), math.min(1, a * 1.4), wk)
        end)
    end
    -- экран полностью закрыт: тут засчитываем поражение и вызываем смерть игры
    after(fadeIn + 50, function()
        if UI.defeatGen ~= gen then return end
        if o.scripted then
            if R.phase == "running" then endRun(o.result or "dead") end
            setText(UI.loseStats, stats())
            setPlayerInput(false)
            local p = getPawn()
            if o.victory then
                -- победа: экран победы самой игры
                if p then pcall(function() p:VICTORY() end) end
                return
            elseif o.restart then
                -- не смерть: просто начать уровень заново
                after(o.hold and (o.hold * 1000) or 3500, function()
                    pcall(function()
                        StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(getPawn(), "RestartLevel", getPC())
                    end)
                end)
                return
            end
            if p and p:GetAddress() == addr then pcall(function() p:PlayerDeath() end) end
            after(5000, function()
                local q = getPawn()
                if q and addr and q:GetAddress() == addr then
                    log("Defeat: player still alive, restarting the level")
                    pcall(function()
                        StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(q, "RestartLevel", getPC())
                    end)
                end
            end)
        end
    end)
    -- держим, потом тает и открывает экран смерти игры
    local hold = fadeIn + (o.hold or 3.5) * 1000
    for i = 0, 20 do
        after(hold + i * 50, function()
            if UI.defeatGen ~= gen then return end
            local a = 1 - i / 20
            paint(a, a, 0)
        end)
    end
    after(hold + 1100, function()
        if UI.defeatGen ~= gen then return end
        for _, w in ipairs({ UI.veil, UI.notice, UI.loseSub, UI.loseStats }) do
            if valid(w) then pcall(function() w:SetVisibility(VIS_HIDE) end) end
        end
        UI.defeatOn = false
    end)
end

-- экраны поражения от Року (игра убила сама) для режимов без своей сцены
-- экраны победы: свой у режима (если не Normal), иначе у мутатора, иначе общий
WIN = {
    normal    = { title = "+ ALL CLEAR +", sub = "Every sample collected. You walk out." },
    stealth   = { title = "+ GHOST +", sub = "She never saw you. Not once." },
    nightmare = { title = "+ DAWN +", sub = "You woke up from the nightmare." },
    shy       = { title = "+ RESPECTFUL +", sub = "You never made her uncomfortable. She'll remember that." },
    zerohour  = { title = "+ JUST IN TIME +", sub = "The clock never got its zero." },
    chaos     = { title = "+ CHAOS TAMED +", sub = "Whatever it threw at you, you handled it." },
    slippery  = { title = "+ STEADY HANDS +", sub = "Nothing slipped when it mattered." },
    sutegoma  = { title = "+ STILL BREATHING +", sub = "SUTEGOMA. You kept the bleeding in check." },
    twins     = { title = "+ ESCAPED BOTH +", sub = "Two of her. None of you." },
    nofood    = { title = "+ TRASH HERO +", sub = "No treats. No problem." },
    zoomies   = { title = "+ OUTRAN HER +", sub = "She was fast. You were faster." },
    razor     = { title = "+ UNSCRATCHED +", sub = "Those claws never found you." },
    darkness  = { title = "+ NIGHT VISION +", sub = "You found your way without the lights." },
    nohud     = { title = "+ BY FEEL +", sub = "No numbers, no bars. Just instinct." },
    nohiding  = { title = "+ NEVER HID +", sub = "Nowhere to hide - and you didn't need to." },
    onehit    = { title = "+ UNTOUCHED +", sub = "One hit would have done it. It never came." },
    heat      = { title = "+ COOL HEAD +", sub = "The heat got to everyone but you." },
    blackouts = { title = "+ EYES ADJUSTED +", sub = "Every time it went black, you kept going." },
}
function winScreen()
    if R.base and R.base ~= "normal" and WIN[R.base] then return WIN[R.base] end
    if R.mode == "chaos" then return WIN.chaos end
    local m = (R.baseMut and MUTS[R.baseMut]) or (R.mutId and MUTS[R.mutId])
    if m and m.shortClock then return WIN.zerohour end
    if m and m.countdown then
        local left = R.lastCountdown or 0
        return { title = "+ OUT BEFORE THE BLAST +", sub = "The reactor still had " .. fmtTime(math.max(0, left)) .. " left." }
    end
    if R.mutId and WIN[R.mutId] then return WIN[R.mutId] end
    return WIN.normal
end

LOSE = {
    chaos = { title = "+ CHAOS WINS +", sub = "Nothing stays the same. Not even you." },
    nightmare = { title = "+ IN THE DARK +", sub = "You never saw it coming." },
}

