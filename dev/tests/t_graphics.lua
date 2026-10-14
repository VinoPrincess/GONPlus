-- Settings -> Graphics: строки меняют консольные переменные, "game" возвращает как было,
-- игра перезаписала — мод ставит заново, счётчик FPS
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(3000)
check(logHas("Graphics: scan:"), "graphics scan in the log")
goto_("SETTINGS"); key("RETURN")
goto_("GRAPHICS / FPS"); key("RETURN")
check(TITLE() and TITLE():find("GRAPHICS"), "graphics screen")
check(hasText("^<  game  >$"), "rows show 'game'")
check(hasText("^<  game: 100%%  >$"), "render scale shows the game's value")
goto_("RENDER SCALE"); key("RIGHT_ARROW"); key("RIGHT_ARROW")
check(CVARS["r.ScreenPercentage"] == 90, "render scale 90%")
goto_("SHADOWS"); key("RIGHT_ARROW")
check(CVARS["r.Shadow.Virtual.Enable"] == 0, "fast shadows: virtual shadows off")
-- игра перезаписала (новая карта) — мод возвращает своё
CVARS["r.Shadow.Virtual.Enable"] = 1
run(2500)
check(CVARS["r.Shadow.Virtual.Enable"] == 0, "kept after the game overwrote it")
key("LEFT_ARROW")
check(CVARS["r.Shadow.Virtual.Enable"] == 1, "back to game value")
goto_("PRESET"); key("RIGHT_ARROW")
check(hasText("%[balanced%]"), "balanced preset")
check(CVARS["r.Shadow.Virtual.Enable"] == 0 and CVARS["r.ReflectionMethod"] == 2, "balanced values")
goto_("RESET TO GAME"); key("RETURN")
check(CVARS["r.ScreenPercentage"] == 100 and CVARS["r.ReflectionMethod"] == 1 and CVARS["r.AntiAliasingMethod"] == 4,
      "reset restores the game's values")
goto_("FRAME TIMING"); key("RETURN")
check(CONSOLE[#CONSOLE] == "stat unit", "frame timing runs stat unit")
goto_("FPS COUNTER"); key("RETURN"); run(1200)
check(hasText("^FPS 60"), "FPS counter shows 60")
local f = io.open(SETTINGS_FILE); local st = f and f:read("a") or ""; if f then f:close() end
check(st:find("gfxFpsShow=1"), "settings saved")
key("BACKSPACE"); check(TITLE() and TITLE():find("SETTINGS"), "back goes to settings")
DONE("graphics")
