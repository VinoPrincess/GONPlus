-- лаборатория: новые вкладки (игрок, Року, чувства, предметы, мир) открываются и не сыплют ошибками
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
startRun()
ROKU_PRESENT = true; run(4000)
key("F1"); run(100)
check(has("+  GON+ LAB  +"), "lab opens")
local seen = {}
for _ = 1, 12 do
    local s = hasText("SECTION:") or ""
    local name = s:match("<%s*(.-)%s*>")
    if name then seen[name] = true end
    key("RIGHT_ARROW")
end
for _, n in ipairs({ "PLAYER", "ROKU", "SENSES", "ITEMS", "WORLD", "ROKU AI", "DARKNESS", "SCANS", "RUN" }) do
    check(seen[n], "section " .. n)
end
-- пройти по каждому пункту новых вкладок: Enter дважды (вкл/выкл) — без ошибок Lua
local function section(n)
    for _ = 1, 40 do if hasText("^%+ SECTION:") then break end key("UP_ARROW") end
    for _ = 1, 12 do
        local s = hasText("SECTION:") or ""
        if s:find("<%s*" .. n .. "%s*>") then return true end
        key("RIGHT_ARROW")
    end
end
for _, n in ipairs({ "PLAYER", "ROKU", "SENSES", "ITEMS", "WORLD" }) do
    check(section(n), "go to " .. n)
    for i = 1, 25 do
        key("DOWN_ARROW")
        if hasText("^%+ SECTION:") then break end
        key("RETURN"); run(200); key("RETURN"); run(200)
    end
end
check(R_CHEATED ~= false, "cheats mark the run")
DONE("labfun")
