-- Settings -> Interface: terminal — окно-терминал слева, полоски с цифрами; обратно в стиль игры
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
goto_("SETTINGS"); key("RETURN")
goto_("INTERFACE"); key("RIGHT_ARROW")
check(has("terminal"), "interface switched to terminal")
check(has("SETTINGS"), "terminal title has no plus signs")
check(hasText("^> INTERFACE"), "selected row looks like '> ROW'")
check(hasText("^GON%+ // TERMINAL$"), "terminal tag")
local f = io.open(SETTINGS_FILE); local st = f and f:read("a") or ""; if f then f:close() end
check(st:find("uiStyle=term") and st:find("barsStyle=term"), "interface and bars saved")
key("BACKSPACE")
check(has("NEW RUN"), "main screen in terminal style")
-- полоски-терминал во время забега: проценты
for _ = 1, 40 do if has("> START") then break end key("DOWN_ARROW") end
check(has("> START"), "START row in terminal style")
key("RETURN"); run(2000)
check(hasText("^100%%$"), "terminal bars show percent")
DONE("terminal")
