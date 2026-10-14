-- Zero Hour: минута на старте, яблоко +20 с (не больше 2:30), время вышло = поражение
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
goto_("MUTATOR: NONE"); key("RETURN")
goto_("ZERO HOUR"); key("RETURN")
check(hasText("MUTATOR: ZERO HOUR"), "Zero Hour picked")
startRun()
check(hasText("^00:5"), "clock starts at about a minute")
run(30000)
PAWN.pinecollected = 1; run(500)
check(logHas("Zero Hour: apple, %+20 s"), "apple adds 20 s")
check(hasText("%+ 20 SECONDS %+"), "flash +20 SECONDS")
for i = 2, 12 do PAWN.pinecollected = i; run(300) end
check(logHas("-> 150 s left") or logHas("-> 14%d s left"), "bank is capped at 2:30")
run(160000)
check(has("+ ZERO HOUR +"), "time out = defeat screen")
DONE("zerohour")
