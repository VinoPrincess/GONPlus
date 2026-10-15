-- главное меню: "Quit game" — первый клик просит подтверждения, второй закрывает игру
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
goto_("QUIT GAME"); key("RETURN")
check(not logHas("Quit game from"), "first click only asks")
check(hasText("CLICK AGAIN TO QUIT") or hasText("click again to quit"), "asks to confirm")
for _ = 1, 40 do if hasText("^%+ QUIT GAME %+$") then break end key("DOWN_ARROW") end
key("RETURN")
check(logHas("Quit game from"), "second click quits")
DONE("quit")
