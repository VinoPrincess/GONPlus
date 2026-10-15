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
-- аптечка: вдвое меньше, но перевязка (кровь стоит)
PAWN.health = 0.5; run(500)
HOOKS.HealUp(); PAWN.health = 0.9; run(600)
check(math.abs(PAWN.health - 0.7) < 0.02, string.format("medkit heals half (%.3f)", PAWN.health))
check(hasText("^%+ BANDAGED %+$"), "bandaged")
local b0 = PAWN.health; run(5000)
check(math.abs(PAWN.health - b0) < 0.002, "no bleeding while bandaged")
-- удар Року: рана открывается
HOOKS.TakeDamage(); run(600)
check(logHas("the wound opens"), "a hit opens the wound")
check(hasText("THE WOUND OPENS"), "bandage torn off by a hit")
-- запах крови: Року бродит сама; стоишь на месте 40 с — идёт к тебе
ROKU_PRESENT = true; run(5000)
check(logHas("Roku roams on her own"), "Roku roams on her own")
GAME_T = GAME_T + 45; run(1000)
check(logHas("follows the blood %(you stood still%)"), "standing still: she smells you")
-- слабость: ниже 30% пульс по краям экрана
PAWN.health = 0.2; run(800)
DONE("sutegoma")
