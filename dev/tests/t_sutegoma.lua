-- SUTEGOMA: кровотечение идёт по времени игры и стоит на паузе
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
setMode("SUTEGOMA")
startRun()
local h0 = PAWN.health; run(10000); local h1 = PAWN.health
check(h0 - h1 > 0.02 and h0 - h1 < 0.05, string.format("bleeds ~0.033 in 10 s (%.4f)", h0 - h1))
PAUSED = true; run(10000); local h2 = PAWN.health
check(math.abs(h1 - h2) < 0.002, "no bleeding while paused")
PAUSED = false
-- бег: вся выносливость за раз -> шкала полная, кровь идёт быстрее
PAWN["Sprint Meter"] = 5.0; run(300)
for i = 1, 20 do PAWN["Sprint Meter"] = 5.0 - i * 0.25; run(260) end
local hA = PAWN.health; run(10000); local hB = PAWN.health
check(hA - hB > 0.08, string.format("bleeds much faster after a full sprint (%.4f in 10 s)", hA - hB))
check(logHas("SUTEGOMA") and hasText("BLOOD LOSS"), "blood loss meter shown")
check(hasText("^%+ HEMORRHAGE %+$"), "warning when the meter is full")
-- отдых: выносливость возвращается, шкала спадает
for i = 1, 20 do PAWN["Sprint Meter"] = i * 0.25; run(260) end
PAWN["Sprint Meter"] = 5.0; run(15000)
local hC = PAWN.health; run(10000); local hD = PAWN.health
check(hC - hD < 0.05, string.format("back to normal bleeding after rest (%.4f in 10 s)", hC - hD))
DONE("sutegoma")
