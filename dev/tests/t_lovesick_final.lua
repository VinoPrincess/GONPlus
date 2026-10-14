-- Lovesick, последние 2 минуты ("SHE ALWAYS KNOWS"): гонится и обнимает, даже если не видит
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1], "labUnlocked=1\nuiAnim=0\nselLoveMin=4\n")
run(600)
setMode("LOVESICK")
startRun()
ROKU_PRESENT = true; ROKU_POS.X = 3000; SEES(false)
run(125000)                                   -- до финала (4 мин - 2 мин) с запасом
check(hasText("ALWAYS KNOWS") or logHas("always knows"), "final phase started")
local before = logCount("hug!")
run(3000)
check(logHas("she always knows %- chasing"), "she chases without seeing you")
ROKU_POS.X = 100; run(1500)
check(logCount("hug!") > before, "she hugs in the final phase without seeing you")
DONE("lovesick_final")
