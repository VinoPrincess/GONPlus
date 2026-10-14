-- Settings -> Interface: minimal — без окна, "+SETTINGS+", "— ПУНКТ", полоски-линии; анимации
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1], "labUnlocked=1\nuiAnim=1\n")
run(800)
goto_("SETTINGS"); key("RETURN"); run(400)
goto_("INTERFACE"); key("LEFT_ARROW"); run(400)       -- game -> (назад по кругу) minimal
check(has("minimal"), "interface switched to minimal")
check(has("+SETTINGS+"), "minimal title like +GOD+OF+NOTHING+")
check(hasText("^— INTERFACE"), "selected row looks like '— ROW'")
local f = io.open(SETTINGS_FILE); local st = f and f:read("a") or ""; if f then f:close() end
check(st:find("uiStyle=min") and st:find("barsStyle=line"), "interface and bars saved")
key("BACKSPACE"); run(400)
check(has("+NEW+RUN+"), "main screen in minimal style")
for _ = 1, 40 do if has("— START") then break end key("DOWN_ARROW") end
check(has("— START"), "START row in minimal style")
key("RETURN"); run(2000)
check(PAUSED == false, "run starts from the minimal menu")
DONE("minimal")
