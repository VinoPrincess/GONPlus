-- Lovesick: свой мозг, объятия растят шкалу, проигрыш по полной шкале
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
setMode("LOVESICK")
startRun()
check(hasText("^LOVE") or hasText("LOVESICK"), "love HUD")
ROKU_PRESENT = true; ROKU_POS.X = 3000; run(4000)
check(logHas("under the love brain"), "love brain takes over")
for _ = 1, 6 do
    run(12000); SEES(true); run(300); ROKU_POS.X = 100; run(500); ROKU_POS.X = 3000; SEES(false)
end
run(8000)
check(logCount("hug!") >= 4, "hugs happen (" .. logCount("hug!") .. ")")
check(hasText("HEAD OVER"), "full heart = lose screen")
DONE("lovesick")
