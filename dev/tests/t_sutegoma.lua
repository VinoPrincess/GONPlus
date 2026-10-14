-- SUTEGOMA: кровотечение идёт по времени игры и стоит на паузе
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
goto_("MUTATOR: NONE"); key("RETURN"); goto_("SUTEGOMA"); key("RETURN")
startRun()
local h0 = PAWN.health; run(10000); local h1 = PAWN.health
check(h0 - h1 > 0.02 and h0 - h1 < 0.05, string.format("bleeds ~0.033 in 10 s (%.4f)", h0 - h1))
PAUSED = true; run(10000); local h2 = PAWN.health
check(math.abs(h1 - h2) < 0.002, "no bleeding while paused")
PAUSED = false
DONE("sutegoma")
