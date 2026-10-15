-- настройки игры в меню GON+: наряд, сложность ванильной игры, перезапуск ради Normal в режимах
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
GI = setmetatable({ GI_Difficulty = 3, MouseSensitivity = 1.0 }, { __index = function(_, k)
    if k == "IsValid" then return function() return true end end
    if k == "GetAddress" then return function() return "gi" end end
end })
local ff = FindFirstOf
FindFirstOf = function(n) if n == "GI_GON_C" then return GI end return ff(n) end
LOAD(arg[1])
run(600)
check(hasText("^%+ ROKU: ") or hasText("^ROKU: "), "outfit row on the main screen")
check(hasText("DIFFICULTY: HARD"), "vanilla difficulty row shows the game's Hard")
-- ванильная игра на Hard: без перезапуска, рекорд отдельный
startRun()
check(logHas("key normal@hard"), "vanilla Hard has its own record key")
check(not logHas("restarting the level"), "no restart when difficulty already matches")
-- новый забег, режим Pure Stealth: игра на Hard -> ставим Normal и перезапускаем уровень
PAWN_ADDR = 2; run(1500)
setMode("PURE STEALTH")
check(not hasText("DIFFICULTY:"), "no difficulty row for GON+ modes")
local before = #CONSOLE
goto_("START"); key("RETURN"); run(500)
local restarted = false
for i = before + 1, #CONSOLE do if CONSOLE[i] == "RestartLevel" then restarted = true end end
check(restarted, "restart for Normal difficulty")
check(GI.GI_Difficulty == 2, "GI difficulty set to Normal")
-- уровень перезапустился: новый персонаж -> забег стартует сам
PAWN_ADDR = 3; run(2500)
check(logHas("Run started: stealth"), "the run starts by itself after the restart")
DONE("gamecfg")
