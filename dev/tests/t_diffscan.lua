-- лаборатория: скан сложности пишет файл и не падает на заглушках
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
check(type(scanDifficulty) == "function", "scanDifficulty exists")
local ok, res = pcall(scanDifficulty)
check(ok, "scan runs: " .. tostring(res))
check(ok and tostring(res):find("^Saved difficulty_scan_") ~= nil, "scan saved: " .. tostring(res))
DONE("diffscan")
