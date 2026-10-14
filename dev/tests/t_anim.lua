-- анимации окна: смена экрана в две фазы, ввод во время анимации доводит её до конца, закрытие
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1], "labUnlocked=1\nuiAnim=1\n")
run(800)
check(TITLE() and TITLE():find("NEW RUN"), "chooser opens with animation on")
goto_("SETTINGS"); key("RETURN")
check(TITLE() and TITLE():find("NEW RUN"), "old page stays while it slides out")
run(400)
check(TITLE() and TITLE():find("SETTINGS"), "new page after the slide")
-- быстрый ввод: назад и сразу ещё раз в настройки — ничего не теряется
key("BACKSPACE"); key("DOWN_ARROW")
check(TITLE() and TITLE():find("NEW RUN"), "input during the slide finishes it at once")
goto_("SETTINGS"); key("RETURN"); run(400)
goto_("INTERFACE"); key("RIGHT_ARROW"); run(400)
check(has("terminal"), "terminal with animations")
key("BACKSPACE"); run(400)
check(has("NEW RUN"), "terminal: back to main after the panel returns")
for _ = 1, 40 do if has("> START") then break end key("DOWN_ARROW") end
key("RETURN"); run(2000)
check(PAUSED == false, "start closes the window")
DONE("anim")
