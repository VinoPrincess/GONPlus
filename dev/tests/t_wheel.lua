-- длинный список: колёсико (ScrollBox) двигает список, выбор остаётся на видимой кнопке
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
goto_("MUTATOR: NONE"); key("RETURN")
check(#SBOXES >= 1, "menu uses a ScrollBox")
check(has("+ NONE +"), "first row selected")
WHEEL(70)
check(logHas("scrolled by the list itself"), "scroll detected")
check(not has("+ NONE +"), "selection follows the scroll (first row no longer selected)")
for _, s in ipairs(SBOXES) do s.off = 0 end
key("BACKSPACE"); goto_("MUTATOR: NONE"); key("RETURN")     -- заново: выбор на первой строке
for _ = 1, 9 do key("DOWN_ARROW") end
local maxOff = 0
for _, s in ipairs(SBOXES) do maxOff = math.max(maxOff, s.off) end
check(maxOff > 0, "arrows scroll the list down (" .. maxOff .. ")")
DONE("wheel")
