-- мутации 1.1: Darkness, One Hit, Blackouts, No HUD, Heat
TESTS = arg[0]:match("^(.*)[/\\]") or "."
dofile(TESTS .. "/mock.lua")
LOAD(arg[1])
run(600)
local addr = 1
local function pick(name)
    addr = addr + 1; PAWN_ADDR = addr; PAWN.health = 1.0; run(1500)
    goto_("MUTATOR: " .. (MUTPREV or "NONE")); key("RETURN")
    goto_(name); key("RETURN")
    MUTPREV = name
    startRun()
end
PAWN_ADDR = 1
pick("DARKNESS")
check(logHas("Dark lamps ON"), "darkness: lamps off")
check(hasText("^The lights are out"), "darkness tagline")
pick("ONE HIT")
check(logHas("Dark lamps off"), "darkness released when the run ended")
PAWN.health = 1.0; run(600); PAWN.health = 0.7; run(800)
check(logHas("One Hit: hit taken"), "one hit kills on the first hit")
pick("BLACKOUTS")
GAME_T = GAME_T + 120; run(3000)
check(logHas("Blackouts: "), "blackout happens")
pick("HEAT")
PAWN["Sprint Meter"] = 1.0; run(300); PAWN["Sprint Meter"] = 2.0; run(300)
check(PAWN["Sprint Meter"] < 1.9, "heat slows stamina recovery")
pick("NO HUD")
run(500)
check(hudHidden and hudHidden(), "no HUD hides the interface")
DONE("newmuts")
