-- Nightmare: темнота (лампы, пресет), наряд Dark, слух
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
-- с 1.1 Nightmare — 4-я сложность ванильной игры
goto_("DIFFICULTY: NORMAL"); key("RIGHT_ARROW"); key("RIGHT_ARROW")
check(hasText("DIFFICULTY: NIGHTMARE"), "Nightmare is a difficulty")
startRun()
check(logHas("Run started: nightmare") and logHas("key nightmare"), "runs as nightmare with the old record key")
ROKU_PRESENT = true; run(3000)
check(logHas("Nightmare: step 3"), "lights step")
check(logHas("Dark lamps ON"), "lamps dimmed")
check(logHas("Dark shadows ON"), "darkness preset on")
check(logHas("%-> Dark"), "Roku outfit Dark")
HOOKS.PlayerDeath(); run(2500)
check(logHas("Dark shadows off") or logHas("restoring"), "darkness restored after death")
DONE("nightmare")
